#!/usr/bin/env python3
"""test-hygiene-gate.py — Apex tests must not depend on the state of one org.

Two patterns make a test pass or fail with the org instead of with the code:

  A  SeeAllData=true          the test reads real records and real users, so it
                              turns red when the data moves (SCRUM-477: 76 -> 61
                              stuck opportunities within one day) or when a new
                              user appears
  B  a fixed user in SOQL     [SELECT .. FROM User WHERE Username = '...@...']
                              exists in one org only (SCRUM-477/478: the Test-Org
                              account was hardcoded, the Prod-Org Drift Gate went
                              red with "List has no rows for assignment")

Both reached master only because nothing stopped them. The Drift Gate runs every
local test against Prod-Org on every PR, so one such test blocks unrelated
tickets later. Only ADDED lines are checked: the two SeeAllData classes already
on master (both SCRUM-477) stay as they are until someone touches those lines.

  scripts/test-hygiene-gate.py --base origin/master     lines added since the merge base
  scripts/test-hygiene-gate.py --files A.cls B.cls      every line counts as added
"""
import argparse, pathlib, re, subprocess, sys

CLASS_RE = re.compile(r"force-app/.*/classes/[^/]+\.cls$")
SEEALL_RE = re.compile(r"SeeAllData\s*=\s*true", re.I)
SOQL_RE = re.compile(r"\[\s*SELECT\b.*?\]", re.I | re.S)
FROM_USER_RE = re.compile(r"\bFROM\s+User\b", re.I)
# A literal address compared in a User query. Creating a test user with
# `new User(Username = 'x@example.com')` is fine and not matched: it is no query.
FIXED_USER_RE = re.compile(r"\b(Username|Email)\s*(=|LIKE|IN)\s*\(?\s*'[^']*@", re.I)

HOW_TO_FIX = (
    "create the users and records the test needs inside the test "
    "(model: SCRUM449OpportunityRiskFlsTest — insert a User with a standard profile, "
    "assign the Permission Set, assert inside System.runAs). Whether real users in an "
    "org hold a Permission Set is a release read-back (scripts/fls-check.sh), not a test."
)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def added_lines(base, path):
    """Line numbers (in the new file) that the diff against base adds."""
    out = git("diff", "-U0", f"{base}...HEAD", "--", path)
    lines = set()
    for m in re.finditer(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", out, re.M):
        start, count = int(m.group(1)), int(m.group(2) or 1)
        lines.update(range(start, start + count))
    return lines


def findings(path, text, added):
    """(line, message) for every violation that touches an added line."""
    found = []
    for no, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith(("//", "*", "/*")):
            continue  # a comment that explains the rule is not a violation
        if no in added and SEEALL_RE.search(line):
            found.append((no, "SeeAllData=true makes the test depend on the org's real data and users"))
    for m in SOQL_RE.finditer(text):
        block = m.group(0)
        if not (FROM_USER_RE.search(block) and FIXED_USER_RE.search(block)):
            continue
        first = text.count("\n", 0, m.start()) + 1
        last = first + block.count("\n")
        if added & set(range(first, last + 1)):
            found.append((first, "a fixed user address in a User query exists in one org only"))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", help="ref to diff against, e.g. origin/master")
    ap.add_argument("--files", nargs="*", help="check these files completely")
    a = ap.parse_args()

    if a.files:
        targets = {f: None for f in a.files}
    elif a.base:
        names = git("diff", "--name-only", "--diff-filter=AM", f"{a.base}...HEAD").split()
        targets = {f: added_lines(a.base, f) for f in names if CLASS_RE.search(f)}
    else:
        ap.error("--base or --files")

    total = 0
    for path, added in sorted(targets.items()):
        text = pathlib.Path(path).read_text(encoding="utf-8")
        if added is None:
            added = set(range(1, text.count("\n") + 2))
        for no, msg in findings(path, text, added):
            total += 1
            print(f"::error file={path},line={no},title=Test depends on the org::{msg} — {HOW_TO_FIX}")
            print(f"{path}:{no}: {msg}")

    checked = len(targets)
    if total:
        print(f"\ntest-hygiene-gate: {total} finding(s) in {checked} changed test class file(s).")
        return 1
    print(f"test-hygiene-gate: {checked} changed Apex class file(s), no org-dependent test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
