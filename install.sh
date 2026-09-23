#!/usr/bin/env bash
# hyprdesk installer — copies configuration and never removes user files.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DRY_RUN=0
WALKTHROUGH=0
NO_GUI="${HYPRDESK_NO_GUI:-0}"

usage() {
    cat <<'TEXT'
hyprdesk

Usage: ./install.sh [--dry-run] [--walkthrough] [--no-gui] [--help]

Kitty is installed first (non-interactively), then hyprdesk opens its visual
walkthrough in Kitty when a graphical session is available.

Core files are copied to ~/.config. Neofetch and the hyprdesk SDDM login screen
are optional. Existing files are backed up and merged; this installer deletes
nothing.
TEXT
}

for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=1 ;;
        --walkthrough) WALKTHROUGH=1 ;;
        --no-gui) NO_GUI=1 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
    esac
done
if (( EUID == 0 )); then
    printf "Run ./install.sh as your normal desktop user, without sudo.\n" >&2
    printf "hyprdesk asks for sudo only when a package or system-wide SDDM change needs it.\n" >&2
    exit 1
fi


log()  { printf '\033[38;5;141m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[38;5;114m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[38;5;221m!\033[0m %s\n' "$*"; }
die()  { printf '\033[38;5;203m✗ %s\033[0m\n' "$*" >&2; exit 1; }

install_kitty_silently() {
    command -v kitty >/dev/null 2>&1 && return 0
    (( DRY_RUN )) && { log '[dry-run] would install Kitty first'; return 0; }

    local install_log="${TMPDIR:-/tmp}/hyprdesk-kitty-install.log"
    log 'Installing Kitty…'
    sudo -v
    if command -v apt-get >/dev/null 2>&1; then
        sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq >"$install_log" 2>&1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq kitty >>"$install_log" 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman --noconfirm --needed kitty >"$install_log" 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf -q install -y kitty >"$install_log" 2>&1
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper --non-interactive --quiet install kitty >"$install_log" 2>&1
    else
        die 'No supported package manager found. Install Kitty, then run this script again.'
    fi
    command -v kitty >/dev/null 2>&1 || {
        tail -30 "$install_log" >&2 || true
        die "Kitty installation failed; details are in $install_log"
    }
}

show_brand() {
    clear 2>/dev/null || true
    if command -v kitty >/dev/null 2>&1 && [[ -f "$ROOT/assets/hyprdesk.png" ]]; then
        kitty +kitten icat --align center --place 84x10@0x0 "$ROOT/assets/hyprdesk.png" 2>/dev/null || true
        printf '\n\n\n\n\n\n\n\n\n\n'
    fi
    printf '\033[1;38;5;219m          hyprdesk\033[0m\n'
    printf '\033[38;5;147m  Hyprland configuration walkthrough\033[0m\n\n'
}

ask() {
    local question="$1" default="$2" answer
    while true; do
        if [[ "$default" == y ]]; then
            read -r -p "$question [Y/n] " answer || answer=""
            answer="${answer:-y}"
        else
            read -r -p "$question [y/N] " answer || answer=""
            answer="${answer:-n}"
        fi
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) warn 'Please answer y or n.' ;;
        esac
    done
}

replace_path_tokens() {
    local destination="$1"
    (( DRY_RUN )) && return 0
    grep -rlZ '@HYPRDESK_HOME@' "$destination" 2>/dev/null |
        xargs -0r sed -i "s|@HYPRDESK_HOME@|$HOME|g" || true
}

