#!/usr/bin/env bash
# Validation for issue #200 — "Stale references to removed legacy UI (kill-switches, deleted
# classes) in CLAUDE.md and comments".
#
# The legacy storyboard UI and its useV4Settings / useDaybreakPanel kill-switches were deleted in
# #166 (98e4135). This script asserts that no *current* guidance — CLAUDE.md, source comments, or
# the LocalizationTests key inventory — still describes them as if they exist.
#
# Historical records are exempt: REDESIGN-V4.md and docs/CODE_REVIEW_4.0.0.md are dated build /
# review logs, not statements about the code as it stands today.

set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

# Classes/files removed in #166 that must no longer be referenced as if they exist.
REMOVED_SYMBOLS=(
  useV4Settings
  useDaybreakPanel
  ParentPanelController
  PreferencesViewController
  AppearanceViewController
  TimezoneAdditionHandler
  TimezoneSearchService
  TimezoneDataSource
  TimezoneCellView
  NoTimezoneView
  CustomPanel
  "Preferences.storyboard"
  "Panel.xib"
  "HourMarkerViewItem"
)

# A line that names a removed symbol *while citing #166* is a deliberate tombstone ("these are
# gone, don't go looking for them"), not stale guidance. Everything else is a finding.

echo "== 1. CLAUDE.md has no references to symbols removed in #166 =="
MD_HITS=0
for sym in "${REMOVED_SYMBOLS[@]}"; do
  hits=$(grep -n -F -- "$sym" CLAUDE.md | grep -v '#166' || true)
  if [ -n "$hits" ]; then
    fail "CLAUDE.md still mentions '$sym' outside a #166 tombstone"
    echo "$hits" | sed 's/^/      /'
    MD_HITS=1
  fi
done
# `PanelController` needs a word-boundary match so DaybreakPanelController doesn't trip it.
hits=$(grep -nE '(^|[^a-zA-Z])PanelController' CLAUDE.md | grep -v 'DaybreakPanelController' | grep -v '#166' || true)
if [ -n "$hits" ]; then
  fail "CLAUDE.md still mentions the removed 'PanelController'"
  echo "$hits" | sed 's/^/      /'
  MD_HITS=1
fi
[ "$MD_HITS" -eq 0 ] && pass "no stale removed-symbol references in CLAUDE.md"

echo "== 2. Every file path in CLAUDE.md's Key Files table exists =="
MISSING=0
while read -r path; do
  [ -z "$path" ] && continue
  if [ ! -e "Meridian/$path" ]; then
    fail "Key Files table lists a non-existent path: Meridian/$path"
    MISSING=1
  fi
done < <(awk '/^## Key Files/{f=1} f&&/^\| `/{gsub(/^\| `/,"");sub(/`.*/,"");print} /^## Test Notes/{f=0}' CLAUDE.md)
[ "$MISSING" -eq 0 ] && pass "all Key Files paths resolve"

echo "== 3. CLAUDE.md documents the shipping V4Settings / Daybreak structure =="
for expected in "Panel/Daybreak/DaybreakPanelController.swift" \
                "Panel/Daybreak/DaybreakViewModel.swift" \
                "Preferences/V4Settings/SettingsRootView.swift" \
                "Preferences/V4Settings/CitiesPane.swift"; do
  if grep -q -F -- "$expected" CLAUDE.md; then
    pass "CLAUDE.md references $expected"
  else
    fail "CLAUDE.md never mentions $expected"
  fi
done

echo "== 4. No Swift source comment references a symbol removed in #166 =="
SWIFT_HITS=0
for sym in "${REMOVED_SYMBOLS[@]}"; do
  hits=$(grep -rn --include="*.swift" -F -- "$sym" Meridian/ | grep -v '#166' || true)
  if [ -n "$hits" ]; then
    fail "Swift sources still mention '$sym' outside a #166 tombstone"
    echo "$hits" | sed 's/^/      /'
    SWIFT_HITS=1
  fi
done
hits=$(grep -rnE --include="*.swift" '(^|[^a-zA-Z])PanelController' Meridian/ | grep -v 'DaybreakPanelController' | grep -v '#166' || true)
if [ -n "$hits" ]; then
  fail "Swift sources still mention the removed 'PanelController'"
  echo "$hits" | sed 's/^/      /'
  SWIFT_HITS=1
fi
# The flags are gone, so no comment should describe behavior as gated by one, or promise the
# legacy UI as a fallback. (`kMenubarV4SingleLine` is NOT one of these — it survives as the
# Settings → Menu Bar "Stacked" user preference, issue #142.)
hits=$(grep -rniE --include="*.swift" 'v4 flag|kill-?switch|instant fallback|(legacy|old) (panel|preferences|settings)[^.]{0,40}fallback' Meridian/ || true)
if [ -n "$hits" ]; then
  fail "Swift comments still describe a v4 rollback flag / legacy-UI fallback"
  echo "$hits" | sed 's/^/      /'
  SWIFT_HITS=1
fi
[ "$SWIFT_HITS" -eq 0 ] && pass "no removed symbols or rollback-flag phrasing in Swift sources"

echo "== 5. LocalizationTests keys are actually used by shipping code =="
TESTFILE="Meridian/MeridianUnitTests/LocalizationTests.swift"
KEYS=$(awk '/private let activeKeys/{f=1;next} f&&/^[[:space:]]*\]/{exit} f&&/^[[:space:]]*"/{sub(/^[[:space:]]*"/,"");sub(/",?[[:space:]]*$/,"");print}' "$TESTFILE")
if [ -z "$KEYS" ]; then
  fail "could not parse activeKeys out of $TESTFILE"
else
  UNUSED=0
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if ! grep -rq --include="*.swift" --exclude-dir=MeridianUnitTests --exclude-dir=MeridianUITests \
         -F -- "\"$key\"" Meridian/; then
      fail "activeKeys lists '$key', which no shipping source uses"
      UNUSED=1
    fi
  done <<< "$KEYS"
  [ "$UNUSED" -eq 0 ] && pass "every activeKeys entry ($(echo "$KEYS" | grep -c .) keys) is used by shipping code"
fi

echo "== 6. Build =="
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
     CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
     >/tmp/meridian-200-build.log 2>&1; then
  pass "xcodebuild build succeeded"
else
  fail "xcodebuild build FAILED (see /tmp/meridian-200-build.log)"
  tail -30 /tmp/meridian-200-build.log | sed 's/^/      /'
fi

echo "== 7. Unit tests =="
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug test \
     -only-testing:MeridianUnitTests -parallel-testing-enabled NO -disable-concurrent-destination-testing \
     CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
     >/tmp/meridian-200-test.log 2>&1; then
  pass "unit tests passed ($(grep -cE "^Test Case '.*' passed" /tmp/meridian-200-test.log) cases)"
else
  fail "unit tests FAILED (see /tmp/meridian-200-test.log)"
  grep -E "error:|failed" /tmp/meridian-200-test.log | head -20 | sed 's/^/      /'
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mALL CHECKS PASSED\033[0m\n'
else
  printf '\033[31mVALIDATION FAILED\033[0m\n'
fi
exit "$FAIL"
