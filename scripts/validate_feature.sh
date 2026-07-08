#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for "seconds time formats in v4 Settings":
# expose 12-hour/24-hour "with seconds" (TimeFormat raw 3/4) in Settings ›
# Appearance, keep the seconds choice flowing through the Menu Bar pane's
# preview / 24-hour toggle / presets, and document it in the user manual.
#
# Extension (UAT feedback): seconds are controlled INDEPENDENTLY per surface —
# Appearance › Show seconds keeps driving the Daybreak popover + preview via
# `timeFormat`, while a new Menu Bar › Seconds toggle (UserDefaults bool
# `showSecondsInMenubar`, default false) drives only the menu-bar clock via
# `DataStore.menubarTimezoneFormat()` (hour style from timeFormat, seconds
# from the menubar pref). Sections 8–10 below validate the split.
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
AP="Meridian/Preferences/V4Settings/AppearancePane.swift"
MBP="Meridian/Preferences/V4Settings/MenuBarPane.swift"
DS="Meridian/Overall App/DataStore.swift"
MANUAL="docs/manual.md"

ok()  { printf "  \033[32mOK:\033[0m   %s\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL:\033[0m %s\n" "$1" >&2; FAIL=$((FAIL+1)); }

check() { # check "description" <grep-args...>
  local desc="$1"; shift
  if grep -q "$@"; then ok "$desc"; else bad "$desc"; fi
}

echo "Seconds time formats in v4 Settings — validation"
echo "------------------------------------------------"

# 1. Appearance pane splits the format into a 12/24 segment + seconds toggle.
check "AppearancePane has a Show seconds row" -Fq 'String(localized: "Show seconds")' "$AP"
check "seconds toggle binding preserves hour style" -Fq 'timeFormat = .standard(twentyFourHour: timeFormat.isTwentyFourHour, seconds: $0)' "$AP"
check "hour segment binding preserves seconds" -Fq 'seconds: timeFormat.includesSeconds)' "$AP"

# 2. The toggle label is in the string catalog.
check "'Show seconds' key exists in the string catalog" -Fq '"Show seconds"' "Meridian/App/Localizable.xcstrings"

# 2b. The Daybreak popover honors the setting (hero + city rows tick seconds).
DVM="Meridian/Panel/Daybreak/DaybreakViewModel.swift"
check "DaybreakViewModel derives a seconds suffix from the setting" -Fq 'store.timeFormat.includesSeconds' "$DVM"
check "hero time appends the seconds suffix" -Fq 'time += secondsSuffix(reference)' "$DVM"
check "city rows append the seconds suffix" -Fq 'time + secondsSuffix(reference)' "$DVM"
check "unit test covers popover seconds display" -Fq 'testHeroSecondsFollowShowSecondsSetting' "Meridian/MeridianUnitTests/DaybreakEngineTests.swift"

# 3. The live PREVIEW card renders seconds for the new formats.
check "preview shows a 24-hour seconds sample (20:17:45)" -Fq '20:17:45' "$AP"
check "preview shows a 12-hour seconds sample (8:17:45 PM)" -Fq '8:17:45 PM' "$AP"

# 4. TimeFormat helpers exist so panes share one definition of "has seconds" / "is 24h".
check "TimeFormat.includesSeconds helper exists" -Eq 'var[[:space:]]+includesSeconds:[[:space:]]*Bool' "$DS"
check "TimeFormat.isTwentyFourHour helper exists" -Eq 'var[[:space:]]+isTwentyFourHour:[[:space:]]*Bool' "$DS"
check "TimeFormat.standard(twentyFourHour:seconds:) exists" -Eq 'static func standard\(twentyFourHour: Bool, seconds: Bool\)' "$DS"

# 5. Menu Bar pane's preview strip renders raw values 3/4 correctly (24h check
#    no longer equates "not .twentyFourHour" with 12-hour; seconds appear).
check "MenuBarPane preview uses includesSeconds" -Fq 'timeFormat.includesSeconds' "$MBP"
check "MenuBarPane preview uses isTwentyFourHour" -Fq 'timeFormat.isTwentyFourHour' "$MBP"
if grep -Fq 'timeFormat == .twentyFourHour ? sample.t24' "$MBP"; then
  bad "MenuBarPane preview still hard-codes the two-format ternary"
else
  ok "MenuBarPane preview no longer hard-codes the two-format ternary"
fi

# 6. The Menu Bar pane's 24-hour toggle and presets preserve the seconds choice
#    instead of clamping raw 3/4 back to 0/1.
check "24-hour toggle preserves seconds" -Fq '.standard(twentyFourHour: on, seconds: timeFormat.includesSeconds)' "$MBP"
check "applyPreset preserves seconds" -Fq '.standard(twentyFourHour: preset.twentyFourHour, seconds: timeFormat.includesSeconds)' "$MBP"

