#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# MoveToMonitor — hand the focused window to the monitor in a direction.
#
#   MoveToMonitor.sh l | r | u | d
#
# Hyprland's movewindow dispatcher wants `mon:<monitor name>`, not a
# direction, so this works out "the monitor to my right" from the actual
# monitor layout first.
#
# Bound to SUPER CTRL ALT + arrow in UserConfigs/UserKeybinds.conf, which
# completes the arrow ladder (each step adds one modifier):
#
#   SUPER          + arrow    focus
#   SUPER SHIFT    + arrow    resize
#   SUPER CTRL     + arrow    move within the layout
#   SUPER ALT      + arrow    swap with the neighbour
#   SUPER CTRL ALT + arrow    send to the monitor in that direction
#
# Dragging with the mouse does the same thing and is usually faster — grab a
# window with SUPER + left-drag and drop it over the other screen. This is
# the keyboard equivalent, and unlike the drag it also works on windows you
# have not floated.

set -euo pipefail

dir="${1:-}"
case "$dir" in
l | r | u | d) ;;
*)
    printf 'MoveToMonitor.sh: direction must be l, r, u or d (got %s)\n' "${dir:-<none>}" >&2
    exit 2
    ;;
esac

monitors="$(hyprctl monitors -j)"

# The monitor holding the focused window. With nothing focused (empty
# workspace, or the cursor over the bar) fall back to the active monitor.
win_monitor="$(hyprctl activewindow -j | jq -r '.monitor // empty')"
current=""
if [ -n "$win_monitor" ]; then
    current="$(jq -c --argjson id "$win_monitor" '[.[] | select(.id == $id)][0] // empty' <<<"$monitors")"
fi
[ -n "$current" ] || current="$(jq -c '[.[] | select(.focused)][0] // empty' <<<"$monitors")"

if [ -z "$current" ]; then
    echo "MoveToMonitor.sh: no monitor found" >&2
    exit 1
fi

cx="$(jq -r '(.x + (.width  / 2)) | floor' <<<"$current")"
cy="$(jq -r '(.y + (.height / 2)) | floor' <<<"$current")"

# Nearest monitor whose centre lies in the requested direction. Comparing
# centres rather than edges is what keeps this correct on stacked and
# mixed-resolution setups, where an edge comparison has no answer.
target="$(jq -r --argjson cx "$cx" --argjson cy "$cy" --arg dir "$dir" '
    [ .[]
      | { name: .name,
          mx: (.x + (.width  / 2)),
          my: (.y + (.height / 2)) }
      | select(($dir == "r" and .mx > $cx)
            or ($dir == "l" and .mx < $cx)
            or ($dir == "d" and .my > $cy)
            or ($dir == "u" and .my < $cy))
      | . + { dist: (((.mx - $cx) | if . < 0 then -. else . end)
                   + ((.my - $cy) | if . < 0 then -. else . end)) }
    ]
    | sort_by(.dist) | .[0].name // empty
' <<<"$monitors")"

if [ -z "$target" ]; then
    printf 'MoveToMonitor.sh: no monitor to the %s\n' "$dir" >&2
    exit 1
fi

hyprctl dispatch movewindow "mon:$target" >/dev/null
# Follow the window, so it is obvious where it landed.
hyprctl dispatch focusmonitor "$target" >/dev/null
printf 'moved window to %s\n' "$target"
