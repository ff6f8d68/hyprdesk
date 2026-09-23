#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# RaiseOnFocus — make a pile of floating windows behave like a desktop.
#
# This desktop does not tile: every window floats (see the catch-all rule in
# UserConfigs/WindowRules.conf), so windows overlap and the stacking order is
# the whole interface. Hyprland leaves two gaps there, and this daemon fills
# both from the one event socket:
#
#   1. Clicking a window focuses it but does NOT reorder the stack, so a
#      window you click can stay buried under whatever is covering it.
#      Verified by screenshotting the overlap of two floating windows:
#      focusing the lower one left it behind (lum 19), while focusing it and
#      dispatching bringactivetotop brought it to the front (lum 255).
#      There is no Hyprland option for this — misc:raise_on_focus and
#      general:raise_on_focus do not exist.
#
#   2. New windows all land on the same spot, dead on top of each other, so
#      a same-sized window underneath is completely hidden and cannot be
#      clicked at all. New floating windows are therefore walked down the
#      screen in a cascade instead.
#
#   3. Monitor rules are only evaluated when they are loaded, so when the
#      Samsung is unplugged mid-session the panel stays parked off to one
#      side instead of becoming the main screen. That is not merely cosmetic:
#      an app that places itself at 0,0 — xfreerdp was caught doing exactly
#      this — lands off the panel entirely, since the panel is not at 0.
#
# Only floating windows are touched. Tiled windows cannot overlap, and
# leaving their internal order alone keeps cyclenext / groups as they were.
#
# Started from ~/.config/hypr/UserConfigs/Startup_Apps.conf.
# Needs: socat (the event socket), jq, hyprctl.

set -uo pipefail

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Single instance. A config reload re-runs exec-once, and two of these would
# both raise, doubling the work for no benefit.
lock="$runtime/hypr-raise-on-focus.pid"
if [ -f "$lock" ] && kill -0 "$(cat "$lock" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
printf '%s' "$$" >"$lock"
trap 'rm -f "$lock"' EXIT

signature="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls "$runtime/hypr" 2>/dev/null | head -1)}"
socket="$runtime/hypr/$signature/.socket2.sock"

if [ ! -S "$socket" ]; then
    printf 'RaiseOnFocus: no event socket at %s\n' "$socket" >&2
    exit 1
fi

# Gap from the monitor edge, matching the borders/gaps used elsewhere.
INSET=6
# How far each newly opened window steps down from the last.
CASCADE_STEP=38
# Steps before the cascade wraps back to the starting corner.
CASCADE_STEPS=6
# The main screen and the secondary screen, matching the monitor rules in
# ~/.config/hypr/monitors.conf.
MAIN_MON="HDMI-A-1" # Samsung LS24AG30x — the main screen
PANEL_MON="eDP-1"   # ThinkPad panel — the secondary screen
# Where the cascade has got to. The event loop below runs in this shell (not
# in a pipeline subshell), so this persists between events.
cascade_slot=0

raise_focused() {
    local info
    info="$(hyprctl activewindow -j 2>/dev/null)" || return 0
    # An empty reply means nothing is focused (all windows closed, etc).
    [ -n "$info" ] || return 0
    [ "$(jq -r '.floating // false' <<<"$info")" = "true" ] || return 0
    hyprctl dispatch bringactivetotop >/dev/null 2>&1
}

