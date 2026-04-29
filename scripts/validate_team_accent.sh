#!/bin/bash
# Validates the F1 team accent color picker feature.
# Run from repo root. Exits non-zero if any check fails.
set -u
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ok()   { echo "  OK:   $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $1"; }

DS="Meridian/Overall App/DataStore.swift"
STR="Meridian/Overall App/Strings.swift"
DEF="Meridian/Overall App/AppDefaults.swift"
PCT="Meridian/Panel/PanelController.swift"
PSL="Meridian/Panel/ParentPanelController+ModernSlider.swift"
AVC="Meridian/Preferences/Appearance/AppearanceViewController.swift"
SBD="Meridian/Preferences/Preferences.storyboard"
SET="Meridian/Overall App/SettingsManager.swift"
LOC="Meridian/App/Localizable.xcstrings"
TST="Meridian/MeridianUnitTests/MeridianUnitTests.swift"

section "TeamAccent enum"
grep -q 'enum TeamAccent: String, Codable, CaseIterable' "$DS" \
    && ok "enum declared (String, Codable, CaseIterable)" \
    || bad "enum not declared with String/Codable/CaseIterable"

n=$(grep -E '^    case (alpine|astonMartin|audi|cadillac|ferrari|haas|mclaren|mercedes|racingBulls|redBull|williams)$' "$DS" | wc -l | tr -d ' ')
[[ "$n" == "11" ]] && ok "11 cases present" || bad "expected 11 cases, got $n"

grep -q 'static let .default.: TeamAccent = .astonMartin' "$DS" \
    && ok "default = astonMartin" \
    || bad "default is not astonMartin"

grep -q 'NSColor(srgbRed:.*alpha: 0.85)' "$DS" \
    && ok "accentColor uses sRGB at alpha 0.85" \
    || bad "accentColor does not match expected NSColor pattern"

grep -q 'case .haas:.*ED1C24' "$DS" \
    && ok "Haas substituted to livery red ED1C24 (real #FFFFFF unusable)" \
    || bad "Haas substitution missing or wrong"

grep -q 'case .cadillac:.*DCA62E' "$DS" \
    && ok "Cadillac substituted to gold DCA62E (real #111111 unusable)" \
    || bad "Cadillac substitution missing or wrong"

section "Notification + UserDefaults"
grep -q 'static let accentColorDidChange' "$DS" \
    && ok "Notification.Name.accentColorDidChange declared" \
    || bad "Notification.Name.accentColorDidChange missing"

grep -q 'static let teamAccent' "$STR" \
    && ok "UserDefaultKeys.teamAccent declared" \
    || bad "UserDefaultKeys.teamAccent missing"

grep -q 'UserDefaultKeys.teamAccent: TeamAccent.default.rawValue' "$DEF" \
    && ok "default registered in AppDefaults" \
    || bad "default not registered in AppDefaults"

grep -q 'var teamAccent: TeamAccent' "$DS" \
    && ok "DataStore.teamAccent typed accessor" \
    || bad "DataStore.teamAccent typed accessor missing"

section "Wired into UI"
grep -q 'DataStore.shared().teamAccent.accentColor' "$PCT" \
    && ok "PanelController pin button uses team accent" \
    || bad "PanelController not using team accent"

grep -q 'name: .accentColorDidChange' "$PCT" \
    && ok "PanelController observes accentColorDidChange" \
    || bad "PanelController missing observer"

grep -q 'applyTeamAccentToSliderControls' "$PSL" \
    && ok "Slider chevron + reset buttons tinted via applyTeamAccentToSliderControls" \
    || bad "applyTeamAccentToSliderControls missing"

section "Appearance tab"
grep -q '@IBOutlet var teamAccentPopup: NSPopUpButton' "$AVC" \
    && ok "@IBOutlet teamAccentPopup" \
    || bad "@IBOutlet teamAccentPopup missing"

grep -q '@IBOutlet var accentColorLabel: NSTextField' "$AVC" \
    && ok "@IBOutlet accentColorLabel" \
    || bad "@IBOutlet accentColorLabel missing"

grep -q 'func setupTeamAccentPopup' "$AVC" \
    && ok "setupTeamAccentPopup() defined" \
    || bad "setupTeamAccentPopup() missing"

grep -q '@IBAction func teamAccentChanged' "$AVC" \
    && ok "@IBAction teamAccentChanged" \
    || bad "@IBAction teamAccentChanged missing"

grep -q '"Accent Color".localized()' "$AVC" \
    && ok "Accent Color label localized" \
    || bad "Accent Color label not localized"

section "Storyboard"
grep -q 'Acc-1r-Row' "$SBD" \
    && ok "gridRow inserted" \
    || bad "gridRow not found in storyboard"

grep -q 'outlet property="teamAccentPopup"' "$SBD" \
    && ok "popup outlet wired" \
    || bad "popup outlet missing in storyboard"

grep -q 'outlet property="accentColorLabel"' "$SBD" \
    && ok "label outlet wired" \
    || bad "label outlet missing in storyboard"

n=$(grep -E '<menuItem.*Acm-iA-' "$SBD" | wc -l | tr -d ' ')
[[ "$n" == "11" ]] && ok "11 menuItems present in storyboard" || bad "expected 11 menuItems in storyboard, got $n"

grep -q 'selector="teamAccentChanged:"' "$SBD" \
    && ok "popup action wired" \
    || bad "popup action missing"

section "Localization"
grep -q '"Accent Color"' "$LOC" \
    && ok "Accent Color present in xcstrings" \
    || bad "Accent Color missing from xcstrings"

section "Settings export/import"
grep -q 'static let teamAccent = "teamAccent"' "$SET" \
    && ok "V2Key.teamAccent declared" \
    || bad "V2Key.teamAccent missing"

grep -q 'V2Key.teamAccent: store.teamAccent.jsonName' "$SET" \
    && ok "buildJSON exports team accent" \
    || bad "buildJSON does not export team accent"

grep -q 'TeamAccent(jsonName: s)' "$SET" \
    && ok "applyV2Preferences imports team accent" \
    || bad "applyV2Preferences does not import team accent"

grep -q 'NotificationCenter.default.post(name: .accentColorDidChange' "$SET" \
    && ok "import posts accentColorDidChange" \
    || bad "import does not post accentColorDidChange"

section "Tests"
grep -q 'class TeamAccentTests: XCTestCase' "$TST" \
    && ok "TeamAccentTests class added" \
    || bad "TeamAccentTests class missing"

n=$(awk '/^class TeamAccentTests/,/^}/' "$TST" | grep -c '^    func test')
[[ "$n" -ge 10 ]] && ok "TeamAccentTests has $n test functions" || bad "TeamAccentTests has only $n test functions (expected ≥ 10)"

section "Build"
echo "  (running xcodebuild Debug, this takes ~30s) ..."
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    -quiet > /tmp/meridian_team_accent_build.log 2>&1; then
    ok "Debug build succeeded"
else
    tail -50 /tmp/meridian_team_accent_build.log
    bad "Debug build failed (see /tmp/meridian_team_accent_build.log)"
fi

echo ""
echo "=== Validation: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
