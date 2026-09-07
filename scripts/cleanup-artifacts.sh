#!/bin/bash
# Reclaim disk from transient Meridian build artifacts.
#
# Everything this removes is regenerable from the repo. It exists because the
# artifacts accumulate in machine-local, non-obvious places that a laptop
# migration would either drag along or silently lose:
#
#   1. Xcode DerivedData. Xcode names each directory Meridian-<hash of the
#      .xcodeproj's ABSOLUTE PATH>, so every checkout path gets its own — agent
#      worktrees under .claude/worktrees, alternate checkouts, even a
#      differently-cased path to the same directory. They are never reaped.
#      Left alone this grew to 4.2 GB across 14 directories, 13 of them dead.
#   2. release.sh staging dirs under /tmp (a full DerivedData tree each).
#   3. The local UAT beta bundle and its build directory.
#   4. The orphan non-container preferences plist that unsigned builds write.
#
# Safe by construction: it only ever touches paths matching Meridian's own
# patterns, always keeps the DerivedData for the checkout it is run from, and
# --dry-run prints the plan without deleting anything.
#
# Usage:
#   scripts/cleanup-artifacts.sh [--dry-run] [--beta]
#
#   --dry-run   Report what would be removed; delete nothing.
#   --beta      Also remove the local UAT beta (~/Applications/Meridian-beta.app)
#               and its build dir. release.sh passes this after a successful
#               release, so a stale beta can't shadow the build just shipped.

set -euo pipefail

DRY_RUN=0
CLEAN_BETA=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1 ;;
        --beta)       CLEAN_BETA=1 ;;
        -h|--help)    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

DERIVED_ROOT="$HOME/Library/Developer/Xcode/DerivedData"
BETA_APP="$HOME/Applications/Meridian-beta.app"
BETA_BUILD_DIR="/tmp/meridian-beta-dd"
ORPHAN_PREFS="$HOME/Library/Preferences/com.tpak.Meridian.plist"
SANDBOX_CONTAINER="$HOME/Library/Containers/com.tpak.Meridian"

RECLAIMED_KB=0
REMOVED_COUNT=0
TAB="$(printf '\t')"

# Filesystem identity of a path, as "device:inode". Used instead of the path
# string because two DerivedData dirs can record different-looking paths for the
# same project: macOS is case-insensitive by default, so /Users/…/source/meridian
# and /Users/…/source/Meridian are one directory. `pwd -P` resolves symlinks but
# NOT case, so string comparison misses that; the inode never does.
fsid() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    stat -f '%d:%i' "$path" 2>/dev/null || true
}

# The DerivedData directory belonging to THIS checkout is never a candidate,
# whatever else the heuristics decide.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROTECTED_PROJECT="$REPO_ROOT/Meridian/Meridian.xcodeproj"

remove() {
    local path="$1" reason="$2" size_kb verb
    [[ -e "$path" ]] || return 0
    size_kb="$(du -sk "$path" 2>/dev/null | cut -f1)"
    size_kb="${size_kb:-0}"
    if [[ $DRY_RUN -eq 1 ]]; then
        verb="would remove"
    else
        rm -rf "$path"
        verb="removed     "
    fi
    printf '  %s %6s MB  %s\n                     (%s)\n' "$verb" "$((size_kb / 1024))" "$path" "$reason"
    RECLAIMED_KB=$((RECLAIMED_KB + size_kb))
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
}

echo "=== Meridian artifact cleanup ==="
if [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry run — nothing will be deleted)"
fi
echo "Protecting DerivedData for: $PROTECTED_PROJECT"

# ── DerivedData ─────────────────────────────────────────────────────
# Classify every Meridian-* directory, then remove two kinds:
#   stale     — its recorded WorkspacePath no longer exists on disk
#   duplicate — another directory points at the SAME real project directory
#               (case-variant or symlinked checkouts); keep this checkout's,
#               else the most recently built.
#
# bash 3.2 on macOS has no associative arrays, so group with sort/awk over a
# "fsid<TAB>exact<TAB>mtime<TAB>dir<TAB>workspace" table instead.
echo ""
echo "── Xcode DerivedData"
BEFORE=$REMOVED_COUNT
TABLE="$(mktemp -t meridian-cleanup)"
DUPES="$(mktemp -t meridian-cleanup-dupes)"
trap 'rm -f "$TABLE" "$DUPES"' EXIT