backup_and_merge() {
    local name source destination
    name="$1"
    source="$2"
    destination="$CONFIG_HOME/$name"
    [[ -d "$source" ]] || die "Missing package component: $source"
    if [[ -e "$destination" && ! -e "$BACKUP_DIR/$name" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$destination" "$BACKUP_DIR/$name"
    fi
    if (( DRY_RUN )); then
        log "[dry-run] would merge config/$name into $destination"
    else
        mkdir -p "$destination"
        cp -a "$source/." "$destination/"
        replace_path_tokens "$destination"
        ok "Installed ~/.config/$name"
    fi
}

install_core() {
    local component
    log 'Copying the core Hyprland desktop configuration'
    for component in hypr kitty waybar rofi swaync wallust nwg-dock-hyprland ags ghostty; do
        backup_and_merge "$component" "$ROOT/config/$component"
    done
}

install_neofetch() {
    log 'Copying the optional Neofetch profile and hyprdesk image'
    backup_and_merge neofetch "$ROOT/optional/neofetch"
}

install_sddm_packages() {
    local install_log="${TMPDIR:-/tmp}/hyprdesk-sddm-install.log"
    (( DRY_RUN )) && { log '[dry-run] would install SDDM and its Qt dependencies'; return 0; }
    log 'Installing SDDM dependencies; your active display manager stays unchanged'
    sudo -v
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' 'gdm3 shared/default-x-display-manager select gdm3' | sudo debconf-set-selections
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            sddm qml-module-qtgraphicaleffects qml-module-qtquick-controls2 \
            qml-module-qtquick-layouts qml-module-qtquick-window2 qmlscene \
            qml-module-qtwebengine qml-module-qtwebchannel qml-module-qtwebview >"$install_log" 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman --noconfirm --needed sddm qt5-declarative qt5-graphicaleffects \
            qt5-quickcontrols2 qt5-webengine qt5-webchannel >"$install_log" 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf -q install -y sddm qt5-qtgraphicaleffects qt5-qtquickcontrols2 \
            qt5-qtwebengine qt5-qtwebchannel >"$install_log" 2>&1
    else
        die 'Automatic SDDM installation supports apt, pacman, and dnf.'
    fi
}

install_sddm_theme() {
    local source="$ROOT/optional/sddm" theme_dst=/usr/share/sddm/themes/hyprdesk
    install_sddm_packages
    if (( DRY_RUN )); then
        log "[dry-run] would install the hyprdesk SDDM theme into $theme_dst"
        return 0
    fi
    log 'Installing the hyprdesk SDDM theme'
    sudo install -d "$theme_dst/fonts" /etc/sddm.conf.d /usr/local/share/fonts/hyprdesk
    sudo install -m 644 "$source/hexglass/Main.qml" "$theme_dst/Main.qml"
    sudo install -m 644 "$source/hexglass/HexCombo.qml" "$theme_dst/HexCombo.qml"
    sudo install -m 644 "$source/hexglass/metadata.desktop" "$theme_dst/metadata.desktop"
    sudo install -m 644 "$source/hexglass/theme.conf" "$theme_dst/theme.conf"
    sudo install -m 644 "$source/hexglass/fonts/Anurati_Regular.otf" "$theme_dst/fonts/Anurati_Regular.otf"
    sudo install -m 644 "$source/hexglass/fonts/Snasm_Light.otf" "$theme_dst/fonts/Snasm_Light.otf"
    sudo install -m 644 "$source/hyprdesk_web.html" "$theme_dst/hyprdesk_web.html"
    sudo install -m 644 "$source/hexglass/fonts/Anurati_Regular.otf" /usr/local/share/fonts/hyprdesk/Anurati_Regular.otf
    sudo install -m 644 "$source/hexglass/fonts/Snasm_Light.otf" /usr/local/share/fonts/hyprdesk/Snasm_Light.otf
    printf '[Theme]\nCurrent=hyprdesk\n' | sudo tee /etc/sddm.conf.d/hyprdesk.conf >/dev/null
    sudo fc-cache -f >/dev/null || true
    if ! bash "$source/preflight.sh" "$theme_dst"; then
        die 'The SDDM theme did not pass preflight. GDM has not been changed.'
    fi
    ok 'The hyprdesk SDDM theme is installed; your current display manager is still active.'
}

switch_to_sddm() {
    (( DRY_RUN )) && { log '[dry-run] would enable SDDM and disable GDM for the next boot'; return 0; }
    [[ -f /usr/share/sddm/themes/hyprdesk/Main.qml ]] || die 'The hyprdesk SDDM theme is not installed.'
    if ! bash "$ROOT/optional/sddm/preflight.sh" /usr/share/sddm/themes/hyprdesk; then
        die 'Preflight failed. GDM has not been changed.'
    fi
    sudo -v
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' 'sddm shared/default-x-display-manager select sddm' | sudo debconf-set-selections
        printf '%s\n' /usr/bin/sddm | sudo tee /etc/X11/default-display-manager >/dev/null
        sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure sddm
    fi
    sudo systemctl disable gdm gdm3 >/dev/null 2>&1 || true
    sudo systemctl enable sddm
    ok 'SDDM will be used on your next logout or reboot. Do not restart the display manager inside Hyprland.'
}

launch_walkthrough() {
    if (( WALKTHROUGH )) || [[ "$NO_GUI" == 1 ]] || [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        return 0
    fi
    if (( DRY_RUN )); then
        exec kitty --title hyprdesk --class hyprdesk-installer --override background='#0a0715' \
            --override foreground='#f5efff' --override cursor='#c9a7ff' \
            -e bash "$ROOT/install.sh" --walkthrough --dry-run
    else
        exec kitty --title hyprdesk --class hyprdesk-installer --override background='#0a0715' \
            --override foreground='#f5efff' --override cursor='#c9a7ff' \
            -e bash "$ROOT/install.sh" --walkthrough
    fi
}

main() {
    install_kitty_silently
    launch_walkthrough
    BACKUP_DIR="$CONFIG_HOME/hyprdesk-backups/$(date +%Y%m%d-%H%M%S)"
    show_brand
    printf 'This installer copies packaged files into ~/.config and backs up every existing\n'
    printf 'target it touches. It never removes originals.\n\n'

    if ask 'Install the core Hyprland, Kitty, Waybar, Rofi, SwayNC, Wallust, dock, AGS, and Ghostty configs?' y; then
        install_core
        if (( DRY_RUN )); then
            log "[dry-run] would apply the shared Bibata cursor to this session"
        else
            bash "$CONFIG_HOME/hypr/scripts/ApplyCursorTheme.sh" --restart || warn "Cursor refresh will complete at the next login."
        fi
    else
        warn 'Core configuration skipped.'
    fi
    printf '\n'
    if ask 'Install the optional Neofetch profile and hyprdesk image?' n; then
        install_neofetch
    else
        log 'Neofetch skipped.'
    fi
    printf '\n'
    if ask 'Install the optional hyprdesk SDDM theme (without switching away from GDM)?' n; then
        install_sddm_theme
        printf '\n'
        if ask 'Switch GDM to SDDM for the next boot now?' n; then
            switch_to_sddm
        else
            log 'GDM remains active. You can enable SDDM later from this package.'
        fi
    else
        log 'SDDM skipped; GDM remains untouched.'
    fi
    printf '\n'
    ok 'hyprdesk walkthrough complete.'
    (( DRY_RUN )) || printf 'Backups (when needed): %s\n' "$BACKUP_DIR"
}

main
