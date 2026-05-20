#!/bin/bash
# Validates the Tahoe menubar-block detection & recovery feature (issue #125).
# Run from repo root. Exits non-zero if any check fails.
#
# Layers checked:
#   1. StatusItemHandler wiring (detection hook + pure helper + deep link)
#   2. Strings / AppDefaults (tahoeOnboardingShown key + default)
#   3. AppDelegate (onboarding alert + didBecomeActive re-check)
#   4. About tab (permanent help link)
#   5. Localization: all 8 new keys translated into 15 supported languages
#   6. Build (Debug, no code signing)
set -u
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ok()      { echo "  OK:   $1"; PASS=$((PASS+1)); }
bad()     { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $1"; }

# ── 1. StatusItemHandler ──────────────────────────────────────────────

section "StatusItemHandler: detection hook + helper + deep link"
SIH="Meridian/Preferences/Menu Bar/StatusItemHandler.swift"

grep -q "func scheduleVisibilityVerification" "$SIH" \
    && ok "scheduleVisibilityVerification declared" \
    || bad "scheduleVisibilityVerification missing"

grep -q "verifyStatusItemVisible" "$SIH" \
    && ok "verifyStatusItemVisible declared" \
    || bad "verifyStatusItemVisible missing"

grep -q "showBlockedRecoveryDialog" "$SIH" \
    && ok "showBlockedRecoveryDialog declared" \
    || bad "showBlockedRecoveryDialog missing"

grep -q "enum MenubarBlockDetection" "$SIH" \
    && ok "MenubarBlockDetection enum declared" \
    || bad "MenubarBlockDetection enum missing"

grep -q "func isStatusItemBlocked" "$SIH" \
    && ok "isStatusItemBlocked pure helper declared" \
    || bad "isStatusItemBlocked pure helper missing"

grep -q "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension" "$SIH" \
    && ok "Control Center deep-link URL present" \
    || bad "Control Center deep-link URL missing"

# ── 2. Strings / AppDefaults ──────────────────────────────────────────

section "Defaults: tahoeOnboardingShown key declared + registered"

grep -q "tahoeOnboardingShown" "Meridian/Overall App/Strings.swift" \
    && ok "tahoeOnboardingShown declared in Strings.swift" \
    || bad "tahoeOnboardingShown not declared"

grep -q "tahoeOnboardingShown" "Meridian/Overall App/AppDefaults.swift" \
    && ok "tahoeOnboardingShown registered in AppDefaults.swift" \
    || bad "tahoeOnboardingShown not registered with default value"

# ── 3. AppDelegate ────────────────────────────────────────────────────

section "AppDelegate: onboarding hook + activation re-check"

grep -q "showTahoeOnboardingIfNeeded" "Meridian/AppDelegate.swift" \
    && ok "showTahoeOnboardingIfNeeded called in applicationDidFinishLaunching" \
    || bad "showTahoeOnboardingIfNeeded missing"

grep -q "presentTahoeOnboardingAlert" "Meridian/AppDelegate.swift" \
    && ok "presentTahoeOnboardingAlert declared" \
    || bad "presentTahoeOnboardingAlert missing"

grep -q "didBecomeActiveNotification" "Meridian/AppDelegate.swift" \
    && ok "didBecomeActiveNotification observer wired for re-check" \
    || bad "didBecomeActiveNotification observer missing"

# ── 4. About tab ──────────────────────────────────────────────────────

section "About tab: permanent menubar troubleshooting link"

grep -q "Can't see Meridian in your menu bar" "Meridian/Preferences/About/AboutView.swift" \
    && ok "help link present in AboutView" \
    || bad "help link missing from AboutView"

grep -q "ControlCenterSettings.open" "Meridian/Preferences/About/AboutView.swift" \
    && ok "help link invokes ControlCenterSettings.open" \
    || bad "help link does not open Control Center settings"

# ── 5. Localization ───────────────────────────────────────────────────

section "Localization: 8 new keys × 16 locales"
if python3 - <<'PY'
import json, sys
required_langs = ["ar","de","en","es","fr","hi","hr","ja","ko","pl","pt-BR","ru","tr","uk","zh-Hans","zh-Hant"]
new_keys = [
    "One quick setup step",
    "macOS Tahoe requires you to explicitly allow apps to put icons in the menu bar. Open System Settings → Control Center, scroll to the third-party apps section, and turn on Meridian.",
    "I've already done this",
    "Meridian isn't visible in your menu bar",
    "macOS appears to be blocking Meridian's menu bar icon. Open System Settings → Control Center, scroll to the third-party apps section, and turn on Meridian.",
    "Open Control Center Settings",
    "Quit Meridian",
    "Can't see Meridian in your menu bar?",
]
with open("Meridian/App/Localizable.xcstrings") as f:
    data = json.load(f)
strings = data.get("strings", {})
missing = []
for key in new_keys:
    entry = strings.get(key)
    if entry is None:
        missing.append((key, "KEY MISSING"))
        continue
    locs = entry.get("localizations", {})
    for lang in required_langs:
        unit = locs.get(lang, {}).get("stringUnit", {})
        value = unit.get("value", "")
        if not value:
            missing.append((key, f"missing {lang}"))
if missing:
    print(f"  FAIL: {len(missing)} localization gap(s):", file=sys.stderr)
    for k, why in missing[:10]:
        print(f"    - {k[:60]}… -> {why}", file=sys.stderr)
    sys.exit(1)
print(f"  OK:   all 8 new keys translated to {len(required_langs)} locales each")
PY
then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi

# ── 6. Build ──────────────────────────────────────────────────────────

section "Build: xcodebuild Debug (no code signing)"
if xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    -quiet > /tmp/meridian_build.log 2>&1; then
    ok "Debug build succeeded"
else
    tail -40 /tmp/meridian_build.log
    bad "Debug build failed (see /tmp/meridian_build.log)"
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "=== Validation: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || exit 1
