#!/usr/bin/env bash
# BuildHyprbars — build the hyprbars plugin and load it into the running session.
#
# Hyprland plugins are C++ shared objects compiled against one exact Hyprland
# ABI, so they cannot be shipped prebuilt for an arbitrary install: the
# `hyprland-plugins` package in the PPA is built for hyprland-unstable 0.53.0
# and hard-depends on it, which would replace the 0.56.x that is actually
# running. Building against the headers of the *installed* Hyprland is what
# makes the ABI match.
#
#   BuildHyprbars.sh           build, install, and load into the running session
#   BuildHyprbars.sh --build   build and install only, do not touch the session
#
# Run this again after every Hyprland upgrade: the ABI moves with it and the
# old .so will be refused at load. Override the source tag if a future release
# needs it — HYPRBARS_TAG=v0.57.0 ./BuildHyprbars.sh
#
# Build dependencies (apt, one-off) — `hyprland-plugin-deps` is the PPA's own
# meta package for this job, so it is used rather than a hand-picked subset: an
# earlier hand-picked list got pkg-config to resolve but still died several
# files into the compile, because glslang-dev was missing as well.
# g++-14 is required on top of it: Hyprland's macros.hpp includes <print>
# unconditionally and Ubuntu 24.04's default g++ 13 has no <print> at all.
#
#   sudo apt install hyprland-plugin-deps g++-14

set -euo pipefail

# hyprland-plugins tags track Hyprland releases and patch releases keep the
# same plugin API, so the 0.56.0 tag is the right source for a 0.56.x Hyprland.
TAG="${HYPRBARS_TAG:-v0.56.0}"

SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/hyprland-plugins"
SRC="$SHARE/src"
SO="$SHARE/hyprbars.so"

build_only=0
[ "${1:-}" = "--build" ] && build_only=1

say() { printf 'BuildHyprbars: %s\n' "$*"; }
die() {
    printf 'BuildHyprbars: %s\n' "$*" >&2
    exit 1
}

# 1a. Headers. Without them pkg-config cannot answer for `hyprland` and the
#     compile dies in a wall of missing includes instead.
if ! pkg-config --exists hyprland 2>/dev/null; then
    die "pkg-config cannot find the Hyprland headers.
Install the build dependencies first, then run this again:

  sudo apt install hyprland-plugin-deps g++-14"
fi

# 1b. Compiler. Hyprland's macros.hpp includes <print> unconditionally, so the
#     compiler must ship a C++23 standard library. Testing for the header is
#     the only honest check — a version number would not catch a g++ that has
#     the C++23 language mode but a libstdc++ without <print>, which is exactly
#     the case here (g++ 13 compiles -std=c++2b fine and then cannot find it).
hascxx23print() {
    printf '#include <print>\nint main(){}\n' |
        "$1" -std=c++2b -fsyntax-only -x c++ - >/dev/null 2>&1
}

pick_cxx() {
    local c
    # HYPRBARS_CXX overrides; then newest-first, so a future g++-15 is used
    # without an edit here.
    for c in "${HYPRBARS_CXX:-}" g++-15 g++-14 g++-13 g++ clang++; do
        [ -n "$c" ] || continue
        command -v "$c" >/dev/null 2>&1 || continue
        if hascxx23print "$c"; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

CXX_CHOSEN="$(pick_cxx)" || die "no compiler with a C++23 <print> was found.
Default g++ is $(g++ --version 2>/dev/null | head -1).
Install one, then run this again:

  sudo apt install g++-14

(Or point HYPRBARS_CXX at a compiler you already have.)"

# 2. Source: shallow clone of the tag, reused on later runs.
if [ -d "$SRC/.git" ]; then
    say "updating $SRC to $TAG"
    git -C "$SRC" fetch --depth 1 origin "tag" "$TAG" >/dev/null 2>&1 || true
    git -C "$SRC" checkout -q "tags/$TAG" 2>/dev/null || true
else
    mkdir -p "$(dirname "$SRC")"
    say "cloning hyprland-plugins at $TAG"
    git clone --depth 1 --branch "$TAG" \
        https://github.com/hyprwm/hyprland-plugins "$SRC" >/dev/null 2>&1
fi

# 3. Build. Both CXX and EXTRA_FLAGS are passed explicitly. The Makefile only
#    derives --no-gnu-unique when CXX is the literal string `g++`, so choosing
#    g++-14 would silently drop it — and that flag matters: without it gcc's
#    unique symbols can crash a plugin host.
#
#    INCLUDES is also passed explicitly, with more modules than the Makefile
#    asks for. `hyprland.pc` does NOT declare Hyprland's internal header
#    dependencies — its Requires omits them — yet its headers include them:
#    config/lua/LuaBindings.hpp pulls in lua.h, and without that module on the
#    include path the build dies with `fatal error: lua.h: No such file or
#    directory`. The extras below are the ones this header set needs. A module
#    that is not installed is dropped rather than failing the build, so a
#    release that stops shipping one does not break this script.
PKGS_CORE="pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon"
PKGS_EXTRA="lua5.4 lcms2 re2 muparser tomlplusplus hyprwire"
PKGS=""
for m in $PKGS_CORE $PKGS_EXTRA; do
    pkg-config --exists "$m" 2>/dev/null && PKGS="$PKGS $m"
done
INCLUDES="$(pkg-config --cflags $PKGS)"

say "building hyprbars against hyprland $(pkg-config --modversion hyprland) with $CXX_CHOSEN"
make -C "$SRC/hyprbars" clean >/dev/null 2>&1 || true
make -C "$SRC/hyprbars" -j"$(nproc)" CXX="$CXX_CHOSEN" EXTRA_FLAGS=--no-gnu-unique INCLUDES="$INCLUDES"

# 4. Install into the home directory — no root involved from here on.
mkdir -p "$SHARE"
install -m 644 "$SRC/hyprbars/hyprbars.so" "$SO"
say "installed $SO"

# 5. Load. Unload first, because loading over an already-loaded plugin is
#    refused — and a rebuild is exactly when you want the new one in.
if [ "$build_only" = 0 ]; then
    if ! command -v hyprctl >/dev/null 2>&1 || ! hyprctl version >/dev/null 2>&1; then
        say "no running Hyprland session to load into; it loads at next login"
        exit 0
    fi
    hyprctl plugin unload "$SO" >/dev/null 2>&1 || true
    if ! out="$(hyprctl plugin load "$SO" 2>&1)" || printf '%s' "$out" | grep -qiE 'error|failed|invalid'; then
        die "Hyprland refused the plugin:
  $out
Usually an ABI mismatch after a Hyprland upgrade. If it has moved on, set
HYPRBARS_TAG to the matching hyprland-plugins tag and re-run."
    fi
    say "loaded into the running session"
    hyprctl plugin list
fi
