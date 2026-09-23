#!/usr/bin/env bash
# Keep Hyprland, GTK clients, and user services on one cursor theme.
set -Eeuo pipefail

CURSOR_THEME="Bibata-Modern-Ice"
CURSOR_SIZE="24"
RESTART_SERVICES=0

case "${1:-}" in
    '') ;;
    --restart) RESTART_SERVICES=1 ;;
    --help|-h)
        printf 'Usage: %s [--restart]\n' "${0##*/}"
        exit 0
        ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

export HYPRCURSOR_THEME="$CURSOR_THEME"
export HYPRCURSOR_SIZE="$CURSOR_SIZE"
export XCURSOR_THEME="$CURSOR_THEME"
export XCURSOR_SIZE="$CURSOR_SIZE"

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2>/dev/null || true
fi

dbus-update-activation-environment --systemd \
    HYPRCURSOR_THEME HYPRCURSOR_SIZE XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true
systemctl --user import-environment \
    HYPRCURSOR_THEME HYPRCURSOR_SIZE XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true

launch_in_session() {
    local program="$1"
    local command="env HYPRCURSOR_THEME=$CURSOR_THEME HYPRCURSOR_SIZE=$CURSOR_SIZE XCURSOR_THEME=$CURSOR_THEME XCURSOR_SIZE=$CURSOR_SIZE $program"
    if command -v hyprctl >/dev/null 2>&1 && hyprctl dispatch exec "$command" >/dev/null 2>&1; then
        return 0
    fi
    nohup env HYPRCURSOR_THEME="$CURSOR_THEME" HYPRCURSOR_SIZE="$CURSOR_SIZE" \
        XCURSOR_THEME="$CURSOR_THEME" XCURSOR_SIZE="$CURSOR_SIZE" "$program" >/dev/null 2>&1 &
}

if (( RESTART_SERVICES )); then
    pkill -x waybar 2>/dev/null || true
    pkill -x swaync 2>/dev/null || true
    command -v waybar >/dev/null 2>&1 && launch_in_session waybar
    command -v swaync >/dev/null 2>&1 && launch_in_session swaync
fi