if [[ -d "$DERIVED_ROOT" ]]; then
    for dir in "$DERIVED_ROOT"/Meridian-*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        ws="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null || true)"

        if [[ -z "$ws" || ! -e "$ws" ]]; then
            remove "$dir" "stale — ${ws:-no recorded workspace} no longer exists"
            continue
        fi

        key="$(fsid "$ws")"
        mtime="$(stat -f '%m' "$dir" 2>/dev/null || echo 0)"
        # exact=1 marks the DerivedData whose recorded WorkspacePath is literally
        # this checkout, so it always outranks a case-variant of the same path.
        exact=0
        if [[ "$ws" == "$PROTECTED_PROJECT" ]]; then exact=1; fi
        printf '%s%s%s%s%s%s%s%s%s\n' \
            "$key" "$TAB" "$exact" "$TAB" "$mtime" "$TAB" "$dir" "$TAB" "$ws" >> "$TABLE"
    done
fi

# Group by filesystem identity; within a group rank the exact-match checkout
# first, then most recently built. The first row of each group is the keeper,
# every later row is a duplicate pointing at the same project.
if [[ -s "$TABLE" ]]; then
    sort -t"$TAB" -k1,1 -k2,2nr -k3,3nr "$TABLE" \
        | awk -F"$TAB" '
            $1 != prev { prev = $1; keeper[$1] = $5; next }
            { print $4 "\t" $5 "\t" keeper[$1] }
        ' > "$DUPES"

    while IFS="$TAB" read -r dupe dupe_ws keeper_ws; do
        [[ -n "$dupe" ]] || continue
        remove "$dupe" "duplicate — $dupe_ws is the same directory as $keeper_ws"
    done < "$DUPES"
fi

if [[ $REMOVED_COUNT -eq $BEFORE ]]; then
    echo "  nothing to remove"
fi

# ── release.sh staging leftovers ────────────────────────────────────
echo ""
echo "── release.sh temp files"
BEFORE=$REMOVED_COUNT
for leftover in /tmp/meridian-release.* /tmp/meridian-release-notes.* /tmp/appcast.* /tmp/appcast-item.*; do
    [[ -e "$leftover" ]] || continue
    remove "$leftover" "leftover release staging"
done
if [[ $REMOVED_COUNT -eq $BEFORE ]]; then
    echo "  nothing to remove"
fi

# ── Beta UAT artifacts ──────────────────────────────────────────────
echo ""
echo "── Local UAT beta"
if [[ $CLEAN_BETA -eq 1 ]]; then
    BEFORE=$REMOVED_COUNT
    if [[ $DRY_RUN -eq 0 ]] && pgrep -f "Meridian-beta.app/Contents/MacOS/Meridian" > /dev/null 2>&1; then
        osascript -e 'tell application "Meridian" to quit' > /dev/null 2>&1 || true
        sleep 2
    fi
    remove "$BETA_APP" "superseded by the released build"
    remove "$BETA_BUILD_DIR" "beta build directory"
    if [[ $REMOVED_COUNT -eq $BEFORE ]]; then
        echo "  nothing to remove"
    fi
else
    echo "  skipped (pass --beta to remove ~/Applications/Meridian-beta.app)"
fi

# ── Orphan preferences ──────────────────────────────────────────────
# Meridian ships sandboxed, so its real preferences live in the container. An
# UNSIGNED build (a Debug unit-test host, or a beta built without the
# entitlements) gets no sandbox and writes to ~/Library/Preferences instead.
# The shipping app never reads that file — it is pure scratch, and it is
# actively misleading, because it can make a beta look like it lost the user's
# data. Only remove it once the container proves the app really is sandboxed.
echo ""
echo "── Orphan preferences plist"
if [[ -e "$ORPHAN_PREFS" && -d "$SANDBOX_CONTAINER" ]]; then
    remove "$ORPHAN_PREFS" "unsigned-build scratch; real prefs live in the sandbox container"
elif [[ -e "$ORPHAN_PREFS" ]]; then
    echo "  KEPT $ORPHAN_PREFS — no sandbox container found, so this may be the live store"
else
    echo "  nothing to remove"
fi

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
    echo "=== Would reclaim $((RECLAIMED_KB / 1024)) MB across $REMOVED_COUNT item(s) ==="
else
    echo "=== Reclaimed $((RECLAIMED_KB / 1024)) MB across $REMOVED_COUNT item(s) ==="
fi
