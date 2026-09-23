#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  HEXGLASS — step 1/3: install sddm + the theme. Does NOT switch DMs.
#  GDM keeps running until you run 2-switch-to-sddm.sh.
#  Usage:  sudo bash ~/.config/hypr/hexglass/sddm/1-install-theme.sh
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DST=/usr/share/sddm/themes/hexglass

echo "▸ installing sddm (universe) + QML deps"
# Pre-answer the "default display manager" debconf question with gdm3 so
# this step never flips the DM; step 2 does that deliberately.
echo "sddm shared/default-x-display-manager select gdm3" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    sddm qml-module-qtgraphicaleffects qml-module-qtquick-controls2 \
    qml-module-qtquick-layouts qml-module-qtquick-window2 qmlscene \
    qml-module-qtwebengine qml-module-qtwebchannel qml-module-qtwebview

echo "▸ installing theme → $THEME_DST"
rm -rf "$THEME_DST"
install -d "$THEME_DST/fonts"
install -m644 "$SRC/hexglass/Main.qml"         "$THEME_DST/"
# HexCombo/Fallback/WebView are legacy QML fallback — no longer used (HTML via WebEngine is exact clone)
# Keep for reference only if they exist, but don't fail if missing
install -m644 "$SRC/hexglass/HexCombo.qml"     "$THEME_DST/" 2>/dev/null || true
install -m644 "$SRC/hexglass_web.html"         "$THEME_DST/" 2>/dev/null || true
install -m644 "$SRC/hexglass/metadata.desktop" "$THEME_DST/"
install -m644 "$SRC/hexglass/theme.conf"       "$THEME_DST/"
install -m644 "$SRC/hexglass/fonts/"*.otf      "$THEME_DST/fonts/"

echo "▸ installing drop-in → /etc/sddm.conf.d/hexglass.conf"
install -d /etc/sddm.conf.d
install -m644 "$SRC/hexglass.conf" /etc/sddm.conf.d/hexglass.conf

# fonts system-wide too (sddm user can't read ~/.local/share/fonts)
install -d /usr/local/share/fonts/hexglass
install -m644 "$SRC/hexglass/fonts/"*.otf /usr/local/share/fonts/hexglass/
fc-cache -f >/dev/null

# make sure GDM is still the active DM after apt fiddled with things
if [[ "$(cat /etc/X11/default-display-manager 2>/dev/null)" != "/usr/sbin/gdm3" ]]; then
    echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
fi
# If sddm's postinst re-pointed display-manager.service at sddm, disabling it
# would leave NO display manager — so always re-enable gdm3 right after.
systemctl disable sddm >/dev/null 2>&1 || true
systemctl enable  gdm3 >/dev/null 2>&1 || true

# ── PREFLIGHT ────────────────────────────────────────────────────────
# Instantiate the theme headlessly. A segfault here means SDDM would show
# a black screen with a cursor, so stop before anyone flips the DM.
echo
if ! bash "$SRC/preflight.sh" "$THEME_DST"; then
    echo "✖ aborting: the theme did not survive preflight. GDM stays active."
    exit 1
fi

cat <<EOF

✔ done. GDM is still your display manager.

PREVIEW (as your normal user, no sudo — opens a window on your desktop):
    bash $SRC/preview.sh
    # or:  sddm-greeter --test-mode --theme $THEME_DST

When it looks right:
    sudo bash $SRC/2-switch-to-sddm.sh
EOF
