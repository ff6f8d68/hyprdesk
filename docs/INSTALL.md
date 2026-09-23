# Installing hyprdesk

## Before you begin

Start from a running Hyprland session if you want the graphical walkthrough.
The profile expects the usual Hyprland desktop tools: Waybar, Rofi, SwayNC,
Wallust, nwg-dock, AGS, and Ghostty. The installer does not install that whole
stack because distributions package it differently. It does install Kitty when
needed, using the detected package manager without package-manager prompts.

Do **not** prefix the installer with `sudo`. It uses your graphical session for the walkthrough and asks for elevation only when a package install or system-wide SDDM action requires it.

Run:

```bash
chmod +x install.sh
./install.sh
```

Use `--no-gui` to keep the walkthrough in the invoking terminal, or use
`--dry-run --no-gui` to inspect the plan without copying files or installing
packages.

## Core desktop choice

The core choice merges the contents of `config/` into the matching directories
inside `~/.config`. Existing directories are copied to a timestamped backup
first. The merge deliberately leaves files that are not part of hyprdesk in
place.

The installer also activates the shared cursor settings and restarts Waybar and
SwayNC so their cursor updates immediately. Rofi receives the same cursor
variables every time the app drawer opens.

## Optional Neofetch

Choose the Neofetch option to install its configuration and hyprdesk image to
`~/.config/neofetch`. It uses Kitty’s graphics protocol for the image, so Kitty
is required to display it as intended.

## Optional SDDM login screen

Selecting the SDDM option first installs SDDM and the Qt modules needed by its
login theme. The active login manager remains unchanged at that stage. The
installer places the theme at `/usr/share/sddm/themes/hyprdesk`, validates its
QML before proceeding, and only offers the GDM-to-SDDM switch after validation.

If you accept the switch, it takes effect after logout or reboot. Do not restart
the display manager from inside Hyprland: doing so ends the current session.
If the validation fails, the installer stops before changing the login manager.

## After installation

Log out and back in to start the entire profile cleanly. Most cursor changes
apply immediately, and Waybar/SwayNC are restarted by the installer. Use the
keybindings configured in Hyprland to open the launcher and inspect the
profile’s normal workflow.
