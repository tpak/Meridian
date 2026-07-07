#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for the backfill data-loss audit fixes:
#   1. AppDelegate.backfillMissingCoordinates merges by stable identity into a
#      FRESH store read instead of writing back the launch-time snapshot.
#   2. StatusItemHandler derives the .second calendar component per call (the
#      old instance-level set only ever gained .second, never lost it).
#   3. The dead NotificationCenter.default didWake observer is deleted
#      (NSWorkspace posts on NSWorkspace.shared.notificationCenter).
#   4. runHomeRowMigrationV1 keeps the FIRST flagged row when no row matches
#      the current system timezone (instead of clearing the flag everywhere).
#   5. migrateInvertedBool writes nothing when the legacy value can't be
#      interpreted (instead of defaulting to 1 == feature hidden).
#
# Run BEFORE implementing (expect failures), then again after (expect all green).
#
#   bash scripts/validate_feature.sh            # static checks + build + new tests
#   bash scripts/validate_feature.sh --no-build # static checks only (fast)
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

PASS=0
FAIL=0
APPD="Meridian/AppDelegate.swift"
SIH="Meridian/Preferences/Menu Bar/StatusItemHandler.swift"
DEFAULTS="Meridian/Overall App/AppDefaults.swift"
UNIT="Meridian/MeridianUnitTests/MeridianUnitTests.swift"
APPD_TESTS="Meridian/MeridianUnitTests/AppDelegateTests.swift"

ok()  { printf "  \033[32mOK:\033[0m   %s\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL:\033[0m %s\n" "$1" >&2; FAIL=$((FAIL+1)); }

check() { # check "description" <grep-args...>
  local desc="$1"; shift
  if grep -q "$@"; then ok "$desc"; else bad "$desc"; fi
}

absent() { # absent "description" <grep-args...>
  local desc="$1"; shift
  if grep -q "$@"; then bad "$desc"; else ok "$desc"; fi
}

echo "Backfill data-loss + timer/migration audit fixes — validation"
echo "--------------------------------------------------------------"

# --- Fix 1: coordinate backfill must not clobber concurrent edits ------------

# The merge is a pure, unit-testable function keyed by stable identity.
check "AppDelegate has mergeBackfilledCoordinates(current:...)" \
  -Eq 'static func mergeBackfilledCoordinates\(current:' "$APPD"

# The identity used for the merge is derived from the model, not the array index.
check "AppDelegate derives a stable backfill identity from TimezoneData" \
  -Eq 'func backfillIdentity\(for' "$APPD"

# The write path re-reads the store AFTER the awaits (fresh read feeding the merge).
check "backfill merges into a fresh store.timezones() read" \
  -Eq 'mergeBackfilledCoordinates\(current: store\.timezones\(\)' "$APPD"

# The old positional write-back of the pre-await snapshot is gone.
absent "no positional snapshot write-back (timezones[index] = encoded)" \
  -Fq 'timezones[index] = encoded' "$APPD"

# Unit test: user edits during backfill survive the merge.
check "unit test covers add+remove during backfill" \
  -Eq 'func testMergeBackfilledCoordinates.*(KeepsUserEdits|PreservesConcurrentEdits)' "$APPD_TESTS"

# --- Fix 2: .second component derived fresh per calculation ------------------

# The sticky instance-level set is gone (a plain local 'var units' is fine)…
absent "no instance-level 'units' property on StatusItemHandler" \
  -Eq 'private (lazy )?var units' "$SIH"

# …and the once-only sticky insert guard with it.
absent "no sticky '!units.contains(.second)' insert guard" \
  -Fq '!units.contains(.second)' "$SIH"

# The component set is rebuilt locally on every calculation.
check "component set derived fresh per call" \
  -Eq 'var units: Set<Calendar\.Component> = \[\.era' "$SIH"

# The minute-boundary branch pins seconds to zero.
check "minute-branch fire date has second == 0" \
  -Fq 'components.second = 0' "$SIH"

# --- Fix 3: dead default-center didWake observer deleted ---------------------

absent "no NotificationCenter.default subscription to NSWorkspace.didWakeNotification" \
  -Fq 'NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)' "$SIH"

# The correct workspace-center subscriptions must remain intact.
check "workspace-center didWake subscription still present" \
  -Fq 'NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)' "$SIH"
check "workspace-center willSleep subscription still present" \
  -Fq 'NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)' "$SIH"

# --- Fix 4: home-row migration keeps first flagged row as fallback -----------

check "runHomeRowMigrationV1 falls back to the first flagged row" \
  -Eq 'keepIndex = flaggedIndices\.first$' "$DEFAULTS"

check "unit test covers two flagged rows with no system match" \
  -Eq 'func testHomeRowMigration.*(NoMatch|NeitherMatches)' "$UNIT"

# --- Fix 5: migrateInvertedBool skips uninterpretable legacy values ----------

absent "migrateInvertedBool no longer defaults garbage to 1 (hidden)" \
  -Fq '?? (object as? Int) ?? 1' "$DEFAULTS"

check "migrateInvertedBool guards on an interpretable legacy value" \
  -Eq 'guard let legacyInt' "$DEFAULTS"

check "unit test covers garbage legacy value leaving registered default" \
  -Eq 'func testInvertedBool_garbageLegacyValue' "$UNIT"

# --- Build + targeted tests ---------------------------------------------------

if [[ "${1:-}" != "--no-build" ]]; then
  echo ""
  echo "Building Debug configuration…"
  if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
      CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= > /tmp/validate_build.log 2>&1; then
    ok "Debug build succeeds"
  else
    bad "Debug build failed (see /tmp/validate_build.log)"
  fi

  echo "Running the new unit tests (serial)…"
  if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug test \
      -only-testing:MeridianUnitTests/AppDelegateTests \
      -only-testing:MeridianUnitTests/MeridianUnitTests \
      -only-testing:MeridianUnitTests/BoolSemanticsMigrationTests \
      -parallel-testing-enabled NO -disable-concurrent-destination-testing \
      CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= > /tmp/validate_tests.log 2>&1; then
    ok "New + surrounding unit tests pass"
  else
    bad "Unit tests failed (see /tmp/validate_tests.log)"
  fi
fi

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
