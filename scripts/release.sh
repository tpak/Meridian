#!/bin/bash
set -euo pipefail

VERSION=""
NOTES=""
PR_NUMBER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n)
            NOTES="$2"
            shift 2
            ;;
        -p)
            PR_NUMBER="$2"
            shift 2
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

# HTML-escape one line of release-note text for embedding in the appcast's
# CDATA block (Sparkle renders that content as HTML). Escape & first so the
# entities themselves don't get re-escaped. Escaping > also neutralizes a
# literal "]]>" that would otherwise terminate the CDATA section early.
# NOTE: only the appcast path uses this — the GitHub release body is
# markdown and must stay unescaped.
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

# ── Phase 1: Validate ──────────────────────────────────────────────

if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release.sh [-n \"release notes\"] X.Y.Z[-betaN]"
    echo "       make release VERSION=X.Y.Z"
    echo "       make release VERSION=X.Y.Z-beta1   (publishes to Sparkle 'beta' channel)"
    exit 1
fi

# Accept stable (X.Y.Z) and beta (X.Y.Z-betaN) versions.
# Beta releases publish a prerelease GitHub release, tag the appcast item with
# <sparkle:channel>beta</sparkle:channel>, and skip the Homebrew cask update.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta[0-9]+)?$ ]]; then
    echo "Error: VERSION must match X.Y.Z or X.Y.Z-betaN pattern (got: $VERSION)"
    exit 1
fi

IS_BETA=0
if [[ "$VERSION" == *-beta* ]]; then
    IS_BETA=1
fi

# Derive a numeric build number from VERSION. Sparkle's
# SUStandardVersionComparator tokenizes versions and BREAKS at the first
# `-`, so "2.21.0-beta1" and "2.21.0-beta2" tokenize identically and are
# treated as equal. That made every beta-to-beta auto-update silently
# fail. We side-step by:
#   - keeping MARKETING_VERSION = display string (e.g. "2.21.0-beta3")
#   - setting CURRENT_PROJECT_VERSION = numeric build (e.g. 2210003)
#   - publishing <sparkle:version>2210003</sparkle:version> in the appcast
#     so Sparkle's comparator gets a clean integer to diff
#   - publishing <sparkle:shortVersionString>2.21.0-beta3</sparkle:shortVersionString>
#     so the user-facing alert still shows the readable version
#
# Encoding: MAJOR*1_000_000 + MINOR*10_000 + PATCH*1_000 + BETA_N
# (BETA_N=100 reserved for stable so stable > any beta of same X.Y.Z).
if [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-beta([0-9]+))?$ ]]; then
    V_MAJOR="${BASH_REMATCH[1]}"
    V_MINOR="${BASH_REMATCH[2]}"
    V_PATCH="${BASH_REMATCH[3]}"
    V_BETA="${BASH_REMATCH[5]:-100}"
    BUILD_NUMBER=$((V_MAJOR * 1000000 + V_MINOR * 10000 + V_PATCH * 1000 + V_BETA))
else
    echo "Error: VERSION '$VERSION' did not parse for build-number derivation"
    exit 1
fi
echo "── Build number derived from VERSION=$VERSION → $BUILD_NUMBER"

# Version monotonicity gate: a typo'd lower version would silently downgrade
# the Homebrew cask and write an out-of-order appcast item. The build-number
# encoding above is strictly increasing across stable and beta releases
# (stable X.Y.Z > any X.Y.Z-betaN because BETA_N=100 for stable), so a
# numeric compare against the newest (top-most) <sparkle:version> in the
# appcast covers both cases.
if [[ ! -f appcast.xml ]]; then
    echo "Error: appcast.xml not found — run from the repository root."
    exit 1
