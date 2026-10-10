#!/bin/bash
# Helpers for Meridian's Homebrew cask (Casks/meridian.rb in tpak/homebrew-tpak).
#
# Sourced by release.sh, which rewrites the cask on every stable release, and by
# check_system_requirements.sh. Defines functions only, so it is safe to source.

# Homebrew names macOS releases by symbol, not by number, so the cask's
# `depends_on macos:` line can't be written from LSMinimumSystemVersion as-is.
# Print Homebrew's name for a macOS version ("26.0" → "tahoe"); print nothing
# and return 1 for a release this table doesn't know. The names are the keys of
# MacOSVersion::SYMBOLS in Homebrew's Library/Homebrew/macos_version.rb —
# check_system_requirements.sh asks Homebrew to confirm the one in use.
homebrew_macos_symbol() {
    case "${1%%.*}" in
        13) echo "ventura" ;;
        14) echo "sonoma" ;;
        15) echo "sequoia" ;;
        26) echo "tahoe" ;;
        27) echo "golden_gate" ;;
        *)  return 1 ;;
    esac
}

# Rewrite the Homebrew cask (stdin → stdout) for a new release: its version,
# the zip's checksum, and the oldest macOS Homebrew will install it on. A bare
# symbol is how Homebrew spells "this release or newer"; the quoted
# ">= :name" spelling it replaces is deprecated. Only the value of a real
# `depends_on macos:` stanza is swapped, so anything else on that line survives
# and a commented-out one is left alone.
render_cask() {
    local version="$1" sha256="$2" macos_symbol="$3"
    sed -E \
        -e "s/version \".*\"/version \"$version\"/" \
        -e "s/sha256 \".*\"/sha256 \"$sha256\"/" \
        -e "s/^([[:space:]]*depends_on macos: )(:[a-z_]+|\"[^\"]*\")/\1:$macos_symbol/"
}

# Say what is wrong with a cask's requirement stanzas (stdin), one problem per
# line; print nothing when Homebrew will install it only where Meridian runs —
# the given macOS release or newer, on Apple silicon. Meridian ships an
# arm64-only binary, which is also why the appcast says hardwareRequirements
# arm64.
cask_requirement_problems() {
    local macos_symbol="$1" cask
    cask="$(cat)"
    if ! grep -qE "^[[:space:]]*depends_on macos: :${macos_symbol}([^a-z_0-9]|\$)" <<< "$cask"; then
        echo "no 'depends_on macos: :$macos_symbol' line"
    fi
    if ! grep -qE "^[[:space:]]*depends_on arch: :arm64([^a-z_0-9]|\$)" <<< "$cask"; then
        echo "no 'depends_on arch: :arm64' line"
    fi
}
