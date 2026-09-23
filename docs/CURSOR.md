# Shared cursor behavior

hyprdesk uses **Bibata Modern Ice** at size **24** everywhere it can:

- Hyprland uses `HYPRCURSOR_THEME` and `HYPRCURSOR_SIZE`.
- GTK, Waybar, Rofi, SwayNC, the dock, and other client applications use
  `XCURSOR_THEME` and `XCURSOR_SIZE`.
- GTK’s saved desktop preference is set to the same theme and size.
- The session’s D-Bus and systemd user environments receive all four values,
  so user services and newly launched applications inherit them.

`config/hypr/scripts/ApplyCursorTheme.sh` is the single synchronization helper.
It runs at session start. The package installer invokes it with `--restart` to
refresh Waybar and SwayNC immediately; the app drawer exports the same values
when it launches Rofi.

## Change the cursor theme

Install both the XCursor and Hyprcursor form of the theme you want. Then change
all four settings together in `config/hypr/configs/ENVariables.conf` (or in the
installed `~/.config/hypr/configs/ENVariables.conf`):

```ini
env = HYPRCURSOR_THEME,Your-Theme
env = HYPRCURSOR_SIZE,24
env = XCURSOR_THEME,Your-Theme
env = XCURSOR_SIZE,24
```

Update `CURSOR_THEME` and `CURSOR_SIZE` at the top of
`config/hypr/scripts/ApplyCursorTheme.sh` to the identical values. Update the
explicit Waybar, SwayNC, AGS, dock, and Rofi launch entries in the same config
if you choose a different theme name. Log out and back in afterwards.

A hand cursor over a clickable control and a text cursor over a text field are
normal cursor *shapes*. This setup keeps their theme, size, and rendering style
consistent with the ordinary Hyprland pointer.
