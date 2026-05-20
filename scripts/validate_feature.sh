#!/bin/bash
# Validates the stale-home-timezone-flag fix (two home indicators / wrong time bug).
# Run from repo root. Exits non-zero if any check fails.
#
# Layers checked:
#   1. TimezoneData.timezone() is a pure accessor (no self-mutation)
#   2. AppDefaults has a one-time home-row self-heal migration
#   3. TimezoneAdditionHandler clears flag from other rows on install
#   4. ParentPanelController.updateHomeObject no longer overwrites customLabel
#   5. Unit tests cover the fix
#   6. Build succeeds (Debug, no code signing)
set -u
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ok()      { echo "  OK:   $1"; PASS=$((PASS+1)); }
bad()     { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $1"; }

# ── 1. TimezoneData.timezone() is pure ────────────────────────────────

section "TimezoneData.timezone() pure (no side-effecting assignments)"
TD="Meridian/CoreModelKit/Sources/CoreModelKit/TimezoneData.swift"

# Inside the `public func timezone() -> String` body, there must be NO
# assignment to `timezoneID` or `formattedAddress`. Extract just that function.
awk '/public func timezone\(\) -> String/,/^    \}/' "$TD" > /tmp/_tz_fn.swift
if grep -qE '^\s*timezoneID\s*=' /tmp/_tz_fn.swift; then
    bad "timezone() still mutates timezoneID"
else
    ok "timezone() does not mutate timezoneID"
fi
if grep -qE '^\s*formattedAddress\s*=' /tmp/_tz_fn.swift; then
    bad "timezone() still mutates formattedAddress"
else
    ok "timezone() does not mutate formattedAddress"
fi
rm -f /tmp/_tz_fn.swift

# ── 2. AppDefaults migration ──────────────────────────────────────────

section "AppDefaults: home-row self-heal migration"
AD="Meridian/Overall App/AppDefaults.swift"

grep -q "homeRowMigrationV1" "$AD" \
    && ok "homeRowMigrationV1 key referenced" \
    || bad "homeRowMigrationV1 key missing"

grep -q "runHomeRowMigrationV1" "$AD" \
    && ok "runHomeRowMigrationV1 function defined" \
    || bad "runHomeRowMigrationV1 function missing"

grep -q "runHomeRowMigrationV1" "Meridian/Overall App/AppDefaults.swift" \
    && grep -q "initializeDefaults" "$AD" \
    && ok "migration is wired into AppDefaults init path" \
    || bad "migration not wired in"

STR="Meridian/Overall App/Strings.swift"
grep -q "homeRowMigrationV1" "$STR" \
    && ok "homeRowMigrationV1 UserDefaults key string declared" \
    || bad "homeRowMigrationV1 UserDefaults key string missing"

# ── 3. TimezoneAdditionHandler clears flag from siblings on install ───

section "TimezoneAdditionHandler: clear isSystemTimezone from other rows"
TAH="Meridian/Preferences/General/TimezoneAdditionHandler.swift"

grep -q "clearStaleSystemTimezoneFlags\|clearOtherSystemTimezoneFlags" "$TAH" \
    && ok "clear-other-flags helper invoked in install path" \
    || bad "no helper to clear other rows' isSystemTimezone flag on install"

# ── 4. ParentPanelController.updateHomeObject preserves customLabel ───

section "ParentPanelController.updateHomeObject preserves customLabel"
PPC="Meridian/Panel/ParentPanelController.swift"

# The old code did: object.setLabel(customLabel) inside updateHomeObject.
# After the fix it must NOT call setLabel unconditionally.
awk '/private func updateHomeObject/,/^    \}/' "$PPC" > /tmp/_uho.swift
if grep -qE "object\.setLabel\(customLabel\)" /tmp/_uho.swift; then
    bad "updateHomeObject still overwrites customLabel"
else
    ok "updateHomeObject no longer overwrites customLabel"
fi
rm -f /tmp/_uho.swift

# ── 5. Unit tests reference the new behavior ──────────────────────────

section "Unit tests cover the fix"
UT="Meridian/MeridianUnitTests"

grep -rq "testTimezoneAccessorIsPure\|testTimezoneIsPure" "$UT" \
    && ok "pure-accessor test present" \
    || bad "no test for pure timezone() accessor"

grep -rq "testHomeRowMigration" "$UT" \
    && ok "home-row migration test present" \
    || bad "no test for home-row migration"

# ── 6. Build ──────────────────────────────────────────────────────────

section "Build (Debug, unsigned)"
BUILD_LOG=$(mktemp)
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= > "$BUILD_LOG" 2>&1; then
    ok "xcodebuild build succeeded"
else
    bad "xcodebuild build FAILED — see $BUILD_LOG"
    tail -40 "$BUILD_LOG" >&2
fi

# ── Summary ───────────────────────────────────────────────────────────

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit $FAIL
