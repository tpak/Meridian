#!/usr/bin/env bash
# Validation for issue #196 — shell injection in `make release` via NOTES=.
#
# The `release` recipe used to build a command string and run it through `eval`, so any NOTES value
# containing a quote plus shell metacharacters executed as shell — on the machine holding the
# Developer ID certificate and the notarization keychain profile.
#
# These checks run `make release` in a throwaway copy of the repo whose `scripts/release.sh` is a
# stub that records its argv. Nothing here touches the real release path, the network, or signing.

set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/scripts"
cp "$REPO/Makefile" "$SANDBOX/Makefile"

# Stub release.sh: records each argument on its own line, bracketed so empty args stay visible.
cat >"$SANDBOX/scripts/release.sh" <<'STUB'
#!/usr/bin/env bash
: >"$ARGV_OUT"
for a in "$@"; do printf '[%s]\n' "$a" >>"$ARGV_OUT"; done
STUB
chmod +x "$SANDBOX/scripts/release.sh"

CANARY="$SANDBOX/pwned"
ARGV_OUT="$SANDBOX/argv"
export ARGV_OUT

# run_release NOTES PR VERSION → populates $ARGV_OUT
run_release() {
  rm -f "$ARGV_OUT"
  ( cd "$SANDBOX" && make release NOTES="$1" PR="$2" VERSION="$3" ) >/dev/null 2>&1
}

echo "== 1. Injection payloads in NOTES do not execute =="
# Each payload tries to create $CANARY through a different escape: quote-break, backticks, $().
PAYLOADS=(
  'x" ; touch '"$CANARY"' ; echo "y'
  'note `touch '"$CANARY"'` end'
  'note $(touch '"$CANARY"') end'
  'note '"'"'; touch '"$CANARY"'; #'
)
for payload in "${PAYLOADS[@]}"; do
  rm -f "$CANARY"
  run_release "$payload" "" "1.2.3"
  if [ -e "$CANARY" ]; then
    fail "payload executed: $payload"
  else
    pass "inert: $payload"
  fi
done
rm -f "$CANARY"

echo "== 2. Hostile NOTES arrives at release.sh verbatim, as one argument =="
payload='x" ; touch /tmp/nope ; echo "y'
run_release "$payload" "" "1.2.3"
expected=$(printf '[-n]\n[%s]\n[1.2.3]\n' "$payload")
if [ "$(cat "$ARGV_OUT")" = "$expected" ]; then
  pass "argv is exactly -n <notes> <version>, notes unmangled"
else
  fail "argv mismatch"
  echo "      expected: $(printf '%s' "$expected" | tr '\n' ' ')"
  echo "      actual:   $(tr '\n' ' ' <"$ARGV_OUT")"
fi

echo "== 3. Multiline NOTES survives as a single argument =="
multi=$'Fix sunrise bug\nAdd keyboard shortcuts (#50)\nTweak "quoted" text'
run_release "$multi" "" "2.0.0"
if [ "$(grep -c '^\[' "$ARGV_OUT")" -eq 3 ] && grep -q 'Add keyboard shortcuts (#50)' "$ARGV_OUT"; then
  pass "3 args, newlines and quotes preserved inside the notes argument"
else
  fail "multiline notes were split or mangled"
  sed 's/^/      /' "$ARGV_OUT"
fi

echo "== 4. Ordinary invocations still pass the right argv =="
run_release "" "" "3.1.4"
[ "$(cat "$ARGV_OUT")" = "[3.1.4]" ] \
  && pass "VERSION only → [3.1.4]" || { fail "VERSION-only argv wrong"; sed 's/^/      /' "$ARGV_OUT"; }

run_release "" "42" "3.1.4"
[ "$(cat "$ARGV_OUT")" = "$(printf '[-p]\n[42]\n[3.1.4]')" ] \
  && pass "PR=42 → -p 42 3.1.4" || { fail "PR argv wrong"; sed 's/^/      /' "$ARGV_OUT"; }

run_release "Fix a bug" "42" "3.1.4"
[ "$(cat "$ARGV_OUT")" = "$(printf '[-n]\n[Fix a bug]\n[-p]\n[42]\n[3.1.4]')" ] \
  && pass "NOTES + PR → -n <notes> -p 42 3.1.4" || { fail "combined argv wrong"; sed 's/^/      /' "$ARGV_OUT"; }

echo "== 5. VERSION and PR are not eval'd either =="
rm -f "$CANARY"
run_release "" "" '1.0.0" ; touch '"$CANARY"' ; echo "'
[ -e "$CANARY" ] && fail "VERSION payload executed" || pass "hostile VERSION is inert"
rm -f "$CANARY"
run_release "" '1 ; touch '"$CANARY" "1.0.0"
[ -e "$CANARY" ] && fail "PR payload executed" || pass "hostile PR is inert"
rm -f "$CANARY"

echo "== 6. The recipe no longer uses eval =="
if grep -nE '(^|[[:space:]])eval[[:space:]]' Makefile >/dev/null; then
  fail "Makefile still runs eval"
  grep -nE '(^|[[:space:]])eval[[:space:]]' Makefile | sed 's/^/      /'
else
  pass "no eval in Makefile"
fi

echo "== 7. Missing VERSION still errors with usage =="
out=$( cd "$SANDBOX" && make release 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "Usage: make release"; then
  pass "make release with no VERSION exits non-zero with usage"
else
  fail "missing-VERSION guard broken (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mALL CHECKS PASSED\033[0m\n'
else
  printf '\033[31mVALIDATION FAILED\033[0m\n'
fi
exit "$FAIL"