fi
LATEST_APPCAST_BUILD="$(grep -Eo '<sparkle:version>[0-9]+</sparkle:version>' appcast.xml | head -1 | tr -dc '0-9' || true)"
if [[ -n "$LATEST_APPCAST_BUILD" ]]; then
    if (( BUILD_NUMBER <= LATEST_APPCAST_BUILD )); then
        echo "Error: build number $BUILD_NUMBER (v$VERSION) is not strictly greater than the"
        echo "       newest appcast item's <sparkle:version> ($LATEST_APPCAST_BUILD)."
        echo "       Releasing it would downgrade Sparkle users and/or the Homebrew cask."
        echo "       Double-check VERSION."
        exit 1
    fi
    echo "── Monotonicity check passed: $BUILD_NUMBER > $LATEST_APPCAST_BUILD (newest appcast item)."
else
    echo "── No existing <sparkle:version> found in appcast.xml; skipping monotonicity check."
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    if [[ "$IS_BETA" == "1" ]]; then
        echo "Note: cutting a beta from non-main branch '$CURRENT_BRANCH'."
        echo "      Beta is OK off any branch (prerelease + beta channel + cask skip)."
        echo "      The version bump and appcast commits will land on '$CURRENT_BRANCH'."
    else
        echo "Error: Stable releases must be cut from 'main' (currently on '$CURRENT_BRANCH')."
        exit 1
    fi
fi

if [[ -n "$(git diff --stat HEAD)" ]]; then
    echo "Error: Working tree has uncommitted changes. Commit or stash changes first."
    exit 1
fi

if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Error: Tag v$VERSION already exists"
    exit 1
fi

for cmd in xcodebuild gh ditto xcrun xmllint; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required tool '$cmd' not found"
        exit 1
    fi
done

# Verify Developer ID certificate is available
SIGN_IDENTITY="Developer ID Application"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "Error: No '$SIGN_IDENTITY' certificate found in keychain."
    echo "       Install a Developer ID Application certificate from https://developer.apple.com"
    exit 1
fi

# Verify notarization credentials are stored
if ! xcrun notarytool history --keychain-profile "meridian-notary" &>/dev/null; then
    echo "Error: Notarization credentials not found. Store them with:"
    echo "  xcrun notarytool store-credentials \"meridian-notary\" \\"
    echo "    --apple-id \"YOUR_APPLE_ID\" --team-id \"YOUR_TEAM_ID\" --password \"APP_SPECIFIC_PASSWORD\""
    exit 1
fi

# Find sign_update
SIGN_UPDATE=""
SPARKLE_PATHS=(
    "$(xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -showBuildSettings 2>/dev/null | grep -m1 BUILD_DIR | awk '{print $3}' 2>/dev/null || true)/../../SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    "$HOME/Library/Developer/Xcode/DerivedData/Meridian-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
)
for path in "${SPARKLE_PATHS[@]}"; do
    # Use compgen for glob expansion
    for expanded in $path; do
        if [[ -x "$expanded" ]]; then
            SIGN_UPDATE="$expanded"
            break 2
        fi
    done
done

if [[ -z "$SIGN_UPDATE" ]]; then
    echo "Error: Sparkle sign_update not found. Build the project in Xcode first to resolve SPM packages."
    exit 1
fi

echo "Using sign_update: $SIGN_UPDATE"

# ── Collect release notes ───────────────────────────────────────────

