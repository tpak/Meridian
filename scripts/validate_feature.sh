#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for issue #191, round 2: kill the multi-display
# replicant CPU loop structurally.
#
# beta10 removed Meridian's own content rewrites from the appearance-change path,
# but the loop persisted: AppKit itself dirties views (_viewDidChangeAppearance: →
# setNeedsDisplay) when the replicant snapshot machinery flips setAppearance: on
# the live view hierarchy hosted inside the status item's button. On Macs whose
# menu bars resolve different appearances per display, every snapshot re-dirties
# and reschedules — no app code involved. The only structural escape is to stop
# hosting live views in the button: render the strip to an NSImage and set
# button.image, which AppKit replicates natively (like every plain menu bar app).
#
# The fix must:
#   1. Not add any subview to the status item's button.
#   2. Render compact content via a MenubarImageRenderer that sets button.image.
#   3. Leave no live-NSView container (StatusContainerView class / StatusItemView
#      class / StatusItemViewConforming protocol) behind.
#   4. Build and pass unit tests.
#
# Run BEFORE implementing (expect failures), then again after (expect all green).
#
#   bash scripts/validate_feature.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

PASS=0
FAIL=0
MB="Meridian/Preferences/Menu Bar"

ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# 1. No subviews are ever installed on the status item's button
if grep -rn "addSubview\|subviews = " "$MB"/StatusItemHandler.swift | sed 's/^[^:]*:[0-9]*://' | grep -qEv '^[[:space:]]*//'; then
    bad "StatusItemHandler still installs/clears subviews on the status button"
else
    ok "StatusItemHandler no longer touches button subviews"
fi

# 2. Renderer exists and the handler sets an image for compact mode
if grep -q "enum MenubarImageRenderer" "$MB"/*.swift && grep -q "MenubarImageRenderer.image" "$MB"/StatusItemHandler.swift; then
    ok "compact mode renders via MenubarImageRenderer into button.image"
else
    bad "no MenubarImageRenderer-driven image path in StatusItemHandler"
fi

# 3. No live-view container classes remain anywhere outside tests
LIVE=$(grep -rn "class StatusContainerView\|class StatusItemView\|StatusItemViewConforming" Meridian --include="*.swift" | grep -cv Tests)
if [ "$LIVE" -eq 0 ]; then
    ok "no live-NSView status container/view classes remain"
else
    bad "live status view machinery still present ($LIVE references)"
fi

# 4. Nothing in the Menu Bar layer uses NSTextField anymore (text is drawn).
# Strip the grep -rn "file:line:" prefix before testing for comment-only lines.
if grep -rn "NSTextField" "$MB" | sed 's/^[^:]*:[0-9]*://' | grep -qEv '^[[:space:]]*//'; then
    bad "Menu Bar layer still hosts NSTextField live views"
else
    ok "Menu Bar layer hosts no NSTextField live views"
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
