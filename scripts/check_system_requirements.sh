#!/usr/bin/env bash
# Everything that states Meridian's system requirements must agree with the project.
#
# The requirement is set in one place — MACOSX_DEPLOYMENT_TARGET — and restated by hand in the
# README, the user manual, the docs landing page and CLAUDE.md, and by release.sh in the Homebrew
# cask, under Homebrew's *name* for the release (homebrew_macos_symbol in homebrew_cask.sh).
# Nothing tied those together, which is how the cask and the README went on saying "macOS 13"
# through three major versions of an app that needed 26: Homebrew installed Meridian on Macs
# where it then refused to launch.
#
# A standing invariant, like check_localization.sh. release.sh runs it before every stable
# release; run it yourself after changing the deployment target.
#
#   scripts/check_system_requirements.sh          # the repo agrees with itself
#   scripts/check_system_requirements.sh --cask   # ...and so does the published cask
#
# --cask reads Casks/meridian.rb from tpak/homebrew-tpak (needs gh and a network). The cask
# describes the *released* app, so it is only expected to match right after a release — which
# is why that half is opt-in rather than part of the default run.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# shellcheck source=scripts/homebrew_cask.sh
source scripts/homebrew_cask.sh

CHECK_CASK=0
if [[ "${1:-}" == "--cask" ]]; then
    CHECK_CASK=1
fi

FAILED=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=1; }
note() { printf '  \033[33m!\033[0m %s\n' "$1"; }

# ── The requirement itself ──────────────────────────────────────────
PBXPROJ="Meridian/Meridian.xcodeproj/project.pbxproj"
TARGETS="$(grep -Eo 'MACOSX_DEPLOYMENT_TARGET = [0-9.]+' "$PBXPROJ" | awk '{print $3}' | sort -u)"
if [[ -z "$TARGETS" || "$(grep -c . <<< "$TARGETS")" != 1 ]]; then
    bad "expected one MACOSX_DEPLOYMENT_TARGET across $PBXPROJ, found: $(tr '\n' ' ' <<< "$TARGETS")"
    exit 1
fi
TARGET="$TARGETS"
MAJOR="${TARGET%%.*}"
ok "deployment target is macOS $TARGET"

# ── The name release.sh will write into the cask ────────────────────
NAME=""
if NAME="$(homebrew_macos_symbol "$TARGET")"; then
    ok "the cask will be given 'depends_on macos: :$NAME'"
else
    bad "no Homebrew name for macOS $MAJOR — add it to homebrew_macos_symbol() in scripts/homebrew_cask.sh"
fi

# Homebrew can only require a whole release, so nothing here can close this gap — but it
# shouldn't pass in silence either. release.sh repeats it in the release summary.
POINT="${TARGET#*.}"
if [[ -n "$NAME" && "$TARGET" == *.* && "$POINT" =~ [1-9] ]]; then
    note "Homebrew can only require a whole release: the cask will still offer Meridian to macOS $MAJOR.0, though it needs $TARGET"
fi

# A name Homebrew doesn't know — a typo in the table — makes the cask fail to load for everyone,
# and release.sh can't tell: it would write the bad name and then find it. So ask Homebrew.
# Only a definite disagreement fails; being unable to ask is a note, not a blocker.
if [[ -n "$NAME" ]]; then
    if command -v brew >/dev/null 2>&1; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew ruby -e "
            begin
              exit(MacOSVersion.from_symbol(:$NAME).to_s == '$MAJOR' ? 0 : 3)
            rescue MacOSVersion::Error
              exit 4
            end" >/dev/null 2>&1
        case $? in
            0) ok "Homebrew agrees that :$NAME is macOS $MAJOR" ;;
            3) bad ":$NAME is not macOS $MAJOR to Homebrew — fix homebrew_macos_symbol() in scripts/homebrew_cask.sh" ;;
            4) bad "Homebrew has no macOS release called :$NAME — a cask using it won't load; fix scripts/homebrew_cask.sh" ;;
            *) note "couldn't ask Homebrew about :$NAME (brew ruby failed), so the name wasn't confirmed" ;;
        esac
    else
        note "Homebrew isn't installed here, so :$NAME wasn't confirmed against it"
    fi
fi

# ── The places that restate it by hand ──────────────────────────────
# A requirement sentence is one that says "requires"/"needs" and then names a macOS version.
for doc in README.md docs/manual.md docs/index.md CLAUDE.md; do
    STATED="$(grep -nE '\b([Rr]equires|[Nn]eeds)\b.*\bmacOS \*{0,2}[0-9]+' "$doc" || true)"
    if [[ -z "$STATED" ]]; then
        bad "$doc doesn't say which macOS Meridian requires"
        continue
    fi
    DOC_OK=1
    while IFS= read -r line; do
        lineno="${line%%:*}"
        said="$(grep -oE 'macOS \*{0,2}[0-9]+' <<< "$line" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')"
        if [[ "$said" != "$MAJOR " ]]; then
            bad "$doc:$lineno says macOS ${said% }, but the app requires macOS $MAJOR"
            DOC_OK=0
        fi
    done <<< "$STATED"

    # A doc that quotes the cask's own line has to quote the right name.
    if [[ -n "$NAME" ]]; then
        while IFS= read -r quoted; do
            [[ -z "$quoted" ]] && continue
            if [[ "${quoted##*: :}" != "$NAME" ]]; then
                bad "$doc:${quoted%%:*} quotes 'depends_on macos: :${quoted##*: :}', but the cask gets :$NAME"
                DOC_OK=0
            fi
        done <<< "$(grep -noE 'depends_on macos: :[a-z_]+' "$doc" || true)"
    fi

    if [[ $DOC_OK -eq 1 ]]; then
        ok "$doc states macOS $MAJOR"
    fi
done

# ── The published cask (opt-in) ─────────────────────────────────────
if [[ $CHECK_CASK -eq 1 && -n "$NAME" ]]; then
    CASK="$(gh api repos/tpak/homebrew-tpak/contents/Casks/meridian.rb --jq .content 2>/dev/null | base64 -d 2>/dev/null || true)"
    if [[ -z "$CASK" ]]; then
        bad "couldn't read Casks/meridian.rb from tpak/homebrew-tpak (--cask needs gh and a network)"
    else
        PROBLEMS="$(cask_requirement_problems "$NAME" <<< "$CASK")"
        if [[ -z "$PROBLEMS" ]]; then
            ok "the published cask installs only on macOS :$NAME or later, on Apple silicon"
        else
            while IFS= read -r problem; do
                bad "the published cask has $problem"
            done <<< "$PROBLEMS"
        fi
    fi
fi

if [[ $FAILED -ne 0 ]]; then
    printf '\n\033[31mSystem requirements are stated inconsistently.\033[0m The deployment target is the source of truth.\n'
    exit 1
fi
