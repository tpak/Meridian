#!/bin/bash
# Validates the Sparkle "install on quit" fix for menubar apps.
#
# Meridian is LSUIElement=true; users rarely quit it, so Sparkle's default
# silent-install-on-quit never triggers. The fix makes AppDelegate conform
# to SPUUpdaterDelegate and immediately installs the downloaded update via
# the willInstallUpdateOnQuit handler.
set -eu

cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }

grep -q "extension AppDelegate: SPUUpdaterDelegate" Meridian/AppDelegate.swift \
    || fail "AppDelegate does not conform to SPUUpdaterDelegate"

grep -q "willInstallUpdateOnQuit" Meridian/AppDelegate.swift \
    || fail "willInstallUpdateOnQuit delegate method not implemented"

grep -q "immediateInstallationBlock\|immediateInstallHandler" Meridian/AppDelegate.swift \
    || fail "immediateInstallHandler not invoked"

grep -qE "updaterDelegate:\s*self" Meridian/AppDelegate.swift \
    || fail "updaterController not constructed with self as delegate"

# Must compile.
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    -quiet > /tmp/meridian_build.log 2>&1 \
    || { tail -40 /tmp/meridian_build.log; fail "build failed"; }

echo "Validation: all checks passed"
