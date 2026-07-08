#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for "seconds time formats in v4 Settings":
# expose 12-hour/24-hour "with seconds" (TimeFormat raw 3/4) in Settings ›
# Appearance, keep the seconds choice flowing through the Menu Bar pane's
# preview / 24-hour toggle / presets, and document it in the user manual.
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
