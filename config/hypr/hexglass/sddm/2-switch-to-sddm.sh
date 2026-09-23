#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  HEXGLASS — step 2/3: make SDDM the login screen (GDM stays installed).
#  Takes effect at next reboot / logout. Revert with 3-revert-to-gdm.sh.
#  Usage:  sudo bash ~/.config/hypr/hexglass/sddm/2-switch-to-sddm.sh
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

[[ -f /usr/share/sddm/themes/hexglass/Main.qml ]] || { echo "theme not installed — run 1-install-theme.sh first"; exit 1; }

# Final safety net: never hand the login screen to a theme that crashes the
# QML engine — that is exactly how you end up staring at a black screen.
if ! bash "$(dirname "${BASH_SOURCE[0]}")/preflight.sh" /usr/share/sddm/themes/hexglass; then
    echo "✖ refusing to switch: fix the theme first (see errors above)."
    echo "  GDM remains your display manager."
    exit 1
fi

echo "▸ setting sddm as default display manager"
echo "sddm shared/default-x-display-manager select sddm" | debconf-set-selections
echo "/usr/bin/sddm" > /etc/X11/default-display-manager
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure sddm

# Ubuntu routes display-manager.service via the file above; make the unit
# state match so there is no race with gdm at boot.
systemctl disable gdm3 >/dev/null 2>&1 || true
systemctl enable  sddm >/dev/null 2>&1 || true

echo
echo "✔ SDDM will start at next boot with the Hexglass theme."
echo "  Do NOT 'systemctl restart display-manager' from inside your session —"
echo "  that kills Hyprland. Log out or reboot instead."
echo "  Revert any time:  sudo bash $(dirname "${BASH_SOURCE[0]}")/3-revert-to-gdm.sh"
