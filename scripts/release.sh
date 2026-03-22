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

# ── Phase 1: Validate ──────────────────────────────────────────────

if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release.sh [-n \"release notes\"] X.Y.Z"
    echo "       make release VERSION=X.Y.Z"
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: VERSION must match X.Y.Z pattern (got: $VERSION)"
    exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Error: Must be on 'main' branch (currently on '$(git branch --show-current)')"
    exit 1
fi

if [[ -n "$(git diff --stat HEAD)" ]]; then
    echo "Error: Working tree has uncommitted changes. Commit or stash changes first."
    exit 1
fi

if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Error: Tag v$VERSION already exists"
    exit 1
fi

for cmd in xcodebuild gh ditto xcrun; do
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

# ── Phase 2: Bump version + commit ─────────────────────────────────

echo "── Bumping version to $VERSION..."
PBXPROJ="Meridian/Meridian.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $VERSION;/g" "$PBXPROJ"

git add "$PBXPROJ"
if git diff --cached --quiet; then
    echo "── Version already set to $VERSION, skipping commit."
else
    git commit -m "Bump version to $VERSION"
    git push origin main
    echo "── Version bumped and pushed."
fi

# ── Phase 3: Build + sign ──────────────────────────────────────────

RELEASE_DIR="/tmp/meridian-release"
rm -rf "$RELEASE_DIR"

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

# Strip extended attributes and resource forks that create ._* files on extraction
echo "── Stripping extended attributes..."
xattr -rc "$APP_PATH"

# Re-sign Sparkle components (SPM pre-built binaries need our identity)
echo "── Re-signing Sparkle framework components..."
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    # Sign inside-out: XPC services first, then helper apps, then framework, then main app
    for xpc in "$SPARKLE_FW"/Versions/B/XPCServices/*.xpc; do
        [[ -d "$xpc" ]] && codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$xpc"
    done
    for helper in "$SPARKLE_FW"/Versions/B/*.app; do
        [[ -d "$helper" ]] && codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$helper"
    done
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FW/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FW"
fi

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

# ── Phase 4: GitHub release ─────────────────────────────────────────

echo "── Creating GitHub release..."
RELEASE_BODY="$(echo "$NOTES" | while IFS= read -r line; do echo "- $line"; done)"
gh release create "v$VERSION" "$ZIP_PATH" --title "v$VERSION" --notes "$RELEASE_BODY"

echo "── GitHub release created."

# ── Phase 5: Update appcast ─────────────────────────────────────────

echo "── Updating appcast.xml..."
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"

# Build <li> items from notes
LI_ITEMS=""
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        LI_ITEMS="$LI_ITEMS                    <li>$line</li>
"
    fi
done <<< "$NOTES"
# Remove trailing newline
LI_ITEMS="${LI_ITEMS%$'\n'}"

DOWNLOAD_URL="https://github.com/tpak/Meridian/releases/download/v$VERSION/Meridian.app.zip"

NEW_ITEM="        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
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
mv "$TMPAPPCAST" "$APPCAST"
rm -f "$TMPITEM"

git add "$APPCAST"
git commit -m "Update appcast.xml for v$VERSION"

if ! git push origin main; then
    echo ""
    echo "WARNING: Failed to push appcast update. The release is live but appcast.xml needs manual push:"
    echo "  git push origin main"
    exit 1
fi

echo "── Appcast updated and pushed."

# ── Phase 6: Update Homebrew cask ──────────────────────────────────

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

# ── Phase 7: Summary ────────────────────────────────────────────────

echo ""
echo "=== Release v$VERSION complete! ==="
echo ""
echo "  GitHub release: https://github.com/tpak/Meridian/releases/tag/v$VERSION"
echo "  Appcast updated with signature and download URL"
echo "  Homebrew cask: brew install --cask tpak/tpak/meridian"
echo ""