# Collect notes from PRs merged since last release
if [[ -z "$NOTES" ]]; then
    # Find the date of the last release tag
    LAST_TAG="$(git tag --sort=-v:refname | head -1)"
    if [[ -n "$LAST_TAG" ]]; then
        SINCE_DATE="$(git log -1 --format=%aI "$LAST_TAG")"
        echo "── Finding PRs merged since $LAST_TAG ($SINCE_DATE)..."
    else
        SINCE_DATE=""
        echo "── Finding merged PRs (no previous release found)..."
    fi

    # Get all PRs merged since last release (or a specific one)
    if [[ -n "$PR_NUMBER" ]]; then
        PR_NUMBERS="$PR_NUMBER"
    elif [[ -n "$SINCE_DATE" ]]; then
        PR_NUMBERS="$(gh pr list --state merged --json number,mergedAt \
            --jq "[.[] | select(.mergedAt > \"$SINCE_DATE\")] | .[].number" 2>/dev/null || true)"
    else
        PR_NUMBERS="$(gh pr list --state merged --limit 5 --json number --jq '.[].number' 2>/dev/null || true)"
    fi

    if [[ -n "$PR_NUMBERS" ]]; then
        while IFS= read -r pr; do
            [[ -z "$pr" ]] && continue
            PR_TITLE="$(gh pr view "$pr" --json title --jq '.title' 2>/dev/null || true)"
            PR_BODY="$(gh pr view "$pr" --json body --jq '.body' 2>/dev/null || true)"

            # Extract bullet points from PR body (skip checkboxes, test plan items, generated lines)
            PR_BULLETS="$(echo "$PR_BODY" | grep -E '^\s*[-*] ' | grep -v -E '\[[ x]\]|Generated with|Test plan' | sed 's/^\s*[-*] //' | head -10)"

            if [[ -n "$PR_BULLETS" ]]; then
                NOTES="${NOTES:+$NOTES
}$PR_BULLETS"
            elif [[ -n "$PR_TITLE" ]]; then
                NOTES="${NOTES:+$NOTES
}$PR_TITLE"
            fi
            echo "  PR #$pr: $PR_TITLE"
        done <<< "$PR_NUMBERS"
    fi
fi

if [[ -z "$NOTES" ]] && ! tty -s; then
    # Read from stdin (piped input)
    NOTES="$(cat)"
fi

if [[ -z "$NOTES" ]] && tty -s; then
    # Interactive: open $EDITOR
    TMPFILE="$(mktemp /tmp/meridian-release-notes.XXXXXX)"
    echo "# Enter release notes (one per line, lines starting with # are ignored)" > "$TMPFILE"
    "${EDITOR:-vi}" "$TMPFILE"
    NOTES="$(grep -v '^#' "$TMPFILE" | sed '/^$/d')"
    rm -f "$TMPFILE"
fi

if [[ -z "$NOTES" ]]; then
    echo "Error: Release notes cannot be empty"
    exit 1
fi

echo ""
echo "=== Releasing Meridian v$VERSION ==="
echo ""
echo "Release notes:"
echo "$NOTES" | while IFS= read -r line; do echo "  - $line"; done
echo ""

# ── Phase 2: Bump version + commit (push deferred) ─────────────────
# The bump commit stays LOCAL until build/sign/notarize/staple all succeed,
# so a failed release can't leave a phantom version bump on origin.

echo "── Bumping version to $VERSION (build $BUILD_NUMBER)..."
PBXPROJ="Meridian/Meridian.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PBXPROJ"

git add "$PBXPROJ"
if git diff --cached --quiet; then
    echo "── Version already set to $VERSION, skipping commit."
else
    git commit -m "Bump version to $VERSION [skip ci]"
    echo "── Version bumped (commit kept local until notarization succeeds)."
fi

# Pin the exact commit this release is built from. Passed to
# `gh release create --target` so the tag points at this commit even if
# the remote branch moves during the multi-minute build/notarize.
RELEASE_REV="$(git rev-parse HEAD)"

# From here on a bump commit exists that origin may not have. If anything
# fails before the flow completes, report exactly what state things are in.
BUMP_PUSHED=0
GH_RELEASE_CREATED=0
APPCAST_COMMITTED=0
APPCAST_PUSHED=0
RELEASE_COMPLETE=0

report_release_state() {
    local exit_code=$?
    [[ $RELEASE_COMPLETE -eq 1 ]] && return 0
    echo ""
    echo "=== Release v$VERSION did NOT complete (exit $exit_code) — current state ==="
    if [[ $BUMP_PUSHED -eq 1 ]]; then
        echo "  * Version bump commit ($RELEASE_REV) is committed and PUSHED to origin."
    else
        echo "  * Version bump commit ($RELEASE_REV) exists LOCALLY only; origin is untouched."
        echo "    To abandon this release: git reset --hard origin/$CURRENT_BRANCH"
    fi
    if [[ $GH_RELEASE_CREATED -eq 1 ]]; then
        echo "  * GitHub release v$VERSION WAS created (undo: gh release delete v$VERSION --cleanup-tag)."
    else
        echo "  * GitHub release v$VERSION was NOT created."
    fi
    if [[ $APPCAST_COMMITTED -eq 1 && $APPCAST_PUSHED -eq 1 ]]; then
        echo "  * appcast.xml WAS updated and pushed (Sparkle clients can see v$VERSION)."
    elif [[ $APPCAST_COMMITTED -eq 1 ]]; then
        echo "  * appcast.xml WAS committed locally but NOT pushed (push with: git push origin main)."
    else
        echo "  * appcast.xml was NOT updated."
    fi
    echo "  Re-running the same release command resumes safely: the existing bump commit"
    echo "  is detected and skipped, and the push happens only after notarization."
}
trap report_release_state EXIT

