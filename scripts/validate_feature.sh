#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for issue #191: multi-display NSStatusItem
# replicant CPU loop (~50% sustained CPU whenever 2+ displays are active).
#
# Root cause (confirmed via sample traces on the affected machine):
# AppKit's replicant machinery calls setAppearance: on the status-item view every
# time it re-snapshots the item for a second display's menu bar. StatusItemView's
# viewDidChangeEffectiveAppearance() override called applyContent(), which rewrote
# the text fields' attributedStringValue, dirtying the view and scheduling the
# next replicant update — an infinite loop that only exists with 2+ displays.
#
# The fix must remove all content mutation from the appearance-change path:
#   1. No viewDidChangeEffectiveAppearance override in StatusItemView (dynamic
#      colors make it unnecessary).
#   2. Text colors are dynamic NSColors (resolve per-appearance at draw time),
#      not baked white/black chosen via hasDarkAppearance.
#   3. applyContent() skips the attributedStringValue write when content is
#      unchanged, so a no-op refresh can never re-dirty the item.
#   4. Project still builds.
#
# Run BEFORE implementing (expect failures), then again after (expect all green).
#
#   bash scripts/validate_feature.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

PASS=0
FAIL=0
SIV="Meridian/Preferences/Menu Bar/StatusItemView.swift"

ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# 1. No viewDidChangeEffectiveAppearance override left in StatusItemView
if grep -q "viewDidChangeEffectiveAppearance" "$SIV"; then
    bad "StatusItemView still overrides viewDidChangeEffectiveAppearance"
else
    ok "StatusItemView has no viewDidChangeEffectiveAppearance override"
fi

# 2. Dynamic color used for menu-bar text (NSColor(name:) dynamic provider)
if grep -q "NSColor(name:" "$SIV"; then
    ok "StatusItemView uses a dynamic NSColor for text"
else
    bad "StatusItemView does not use a dynamic NSColor for text"
fi

# 3. No appearance-conditional color selection left anywhere outside tests
REFS=$(grep -rn "hasDarkAppearance" Meridian --include="*.swift" | grep -cv Tests)
if [ "$REFS" -eq 0 ]; then
    ok "no non-test references to hasDarkAppearance remain"
else
    bad "hasDarkAppearance still referenced $REFS time(s) outside tests"
fi

# 4. applyContent guards against no-op writes (tracks last applied content)
if grep -q "lastApplied" "$SIV"; then
    ok "applyContent skips redundant attributedStringValue writes"
else
    bad "applyContent has no last-applied guard against redundant writes"
fi

# 5. Build succeeds
echo "Building (this takes a minute)…"
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    > /tmp/validate_191_build.log 2>&1; then
    ok "xcodebuild Debug build succeeds"
else
    bad "xcodebuild Debug build failed (see /tmp/validate_191_build.log)"
fi

echo
echo "$PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
    echo "== VALIDATION FAILED =="
    exit 1
fi
echo "== ALL CHECKS PASSED =="
