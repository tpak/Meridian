#!/usr/bin/env python3
"""Convert an Xcode .xcresult bundle's coverage into SonarQube generic coverage XML.

SonarQube cannot read .xcresult bundles, so CI converts one with this script and
points sonar.coverageReportPaths at the output. Usage:

    python3 scripts/xccov_to_sonar.py TestResults/unit-tests.xcresult --root . > coverage.xml

Only files inside --root are emitted, with repo-relative paths, so SonarQube can
match them to the sources it indexed. Anything outside (SPM checkouts, SDK
headers) is dropped. Exits non-zero if the bundle yields no coverable file, so
CI can skip the coverage import rather than publish a misleading 0%.
"""

import argparse
import pathlib
import re
import subprocess
import sys
from xml.sax.saxutils import quoteattr

# " 12: 3" -> executable, hit 3 times. " 12: *" -> not executable, no line emitted.
LINE_RE = re.compile(r"^\s*(\d+):\s*(\S+)\s*$")


def xccov(args):
    """Run xccov and return stdout, or None if the bundle can't be read that way."""
    try:
        out = subprocess.run(
            ["xcrun", "xccov", "view", "--archive", *args],
            capture_output=True, text=True, check=True,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"xccov failed: {exc}", file=sys.stderr)
        return None
    return out.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xcresult")
    ap.add_argument("--root", default=".", help="repo root; paths are emitted relative to it")
    opts = ap.parse_args()

    root = pathlib.Path(opts.root).resolve()
    listing = xccov(["--file-list", opts.xcresult])
    if listing is None:
        return 1

    emitted = 0
    chunks = []
    for raw in listing.splitlines():
        path = raw.strip()
        if not path:
            continue
        try:
            rel = pathlib.Path(path).resolve().relative_to(root)
        except ValueError:
            continue  # outside the checkout - SPM checkout, SDK header, etc.

        detail = xccov(["--file", path, opts.xcresult])
        if detail is None:
            continue

        lines = []
        for entry in detail.splitlines():
            match = LINE_RE.match(entry)
            if not match:
                continue
            number, hits = match.group(1), match.group(2)
            if hits == "*":
                continue  # comment, blank, declaration - nothing to cover
            covered = "false" if hits == "0" else "true"
            lines.append(f'    <lineToCover lineNumber="{number}" covered="{covered}"/>')

        if lines:
            chunks.append(f"  <file path={quoteattr(str(rel))}>")
            chunks.extend(lines)
            chunks.append("  </file>")
            emitted += 1

    if not emitted:
        print("no coverable files found inside --root", file=sys.stderr)
        return 1

    print('<?xml version="1.0" encoding="UTF-8"?>')
    print('<coverage version="1">')
    print("\n".join(chunks))
    print("</coverage>")
    print(f"converted coverage for {emitted} files", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
