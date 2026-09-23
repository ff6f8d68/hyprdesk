#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Unified glass — launchpad
#
# Single entry point for the app menu, so SUPER + D and the launcher button
# on nwg-dock behave identically. The rofi theme/config it loads come from
# ~/.config/rofi/config-glass-launchpad.rasi (glass, wallust-tinted), and the
# blur behind it is supplied by Hyprland:
#     layerrule = match:namespace rofi, blur on
# in ~/.config/hypr/UserConfigs/WindowRules.conf

set -euo pipefail

export HYPRCURSOR_THEME="Bibata-Modern-Ice"
export HYPRCURSOR_SIZE="24"
export XCURSOR_THEME="Bibata-Modern-Ice"
export XCURSOR_SIZE="24"


rofi_config="$HOME/.config/rofi/config-glass-launchpad.rasi"

# Toggle: invoking it again while the menu is open closes it
if pgrep -x rofi >/dev/null 2>&1; then
    pkill -x rofi
    exit 0
fi

exec rofi -show drun -config "$rofi_config" "$@"
