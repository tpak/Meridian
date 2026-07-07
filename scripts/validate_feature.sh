#!/usr/bin/env bash
#
# validate_feature.sh — TDD checks for release-pipeline hardening in
# scripts/release.sh + the new appcast-validate CI workflow.
#
# Run BEFORE implementing (expect failures), then again after (expect all green).
#
#   bash scripts/validate_feature.sh
#
# SC2016: single-quoted grep patterns intentionally contain literal $.
# SC2015: `test && ok || bad` is safe here — ok() always succeeds.
# shellcheck disable=SC2016,SC2015
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

PASS=0
FAIL=0
RS="scripts/release.sh"
WF=".github/workflows/appcast-validate.yml"

ok()  { printf "  \033[32mOK:\033[0m   %s\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL:\033[0m %s\n" "$1" >&2; FAIL=$((FAIL+1)); }

check() { # check "description" <grep-args...>
  local desc="$1"; shift
  if grep -q "$@"; then ok "$desc"; else bad "$desc"; fi
}

first_line() { # first_line [grep-flags] <pattern> <file> — prints line number or 0
  local n
  n="$(grep -n "$@" | head -1 | cut -d: -f1)"
  echo "${n:-0}"
}

echo "Release-pipeline hardening — validation"
echo "---------------------------------------"

# ── 0. release.sh still parses ──────────────────────────────────────
if bash -n "$RS" 2>/dev/null; then
  ok "release.sh passes bash -n syntax check"
else
  bad "release.sh passes bash -n syntax check"
fi

# ── 1. HTML-escaping of appcast release notes ───────────────────────
check "html_escape() function exists" -Eq '^html_escape\(\)' "$RS"

# Raw, unescaped interpolation into <li> must be gone.
if grep -Fq '<li>$line</li>' "$RS"; then
  bad "appcast <li> items no longer interpolate raw \$line"
else
  ok "appcast <li> items no longer interpolate raw \$line"
fi

# The GitHub release body (markdown) must remain UNescaped.
check "GitHub release body still uses raw notes (markdown, unescaped)" -Fq 'echo "- $line"' "$RS"

