#!/usr/bin/env bash
# ci-prod-validate.sh — die Lifecycle eines deploy-Validation fuer CI:
# waann immer der GitHub-Step get cancelled, heisst die Validation Du hast
# startet in dem Org get cancelled too.
#
#   scripts/ci-prod-validate.sh --org Prod-Org --source-dir force-app \
#       --test-level RunLocalTests --wait 30 --out prod-validate.json
#   scripts/ci-prod-validate.sh --cancel --org Prod-Org --id-file .ci-validate-job-id
#
# Deshalb two Modes, one Script:
#   validate (default)  start async, remember the job id, poll for the verdict,
#                       write the verdict file the gate parser already reads.
#   --cancel            the `if: cancelled()` step: cancel exactly the id in the
#                       id-file, never the most recent operation.
#
# Measured 2026-11-17: a cancelled GitHub step kills this process after a few
# seconds — too short for `sf project deploy cancel` to finish. So the id gets
# written to a file the moment it is known, and the workflow's second step
# (`if: cancelled()`) reads that file. The trap is only the fallback.
# The pile-up it prevents was measured: six runs on one PR, five cancelled,
# queue wait 8 to 44 minutes while each validation ran 9 to 12 minutes.
#
# Exit codes: 0 only with a verdict. 1 with no verdict — a gate that could not
# answer stays red, never green.
set -uo pipefail

ORG="" SOURCE_DIR="" MANIFEST="" TEST_LEVEL="" WAIT=30 OUT="" ID_FILE=".ci-validate-job-id"
MODE="validate" TESTS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --cancel)      MODE="cancel"; shift ;;
    --org)         ORG="${2:?}"; shift 2 ;;
    --source-dir)  SOURCE_DIR="${2:?}"; shift 2 ;;
    --manifest)    MANIFEST="${2:?}"; shift 2 ;;
    --test-level)  TEST_LEVEL="${2:?}"; shift 2 ;;
    -t|--tests)    IFS=',' read -r -a T <<<"${2:?}"; TESTS+=("${T[@]}"); shift 2 ;;
    --wait)        WAIT="${2:?}"; shift 2 ;;
    --out)         OUT="${2:?}"; shift 2 ;;
    --id-file)     ID_FILE="${2:?}"; shift 2 ;;
    -h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---- JSON helpers ----------------------------------------------------------
# sf prints a version warning before the JSON, so the payload starts at the
# first '{'. A helper that cannot find the key prints an empty string: the
# caller decides, no silent default.
jsonfield() { # jsonfield <key> — reads JSON on stdin, prints the scalar or ""
  python3 -c '
import json, sys
key = sys.argv[1]
raw = sys.stdin.read()
i = raw.find("{")
if i < 0:
    sys.exit(0)
try:
    d = json.loads(raw[i:])
except Exception:
    sys.exit(0)
r = d.get("result", d)
v = r.get(key, d.get(key))
if v is True:
    print("true")
elif v is False:
    print("false")
elif v is not None:
    print(v)
' "$1"
}

cancel_job() { # cancel_job <grund> — cancel the id we started, tolerate "already completed"
  local why="${1:-cancel-step}"
  local answer state
  CANCELLED=1
  answer=$(sf project deploy cancel -o "$ORG" -i "$JOB" --json 2>&1)
  state=$(printf '%s' "$answer" | jsonfield status)
  if printf '%s' "$answer" | grep -qi "CannotCancelDeployError\|already completed"; then
    echo "cancel ($why): nothing to cancel — operation $JOB already finished"
  else
    echo "cancel ($why): operation $JOB cancelled (org answer: ${state:-see below})"
  fi
  printf '%s\n' "$answer"
}

# ---- Mode: cancel (the `if: cancelled()` step) -----------------------------
if [ "$MODE" = "cancel" ]; then
  if [ ! -s "$ID_FILE" ]; then
    echo "::error title=CI validate::no job id in $ID_FILE — the validation never started, nothing to cancel"
    exit 0
  fi
  JOB=$(tr -d '[:space:]' < "$ID_FILE")
  # A stale id file must not cancel another PR's finished operation: check live first.
  LIVE=$(sf project deploy report -o "$ORG" -i "$JOB" --json 2>/dev/null | jsonfield done)
  if [ "$LIVE" = "true" ]; then
    echo "::error title=CI validate::operation $JOB already finished — nothing to cancel"
    exit 0
  fi
  cancel_job "cancelled-step"
  # AC4: a cancelled run never reports green. The gate parser still has to see
  # no verdict, so this step never writes the verdict file.
  echo "::error title=CI validate::no verdict — validation $JOB cancelled by the run"
  exit 0
