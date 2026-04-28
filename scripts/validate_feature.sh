#!/bin/bash
# Validates the Sparkle beta-channel feature (issue #98).
# Run from repo root. Exits non-zero if any check fails.
#
# Three groups of checks:
#   1. App-side wiring (UserDefaultKeys key, AppDelegate delegate, About toggle)
#   2. Release tooling (version regex, sparkle:channel injection, prerelease, cask skip)
#   3. Compilation (full xcodebuild)
set -u
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ok()   { echo "  OK:   $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $1"; }

# ── 1. App-side wiring ────────────────────────────────────────────────

section "App: UserDefaultKeys"
STRINGS_FILE="Meridian/Overall App/Strings.swift"
grep -q 'static let betaUpdatesEnabled' "$STRINGS_FILE" \
    && ok "betaUpdatesEnabled key declared in Strings.swift" \
    || bad "betaUpdatesEnabled key missing in Strings.swift"

section "App: AppDelegate Sparkle channel delegate"
APPDELEGATE="Meridian/AppDelegate.swift"
grep -qE 'func allowedChannels\(for[^)]*\) -> Set<String>' "$APPDELEGATE" \
    && ok "allowedChannels(for:) implemented in AppDelegate" \
    || bad "allowedChannels(for:) not implemented in AppDelegate"

grep -q 'UserDefaultKeys.betaUpdatesEnabled' "$APPDELEGATE" \
    && ok "AppDelegate reads UserDefaultKeys.betaUpdatesEnabled" \
    || bad "AppDelegate does not reference UserDefaultKeys.betaUpdatesEnabled"

grep -qE '"beta"' "$APPDELEGATE" \
    && ok "AppDelegate references the \"beta\" channel literal" \
    || bad "AppDelegate is missing the \"beta\" channel literal"

# Existing Sparkle hooks must be preserved (regression guard).
grep -q "willInstallUpdateOnQuit" "$APPDELEGATE" \
    && ok "existing willInstallUpdateOnQuit hook still present" \
    || bad "willInstallUpdateOnQuit hook was removed"

section "App: About tab beta toggle"
ABOUT_VIEW="Meridian/Preferences/About/AboutView.swift"
grep -q 'UserDefaultKeys.betaUpdatesEnabled' "$ABOUT_VIEW" \
    && ok "AboutView binds to betaUpdatesEnabled" \
    || bad "AboutView does not bind to betaUpdatesEnabled"

grep -qE 'BetaChannelToggle|Receive beta releases|Include beta releases' "$ABOUT_VIEW" \
    && ok "AboutView declares a beta-channel toggle" \
    || bad "AboutView has no visible beta toggle (looked for BetaChannelToggle / 'Receive beta releases' / 'Include beta releases')"

# ── 2. Release tooling ───────────────────────────────────────────────

section "Release script: version handling"
RELEASE="scripts/release.sh"

# Regex must permit X.Y.Z-betaN (look for -beta inside the bash =~ pattern).
grep -qE 'VERSION.*=~.*-beta' "$RELEASE" \
    && ok "release.sh version regex permits a -betaN suffix" \
    || bad "release.sh version regex still rejects -betaN suffixes"

grep -qE 'IS_BETA|is_beta|BETA_RELEASE' "$RELEASE" \
    && ok "release.sh detects a beta version string" \
    || bad "release.sh has no beta detection"

section "Release script: appcast channel + prerelease"
grep -q 'sparkle:channel' "$RELEASE" \
    && ok "release.sh emits <sparkle:channel> for beta items" \
    || bad "release.sh does not emit <sparkle:channel>"

grep -q -- '--prerelease' "$RELEASE" \
    && ok "release.sh passes --prerelease to gh for betas" \
    || bad "release.sh never passes --prerelease"

section "Release script: skip Homebrew cask for betas"
# Look for a guard around the Homebrew section that references beta.
if awk '/Update Homebrew cask/,/Homebrew cask updated/' "$RELEASE" \
    | grep -qE 'IS_BETA|is_beta|BETA_RELEASE|Skipping cask.*beta|skipping.*cask'; then
    ok "release.sh skips Homebrew cask update for betas"
else
    bad "release.sh always updates Homebrew cask (must skip for betas)"
fi

# ── 3. Compilation ───────────────────────────────────────────────────

section "Build: xcodebuild Debug (no code signing)"
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    -quiet > /tmp/meridian_build.log 2>&1; then
    ok "Debug build succeeded"
else
    tail -40 /tmp/meridian_build.log
    bad "Debug build failed (see /tmp/meridian_build.log)"
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "=== Validation: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
