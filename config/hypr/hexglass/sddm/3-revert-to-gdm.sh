#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  HEXGLASS — revert: GDM back as the login screen (sddm stays installed).
#  Usage:  sudo bash ~/.config/hypr/hexglass/sddm/3-revert-to-gdm.sh
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

echo "gdm3 shared/default-x-display-manager select gdm3" | debconf-set-selections
echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure gdm3
systemctl disable sddm >/dev/null 2>&1 || true
systemctl enable  gdm3 >/dev/null 2>&1 || true
echo "✔ GDM (with the Hexglass recolor) is the login screen again at next boot."