# Behavior test: extract html_escape and run it against nasty inputs.
FN_FILE="$(mktemp "${TMPDIR:-/tmp}/meridian-html-escape.XXXXXX")"
sed -n '/^html_escape()/,/^}/p' "$RS" > "$FN_FILE"
if [[ -s "$FN_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$FN_FILE"
  if declare -f html_escape >/dev/null; then
    t1="$(html_escape 'Fix A & B')"
    t2="$(html_escape 'Show <n> zones')"
    t3="$(html_escape 'end ]]> boom')"
    [[ "$t1" == 'Fix A &amp; B' ]]        && ok "escape: 'Fix A & B' -> '$t1'"        || bad "escape: 'Fix A & B' gave '$t1' (want 'Fix A &amp; B')"
    [[ "$t2" == 'Show &lt;n&gt; zones' ]] && ok "escape: 'Show <n> zones' -> '$t2'"   || bad "escape: 'Show <n> zones' gave '$t2' (want 'Show &lt;n&gt; zones')"
    [[ "$t3" == 'end ]]&gt; boom' ]]      && ok "escape: 'end ]]> boom' -> '$t3' (CDATA-safe)" || bad "escape: 'end ]]> boom' gave '$t3' (want 'end ]]&gt; boom')"
  else
    bad "html_escape could not be sourced for behavior tests (3 checks skipped)"
    FAIL=$((FAIL+2))
  fi
else
  bad "html_escape not extractable from release.sh (behavior tests skipped)"
  FAIL=$((FAIL+2))
fi
rm -f "$FN_FILE"

# ── 2. xmllint gate before committing appcast ───────────────────────
check "release.sh runs 'xmllint --noout' on the generated appcast" -Fq 'xmllint --noout' "$RS"
check "xmllint listed as a required tool" -Eq 'for cmd in .*xmllint' "$RS"

XMLLINT_LINE="$(first_line 'xmllint --noout' "$RS")"
GITADD_LINE="$(first_line 'git add "\$APPCAST"' "$RS")"
if [[ "$XMLLINT_LINE" -gt 0 && "$GITADD_LINE" -gt 0 && "$XMLLINT_LINE" -lt "$GITADD_LINE" ]]; then
  ok "xmllint gate runs BEFORE 'git add appcast.xml' (line $XMLLINT_LINE < $GITADD_LINE)"
else
  bad "xmllint gate runs BEFORE 'git add appcast.xml' (xmllint@$XMLLINT_LINE, git add@$GITADD_LINE)"
fi

# ── 3. Version-bump push deferred until after notarization ──────────
# Match actual push COMMANDS (top-level or 'if ! ...'), not echo'd recovery text.
NOTARIZE_LINE="$(first_line 'notarytool submit' "$RS")"
PUSH_LINE="$(first_line -E '^(if ! )?git push origin main' "$RS")"
if [[ "$PUSH_LINE" -gt 0 && "$NOTARIZE_LINE" -gt 0 && "$PUSH_LINE" -gt "$NOTARIZE_LINE" ]]; then
  ok "first 'git push origin main' happens AFTER notarization (line $PUSH_LINE > $NOTARIZE_LINE)"
else
  bad "first 'git push origin main' happens AFTER notarization (push@$PUSH_LINE, notarize@$NOTARIZE_LINE)"
fi

GHREL_LINE="$(first_line -E '^[[:space:]]*gh release create' "$RS")"
if [[ "$PUSH_LINE" -gt 0 && "$GHREL_LINE" -gt 0 && "$PUSH_LINE" -lt "$GHREL_LINE" ]]; then
  ok "bump push happens BEFORE 'gh release create' (line $PUSH_LINE < $GHREL_LINE)"
else
  bad "bump push happens BEFORE 'gh release create' (push@$PUSH_LINE, gh release@$GHREL_LINE)"
fi

check "EXIT trap installed for failure-state reporting" -Eq 'trap .* EXIT' "$RS"
check "recovery report function exists" -Eq 'report_release_state\(\)' "$RS"

# ── 4. gh release create pinned with --target ───────────────────────
check "gh release create uses --target with a captured rev" -Eq 'gh release create .*--target "\$RELEASE_REV"' "$RS"
check "RELEASE_REV captured via git rev-parse HEAD" -Fq 'RELEASE_REV="$(git rev-parse HEAD)"' "$RS"

# ── 5. Sparkle re-signing: dynamic version dir + fail loudly ────────
if grep -Fq 'Versions/B' "$RS"; then
  bad "hardcoded Sparkle 'Versions/B' path removed"
else
  ok "hardcoded Sparkle 'Versions/B' path removed"
fi
check "Sparkle version dir resolved dynamically (Versions/Current)" -Fq 'Versions/Current' "$RS"
check "Sparkle XPC signing counts what it signed" -Eq 'XPC_COUNT' "$RS"
check "Sparkle signing aborts if XPC/helper globs match nothing" -Eq 'XPC_COUNT -eq 0 .*HELPER_COUNT -eq 0' "$RS"

# ── 6. Version monotonicity check ───────────────────────────────────
check "extracts newest <sparkle:version> from appcast.xml" -Eq 'LATEST_APPCAST_BUILD' "$RS"
check "aborts unless BUILD_NUMBER strictly greater" -Eq 'BUILD_NUMBER <= LATEST_APPCAST_BUILD' "$RS"

# ── 7. RELEASE_DIR via mktemp ───────────────────────────────────────
check "RELEASE_DIR uses mktemp -d (no fixed world-writable path)" -Fq 'RELEASE_DIR="$(mktemp -d /tmp/meridian-release.XXXXXX)"' "$RS"
if grep -Eq '^RELEASE_DIR="/tmp/meridian-release"' "$RS"; then
  bad "fixed RELEASE_DIR=/tmp/meridian-release removed"
else
  ok "fixed RELEASE_DIR=/tmp/meridian-release removed"
fi

# ── 8. Current repo appcast is valid (sanity of the gate itself) ────
if xmllint --noout appcast.xml 2>/dev/null; then
  ok "current appcast.xml passes xmllint --noout"
else
  bad "current appcast.xml passes xmllint --noout"
fi

TOTAL_ENC="$(xmllint --xpath 'count(//enclosure)' appcast.xml 2>/dev/null)"
VALID_ENC="$(xmllint --xpath 'count(//enclosure[string-length(@*[local-name()="edSignature"]) > 0 and string-length(@length) > 0])' appcast.xml 2>/dev/null)"
if [[ -n "$TOTAL_ENC" && "$TOTAL_ENC" -gt 0 && "$TOTAL_ENC" == "$VALID_ENC" ]]; then
  ok "all $TOTAL_ENC current enclosures carry non-empty edSignature + length"
else
  bad "all current enclosures carry non-empty edSignature + length (total=$TOTAL_ENC valid=$VALID_ENC)"
fi

# ── 9. Appcast-validate CI workflow ─────────────────────────────────
if [[ -f "$WF" ]]; then
  ok "workflow $WF exists"
  check "workflow triggers on push" -Eq '^  push:' "$WF"
  check "workflow triggers on pull_request" -Eq '^  pull_request:' "$WF"
  check "workflow is path-filtered to appcast.xml" -Fq "'appcast.xml'" "$WF"
  check "workflow runs on ubuntu-latest" -Fq 'ubuntu-latest' "$WF"
  check "workflow installs libxml2-utils when needed" -Fq 'libxml2-utils' "$WF"
  check "workflow runs xmllint --noout appcast.xml" -Fq 'xmllint --noout appcast.xml' "$WF"
  check "workflow checks enclosure edSignature attribute" -Fq 'edSignature' "$WF"
  check "workflow checks enclosure length attribute" -Fq '@length' "$WF"
  # Loose YAML sanity if PyYAML is available; skip silently otherwise.
  if python3 -c 'import yaml' 2>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$WF'))" 2>/dev/null; then
      ok "workflow YAML parses (PyYAML)"
    else
      bad "workflow YAML parses (PyYAML)"
    fi
  fi
else
  bad "workflow $WF exists (8 sub-checks skipped)"
  FAIL=$((FAIL+8))
fi

# ── 10. Existing behavior preserved ─────────────────────────────────
check "beta prerelease flag preserved" -Fq -- '--prerelease' "$RS"
check "beta sparkle channel tag preserved" -Fq '<sparkle:channel>beta</sparkle:channel>' "$RS"
check "idempotent re-run path preserved (skip commit when version already set)" -Fq 'skipping commit' "$RS"
check "stable-from-main branch check preserved" -Fq "Stable releases must be cut from 'main'" "$RS"
check "Homebrew cask skip for betas preserved" -Fq 'Skipping Homebrew cask update for beta release' "$RS"

echo ""
echo "---------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All checks passed."
