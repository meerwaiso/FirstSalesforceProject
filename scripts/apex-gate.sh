#!/usr/bin/env bash
# apex-gate.sh — run the Apex tests on THIS branch's code, not on what Test-Org holds.
#
#   scripts/apex-gate.sh --base origin/master --tests SCRUM483FooTest,SCRUM483BarTest
#   scripts/apex-gate.sh --base origin/master                 # no ticket tests -> RunLocalTests
#   scripts/apex-gate.sh                                      # no base: whole force-app, RunLocalTests
#
# Why: the old gate ran `sf apex run test` against Test-Org, i.e. against whatever an
# agent had last deployed there. SCRUM-483 (27.11.2026): CI on head 02e44d6 failed five
# methods with MIXED_DML_OPERATION for three rework rounds — on the 13:14 version of the
# test classes, because the reworked ones were never deployed. The same head, checked
# here, passes 9/9 and shows the one real blocker the old gate never could: a class at
# 50.6 % coverage, which the Prod deploy would refuse.
#
# How: the files the branch adds or changes under force-app/ become a manifest, and that
# manifest is validated check-only against the org with the given tests. Nothing is saved
# in the org. This is the same rule a Prod deploy applies: every Apex class and trigger in
# the delta needs 75 % coverage from the tests that run.
#
# Agents: run exactly this before a handoff. A green deploy-validate of a hand-picked
# manifest and a green `sf apex run test` against the org do not predict this gate.
#
# Exit code: 0 only when the validation succeeded. Verdict JSON: apex-gate.json.
set -uo pipefail

BASE="" ORG="Test-Org" TESTS="" OUT="apex-gate.json" WAIT=30
while [ $# -gt 0 ]; do
  case "$1" in
    --base)  BASE="${2:?}"; shift 2 ;;
    --org)   ORG="${2:?}"; shift 2 ;;
    --tests) TESTS="${2:-}"; shift 2 ;;
    --out)   OUT="${2:?}"; shift 2 ;;
    --wait)  WAIT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
TARGET=()
if [ -n "$BASE" ]; then
  # Added, modified, renamed — a deletion cannot be validated as source.
  mapfile -t FILES < <(git diff --name-only --diff-filter=AMR "$BASE...HEAD" -- force-app)
  if [ "${#FILES[@]}" -eq 0 ]; then
    echo "apex-gate: nothing under force-app/ changed against $BASE — nothing to test."
    exit 0
  fi
  ARGS=()
  for f in "${FILES[@]}"; do ARGS+=(--source-dir "$f"); done
  sf project generate manifest "${ARGS[@]}" --output-dir "$DIR" --name package.xml >/dev/null 2>"$DIR/gen.err" \
    || { echo "apex-gate: could not build the delta manifest:" >&2; cat "$DIR/gen.err" >&2; exit 1; }
  TARGET=(--manifest "$DIR/package.xml")
  echo "apex-gate: ${#FILES[@]} changed file(s) under force-app/ -> $(grep -c '<members>' "$DIR/package.xml") component(s)"
else
  TARGET=(--source-dir force-app)
  echo "apex-gate: no base given — validating the whole force-app/"
fi

if [ -n "$TESTS" ]; then
  LEVEL=(--test-level RunSpecifiedTests --tests "$TESTS")
  echo "apex-gate: tests $TESTS"
else
  LEVEL=(--test-level RunLocalTests)
  echo "apex-gate: no ticket tests named — RunLocalTests"
fi

"$(dirname "$0")/ci-prod-validate.sh" --org "$ORG" "${TARGET[@]}" "${LEVEL[@]}" --wait "$WAIT" --out "$OUT"
RC=$?
[ -s "$OUT" ] || { echo "apex-gate: no verdict (exit $RC) — red, never green" >&2; exit 1; }

python3 - "$OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
r = d.get("result") or {}
def as_list(x): return x if isinstance(x, list) else ([x] if x else [])
det = r.get("details") or {}
rt = det.get("runTestResult") or {}
print(f"\nAPEX GATE: {r.get('status')} — tests {r.get('numberTestsCompleted')}/{r.get('numberTestsTotal')} passed, "
      f"{r.get('numberTestErrors')} failed, {r.get('numberComponentErrors')} component error(s)")
for f in as_list(det.get("componentFailures")):
    msg = f"{f.get('fullName')}: {f.get('problem')}"
    print(f"::error title=Component error::{msg}"); print("  COMPONENT", msg)
for f in as_list(rt.get("failures")):
    msg = f"{f.get('name')}.{f.get('methodName')}: {(f.get('message') or '').splitlines()[0][:300]}"
    print(f"::error title=Apex test failed::{msg}"); print("  FAIL", msg)
for w in as_list(rt.get("codeCoverageWarnings")):
    msg = f"{w.get('name')}: {w.get('message')}"
    print(f"::error title=Coverage below 75 %::{msg}"); print("  COVERAGE", msg)
sys.exit(0 if r.get("success") else 1)
PY
