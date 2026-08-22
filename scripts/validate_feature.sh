#!/usr/bin/env bash
# Validation for issue #199 — remove LocationController.
#
# LocationController requested location permission and reverse-geocoded the user's position onto
# the home row. It was never instantiated in app code (only in its own unit test), and the app is
# sandboxed without `com.apple.security.personal-information.location`, so CoreLocation would have
# been denied even if it had run. Removing it also lets the NSLocation* usage strings come out of
# Info.plist, so the app stops declaring a privacy capability it never exercises.

set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

PLIST=Meridian/App/Meridian-Info.plist
ENTITLEMENTS=Meridian/App/Meridian.entitlements

echo "== 1. LocationController and its test are gone =="
for f in Meridian/App/LocationController.swift Meridian/MeridianUnitTests/LocationControllerTests.swift; do
  [ -e "$f" ] && fail "$f still exists" || pass "$f removed"
done

echo "== 2. No source or project file still references the symbols =="
for sym in LocationController LocationControllerDelegate CLLocationManager determineAndRequestLocationAuthorization; do
  hits=$(grep -rn --include="*.swift" -F -- "$sym" Meridian/ || true)
  if [ -n "$hits" ]; then
    fail "Swift sources still reference '$sym'"
    echo "$hits" | sed 's/^/      /'
  else
    pass "no Swift reference to $sym"
  fi
done
if grep -q "LocationController" Meridian/Meridian.xcodeproj/project.pbxproj; then
  fail "project.pbxproj still lists LocationController (build phase or file ref)"
  grep -n "LocationController" Meridian/Meridian.xcodeproj/project.pbxproj | sed 's/^/      /'
else
  pass "project.pbxproj has no LocationController entries"
fi

echo "== 3. The reverse-geocoding API it was the only caller of is gone =="
hits=$(grep -rn --include="*.swift" "reverse(location" Meridian/ || true)
if [ -n "$hits" ]; then
  fail "reverse(location:) survives with no caller"
  echo "$hits" | sed 's/^/      /'
else
  pass "GeocodingServicing.reverse and its MapKit implementation removed"
fi
# forward() must stay — NetworkManager.geocodeAddress uses it.
if grep -q "func forward(addressString" "Meridian/Overall App/GeocodingService.swift"; then
  pass "forward(addressString:) still present (still used by geocodeAddress)"
else
  fail "forward(addressString:) was removed — that one is live"
fi

echo "== 4. Info.plist no longer declares location usage =="
if grep -q -i "NSLocation" "$PLIST"; then
  fail "$PLIST still declares a location usage description"
  grep -n -i "NSLocation" "$PLIST" | sed 's/^/      /'
else
  pass "no NSLocation* keys in $PLIST"
fi
if python3 -c "import plistlib,sys; plistlib.load(open(sys.argv[1],'rb'))" "$PLIST" 2>/dev/null; then
  pass "$PLIST is still a valid plist"
else
  fail "$PLIST is malformed"
fi

echo "== 5. No location entitlement was introduced =="
if grep -q -i "location" "$ENTITLEMENTS"; then
  fail "$ENTITLEMENTS gained a location entitlement — removal shouldn't add one"
else
  pass "entitlements unchanged w.r.t. location"
fi

echo "== 6. The AppDefaults comment no longer promises LocationController =="
if grep -n "LocationController" "Meridian/Overall App/AppDefaults.swift" >/dev/null; then
  fail "AppDefaults.swift still cites LocationController as a coordinate source"
  grep -n "LocationController" "Meridian/Overall App/AppDefaults.swift" | sed 's/^/      /'
else
  pass "AppDefaults comment updated"
fi

echo "== 7. The coordinate path that DOES run is untouched =="
if grep -q "backfillMissingCoordinates" Meridian/AppDelegate.swift; then
  pass "AppDelegate.backfillMissingCoordinates still present (the live coordinate source)"
else
  fail "backfillMissingCoordinates disappeared — that's the path users actually rely on"
fi

echo "== 8. Build =="
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
     CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
     >/tmp/meridian-199-build.log 2>&1; then
  pass "xcodebuild build succeeded"
else
  fail "xcodebuild build FAILED (see /tmp/meridian-199-build.log)"
  grep -E "error:" /tmp/meridian-199-build.log | head -20 | sed 's/^/      /'
fi

echo "== 9. Unit tests =="
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug test \
     -only-testing:MeridianUnitTests -parallel-testing-enabled NO -disable-concurrent-destination-testing \
     CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
     >/tmp/meridian-199-test.log 2>&1; then
  pass "unit tests passed ($(grep -cE "^Test Case '.*' passed" /tmp/meridian-199-test.log) cases)"
else
  fail "unit tests FAILED (see /tmp/meridian-199-test.log)"
  grep -E "error:|failed" /tmp/meridian-199-test.log | head -20 | sed 's/^/      /'
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mALL CHECKS PASSED\033[0m\n'
else
  printf '\033[31mVALIDATION FAILED\033[0m\n'
fi
exit "$FAIL"
