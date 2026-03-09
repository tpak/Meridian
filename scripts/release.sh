#!/bin/bash
set -euo pipefail

VERSION=""
NOTES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n)
            NOTES="$2"
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

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: Working tree is not clean. Commit or stash changes first."
    exit 1
fi

if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "Error: Tag v$VERSION already exists"
    exit 1
fi

for cmd in xcodebuild gh ditto; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required tool '$cmd' not found"
        exit 1
    fi
done

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

if [[ -z "$NOTES" ]] && ! tty -s; then
    # Read from stdin (piped input)
    NOTES="$(cat)"
fi

if [[ -z "$NOTES" ]]; then
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
git commit -m "Bump version to $VERSION"
git push origin main

echo "── Version bumped and pushed."

# ── Phase 3: Build + sign ──────────────────────────────────────────

RELEASE_DIR="/tmp/meridian-release"
rm -rf "$RELEASE_DIR"

echo "── Building release..."
xcodebuild -project Meridian/Meridian.xcodeproj -scheme Meridian -configuration Release \
    -derivedDataPath "$RELEASE_DIR" \
    CODE_SIGN_IDENTITY="-" clean build 2>&1 | tail -5

APP_PATH="$(find "$RELEASE_DIR" -name "Meridian.app" -type d | head -1)"
if [[ -z "$APP_PATH" ]]; then
    echo "Error: Meridian.app not found after build"
    exit 1
fi

ZIP_PATH="$RELEASE_DIR/Meridian.app.zip"
echo "── Creating zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

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

# ── Phase 6: Summary ────────────────────────────────────────────────

echo ""
echo "=== Release v$VERSION complete! ==="
echo ""
echo "  GitHub release: https://github.com/tpak/Meridian/releases/tag/v$VERSION"
echo "  Appcast updated with signature and download URL"
echo ""
