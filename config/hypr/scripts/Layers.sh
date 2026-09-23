#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Layers — named special workspaces used as stacked planes.
#
# Hyprland shows at most ONE special workspace per monitor, so a layer is a
# plane that floats above your normal workspace and tiles its own windows
# independently. Raising another layer swaps which one is up — the previous
# plane hides on its own — so you flip between layers rather than overlaying
# an unlimited number at once.
#
#   Layers.sh raise N     raise layer N, or lower it if it is already up
#   Layers.sh send N      move the focused window onto layer N, then follow it
#   Layers.sh hide        hide whichever layer is currently up
#   Layers.sh next        flip to the next plane        (none -> 1 -> 2 -> 3 -> none)
#   Layers.sh prev        flip to the previous plane
#   Layers.sh toggle      move the focused window into the up plane, or back out
#                         of it if it is already on one
#   Layers.sh toggleplane show the last plane used, or hide the one that is up
#   Layers.sh status      print the visible layer name (empty when none)
#   Layers.sh list        print every layer and its window count
#
# Planes are styled in ~/.config/hypr/UserConfigs/WorkSpaceRules.conf with
# cascading insets, so each one reads as sitting further up the stack.
#
# Keyboard: UserConfigs/UserKeybinds.conf  (SUPER ALT + 1/2/3, + SHIFT to send)
# Mouse:    UserConfigs/UserKeybinds.conf  (middle-click / CTRL + scroll)

set -euo pipefail

max_layer=3
runtime="${XDG_RUNTIME_DIR:-/tmp}"
state="$runtime/hypr-last-layer"

# Name of the special workspace raised on the focused monitor, e.g.
# 'special:layer2' — empty when no layer is up.
visible_layer() {
    hyprctl monitors -j | jq -r '.[] | select(.focused) | .specialWorkspace.name'
}

require_layer_number() {
    case "${1:-}" in
    [1-$max_layer]) : ;;
    *)
        printf 'Layers.sh: layer must be 1..%s (got %s)\n' "$max_layer" "${1:-}" >&2
        exit 2
        ;;
    esac
}

remember() { printf '%s' "$1" >"$state"; }

last_layer() {
    local n
    n="$(cat "$state" 2>/dev/null || true)"
    case "$n" in
    [1-$max_layer]) printf '%s' "$n" ;;
    *) printf '1' ;;
    esac
}

raise_plane() { # N — ensure plane N is the visible one
    local want="special:layer$1"
    remember "$1"
    [ "$(visible_layer)" = "$want" ] && return 0
    hyprctl dispatch togglespecialworkspace "layer$1" >/dev/null
}

hide_plane() {
    local current
    current="$(visible_layer)"
    [ -z "$current" ] && return 0
    hyprctl dispatch togglespecialworkspace "${current#special:}" >/dev/null
}

case "${1:-}" in
raise)
    require_layer_number "${2:-}"
    # Toggling the raised layer lowers it; toggling a different one swaps.
    hyprctl dispatch togglespecialworkspace "layer$2" >/dev/null
    remember "$2"
    ;;

send)
    require_layer_number "${2:-}"
    addr="$(hyprctl activewindow -j | jq -r '.address // empty')"
    if [ -z "$addr" ]; then
        echo "Layers.sh: nothing focused to move" >&2
        exit 1
    fi
    # Order matters, and getting it wrong fails silently — movetoworkspacesilent
    # returns "ok" even when it moves nothing:
    #   1. a special workspace has to EXIST before anything can move onto it
    #   2. raising an empty plane hands focus to the plane
    # So show the plane first, then move the window BY ADDRESS, which does not
    # depend on focus still being where it was.
    if [ "$(visible_layer)" != "special:layer$2" ]; then
        hyprctl dispatch togglespecialworkspace "layer$2" >/dev/null
    fi
    hyprctl dispatch movetoworkspacesilent "special:layer$2,address:$addr" >/dev/null
    remember "$2"
    ;;

hide)
    hide_plane
    ;;

next | prev)
    current="$(visible_layer)"
    num=0
    [ -n "$current" ] && num="${current#special:layer}"
    if [ "$1" = next ]; then
        num=$((num + 1))
        [ "$num" -gt "$max_layer" ] && num=0
    else
        num=$((num - 1))
        [ "$num" -lt 0 ] && num=$max_layer
    fi
    # Stepping past the top falls out of the stack entirely, so scrolling
    # both raises and dismisses planes without a separate gesture.
    if [ "$num" = 0 ]; then hide_plane; else raise_plane "$num"; fi
    ;;

