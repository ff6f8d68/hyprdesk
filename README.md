# hyprdesk

hyprdesk is a cohesive Hyprland desktop profile: a dark glass workspace with a
consistent terminal, bar, launcher, notifications, dock, wallpaper palette,
and an optional custom login screen. It is designed to give a new Hyprland
installation a finished, usable desktop rather than a collection of unrelated
themes.

## What hyprdesk configures

- Hyprland behavior, keybinds, animations, lock screen, monitor profiles, and
  workspace rules.
- Kitty, Waybar, Rofi, SwayNC, Wallust, nwg-dock, AGS, and Ghostty styling.
- One cursor across the compositor and GTK/Wayland clients: **Bibata Modern
  Ice**, size **24**.
- An optional Neofetch profile with the hyprdesk image.
- An optional `hyprdesk` SDDM login theme. Changing GDM to SDDM is always a
  separate confirmation.

## Install

Run the installer from this directory:

Do **not** run the whole installer with `sudo`. It launches a Kitty walkthrough in your desktop session and requests sudo only for individual package or system-wide SDDM actions.

```bash
./install.sh
```

Kitty is installed first when it is missing. In a graphical session, the
installer then opens a branded walkthrough in Kitty. Choose the core desktop
profile, Neofetch, and SDDM independently. `./install.sh --dry-run --no-gui`
shows the decisions and destinations without changing anything.

The installer assumes Hyprland and the desktop programs above are already
available. It installs Kitty automatically; install any other missing desktop
program through your distribution’s package manager.

## Safety and updates

Before it merges a component into `~/.config`, the installer stores the current
component under `~/.config/hyprdesk-backups/<timestamp>`. It only copies and
updates files; it never removes files. Review the backup before manually
rolling anything back.

For setup details and optional components, see [docs/INSTALL.md](docs/INSTALL.md).
For cursor behavior and changing the shared cursor theme, see
[docs/CURSOR.md](docs/CURSOR.md).

## Layout

- `config/` — desktop configuration installed by the core choice.
- `optional/neofetch/` — the optional Neofetch profile and image.
- `optional/sddm/` — the optional SDDM theme and validation helper.
- `assets/` — hyprdesk artwork used by the installer.
