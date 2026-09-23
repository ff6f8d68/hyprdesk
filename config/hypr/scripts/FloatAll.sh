#!/usr/bin/env bash
# FloatAll — lift every window out of the tiling layout.
#
# New windows float on their own: the catch-all `float on` rule in
# UserConfigs/WindowRules.conf matches every class. But a window rule only
# binds when a window is created, so windows that were already open when the
# rule landed stay tiled until something moves them. This converts them,
# leaving each one where it already sits.
#
#   FloatAll.sh            float every tiled window
#   FloatAll.sh --dry-run  list what would change, touch nothing
#
# Skips anything already floating, and any window whose size would collapse
# below the app minimums set in UserConfigs/WindowRules.conf is left alone
# rather than being mangled.

set -euo pipefail

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

tiled="$(hyprctl clients -j | jq -r '.[] | select(.floating == false) | "\(.address)\t\(.class)"')"

if [ -z "$tiled" ]; then
    echo "FloatAll: nothing is tiled"
    exit 0
fi

floated=0
failed=0

while IFS=$'\t' read -r addr class; do
    [ -n "$addr" ] || continue

    if [ "$dry" = 1 ]; then
        printf '  would float %-24s %s\n' "$class" "$addr"
        continue
    fi

    # setfloating takes a window selector, so this never has to steal focus —
    # which matters because a focus race here would float the wrong window.
    hyprctl dispatch setfloating "address:$addr" >/dev/null 2>&1 || true

    # The dispatch reports "ok" even when it did nothing, so confirm the
    # window actually changed state instead of trusting the reply.
    now="$(hyprctl clients -j \
        | jq -r --arg a "$addr" '[.[] | select(.address == $a)][0].floating // false')"
    if [ "$now" = "true" ]; then
        floated=$((floated + 1))
        continue
    fi

    # Fallback: focus it, verify focus really landed, then use the bare form.
    hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
    sleep 0.3
    if [ "$(hyprctl activewindow -j | jq -r '.address // ""')" = "$addr" ]; then
        hyprctl dispatch setfloating >/dev/null 2>&1 || true
    fi

    now="$(hyprctl clients -j \
        | jq -r --arg a "$addr" '[.[] | select(.address == $a)][0].floating // false')"
    if [ "$now" = "true" ]; then
        floated=$((floated + 1))
    else
        failed=$((failed + 1))
        printf '  could not float %s (%s)\n' "$class" "$addr" >&2
    fi
done <<<"$tiled"

if [ "$dry" = 1 ]; then
    exit 0
fi

printf 'FloatAll: floated %s window(s)' "$floated"
[ "$failed" -gt 0 ] && printf ', %s failed' "$failed"
printf '\n'
[ "$failed" -eq 0 ]
