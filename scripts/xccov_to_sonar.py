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


def checked_dir(raw):
    """Resolve a path from argv and confirm it is a real directory.

    Nothing here is run through a shell, but validating before the value reaches
    xcrun keeps unchecked argv strings off the command line entirely.
    """
    resolved = pathlib.Path(raw).resolve(strict=False)
    return resolved if resolved.is_dir() else None


def xccov(args):
    """Run xccov and return stdout, or None if the bundle can't be read that way."""
    try:
        completed = subprocess.run(
            ["xcrun", "xccov", "view", "--archive", *args],
            capture_output=True, text=True, check=True, shell=False,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"xccov failed: {exc}", file=sys.stderr)
        return None
    return completed.stdout


def covered_lines(detail):
    """Turn xccov's per-line report into <lineToCover> elements."""
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
    return lines


def file_element(listed, bundle, root):
    """Build the <file> block for one source path, or None if it contributes nothing.

    Containment in root is checked *before* the path reaches xccov, so the only
    strings handed to the command are ones resolving inside the checkout.
    """
    source = pathlib.Path(listed).resolve(strict=False)
    try:
        rel = source.relative_to(root)
    except ValueError:
        return None  # outside the checkout - SPM checkout, SDK header, etc.

    detail = xccov(["--file", str(source), str(bundle)])
    if detail is None:
        return None

    lines = covered_lines(detail)
    if not lines:
        return None
    return [f"  <file path={quoteattr(str(rel))}>", *lines, "  </file>"]


def convert(bundle, root):
    """Return the <file> blocks for every covered source inside root."""
    listing = xccov(["--file-list", str(bundle)])
    if listing is None:
        return None

    chunks = []
    for raw in listing.splitlines():
        listed = raw.strip()
        if not listed:
            continue
        element = file_element(listed, bundle, root)
        if element:
            chunks.extend(element)
    return chunks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xcresult")
    ap.add_argument("--root", default=".", help="repo root; paths are emitted relative to it")
    opts = ap.parse_args()

    bundle = checked_dir(opts.xcresult)
    if bundle is None:
        print(f"not an .xcresult bundle: {opts.xcresult}", file=sys.stderr)
        return 1

    root = checked_dir(opts.root)
    if root is None:
        print(f"not a directory: {opts.root}", file=sys.stderr)
        return 1

    chunks = convert(bundle, root)
    if not chunks:
        print("no coverable files found inside --root", file=sys.stderr)
        return 1

    print('<?xml version="1.0" encoding="UTF-8"?>')
    print('<coverage version="1">')
    print("\n".join(chunks))
    print("</coverage>")
    print(f"converted coverage for {chunks.count('  </file>')} files", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
