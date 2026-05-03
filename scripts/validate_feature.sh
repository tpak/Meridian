#!/bin/bash
# Validates the accent color trademark disclaimer popover (feature/accent-color-disclaimer).
# Run from repo root. Exits non-zero if any check fails.
#
# Three groups of checks:
#   1. Storyboard wiring (info button, action selector, outlet)
#   2. Swift wiring (outlet, action, popover view controller, SF Symbol)
#   3. Localization + compilation
set -u
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ok()      { echo "  OK:   $1"; PASS=$((PASS+1)); }
bad()     { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $1"; }

# ── 1. Storyboard ─────────────────────────────────────────────────────

section "Storyboard: info button + outlet + action"
SB="Meridian/Preferences/Preferences.storyboard"

grep -q 'id="Acc-Bt-Inf"' "$SB" \
    && ok "info button (Acc-Bt-Inf) present" \
    || bad "info button (Acc-Bt-Inf) missing from storyboard"

grep -q 'selector="showAccentColorInfo:"' "$SB" \
    && ok "showAccentColorInfo: action wired" \
    || bad "showAccentColorInfo: action not wired"

grep -q 'property="accentColorInfoButton"' "$SB" \
    && ok "accentColorInfoButton outlet wired" \
    || bad "accentColorInfoButton outlet missing"

# Popup must still be present and wired (regression guard for the
# stackView restructure of the gridCell).
grep -q 'property="teamAccentPopup"' "$SB" \
    && ok "teamAccentPopup outlet preserved" \
    || bad "teamAccentPopup outlet was removed"

grep -q 'selector="teamAccentChanged:"' "$SB" \
    && ok "teamAccentChanged: action preserved" \
    || bad "teamAccentChanged: action was removed"

# ── 2. Swift ──────────────────────────────────────────────────────────

section "Swift: outlet, action, view controller, SF Symbol"
APPEAR="Meridian/Preferences/Appearance/AppearanceViewController.swift"

grep -q '@IBOutlet var accentColorInfoButton: NSButton!' "$APPEAR" \
    && ok "@IBOutlet accentColorInfoButton declared" \
    || bad "@IBOutlet accentColorInfoButton missing"

grep -q '@IBAction func showAccentColorInfo' "$APPEAR" \
    && ok "@IBAction showAccentColorInfo declared" \
    || bad "@IBAction showAccentColorInfo missing"

grep -q 'class AccentColorInfoViewController' "$APPEAR" \
    && ok "AccentColorInfoViewController declared" \
    || bad "AccentColorInfoViewController missing"

grep -q 'systemSymbolName: "info.circle"' "$APPEAR" \
    && ok "info.circle SF Symbol assigned to button" \
    || bad "info.circle SF Symbol not assigned"

grep -q 'NSPopover' "$APPEAR" \
    && ok "NSPopover used for the disclaimer" \
    || bad "NSPopover not used"

# ── 3. Localization ──────────────────────────────────────────────────

section "Localization: disclaimer strings present in xcstrings"
XCS="Meridian/App/Localizable.xcstrings"

grep -q '"About these colors"' "$XCS" \
    && ok "title string present" \
    || bad "title string missing"

grep -q '"About accent colors"' "$XCS" \
    && ok "accessibility label string present" \
    || bad "accessibility label string missing"

grep -q "Meridian is an independent project, built by an F1 fan" "$XCS" \
    && ok "body disclaimer present" \
    || bad "body disclaimer missing"

grep -q "Team names are trademarks of their respective owners" "$XCS" \
    && ok "trademark attribution present" \
    || bad "trademark attribution missing"

grep -q "Colors are fan approximations" "$XCS" \
    && ok "fan-approximation acknowledgement present" \
    || bad "fan-approximation acknowledgement missing"

# ── 4. Build ─────────────────────────────────────────────────────────

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
