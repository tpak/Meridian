#!/usr/bin/env python3
"""Compute SonarQube's new_coverage metric locally, before the push.

The quality gate fails a pull request when coverage on *new* code is under 80%.
That verdict currently only arrives from CI, minutes after the push, which is how
PR #224 merged at 75% -- nobody could see the number while there was still a cheap
opportunity to fix it. This reproduces the metric on a laptop.

"New code" is the set of lines the branch adds or changes relative to a base ref.
Only lines the coverage report considers coverable count: declarations, comments
and blank lines are not in the report and are not in the denominator, which is
exactly how Sonar computes it.

    # full cycle -- run the tests, convert, report
    python3 scripts/new_code_coverage.py --xcresult TestResults/unit-tests.xcresult

    # reuse a report you already have
    python3 scripts/new_code_coverage.py --coverage coverage.xml --base origin/main

Exits non-zero when new-code coverage is below the threshold, so it works as a
pre-push check. A branch that adds no coverable lines passes: Sonar skips the
condition rather than failing it when the metric is empty, and so do we.
"""

import argparse
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent

# "@@ -1,2 +34,5 @@" -> the post-image hunk starts at 34 and runs 5 lines.
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def git(args, cwd):
    """Run a git command and return stdout, or None if git itself failed."""
    try:
        completed = subprocess.run(
            ["git", *args], capture_output=True, text=True, check=True,
            shell=False, cwd=str(cwd),
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"git failed: {exc}", file=sys.stderr)
        return None
    return completed.stdout


def changed_lines_from_git(base, root):
    """Map each changed Swift file to the set of line numbers the branch added.

    Uses the three-dot form so the comparison is against the merge base, matching
    what Sonar analyses for a pull request rather than penalising the branch for
    everything that landed on main in the meantime.
    """
    diff = git(["diff", "--unified=0", "--no-color", f"{base}...HEAD", "--", "*.swift"], root)
    if diff is None:
        return None

    changed = {}
    current = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            target = line[4:].strip()
            # /dev/null is a deletion; the b/ prefix is git's post-image marker.
            current = target[2:] if target.startswith("b/") else None
            continue
        if current is None:
            continue
        match = HUNK_RE.match(line)
        if not match:
            continue
        start = int(match.group(1))
        count = 1 if match.group(2) is None else int(match.group(2))
        if count:  # count 0 is a pure deletion -- it adds no line to review
            changed.setdefault(current, set()).update(range(start, start + count))
    return changed


def changed_lines_from_file(path):
    """Read a literal "path:line" list. Keeps the arithmetic testable without git."""
    changed = {}
    for raw in pathlib.Path(path).read_text().splitlines():
        entry = raw.strip()
        if not entry or ":" not in entry:
            continue
        name, _, number = entry.rpartition(":")
        if number.isdigit():
            changed.setdefault(name, set()).add(int(number))
    return changed


def coverage_from_xcresult(bundle, root):
    """Convert an .xcresult with the same script CI uses, so both read one source."""
    converter = HERE / "xccov_to_sonar.py"
    try:
        completed = subprocess.run(
            [sys.executable, str(converter), str(bundle), "--root", str(root)],
            capture_output=True, text=True, check=True, shell=False,
        )
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"coverage conversion failed: {exc}", file=sys.stderr)
        return None
    return completed.stdout


def sonar_property(text, key):
    """Read one property out of sonar-project.properties. Blank when absent."""
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        if name.strip() == key:
            return value.strip()
    return ""


def sonar_pattern(glob):
    """Translate one Sonar path pattern into a regex.

    Sonar's globs are not fnmatch: ** spans directory separators and * does not.
    fnmatch.translate collapses that distinction and would quietly over-exclude.
    """
    out, index = [], 0
    while index < len(glob):
        char = glob[index]
        if glob.startswith("**/", index):
            out.append("(?:.*/)?")
            index += 3
        elif glob.startswith("**", index):
            out.append(".*")
            index += 2
        elif char == "*":
            out.append("[^/]*")
            index += 1
        elif char == "?":
            out.append("[^/]")
            index += 1
        else:
            out.append(re.escape(char))
            index += 1
    return re.compile("^" + "".join(out) + "$")


