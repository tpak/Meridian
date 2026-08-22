#!/usr/bin/env bash
# Every localizable literal in shipping code must have a Localizable.xcstrings entry.
#
# String(localized:) falls back to the literal when a key is missing, so a string that never made
# it into the catalog looks perfectly fine in English while being untranslatable in every other
# language — it silently never reaches the translators. That's how #202 happened.
#
# Unlike scripts/validate_feature.sh (a per-task scratch file, overwritten by whatever work is in
# flight), this is a standing invariant. Run it after adding user-facing strings.

set -uo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, os, re, sys

CATALOG = 'Meridian/App/Localizable.xcstrings'
catalog = json.load(open(CATALOG))['strings']

# String(localized: "x") | "x".localized() | NSLocalizedString("x", ...)
pat = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"'
                 r'|"((?:[^"\\]|\\.)*)"\.localized\(\)'
                 r'|NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"')

missing, checked = [], 0
for root, _, files in os.walk('Meridian'):
    if any(skip in root for skip in ('MeridianUnitTests', 'MeridianUITests', 'Dependencies')):
        continue
    for name in (f for f in files if f.endswith('.swift')):
        path = os.path.join(root, name)
        for m in pat.finditer(open(path).read()):
            key = next(g for g in m.groups() if g is not None)
            if '\\(' in key:          # interpolated — not a literal catalog key
                continue
            checked += 1
            if key not in catalog:
                missing.append((path, key))

if missing:
    for path, key in missing:
        print("  \033[31m✗\033[0m %r used in %s has no %s entry" % (key, path, os.path.basename(CATALOG)))
    print("\n\033[31m%d string(s) can never be translated.\033[0m Add them to %s." % (len(missing), CATALOG))
    sys.exit(1)

print("  \033[32m✓\033[0m all %d localized literals resolve to a catalog entry" % checked)
PY
