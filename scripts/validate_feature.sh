#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for issue #142: "bring back stacked time in
# compact menu bar" as an opt-in 6th menu-bar preset ("Stacked").
#
# Run BEFORE implementing (expect failures), then again after (expect all green).
#
#   bash scripts/validate_feature.sh            # static checks + Debug build
#   bash scripts/validate_feature.sh --no-build # static checks only (fast)
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

PASS=0
FAIL=0
SIV="Meridian/Preferences/Menu Bar/StatusItemView.swift"
SCV="Meridian/Preferences/Menu Bar/StatusContainerView.swift"
PANE="Meridian/Preferences/V4Settings/MenuBarPane.swift"
GP="Meridian/Preferences/V4Settings/GeneralPane.swift"
APPD="Meridian/AppDelegate.swift"
KEY="com.tpak.meridian.v4.menubarStacked"

ok()  { printf "  \033[32mOK:\033[0m   %s\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL:\033[0m %s\n" "$1" >&2; FAIL=$((FAIL+1)); }

check() { # check "description" <grep-args...>
  local desc="$1"; shift
  if grep -q "$@"; then ok "$desc"; else bad "$desc"; fi
}

echo "Issue #142 — Stacked menu-bar preset — validation"
echo "------------------------------------------------"

# 1. The single-line switch is no longer a hard-coded constant.
if grep -Eq '^[[:space:]]*let[[:space:]]+kMenubarV4SingleLine[[:space:]]*=[[:space:]]*true' "$SIV"; then
  bad "kMenubarV4SingleLine is no longer a hard-coded 'let ... = true'"
else
  ok "kMenubarV4SingleLine is no longer a hard-coded 'let ... = true'"
fi

# 2. It is now a computed value (var with a Bool body).
check "kMenubarV4SingleLine is now computed (var ...: Bool {)" -Eq 'var[[:space:]]+kMenubarV4SingleLine[[:space:]]*:[[:space:]]*Bool[[:space:]]*\{' "$SIV"

# 3. The render path reads the new UserDefault key.
check "render path (StatusItemView) references the new key" -Fq "$KEY" "$SIV"

# 4. A reader exists for the stacked layout flag.
check "menubarStackedLayoutEnabled reader exists" -Eq 'menubarStackedLayoutEnabled' "$SIV"

# 5. Default is OFF (single-line preserved for everyone) — reader falls back to false.
check "stacked default is false (?? false)" -Eq 'as\? Bool \?\? false' "$SIV"

# 6. MenuBarPane exposes a 6th "Stacked" preset.
check "MenuBarPane has a 'stacked' preset id" -Eq 'id:[[:space:]]*"stacked"' "$PANE"
check "MenuBarPane has a 'Stacked' preset label" -Fq 'String(localized: "Stacked")' "$PANE"

# 7. MenuBarPane persists the new key via @AppStorage.
check "MenuBarPane binds the new key via @AppStorage" -Fq "@AppStorage(\"$KEY\")" "$PANE"

# 8. Selecting a preset applies the stacked flag.
check "applyPreset writes the stacked flag" -Eq 'menubarStacked[[:space:]]*=[[:space:]]*preset\.stacked' "$PANE"

# 9. The preset model carries a 'stacked' field.
check "MenuBarPreset model has a 'stacked' field" -Eq 'let[[:space:]]+stacked:[[:space:]]*Bool' "$PANE"

# 10. Preview can render a two-line (stacked) chip.
check "preview supports a two-line/stacked chip (bottomLabel)" -Eq 'bottomLabel' "$PANE"

# 11. UAT r5: stacked menu-bar item height tracks the live bar thickness (a fixed/oversized height
#     overflows the 22pt bar and crams the time onto the bottom edge).
check "menubarItemHeight tracks bar thickness" -Eq 'var menubarItemHeight: CGFloat \{ NSStatusBar\.system\.thickness \}' "$SCV"

# 12. UAT fix: preset cards reserve two sample lines so the Stacked card doesn't grow its row.
check "preset card reserves two sample lines" -Fq 'reservesSpace: true' "$PANE"

# 13. UAT r2: stacked menu-bar name line uses semibold (matches the cleaner preview), not bold.
check "menu-bar name font is semibold" -Eq 'systemFont\(ofSize: 10, weight: .semibold\)' "$SIV"
if grep -q 'boldSystemFont(ofSize: 10)' "$SIV"; then bad "menu-bar name still uses boldSystemFont"; else ok "menu-bar name no longer boldSystemFont"; fi

# 14. UAT r2: preset card sample is right-justified.
check "preset card sample is right-justified" -Fq 'multilineTextAlignment(.trailing)' "$PANE"

# 15. UAT r2: 'Check Now' lives on its own row (empty-label FormRow under the segment).
check "Check Now is on its own FormRow" -Eq 'FormRow\(label: ""\)' "$GP"

