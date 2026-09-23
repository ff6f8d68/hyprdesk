#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  HEXGLASS — preview the greeter (now HTML exact clone via WebEngineView)
#  No sudo. Needs step 1 done (sddm installed). QML just hosts the HTML,
#  so --dev and installed are pixel-identical to sci_fi_welcome_screen(3).html
#  Usage:
#    bash preview.sh              # installed theme → sddm-greeter (WebEngine HTML)
#    bash preview.sh --dev        # source theme → sddm-greeter (WebEngine HTML) — exact clone
#    bash preview.sh --html       # HTML in Firefox (no SDDM, browser preview)
#    bash preview.sh --dev --html # compare: greeter + Firefox side-by-side
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_SRC="$SRC_DIR/hexglass"
THEME_DST=/usr/share/sddm/themes/hexglass
HTML_SRC="$SRC_DIR/hexglass_web.html"
HTML_DST="$THEME_DST/hexglass_web.html"

# parse flags (order independent)
DEV=0; HTML=0
for a in "$@"; do case "$a" in --dev) DEV=1;; --html|--web|--browser) HTML=1;; --help|-h) echo "Usage: $0 [--dev] [--html]"; echo "  --dev  use source theme in ~/.config (before reinstall)"; echo "  --html open hexglass_web.html exact clone in Firefox"; exit 0;; *) echo "unknown arg $a (try --help)"; exit 1;; esac; done

THEME=$THEME_DST
[[ $DEV -eq 1 ]] && THEME="$THEME_SRC"

HTML_FILE="$HTML_DST"
[[ $DEV -eq 1 ]] && HTML_FILE="$HTML_SRC"
# dev HTML may be at .. /hexglass_web.html, installed is theme dir — both exist
[[ -f "$HTML_FILE" ]] || HTML_FILE="$HTML_SRC"
[[ -f "$HTML_FILE" ]] || { echo "no HTML at $HTML_FILE"; exit 1; }

if [[ $HTML -eq 1 && $DEV -eq 0 ]]; then
    # HTML only
    if command -v firefox >/dev/null 2>&1; then
        echo "▸ opening HTML exact clone $HTML_FILE → Firefox (1920×1080)"
        # new window, 1920×1080, file:// — close FF window to exit
        firefox --new-window --window-size 1920,1080 "file://$HTML_FILE" &
        # also offer xdg-open fallback if snap firefox blocks --window-size
        sleep 1; echo "  (if window didn't appear, try: xdg-open file://$HTML_FILE )"
        wait $! 2>/dev/null || true
        exit 0
    else
        echo "firefox not found — falling back to xdg-open"
        xdg-open "file://$HTML_FILE"
        exit 0
    fi
fi

if [[ $HTML -eq 1 && $DEV -eq 1 ]]; then
    # compare mode: HTML in FF + QML greeter
    if command -v firefox >/dev/null 2>&1; then
        echo "▸ compare: HTML $HTML_FILE → Firefox + QML $THEME → sddm-greeter"
        firefox --new-window --window-size 1920,1080 "file://$HTML_FILE" &
        FF_PID=$!
        sleep 1
    else
        echo "firefox not found — opening HTML via xdg-open + QML"
        xdg-open "file://$HTML_FILE" &
        FF_PID=$!
    fi
    command -v sddm-greeter >/dev/null || { echo "sddm not installed — run: sudo bash $SRC_DIR/1-install-theme.sh"; exit 1; }
    echo "▸ previewing QML $THEME  (close greeter window to exit; FF stays open)"
    sddm-greeter --test-mode --theme "$THEME"
    echo "  QML closed — FF PID $FF_PID still open (close FF window when done)"
    exit 0
fi

# QML only (default) — now HTML exact clone via WebEngineView, not approximation
command -v sddm-greeter >/dev/null || { echo "sddm not installed — run: sudo bash $SRC_DIR/1-install-theme.sh"; exit 1; }
echo "▸ previewing $THEME via WebEngineView (HTML exact clone, close window to exit; JS logs below)"
exec sddm-greeter --test-mode --theme "$THEME"