fi

# ---- Mode: validate --------------------------------------------------------
if [ -z "$ORG" ]; then echo "usage: $0 --org <alias> (--source-dir <dir> | --manifest <package.xml>) [--test-level <level>] [--tests a,b] [--wait <min>] [--out <file>] [--id-file <file>]" >&2; exit 2; fi
if [ -z "$SOURCE_DIR" ] && [ -z "$MANIFEST" ]; then echo "either --source-dir or --manifest is required" >&2; exit 2; fi

SF_ARGS=()
SF_ARGS+=(-o "$ORG")
[ -n "$SOURCE_DIR" ] && SF_ARGS+=(--source-dir "$SOURCE_DIR")
[ -n "$MANIFEST" ]   && SF_ARGS+=(--manifest "$MANIFEST")
[ -n "$TEST_LEVEL" ] && SF_ARGS+=(--test-level "$TEST_LEVEL")
for t in "${TESTS[@]:-}"; do [ -n "$t" ] && SF_ARGS+=(-t "$t"); done

JOB="" FINISHED=0 CANCELLED=""

cleanup() {
  # A SIGTERM trips both handlers; the operation is cancelled once, the message
  # printed once.
  if [ "$FINISHED" -eq 0 ] && [ -z "$CANCELLED" ]; then
    if [ -n "$JOB" ]; then
      cancel_job "trap"
      echo "::error title=CI validate ($ORG)::no verdict — validation $JOB cancelled, the org no longer holds a live operation"
    else
      echo "::error title=CI validate ($ORG)::no verdict — the validation never started"
    fi
    exit 1
  fi
}
trap cleanup INT TERM EXIT

# A stale id file must never be mistaken for this run's operation: truncate it
# before the operation starts, so the `if: cancelled()` step either finds this
# run's id or finds nothing.
: > "$ID_FILE"
START=$(sf project deploy validate "${SF_ARGS[@]}" --async --json 2>&1)
JOB=$(printf '%s' "$START" | jsonfield id)
if [ -z "$JOB" ]; then
  printf '%s\n' "$START"
  echo "::error title=CI validate ($ORG)::validate --async returned no job id"
  exit 1
fi
# The id goes out the moment it is known — before any polling. This is what the
# `if: cancelled()` step reads; a killed process never gets a second chance.
printf '%s\n' "$JOB" > "$ID_FILE"
echo "started validation $JOB in $ORG (id written to $ID_FILE); status $(printf '%s' "$START" | jsonfield status)"

DEADLINE=$(( $(date +%s) + WAIT * 60 ))
while :; do
  sleep 15
  REPORT=$(sf project deploy report -o "$ORG" -i "$JOB" --json 2>/dev/null)
  DONE=$(printf '%s' "$REPORT" | jsonfield done)
  if [ "$DONE" = "true" ]; then
    STATUS=$(printf '%s' "$REPORT" | jsonfield status)
    # AC4: an operation that ended Canceled — cancelled by the `if: cancelled()`
    # step while this loop was still polling — produced no verdict. Writing an
    # empty findings file here would hand the parser a green gate for a run that
    # never validated anything.
    if printf '%s' "$STATUS" | grep -qi cancel; then
      FINISHED=1
      echo "::error title=CI validate ($ORG)::operation $JOB ended Canceled — no verdict, never green"
      exit 1
    fi
    FINISHED=1
    if [ -n "$OUT" ]; then
      # The shape the existing parser reads: result.details.componentFailures
      # plus the message fallback. Nothing here reformats the findings.
      printf '%s' "$REPORT" | python3 -c '
import json, sys
raw = sys.stdin.read()
d = json.loads(raw[raw.find("{"):])
r = d.get("result", d)
out = {"result": r, "message": r.get("errorMessage") or d.get("message") or ""}
with open(sys.argv[1], "w") as fh:
    json.dump(out, fh)
' "$OUT" || { echo "::error title=CI validate ($ORG)::could not write $OUT"; exit 1; }
      echo "verdict written to $OUT ($(printf '%s' "$REPORT" | jsonfield status))"
    else
      printf '%s\n' "$REPORT"
    fi
    exit 0
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "::error title=CI validate ($ORG)::wait budget ${WAIT} min spent, operation $JOB still live — cancelling it so it cannot pile up"
    exit 1
  fi
done