toggle)
    # Move the focused window into the plane that is up — or, if it already
    # lives on a plane, hand it back to the normal workspace underneath.
    info="$(hyprctl activewindow -j 2>/dev/null)"
    if [ -z "$info" ] || [ "$(jq -r '.address // empty' <<<"$info")" = "" ]; then
        echo "Layers.sh: nothing focused to move" >&2
        exit 1
    fi
    ws="$(jq -r '.workspace.name // empty' <<<"$info")"
    addr="$(jq -r '.address // empty' <<<"$info")"
    case "$ws" in
    special:layer*)
        # Back to the normal workspace on the monitor the window sits on,
        # addressed by window so it cannot hit the wrong one.
        monitor="$(jq -r '.monitor // empty' <<<"$info")"
        dest="$(hyprctl monitors -j |
            jq -r --argjson id "$monitor" '[.[] | select(.id == $id)][0].activeWorkspace.id')"
        out="$(hyprctl dispatch movetoworkspacesilent "$dest,address:$addr" 2>&1)"
        case "$out" in
        ok*) printf 'moved window out to workspace %s\n' "$dest" ;;
        *)
            printf 'Layers.sh: move failed: %s\n' "$out" >&2
            exit 1
            ;;
        esac
        # That was the plane's last window — drop the plane too, rather than
        # leaving an empty pane hovering over the workspace.
        left="$(hyprctl workspaces -j |
            jq -r --arg w "$ws" '[.[] | select(.name == $w)][0].windows // 0')"
        if [ "${left:-0}" -eq 0 ]; then
            hyprctl dispatch togglespecialworkspace "${ws#special:}" >/dev/null
        fi
        ;;
    *)
        target="$(visible_layer)"
        [ -z "$target" ] && target="special:layer$(last_layer)"
        mon_id="$(jq -r '.monitor // empty' <<<"$info")"
        mon_name="$(hyprctl monitors -j |
            jq -r --argjson id "$mon_id" '[.[] | select(.id == $id)][0].name')"
        shown="$(hyprctl monitors -j |
            jq -r --argjson id "$mon_id" '[.[] | select(.id == $id)][0].specialWorkspace.name')"
        # Show the plane FIRST, for two independent reasons:
        #   - a special workspace has to exist before anything can move onto
        #     it, and movetoworkspacesilent cheerfully reports "ok" even when
        #     it moved nothing, so the wrong order fails silently
        #   - it must appear on the monitor the WINDOW is on, not wherever
        #     focus happened to be — togglespecialworkspace only ever acts on
        #     the focused monitor, so a window from the other screen would
        #     otherwise vanish into a plane that stays hidden
        # The move then goes BY ADDRESS, because raising an empty plane hands
        # focus to the plane and the focused window is gone.
        if [ "$shown" != "$target" ]; then
            hyprctl dispatch focusmonitor "$mon_name" >/dev/null
            hyprctl dispatch togglespecialworkspace "${target#special:}" >/dev/null
        fi
        out="$(hyprctl dispatch movetoworkspacesilent "$target,address:$addr" 2>&1)"
        case "$out" in
        ok*) printf 'moved window onto %s\n' "$target" ;;
        *)
            printf 'Layers.sh: move failed: %s\n' "$out" >&2
            exit 1
            ;;
        esac
        remember "${target#special:layer}"
        hyprctl dispatch focusmonitor "$mon_name" >/dev/null
        ;;
    esac
    ;;

toggleplane)
    if [ -n "$(visible_layer)" ]; then
        hide_plane
    else
        raise_plane "$(last_layer)"
    fi
    ;;

status)
    visible_layer
    ;;

list)
    out="$(hyprctl workspaces -j |
        jq -r '.[] | select(.name | startswith("special:layer"))
               | "\(.name)\t\(.windows) window(s)"')"
    if [ -z "$out" ]; then
        echo "(no layers yet — send something to one with SUPER ALT SHIFT 1/2/3)"
    else
        printf '%s\n' "$out"
    fi
    ;;

*)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