# 16. UAT r2: fresh-install start-at-login default.
check "enableStartAtLoginByDefault exists" -Eq 'func enableStartAtLoginByDefault' "$APPD"
check "start-at-login wired into launch" -Eq 'enableStartAtLoginByDefault\(\)' "$APPD"

# 17. UAT r2: fresh-install daily update cadence.
check "fresh-install sets daily update interval (86400)" -Eq 'updateCheckInterval = 86400' "$APPD"

# 18. UAT r5: stacked lines have their text centres placed symmetrically about the bar middle
#     (verified by screenshot: tight, centred pair, time off the bottom edge).
check "stacked name text centred above the middle" -Fq 'locationView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -halfGap)' "$SIV"
check "stacked time text centred below the middle" -Fq 'timeView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: halfGap)' "$SIV"
if grep -q 'multiplier: 0.35\|multiplier: 0.5' "$SIV"; then bad "stacked still uses a proportional split"; else ok "stacked no longer uses a proportional split"; fi

# 19. UAT r5: General-pane command buttons use the visible ShadedButtonStyle (the system .bordered
#     style was near-invisible on the dark canvas); no .plain command buttons remain.
check "command buttons use ShadedButtonStyle" -Fq 'buttonStyle(ShadedButtonStyle())' "$GP"
check "ShadedButtonStyle is defined" -Fq 'struct ShadedButtonStyle: ButtonStyle' "$GP"
if grep -q 'buttonStyle(.plain)' "$GP"; then bad "GeneralPane still has a .plain command button"; else ok "no .plain command buttons remain in GeneralPane"; fi

# 20. UAT r5: stacked menu-bar item height matches the bar (no fixed 30pt that overflowed the 22pt bar).
if grep -q 'stackedMenubarItemHeight\|multiplier: 0.5\|: 30' "$SCV"; then bad "stacked item still uses a fixed/oversized height"; else ok "stacked item height matches the bar thickness"; fi

# 21. UAT r6: the Daybreak panel sits below the bar (gap), not flush against it.
DPC="Meridian/Panel/Daybreak/DaybreakPanelController.swift"
check "panel anchors with a gap below the bar" -Fq 'buttonRect.minY + bodyTopInset - bodyGapBelowBar' "$DPC"

# --- New "Midnight Sundial" icons ---
AIS="Meridian/Media.xcassets/AppIcon.appiconset"
MBI="Meridian/Media.xcassets/MenuBarIcon.imageset"
SIH="Meridian/Preferences/Menu Bar/StatusItemHandler.swift"
FAD="Meridian/Overall App/Foundation + Additions.swift"

# 22. New AppIcon iconset present (all 10), old Clocker/meridian-* art gone.
if [ "$(find "$AIS" -name 'icon_*.png' | wc -l | tr -d ' ')" = "10" ]; then ok "AppIcon has the 10 new icon_*.png"; else bad "AppIcon missing new icon_*.png"; fi
if find "$AIS" -iname '*clocker*' -o -iname 'meridian-*.png' 2>/dev/null | grep -q .; then bad "old Clocker/meridian-* app-icon art still present"; else ok "old app-icon art removed"; fi
check "AppIcon Contents.json maps the new files" -Fq 'icon_512x512@2x.png' "$AIS/Contents.json"

# 23. MenuBarIcon template imageset present and rendered as template.
if [ -f "$MBI/MenuBarIcon.png" ] && [ -f "$MBI/MenuBarIcon@2x.png" ]; then ok "MenuBarIcon imageset has the template pair"; else bad "MenuBarIcon imageset PNGs missing"; fi
check "MenuBarIcon renders as a template image" -Fq '"template-rendering-intent" : "template"' "$MBI/Contents.json"

# 24. Old unused menu-bar icon asset removed.
if [ -d "Meridian/Media.xcassets/Menubar Icons" ]; then bad "old 'Menubar Icons' (LightModeIcon) folder still present"; else ok "old 'Menubar Icons' folder removed"; fi

# 25. Code loads the template glyph (not the old clock.fill SF Symbol).
check "menubarIcon name points at MenuBarIcon" -Fq 'NSImage.Name("MenuBarIcon")' "$FAD"
check "status item loads the template icon" -Fq 'NSImage(named: .menubarIcon)' "$SIH"
check "status item icon is set as a template" -Eq 'image\?\.isTemplate = true' "$SIH"
if grep -q 'clock.fill' "$SIH"; then bad "still references the clock.fill SF Symbol"; else ok "no clock.fill reference remains"; fi

echo ""
if [[ "${1:-}" == "--no-build" ]]; then
  echo "Skipping build (--no-build)."
else
  echo "Building (Debug, no code signing)…"
  BUILD_LOG=$(mktemp)
  if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
       CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
       >"$BUILD_LOG" 2>&1; then
    ok "Debug build succeeded"
  else
    bad "Debug build FAILED — see $BUILD_LOG"
    tail -25 "$BUILD_LOG" >&2
  fi
fi

echo ""
echo "------------------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && { echo "ALL GREEN"; exit 0; } || { echo "FAILURES PRESENT"; exit 1; }
