#!/usr/bin/env bash
# Validation for issue #197 — pin GitHub Actions to commit SHAs and declare workflow permissions.
#
# A tag like `actions/checkout@v7` is mutable: whoever controls the upstream repo can re-point it,
# and the new code runs with this workflow's GITHUB_TOKEN. Pinning to an immutable commit SHA (with
# the version as a trailing comment, which Dependabot reads and bumps) removes that.
#
# Checks 1-3 are offline; check 4 verifies against the upstream repos and is skipped without `gh`.

set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
skip() { printf '  \033[33m—\033[0m %s\n' "$1"; }

WORKFLOWS=(.github/workflows/*.yml)

echo "== 1. Workflows are valid YAML =="
for wf in "${WORKFLOWS[@]}"; do
  if python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1]))" "$wf" 2>/dev/null; then
    pass "$(basename "$wf") parses"
  else
    # PyYAML isn't guaranteed on every machine; don't fail the run over a missing module.
    if python3 -c "import yaml" 2>/dev/null; then
      fail "$(basename "$wf") is not valid YAML"
    else
      skip "PyYAML not installed — skipping YAML parse"
      break
    fi
  fi
done

echo "== 2. Every 'uses:' is pinned to a 40-hex commit SHA =="
UNPINNED=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  file=${line%%:*}; rest=${line#*:}; lineno=${rest%%:*}; text=${rest#*:}
  ref=$(printf '%s' "$text" | sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]]*(#.*)?$//')
  sha=${ref##*@}
  if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    fail "$file:$lineno pinned to a mutable ref: $ref"
    UNPINNED=1
  fi
done < <(grep -rn "uses:" "${WORKFLOWS[@]}" || true)
[ "$UNPINNED" -eq 0 ] && pass "all uses: refs are commit SHAs"

echo "== 3. Every pinned SHA carries a '# vX.Y.Z' version comment =="
NOCOMMENT=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  file=${line%%:*}; rest=${line#*:}; lineno=${rest%%:*}; text=${rest#*:}
  if ! printf '%s' "$text" | grep -qE '@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+(\.[0-9]+)*'; then
    fail "$file:$lineno has no '# vX.Y.Z' comment (Dependabot needs it to bump the pin)"
    NOCOMMENT=1
  fi
done < <(grep -rn "uses:" "${WORKFLOWS[@]}" || true)
[ "$NOCOMMENT" -eq 0 ] && pass "all pins are annotated with their version"

echo "== 4. Each pin resolves to the upstream tag named in its comment =="
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  skip "gh unavailable or unauthenticated — skipping upstream verification"
else
  BAD=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file=${line%%:*}; rest=${line#*:}; lineno=${rest%%:*}; text=${rest#*:}
    # Check 3 already reports uncommented pins; skip them here so the message stays readable.
    printf '%s' "$text" | grep -q '#' || continue
    ref=$(printf '%s' "$text" | sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]]*#.*$//')
    tag=$(printf '%s' "$text" | sed -E 's/.*#[[:space:]]*//')
    action=${ref%@*}; sha=${ref##*@}
    # github/codeql-action/init → the tags live on the github/codeql-action repo.
    repo=$(printf '%s' "$action" | cut -d/ -f1,2)
    actual=$(gh api "repos/$repo/git/ref/tags/$tag" --jq '.object.sha + " " + .object.type' 2>/dev/null)
    [ -z "$actual" ] && { fail "$file:$lineno tag $tag not found in $repo"; BAD=1; continue; }
    set -- $actual
    resolved=$1
    # Annotated tags point at a tag object; dereference to the commit.
    if [ "$2" = "tag" ]; then
      resolved=$(gh api "repos/$repo/git/tags/$1" --jq '.object.sha' 2>/dev/null)
    fi
    if [ "$resolved" = "$sha" ]; then
      pass "$action@$tag → ${sha:0:12}"
    else
      fail "$file:$lineno claims $tag but $tag is ${resolved:0:12}, not ${sha:0:12}"
      BAD=1
    fi
  done < <(grep -rn "uses:" "${WORKFLOWS[@]}" || true)
  [ "$BAD" -eq 0 ] && pass "every pin matches its upstream tag"
fi

echo "== 5. Every workflow declares top-level permissions =="
for wf in "${WORKFLOWS[@]}"; do
  if grep -qE '^permissions:' "$wf"; then
    pass "$(basename "$wf") declares a top-level permissions block"
  else
    fail "$(basename "$wf") has no top-level permissions: block"
  fi
done

echo "== 6. Dependabot still watches github-actions =="
if grep -q 'package-ecosystem: "github-actions"' .github/dependabot.yml; then
  pass "dependabot.yml keeps the github-actions ecosystem (it bumps SHA pins)"
else
  fail "dependabot.yml no longer watches github-actions — pins would go stale"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mALL CHECKS PASSED\033[0m\n'
else
  printf '\033[31mVALIDATION FAILED\033[0m\n'
fi
exit "$FAIL"
