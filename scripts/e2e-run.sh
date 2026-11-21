#!/usr/bin/env bash
# e2e-run.sh — run one Playwright spec and end with a short verdict.
#
#   scripts/e2e-run.sh tests/e2e/SCRUM-467-offer-validity.spec.ts            # re-run what failed last time, else all
#   scripts/e2e-run.sh tests/e2e/SCRUM-467-offer-validity.spec.ts --all      # the whole spec (before a handoff)
#   scripts/e2e-run.sh tests/e2e/SCRUM-467-offer-validity.spec.ts --grep "AC9:|AC10:"
#
# Why: a whole spec runs 8-15 minutes. Re-running all of it to check one fixed
# test cost SCRUM-467 about 35 minutes (runs 3-6 had exactly one failure each).
# This script remembers which tests of a spec failed and, by default, runs only
# those. A green re-run of the failed tests is NOT a handoff verdict: finish
# with --all.
#
# Waiting: an agent's terminal call stops after 180 s. Targeted re-runs usually
# fit; a whole spec does not — start it as a background process and wait for
# its completion notice. No `sleep`: the summary is the last thing printed, so
# the notice already carries the verdict.
#
# The full Playwright output goes to .e2e-run/logs/ (git-ignored).
# Exit code: Playwright's (0 = every selected test passed).
set -uo pipefail

SPEC="" MODE="auto" GREP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     MODE="all"; shift ;;
    --grep)    MODE="grep"; GREP="${2:?--grep needs a pattern}"; shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*)        echo "unknown option: $1" >&2; exit 2 ;;
    *)         SPEC="$1"; shift ;;
  esac
done
[ -n "$SPEC" ] || { echo "usage: $0 <spec file> [--all | --grep <pattern>]" >&2; exit 2; }
[ -f "$SPEC" ] || { echo "no such spec: $SPEC" >&2; exit 2; }

CONFIG="${PW_CONFIG:-playwright.config.ts}"
NAME=$(basename "$SPEC" | sed 's/\.spec\.[tj]s$//')
# Not under test-results/: Playwright empties that folder at the start of every run.
STATE_DIR=".e2e-run/state"; LOG_DIR=".e2e-run/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"
FAILED_FILE="$STATE_DIR/$NAME.failed"          # one failing test title per line
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/$NAME-$STAMP.log"
# Absolute: Playwright resolves a relative PLAYWRIGHT_JSON_OUTPUT_NAME against the config file.
JSON="$PWD/$LOG_DIR/$NAME-$STAMP.json"

# What to run. "auto": the tests that failed in this spec's last run; none recorded -> all.
ARGS=()
if [ "$MODE" = "auto" ] && [ -s "$FAILED_FILE" ]; then
  GREP=$(python3 - "$FAILED_FILE" <<'PY'
import re, sys
titles = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print("|".join(re.escape(t) for t in titles))
PY
)
  MODE="failed"
fi
[ -n "$GREP" ] && ARGS+=(--grep "$GREP")

case "$MODE" in
  failed) echo "e2e-run: $NAME — re-running the $(grep -c . "$FAILED_FILE") test(s) that failed last time (use --all before a handoff)" ;;
  grep)   echo "e2e-run: $NAME — tests matching: $GREP" ;;
  *)      echo "e2e-run: $NAME — whole spec" ;;
esac

START=$(date +%s)
PLAYWRIGHT_JSON_OUTPUT_NAME="$JSON" npx playwright test -c "$CONFIG" "$SPEC" "${ARGS[@]}" \
  --reporter=line,json >"$LOG" 2>&1
RC=$?
SECS=$(( $(date +%s) - START ))

# Summary from the JSON report: counts, and per failing test its title and the
# first lines of its error. Also records this run's failures for the next "auto" run.
python3 - "$JSON" "$FAILED_FILE" "$MODE" "$RC" "$SECS" "$LOG" <<'PY'
import json, os, re, sys
path, failed_file, mode, rc, secs, log = sys.argv[1:7]
ansi = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
try:
    report = json.load(open(path, encoding="utf-8"))
except Exception:
    print(f"\nE2E RESULT: no report (Playwright exit {rc}) — read {log}")
    sys.exit(0)

def walk(suite):
    for spec in suite.get("specs", []):
        for test in spec.get("tests", []):
            yield spec.get("title", "?"), test
    for child in suite.get("suites", []):
        yield from walk(child)

passed, failed, skipped, flaky = [], [], [], []
for root in report.get("suites", []):
    for title, test in walk(root):
        status = test.get("status")            # expected | unexpected | flaky | skipped
        if status == "expected":
            passed.append(title)
        elif status == "flaky":
            flaky.append(title)
        elif status == "skipped":
            skipped.append(title)
        else:
            err = ""
            for res in test.get("results", []):
                e = (res.get("error") or {}).get("message") or ""
                if e:
                    err = e
            lines = [l.strip() for l in ansi.sub("", err).splitlines() if l.strip()][:3]
            failed.append((title, lines))

# Only a run over the remembered set or the whole spec may update the memory;
# a free --grep run says nothing about the tests it did not select.
if mode in ("auto", "all", "failed"):
    with open(failed_file, "w", encoding="utf-8") as fh:
        fh.writelines(t + "\n" for t, _ in failed)
    if mode == "failed" and not failed and os.path.exists(failed_file):
        os.remove(failed_file)

total = len(passed) + len(failed) + len(skipped) + len(flaky)
m, s = divmod(int(secs), 60)
scope = {"failed": "previously failed tests", "grep": "--grep selection", "all": "whole spec", "auto": "whole spec"}[mode]
print(f"\nE2E RESULT ({scope}, {m}m{s:02d}s): {len(passed)} passed, {len(failed)} failed"
      + (f", {len(flaky)} flaky" if flaky else "") + (f", {len(skipped)} skipped" if skipped else "")
      + f" of {total}")
for title, lines in failed:
    print(f"  FAIL {title}")
    for l in lines:
        print(f"       {l[:200]}")
if mode in ("failed", "grep") and not failed:
    print("  The selection is green. Run --all before handing over.")
print(f"  full log: {log}")
PY
exit $RC
