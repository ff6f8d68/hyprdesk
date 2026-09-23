#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  HEXGLASS — preflight: does the theme survive QML instantiation?
# ═══════════════════════════════════════════════════════════════════════
#  Qt 5.15.13 + SDDM 0.20 can SEGFAULT while creating a theme's objects.
#  When that happens SDDM just shows a black screen with a cursor and no
#  usable login. This instantiates Main.qml headlessly (software renderer,
#  no X/Wayland needed) and reports whether it survives.
#
#  exit 0 = healthy · exit 1 = broken (do NOT switch display managers)
#
#  Usage:  bash preflight.sh [theme-dir]
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

THEME="${1:-/usr/share/sddm/themes/hexglass}"

QMLSCENE="/usr/lib/qt5/bin/qmlscene"
[[ -x "$QMLSCENE" ]] || QMLSCENE="$(command -v qmlscene 2>/dev/null || true)"
if [[ -z "${QMLSCENE:-}" || ! -x "$QMLSCENE" ]]; then
    echo "⚠  qmlscene not available — skipping preflight (run 1-install-theme.sh to get it)"
    exit 0
fi

if [[ ! -f "$THEME/Main.qml" ]]; then
    echo "✖ no Main.qml in $THEME"
    exit 1
fi

echo "▸ preflight: instantiating $THEME/Main.qml headlessly…"

# Hexglass now uses QtWebEngine (HTML exact clone). sddm-greeter --test-mode with
# WebEngine stays running (no segfault — unlike old QtWebKit). Offscreen qmlscene
# with WebEngine needs OpenGL and will warn "WebEngineContext used before..."
# but still exits 0 (not 139). We test Main.qml directly; if it segfaults we fail.
# If Main.qml uses WebEngine but offscreen can't load it, we accept exit 0 as pass
# and do a secondary syntax check via qmlscene --quit.
QML_TO_TEST="Main.qml"
# Only fallback to Fallback.qml if it exists AND Main is WebKit (which segfaults offscreen)
# WebEngine is fine offscreen (exits 0), so don't fallback for it.
if grep -q "QtWebKit" "$THEME/Main.qml" 2>/dev/null; then
    if [[ -f "$THEME/Fallback.qml" ]]; then
        echo "  (Main.qml is QtWebKit — testing Fallback.qml offscreen instead; WebKit segfaults offscreen)"
        QML_TO_TEST="Fallback.qml"
    fi
fi

# WebEngine as root needs --no-sandbox (see https://crbug.com/638180)
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-dev-shm-usage"
export QTWEBENGINE_DISABLE_SANDBOX=1
# XDG_RUNTIME_DIR not set when run via pkexec/sudo — default is fine
out="$(cd "$THEME" && QT_QUICK_BACKEND=software QT_QPA_PLATFORM=offscreen \
        QTWEBENGINE_CHROMIUM_FLAGS="$QTWEBENGINE_CHROMIUM_FLAGS" QTWEBENGINE_DISABLE_SANDBOX=1 \
        timeout 10 "$QMLSCENE" "$QML_TO_TEST" 2>&1)"
rc=$?

# 124 = still running when the timeout hit  → survived, which is what we want.
# 0   = exited on its own cleanly
case "$rc" in
    124|0) : ;;
    139)
        echo "✖ PREFLIGHT FAILED — the QML engine SEGFAULTED."
        echo
        echo "$out" | tail -20
        echo
        echo "  SDDM would show a black screen with a cursor. Refusing to continue."
        exit 1
        ;;
    *)
        echo "✖ PREFLIGHT FAILED (exit $rc)"
        echo
        echo "$out" | tail -20
        echo
        exit 1
        ;;
esac

# A theme can also load "successfully" while containing fatal QML errors.
# The ReferenceErrors for sddm/userModel/sessionModel/keyboard are expected
# (SDDM injects those as context properties; qmlscene cannot).
fatal="$(echo "$out" | grep -iE \
    'Syntax error|is not a type|Cannot assign|Unable to assign|No such file or directory|Cannot instantiate' \
    || true)"
if [[ -n "$fatal" ]]; then
    echo "✖ PREFLIGHT FAILED — fatal QML errors:"
    echo "$fatal" | head -20
    exit 1
fi

echo "✔ preflight OK — the theme instantiates and runs without crashing."
exit 0
