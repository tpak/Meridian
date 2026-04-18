#!/bin/bash
# Validates Sparkle update-check logging.
#
# AppDelegate's SPUUpdaterDelegate extension should log when a scheduled or
# user-initiated check starts, when it finds an update, when it finds none,
# and when it aborts with an error. Without these hooks, users can't tell
# from Console.app whether Sparkle is running its scheduled checks at all.
set -eu

cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
ok()   { echo "OK:   $1"; }

FILE="Meridian/AppDelegate.swift"

grep -qE "mayPerform(UpdateCheck)? " "$FILE"              || fail "check-start hook (mayPerform:) not implemented"
ok "check-start hook implemented"

grep -q 'Sparkle: checking for updates' "$FILE"           || fail "check-start log message missing"
ok "check-start log message present"

grep -q "didFindValidUpdate" "$FILE"                      || fail "didFindValidUpdate hook not implemented"
grep -q 'Sparkle: found update' "$FILE"                   || fail "found-update log message missing"
ok "found-update hook + log present"

grep -q "updaterDidNotFindUpdate" "$FILE"                 || fail "updaterDidNotFindUpdate hook not implemented"
grep -q 'Sparkle: no update available' "$FILE"            || fail "no-update log message missing"
ok "no-update hook + log present"

grep -q "didAbortWithError" "$FILE"                       || fail "didAbortWithError hook not implemented"
grep -q 'Sparkle: update check aborted' "$FILE"           || fail "abort log message missing"
ok "abort hook + log present"

# Existing install-on-quit log must still be present (regression guard).
grep -q "willInstallUpdateOnQuit" "$FILE"                 || fail "willInstallUpdateOnQuit hook regressed"
ok "existing install-on-quit hook preserved"

# Must compile.
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    -quiet > /tmp/meridian_build.log 2>&1 \
    || { tail -40 /tmp/meridian_build.log; fail "build failed"; }
ok "build succeeded"

echo "Validation: all checks passed"