def excluded_matcher(root):
    """Build the predicate for "Sonar would not count this file's coverage".

    Test sources and excluded paths are read from sonar-project.properties rather
    than restated here, so the local number cannot drift from the gate's. Test
    files run on every invocation and are therefore ~100% covered; counting them
    inflates new-code coverage and hides exactly the gap the gate is measuring.
    """
    config = root / "sonar-project.properties"
    if not config.is_file():
        return lambda path: False

    text = config.read_text()
    patterns = []
    for key in ("sonar.exclusions", "sonar.coverage.exclusions"):
        for glob in sonar_property(text, key).split(","):
            if glob.strip():
                patterns.append(sonar_pattern(glob.strip()))
    # sonar.tests names directory roots, not globs.
    roots = [entry.strip().rstrip("/") for entry in sonar_property(text, "sonar.tests").split(",") if entry.strip()]

    def excluded(path):
        if any(path == r or path.startswith(r + "/") for r in roots):
            return True
        return any(pattern.match(path) for pattern in patterns)

    return excluded


def parse_coverage(xml_text):
    """Map each file path to {line number: covered?} from generic coverage XML."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as exc:
        print(f"coverage report is not valid XML: {exc}", file=sys.stderr)
        return None

    report = {}
    for element in root.findall("file"):
        path = element.get("path")
        if not path:
            continue
        lines = report.setdefault(path, {})
        for line in element.findall("lineToCover"):
            number = line.get("lineNumber")
            if number and number.isdigit():
                lines[int(number)] = line.get("covered") == "true"
    return report


def measure(report, changed, excluded=None):
    """Intersect the changed lines with the coverable ones.

    Returns (per-file results, total coverable, total covered). A changed line the
    report does not mention is not coverable -- a comment, a blank line, or a file
    with no coverage data at all -- and is left out of both halves of the ratio.
    Files Sonar excludes from coverage are skipped entirely, for the same reason.
    """
    per_file = {}
    total = covered = 0
    for path, lines in sorted(changed.items()):
        if excluded and excluded(path):
            continue
        coverable = report.get(path)
        if not coverable:
            continue
        hits = sorted(line for line in lines if line in coverable)
        if not hits:
            continue
        misses = [line for line in hits if not coverable[line]]
        per_file[path] = (len(hits) - len(misses), len(hits), misses)
        total += len(hits)
        covered += len(hits) - len(misses)
    return per_file, total, covered


def report_result(per_file, total, covered, threshold):
    """Print the per-file breakdown and return the process exit code."""
    if not total:
        print("no new coverable lines -- nothing for the coverage gate to judge")
        return 0

    percent = covered * 100.0 / total
    print(f"new code coverage: {percent:.1f}%  ({covered}/{total} lines)  threshold {threshold:.0f}%")
    print()
    for path, (file_covered, file_total, misses) in per_file.items():
        print(f"  {path}  {file_covered}/{file_total}")
        if misses:
            print(f"      uncovered: {', '.join(str(line) for line in misses)}")
    print()

    if percent + 1e-9 < threshold:
        print(f"FAIL: new code coverage {percent:.1f}% is below the {threshold:.0f}% threshold")
        return 1
    print(f"OK: new code coverage {percent:.1f}% meets the {threshold:.0f}% threshold")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = ap.add_mutually_exclusive_group(required=True)
    source.add_argument("--coverage", help="generic coverage XML, as produced by xccov_to_sonar.py")
    source.add_argument("--xcresult", help=".xcresult bundle to convert first")
    ap.add_argument("--base", default="origin/main", help="ref to diff against (default: origin/main)")
    ap.add_argument("--changed", help="literal 'path:line' list, instead of diffing against --base")
    ap.add_argument("--threshold", type=float, default=80.0, help="minimum new-code coverage (default: 80)")
    ap.add_argument("--root", default=str(HERE.parent), help="repo root; coverage paths are relative to it")
    opts = ap.parse_args()

    root = pathlib.Path(opts.root).resolve(strict=False)
    if not root.is_dir():
        print(f"not a directory: {opts.root}", file=sys.stderr)
        return 2

    if opts.xcresult:
        xml_text = coverage_from_xcresult(opts.xcresult, root)
    else:
        path = pathlib.Path(opts.coverage)
        if not path.is_file():
            print(f"no such coverage report: {opts.coverage}", file=sys.stderr)
            return 2
        xml_text = path.read_text()
    if xml_text is None:
        return 2

    report = parse_coverage(xml_text)
    if report is None:
        return 2

    if opts.changed:
        changed = changed_lines_from_file(opts.changed)
    else:
        changed = changed_lines_from_git(opts.base, root)
    if changed is None:
        return 2

    per_file, total, covered = measure(report, changed, excluded_matcher(root))
    return report_result(per_file, total, covered, opts.threshold)


if __name__ == "__main__":
    sys.exit(main())
