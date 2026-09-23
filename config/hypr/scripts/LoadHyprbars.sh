#!/usr/bin/env bash
# LoadHyprbars — load the hyprbars plugin into the session and apply its rules.
#
# Run at login from Startup_Apps.conf. Does nothing at all when the plugin has
# not been built, so this is safe to leave in the autostart list permanently.
#
#   ./LoadHyprbars.sh          load and apply rules
#   ./LoadHyprbars.sh --quiet  same, but only report problems
#
# Why the rules are applied here instead of living in WindowRules.conf:
# `hyprbars:no_bar` is a field the plugin registers when it initialises, and
# Hyprland validates rule fields at parse time — a rule naming it while the
# plugin is absent is a hard config error ("invalid field type hyprbars:no_bar",
# verified). exec-once also runs *after* the config is parsed, so even with the
# plugin installed those rules could never be picked up from the config at
# login. Applying them with `hyprctl keyword` right after the load is the only
# point at which they are both valid and effective.
#
# hyprbars decorates every window it is handed and has no popup or dialog
# filtering of its own, and this session force-floats everything, so without
# these rules every modal prompt would grow a titlebar too.

set -uo pipefail

SO="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-plugins/hyprbars.so"

quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1
say() { [ "$quiet" = 1 ] || printf 'LoadHyprbars: %s\n' "$*"; }

# Nothing to do on a session where the plugin was never built. Staying silent
# here is deliberate: this runs at every login and a missing plugin is an
# expected state, not a fault.
[ -f "$SO" ] || exit 0

command -v hyprctl >/dev/null 2>&1 || exit 0
hyprctl version >/dev/null 2>&1 || exit 0

# Already loaded? Loading a second time is refused, so check rather than spam
# the log with an error at every restart of this script.
#
# Match the plugin's NAME line, not the path: `hyprctl plugin list` prints
# "Plugin hyprbars by Vaxry:" plus a handle/version/description, and the .so
# path appears nowhere in it (verified — a grep for the filename matches zero
# lines), so a path-based guard silently re-loads on every run.
if hyprctl plugin list 2>/dev/null | grep -q 'Plugin hyprbars'; then
    say "already loaded"
else
    if ! out="$(hyprctl plugin load "$SO" 2>&1)"; then
        printf 'LoadHyprbars: could not load %s:\n  %s\n' "$SO" "$out" >&2
        printf 'LoadHyprbars: rebuild it with BuildHyprbars.sh (an ABI mismatch after a Hyprland upgrade looks exactly like this).\n' >&2
        exit 1
    fi
    say "loaded $SO"
fi

# windowrule is a `keyword`, so each line becomes a dynamic rule. Dynamic rules
# survive `hyprctl reload` (measured), so a later reload will not silently drop
# these — and this script re-applies them on every login regardless.
apply() {
    local rule="$1"
    if ! out="$(hyprctl keyword windowrule "$rule" 2>&1)"; then
        printf 'LoadHyprbars: rule rejected: %s\n  %s\n' "$rule" "$out" >&2
        return 1
    fi
    say "rule applied: $rule"
}

# Modal prompts — certificate dialogs, file choosers, "are you sure" boxes.
# A titlebar on these is chrome with nowhere to drag them from.
apply 'match:modal true, hyprbars:no_bar true'

# Portals and simple dialogs, which also have no business being dragged around.
apply 'match:class ^(xdg-desktop-portal.*|zenity|hyprland-share-picker)$, hyprbars:no_bar true'