# ── Phase 3: Build + sign ──────────────────────────────────────────

RELEASE_DIR="$(mktemp -d /tmp/meridian-release.XXXXXX)"
echo "── Release staging dir: $RELEASE_DIR"

echo "── Building release..."
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Release \
    -derivedDataPath "$RELEASE_DIR" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM=3LWTY5PDSS \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build 2>&1 | tail -5

APP_PATH="$(find "$RELEASE_DIR" -name "Meridian.app" -type d | head -1)"
if [[ -z "$APP_PATH" ]]; then
    echo "Error: Meridian.app not found after build"
    exit 1
fi

# Read the deployment target stamped into the freshly-built bundle.
# Used below for the appcast's <sparkle:minimumSystemVersion> so Sparkle
# clients on older macOS don't try to install an installer their OS
# can't run. LSMinimumSystemVersion in Info.plist is wired to
# ${MACOSX_DEPLOYMENT_TARGET} so it always matches the binary.
MIN_OS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null)"
if [[ -z "$MIN_OS" ]]; then
    echo "Error: could not read LSMinimumSystemVersion from $APP_PATH/Contents/Info.plist"
    exit 1
fi
echo "── Deployment target: macOS $MIN_OS"

# Strip extended attributes and resource forks that create ._* files on extraction
echo "── Stripping extended attributes..."
xattr -rc "$APP_PATH"

# Re-sign Sparkle components (SPM pre-built binaries need our identity)
echo "── Re-signing Sparkle framework components..."
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
    echo "Error: Sparkle.framework not found at $SPARKLE_FW"
    echo "       The app cannot self-update without it — aborting."
    exit 1
fi

# Resolve the framework version dir dynamically (Sparkle currently names its
# single version "B" — don't hardcode that) so a Sparkle bump that changes
# the layout can't silently skip re-signing.
SPARKLE_VDIR=""
if [[ -d "$SPARKLE_FW/Versions/Current/" ]]; then
    SPARKLE_VDIR="$(cd "$SPARKLE_FW/Versions/Current" && pwd -P)"