# Walk a newly opened floating window down the cascade. Only windows that
# landed unpositioned are touched: an app that placed itself (a centred
# dialog, a window with a remembered position) has picked its own spot and is
# left exactly where it asked to be.
cascade_new() {
    local win mon wx wy ww wh mx my mw mh rl rt rb
    local nx ny corner_x corner_y centre_x centre_y
    # payload is "address,workspace,class,title" — the address is first out of
    # the comma-separated fields, but a class or title may itself contain one.
    local addr="${1%%,*}"
    # The event socket reports the address without its 0x prefix
    # ("openwindow>>61291ea9e220,2,kitty,sleep") while hyprctl reports, and its
    # selectors require, the 0x form. Normalise rather than trusting either.
    case "$addr" in
    0x*) ;;
    [0-9a-fA-F]*) addr="0x$addr" ;;
    *) return 0 ;;
    esac

    # openwindow fires at map time; give the client a moment to settle and
    # report its real geometry.
    sleep 0.15

    win="$(hyprctl clients -j 2>/dev/null \
        | jq -rc --arg a "$addr" '[.[] | select(.address == $a)][0] // empty')"
    [ -n "$win" ] || return 0
    [ "$(jq -r '.floating // false' <<<"$win")" = "true" ] || return 0

    mon="$(hyprctl monitors -j 2>/dev/null \
        | jq -rc --argjson i "$(jq -r '.monitor // -1' <<<"$win")" '.[] | select(.id == $i)')"
    [ -n "$mon" ] || return 0

    read -r wx wy ww wh < <(jq -r '"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' <<<"$win")
    read -r mx my mw mh < <(jq -r '"\(.x) \(.y) \(.width) \(.height)"' <<<"$mon")
    read -r rl rt rb < <(jq -r '"\(.reserved[0]) \(.reserved[1]) \(.reserved[2])"' <<<"$mon")

    # The two spots a window can land in when Hyprland placed it rather than
    # the app: the top-left of the work area, and (for any window whose size
    # came from a rule, which is every window here) the centre of the work
    # area. Anything sitting elsewhere positioned itself and is left alone.
    corner_x=$((mx + rl + INSET))
    corner_y=$((my + rt + INSET))
    centre_x=$((mx + (mw - ww) / 2))
    centre_y=$((my + rt + (mh - rt - rb - wh) / 2))

    near() { [ "$1" -le $(($2 + 3)) ] && [ "$1" -ge $(($2 - 3)) ]; }

    if [ "$wx" -ge $((mx + mw)) ] || [ $((wx + ww)) -le "$mx" ] ||
        [ "$wy" -ge $((my + mh)) ] || [ $((wy + wh)) -le "$my" ]; then
        # Landed completely outside its own monitor. XWayland apps manage this
        # by placing a dialog against stale screen geometry — FreeRDP's
        # certificate prompt was caught at 28551,25797, where no pointer can
        # ever reach it. Rescue it to the middle of its monitor rather than
        # leaving it stranded.
        nx=$((centre_x + cascade_slot * CASCADE_STEP))
        ny=$((centre_y + cascade_slot * CASCADE_STEP))
    elif near "$wx" "$corner_x" && near "$wy" "$corner_y"; then
        nx=$((wx + cascade_slot * CASCADE_STEP))
        ny=$((wy + cascade_slot * CASCADE_STEP))
    elif near "$wx" "$centre_x" && near "$wy" "$centre_y"; then
        # Step out from wherever it landed, so by design the first window is
        # not moved at all and the pile spreads from there.
        nx=$((wx + cascade_slot * CASCADE_STEP))
        ny=$((wy + cascade_slot * CASCADE_STEP))
    else
        # It positioned itself somewhere sane; leave it exactly there.
        return 0
    fi

    # Wrap rather than walk off the monitor.
    if [ $((nx + ww)) -gt $((mx + mw - INSET)) ] || [ $((ny + wh)) -gt $((my + mh - INSET)) ]; then
        cascade_slot=0
        nx=$wx
        ny=$wy
    fi

    if hyprctl dispatch movewindowpixel "exact $nx $ny,address:$addr" >/dev/null 2>&1; then
        cascade_slot=$(((cascade_slot + 1) % CASCADE_STEPS))
    fi
}