# 7. User manual documents the new toggle and the per-second tick.
check "manual documents the Show seconds toggle" -Fq '**Show seconds**' "$MANUAL"
check "manual mentions the menu-bar clock ticking every second" -Fq 'ticks every second' "$MANUAL"

# ------------------------------------------------------------------
# Independent menu-bar seconds (UAT follow-up) — sections 8–10.
# ------------------------------------------------------------------
STR="Meridian/Overall App/Strings.swift"
AD="Meridian/Overall App/AppDefaults.swift"
SIH="Meridian/Preferences/Menu Bar/StatusItemHandler.swift"
SCV="Meridian/Preferences/Menu Bar/StatusContainerView.swift"
TDO="Meridian/Panel/Data Layer/TimezoneDataOperations.swift"
SM="Meridian/Overall App/SettingsManager.swift"
TESTS="Meridian/MeridianUnitTests/MeridianUnitTests.swift"

# 8. New pref: key constant, registered default (false), typed accessor, and
#    the derived menu-bar format on DataStore.
check "UserDefaultKeys has showSecondsInMenubar" -Fq 'static let showSecondsInMenubar = "showSecondsInMenubar"' "$STR"
check "AppDefaults registers showSecondsInMenubar default false" -Fq 'UserDefaultKeys.showSecondsInMenubar: false' "$AD"
check "DataStore.menubarShowSeconds typed accessor exists" -Eq 'var[[:space:]]+menubarShowSeconds:[[:space:]]*Bool' "$DS"
check "DataStore.menubarTimezoneFormat() exists" -Fq 'func menubarTimezoneFormat() -> NSNumber' "$DS"
check "menubarTimezoneFormat derives hour style from timeFormat + seconds from menubarShowSeconds" \
  -Fq 'standard(twentyFourHour: timeFormat.isTwentyFourHour, seconds: menubarShowSeconds)' "$DS"

# 9. Menu-bar render paths use the menubar format; popover/panel paths don't.
check "StatusItemHandler seconds check uses menubarTimezoneFormat" -Fq 'shouldShowSeconds(store.menubarTimezoneFormat())' "$SIH"
check "StatusContainerView width/seconds logic uses menubarTimezoneFormat" -Fq 'store.menubarTimezoneFormat()' "$SCV"
if grep -Fq 'store.timezoneFormat()' "$SCV"; then
  bad "StatusContainerView still reads the popover format (store.timezoneFormat())"
else
  ok "StatusContainerView no longer reads the popover format"
fi
check "TimezoneDataOperations exposes a menubarTime(with:) variant" -Fq 'func menubarTime(with' "$TDO"
check "compact menu strings render via menubarTime" -Fq 'menubarTime(with: 0)' "$TDO"
check "popover secondsSuffix still keyed off timeFormat (unchanged)" -Fq 'store.timeFormat.includesSeconds' "$DVM"

# 10. Settings UI, preview, export/import, catalog, manual, tests.
check "MenuBarPane has a Seconds row" -Fq 'String(localized: "Seconds")' "$MBP"
check "MenuBarPane Seconds toggle binds the menubar pref" -Fq '$menubarShowSeconds' "$MBP"
if grep -Fq 'timeFormat.includesSeconds ? ":32"' "$MBP"; then
  bad "MenuBarPane preview strip still keys seconds off the Appearance timeFormat"
else
  ok "MenuBarPane preview strip no longer keys seconds off the Appearance timeFormat"
fi
check "MenuBarPane preview strip uses the menubar pref for the :32 sample" -Fq 'menubarShowSeconds ? ":32"' "$MBP"
check "'Seconds' key exists in the string catalog" -Fq '"Seconds": {' "Meridian/App/Localizable.xcstrings"
check "SettingsManager v2 exports showSecondsInMenubar" -Fq 'V2Key.showSecondsInMenubar: store.menubarShowSeconds' "$SM"
check "SettingsManager v2 imports showSecondsInMenubar" -Fq 'prefs[V2Key.showSecondsInMenubar] as? Bool' "$SM"
check "manual: Appearance Show seconds is popover-only and points at Menu Bar pane" -Fq 'popover only' "$MANUAL"
check "manual: Menu Bar fine-tune list documents the Seconds toggle" -Fq '**Seconds**' "$MANUAL"
check "unit test covers menubarTimezoneFormat derivation" -Fq 'func testMenubarTimezoneFormat' "$TESTS"

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