else
    for candidate in "$SPARKLE_FW"/Versions/*/; do
        candidate="${candidate%/}"
        [[ -d "$candidate" ]] || continue
        [[ "$(basename "$candidate")" == "Current" ]] && continue
        SPARKLE_VDIR="$candidate"
        break
    done
fi
if [[ -z "$SPARKLE_VDIR" || ! -d "$SPARKLE_VDIR" ]]; then
    echo "Error: could not resolve a version directory under $SPARKLE_FW/Versions"
    exit 1
fi
echo "  Sparkle version dir: $SPARKLE_VDIR"

# Sign inside-out: XPC services first, then helper apps, then framework, then main app.
# Count what we sign and FAIL LOUDLY if a glob matches nothing — a Sparkle
# layout change must never silently ship unsigned installer components.
XPC_COUNT=0
for xpc in "$SPARKLE_VDIR"/XPCServices/*.xpc; do
    [[ -d "$xpc" ]] || continue
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$xpc"
    XPC_COUNT=$((XPC_COUNT + 1))
done
HELPER_COUNT=0
for helper in "$SPARKLE_VDIR"/*.app; do
    [[ -d "$helper" ]] || continue
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$helper"
    HELPER_COUNT=$((HELPER_COUNT + 1))
done
if [[ $XPC_COUNT -eq 0 || $HELPER_COUNT -eq 0 ]]; then
    echo "Error: expected Sparkle installer components were not found under $SPARKLE_VDIR"
    echo "       (XPC services signed: $XPC_COUNT, helper apps signed: $HELPER_COUNT)."
    echo "       The Sparkle framework layout has likely changed — update the signing"
    echo "       paths in scripts/release.sh before releasing."
    exit 1
fi
if [[ ! -e "$SPARKLE_VDIR/Autoupdate" ]]; then
    echo "Error: Sparkle Autoupdate binary not found at $SPARKLE_VDIR/Autoupdate"
    exit 1
fi
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_VDIR/Autoupdate"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FW"
echo "  Signed $XPC_COUNT XPC service(s), $HELPER_COUNT helper app(s), Autoupdate, and the framework."

# Re-sign the main app (picks up entitlements, ensures timestamp)
ENTITLEMENTS="Meridian/App/Meridian.entitlements"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"

# Verify the app is properly signed
echo "── Verifying code signature..."
if ! codesign --verify --deep --strict "$APP_PATH" 2>&1; then
    echo "Error: Code signature verification failed"
    exit 1
fi
echo "  Signature valid."

ZIP_PATH="$RELEASE_DIR/Meridian.app.zip"
echo "── Creating zip for notarization..."
ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# Notarize
echo "── Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "meridian-notary" --wait

echo "── Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# Strip all xattrs after stapling, then re-zip without resource forks
# This prevents ._* AppleDouble files from appearing on extraction
xattr -rc "$APP_PATH"
rm "$ZIP_PATH"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "  Notarized and stapled."

echo "── Signing with Sparkle..."
SIGN_OUTPUT="$("$SIGN_UPDATE" "$ZIP_PATH")"
echo "  $SIGN_OUTPUT"

ED_SIGNATURE="$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

if [[ -z "$ED_SIGNATURE" || -z "$LENGTH" ]]; then
    echo "Error: Failed to parse signature output"
    echo "Raw output: $SIGN_OUTPUT"
    exit 1
fi

echo "  Signature: ${ED_SIGNATURE:0:20}..."
echo "  Length: $LENGTH"

# ── Phase 4: Push version bump + GitHub release ─────────────────────

# Deferred from Phase 2: only publish the bump commit now that build,
# signing, notarization, and stapling have all succeeded.
echo "── Pushing version bump..."
git push origin main
if [[ "$CURRENT_BRANCH" == "main" ]]; then
    BUMP_PUSHED=1
fi

echo "── Creating GitHub release..."
RELEASE_BODY="$(echo "$NOTES" | while IFS= read -r line; do echo "- $line"; done)"
# macOS bash 3.x trips on expanding empty arrays under `set -u`, so split the
# command on whether the prerelease flag applies instead of using an array.
# --target pins the tag to the commit this release was built from (captured
# in Phase 2), not whatever the remote branch head happens to be by now.
if [[ $IS_BETA -eq 1 ]]; then
    gh release create "v$VERSION" "$ZIP_PATH" --title "v$VERSION" --notes "$RELEASE_BODY" --target "$RELEASE_REV" --prerelease
else
    gh release create "v$VERSION" "$ZIP_PATH" --title "v$VERSION" --notes "$RELEASE_BODY" --target "$RELEASE_REV"
fi
GH_RELEASE_CREATED=1

echo "── GitHub release created."

# ── Phase 5: Update appcast ─────────────────────────────────────────

echo "── Updating appcast.xml..."
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"

# Build <li> items from notes. Each line is HTML-escaped: the CDATA content
# is rendered as HTML by Sparkle, and an unescaped "]]>" in a note would
# terminate the CDATA block and corrupt the feed.
LI_ITEMS=""
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        LI_ITEMS="$LI_ITEMS                    <li>$(html_escape "$line")</li>
"
    fi
done <<< "$NOTES"
# Remove trailing newline
LI_ITEMS="${LI_ITEMS%$'\n'}"

DOWNLOAD_URL="https://github.com/tpak/Meridian/releases/download/v$VERSION/Meridian.app.zip"

# Beta items get a <sparkle:channel>beta</sparkle:channel> tag so only users who
# enabled "Receive beta releases" in About see them. Stable items omit the tag
# (the default channel is always allowed).
CHANNEL_TAG=""
if [[ $IS_BETA -eq 1 ]]; then
    CHANNEL_TAG="
            <sparkle:channel>beta</sparkle:channel>"
fi

NEW_ITEM="        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>$CHANNEL_TAG
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <description><![CDATA[
                <ul>
$LI_ITEMS
                </ul>
            ]]></description>
            <enclosure url=\"$DOWNLOAD_URL\" length=\"$LENGTH\" type=\"application/octet-stream\" sparkle:edSignature=\"$ED_SIGNATURE\"/>
        </item>"

# Insert new item after <title>Meridian</title> using temp files for reliability
APPCAST="appcast.xml"
TMPITEM="$(mktemp /tmp/appcast-item.XXXXXX)"
TMPAPPCAST="$(mktemp /tmp/appcast.XXXXXX)"
printf '%s\n' "$NEW_ITEM" > "$TMPITEM"
awk '
    /<title>Meridian<\/title>/ {
        print
        while ((getline line < "'"$TMPITEM"'") > 0) print line
        next
    }
    { print }
' "$APPCAST" > "$TMPAPPCAST"
rm -f "$TMPITEM"

# Validate the generated feed BEFORE it replaces appcast.xml or gets
# committed — a malformed appcast would break updates for every user.
if ! xmllint --noout "$TMPAPPCAST"; then
    echo "Error: generated appcast is not well-formed XML — aborting before commit."
    echo "       Inspect the generated file at: $TMPAPPCAST"
    echo "       appcast.xml in the working tree is unchanged."
    exit 1
fi
mv "$TMPAPPCAST" "$APPCAST"

git add "$APPCAST"
git commit -m "Update appcast.xml for v$VERSION"
APPCAST_COMMITTED=1

if ! git push origin main; then
    echo ""
    echo "WARNING: Failed to push appcast update. The release is live but appcast.xml needs manual push:"
    echo "  git push origin main"
    exit 1
fi
APPCAST_PUSHED=1

echo "── Appcast updated and pushed."

# ── Phase 6: Update Homebrew cask ──────────────────────────────────
# Skipped for betas — the Homebrew cask tracks stable releases only.

if [[ $IS_BETA -eq 1 ]]; then
    echo "── Skipping Homebrew cask update for beta release."
else
    echo "── Updating Homebrew cask..."
    ZIP_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

    CASK_REPO="tpak/homebrew-tpak"
    CASK_FILE="Casks/meridian.rb"

    if FILE_SHA="$(gh api "repos/$CASK_REPO/contents/$CASK_FILE" --jq '.sha' 2>/dev/null)"; then
        CASK_CONTENT="$(gh api "repos/$CASK_REPO/contents/$CASK_FILE" \
            --jq '.content' | base64 -d \
            | sed "s/version \".*\"/version \"$VERSION\"/" \
            | sed "s/sha256 \".*\"/sha256 \"$ZIP_SHA256\"/")"

        ENCODED="$(printf '%s' "$CASK_CONTENT" | base64)"

        gh api --method PUT "repos/$CASK_REPO/contents/$CASK_FILE" \
            -f message="Update meridian to v$VERSION" \
            -f content="$ENCODED" \
            -f sha="$FILE_SHA" > /dev/null

        echo "── Homebrew cask updated to v$VERSION."
    else
        echo "WARNING: Homebrew cask file not found at $CASK_REPO/$CASK_FILE. Skipping cask update."
    fi
fi

# ── Phase 7: Summary ────────────────────────────────────────────────

RELEASE_COMPLETE=1

echo ""
echo "=== Release v$VERSION complete! ==="
echo ""
echo "  GitHub release: https://github.com/tpak/Meridian/releases/tag/v$VERSION"
echo "  Appcast updated with signature and download URL"
echo "  Homebrew cask: brew install --cask tpak/tpak/meridian"
echo ""