# Hold the two screens in the arrangement the config declares: the Samsung at
# the ORIGIN (it is the main screen) and the ThinkPad panel immediately to its
# RIGHT, which is where the panel physically sits and the side the pointer is
# expected to cross on.
#
# This has to run on hotplug because Hyprland does not re-evaluate the rules of
# a monitor that is already present. Measured both failure modes: disabling the
# Samsung left the panel parked off to one side instead of taking over as main,
# and re-adding it could leave both screens at the origin. Both strand windows
# where no pointer can reach them (a FreeRDP dialog was caught at 28551,25797).
#
# Only positions are ever changed — each screen keeps its own live mode and
# scale, so nothing here can silently cost the Samsung its 144Hz.
enforce_main_screen() {
    local mons main_x main_w main_mode panel_x panel_mode want_x
    # Give Hyprland a moment: these events fire while it is still finishing
    # the add/remove, and the answer must be read after it settles.
    sleep 0.4
    mons="$(hyprctl monitors -j 2>/dev/null)" || return 0
    [ -n "$mons" ] || return 0

    main_x="$(jq -r --arg n "$MAIN_MON" '[.[]|select(.name==$n)][0].x // empty' <<<"$mons")"
    panel_x="$(jq -r --arg n "$PANEL_MON" '[.[]|select(.name==$n)][0].x // empty' <<<"$mons")"
    [ -n "$panel_x" ] || return 0

    # Read the panel's mode before anything moves: only positions are ever set,
    # so each screen keeps the mode it already had and nothing here can drop the
    # Samsung's 144Hz. The main screen's mode is read further down, where it is
    # only reached when that screen exists — reading a missing monitor's
    # refreshRate makes jq error, which would put noise in the log on every
    # unplug, the exact moment this function matters most.
    panel_mode="$(jq -r --arg n "$PANEL_MON" '[.[]|select(.name==$n)][0] | "\(.width)x\(.height)@\(.refreshRate | round)"' <<<"$mons")"

    if [ -z "$main_x" ]; then
        # Main screen gone: the panel becomes the main screen and takes the
        # origin, so nothing that assumes 0,0 can land off-screen.
        [ "$panel_x" = 0 ] || hyprctl keyword monitor "$PANEL_MON, $panel_mode, 0x0, 1" >/dev/null 2>&1
        return 0
    fi

    # Both screens present. The panel belongs immediately to the right of the
    # main screen — its x is the main screen's measured width, so a different
    # resolution or scale cannot leave a gap or an overlap. Anything other than
    # that means Hyprland placed them itself after the hotplug and got it wrong.
    want_x="$(jq -r --arg n "$MAIN_MON" '[.[]|select(.name==$n)][0].width // empty' <<<"$mons")"
    if [ "$main_x" != 0 ] || [ "$panel_x" != "$want_x" ]; then
        main_mode="$(jq -r --arg n "$MAIN_MON" '[.[]|select(.name==$n)][0] | "\(.width)x\(.height)@\(.refreshRate | round)"' <<<"$mons")"
        hyprctl keyword monitor "$MAIN_MON, $main_mode, 0x0, 1" >/dev/null 2>&1
        hyprctl keyword monitor "$PANEL_MON, $panel_mode, ${want_x}x0, 1" >/dev/null 2>&1
    fi
}

# -U keeps socat one-way (socket -> stdout) so it can be read as a stream.
#
# A coproc rather than `socat ... | while read ...` for two reasons:
#   - the loop then runs in this shell, so the cascade counter survives
#     between events instead of living in a pipeline subshell;
#   - SOCAT_PID gives the trap something concrete to kill. Killing the script
#     on its own leaves socat orphaned and still holding the event socket
#     open, and the next start then finds it already connected.
# `exec` matters: without it SOCAT_PID is the subshell wrapping the command,
# and killing that leaves socat itself parentless and still holding the socket.
# With exec the subshell becomes socat, so SOCAT_PID is socat.
coproc SOCAT { exec socat -U - "UNIX-CONNECT:$socket"; }

# A plain `kill` sends SIGTERM, and bash does NOT run an EXIT trap for an
# untrapped signal — so the EXIT trap below would never fire and socat would
# be left orphaned again. Catch the signal and exit cleanly instead.
trap 'exit 0' TERM INT HUP
trap 'kill "$SOCAT_PID" 2>/dev/null; rm -f "$lock"' EXIT

while read -r event <&"${SOCAT[0]}"; do
    case "$event" in
    activewindow\>\>* | focusgained\>\>*) raise_focused ;;
    # openwindow payload: address,workspace,class,title
    openwindow\>\>*) cascade_new "${event#openwindow>>}" ;;
    # monitor hotplug — the payload is the monitor name, but everything is
    # re-read rather than trusted, so the name is not used.
    monitoradded\>\>* | monitorremoved\>\>*) enforce_main_screen ;;
    esac
done
