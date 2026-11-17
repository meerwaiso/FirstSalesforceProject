# SCRUM-463 — CI: a cancelled run cancels the Salesforce validation it started

Design by Architect-Agent, 2026-11-17. Ticket: SCRUM-463 (Story, "Anforderungen").
**Deliverable is a proposal.** `.github/workflows/` is not any agent's to edit; the
workflow line below is applied only with the user's approval.

## Goal

A GitHub run that is cancelled must cancel the Salesforce deploy validation it started,
so the org never holds more than one live validation per pull request and a gate that
never answered is never mistaken for a green one.

## ADR — where the change lives (and why not Apex/Flow)

| Option | Decision |
|---|---|
| Apex / Flow / Salesforce metadata | **Not applicable.** Nothing in this ticket is org logic. No class, no field, no Permission Set, no Flow. The behaviour is a property of the CI transport, not of the platform. |
| New workflow file | **Rejected.** A second workflow would still sit in `.github/workflows/` and would duplicate the gate. |
| Logic in a repo script + one workflow line | **Chosen.** Everything reusable moves into `scripts/` (the house location — `scripts/fls-check.sh`, `scripts/apex-probe.sh` already live there). The workflow keeps a single call site, so the diff the user has to approve is one line, not a step. |

Why this split matters: the script is a normal repo file — the Developer may implement
it. The workflow line is the only part under the "no agent may edit" rule. Splitting the
change that way turns a forbidden 40-line edit into a 1-line decision the user can
actually read and approve.

## Measured, this machine, 2026-11-17 (probes run in Test-Org, check-only)

1. **The job id exists at start.** `sf project deploy validate --async --json -o Test-Org
   -x manifest/scr462-phase1-fields.xml --test-level RunSpecifiedTests --tests SCRUM461CompetitorFlsTest`
   returned immediately: `result.id = 0AfWU00000dBZgj0AG`, `done: false`, `status: "Queued"`.
   So the id is captured in the step that starts the validation — the constraint the PO
   put on the implementation is satisfiable.
2. **The verdict is readable after the fact.** `sf project deploy report -o Test-Org -i <id> --json`
   returned the finished validation: `checkOnly: true`, `details.componentSuccesses[]`
   (with `fullName`, `problem`, `success`), `runTestResult` (`numTestsRun`, `numFailures`),
   and progress fields `done`, `status`, `numberComponentsTotal`, `numberTestsTotal`,
   `numberTestsCompleted`. The existing gate parser reads `result.details.componentFailures`
   and a `message` fallback — both present in this shape.
3. **Cancel is refused when the operation already finished.** `sf project deploy cancel -o Test-Org -i <id> --json`
   → `CannotCancelDeployError`, exit code 1, `INVALID_ID_FIELD: Deployment already completed`.
   The cancel must therefore be guarded by `done` and must not be allowed to redden a step
   that already has a verdict.
4. **Unverified leg, named.** No probe stayed live long enough to cancel: both validations
   finished in seconds (18:16:12 → 18:16:16; the 20-component one inside 20 s). Whether
   `cancel -i` succeeds on an *InProgress* operation was not observed. Falsifier for the
   Tester/DevOps: a validation still `done: false` when cancelled — if cancel then answers
   `INVALID_ID_FIELD`, AC1 is not met by this mechanism. The real drift-gate validation
   runs 9–12 minutes, so the trap fires on a live operation in practice.
5. Test-Org Apex budget at the time of the probes: 85 `ApexTestQueueItem` rows in 24 h —
   the probes added a handful; the ceiling is `max(500, 10 × test classes)`.

## Components

- **`scripts/ci-prod-validate.sh`** (new, repo script — Developer's to implement): owns the
  validation lifecycle. Starts it async, remembers the job id, polls for the verdict, and
  cancels the live operation if the shell is killed. Writes `prod-validate.json` in the
  shape the existing parser already reads.
- **`.github/workflows/ci.yml`** (user's to approve): the Drift Gate step calls that script
  instead of the CLI directly. One line.
- **The gate parser stays untouched.** The script adapts the transport, not the verdict.
  This is the interface decision: the parser is the single authority for "drift / no drift /
  no verdict"; the script only guarantees that a cancelled run produces the third one.

## Interface / pseudocode

```
ci-prod-validate.sh  --org <alias> --manifest <package.xml> --test-level <level>
                     --tests <classes> --wait <minutes> --out <prod-validate.json>

JOB="" ; FINISHED=0
on_exit:                                  # trap TERM INT EXIT
    if FINISHED == 0 and JOB != "":
        sf project deploy cancel -o ORG -i JOB --json || true     # AC1
        print "::error title=Prod drift gate::no verdict — validation JOB cancelled"
        exit 1                                                     # AC4
    fi

R = sf project deploy validate --async --json …            # returns in seconds
JOB = R.result.id
loop until wait budget:
    R = sf project deploy report -o ORG -i JOB --json
    if R.result.done == true:
        FINISHED = 1
        write { "result": R.result, "message": R.result.errorMessage or "" } to OUT
        exit 0                                                   # AC3
    sleep 15
on timeout: FINISHED stays 0 → on_exit cancels and fails         # AC4
```

Exit codes: `0` only with a verdict; `1` with no verdict. The gate job must stay red
whenever it could not answer — the parser's existing "Validation produced no usable
result" branch remains as the backstop, so a missing verdict cannot become green twice.

## AC walk

| AC | How the design meets it | Evidence |
|---|---|---|
| AC1 cancelled run cancels the live validation | trap fires while `done == false`, `cancel -i <id>` on the id captured at start | id capture verified; **cancel on a live operation unverified** (see 4) |
| AC2 never more than one live validation per PR | every cancelled run cancels its own operation; the concurrency group already cancels the older GitHub run | measured pile-up: six runs, five cancelled, queue wait 8–44 min |
| AC3 a finished validation still yields its verdict | `deploy report -i` returns the full result; the parser reads it unchanged | verified on a completed validation |
| AC4 a cancelled validation reports "no verdict", never green | explicit `::error` line + exit 1; parser backstop unchanged | design decision, verified by the parser's existing branch |

## Scope decision the PO left open

The Test-Org smoke step runs the same kind of validation (`--wait 30`, advisory). Apply
the same script there too: the measured pile-up was on Prod, but Test-Org carries the
**24-hour Apex test budget**, and every stacked validation that keeps running burns
`ApexTestQueueItem` rows for nothing. One script, two call sites, `--org` as a parameter.
This is a recommendation, not a decision — the user approves both lines or neither.

## Governor-limit / risk notes

- Polling costs one CLI call per 15 s against the org; the wait budget is unchanged, so
  no new wall-clock is added to the job.
- `--async` changes the CLI's exit-code semantics: the validate no longer signals findings
  through its own exit code. The parser decides — do not "simplify" it by trusting the CLI.
- `cancel` on a completed operation exits 1; the trap must be guarded by `FINISHED` and
  run with `|| true`, otherwise a normal completion turns the step red (AC3).
- `-r / --use-most-recent` is **not** acceptable here: with several PRs live it can cancel
  another PR's operation. Only the explicit `-i <id>`.

## What is not decided here

The workflow line is not applied and will not be applied by any agent. Implementation of
`scripts/ci-prod-validate.sh` starts only after the user's approval is recorded in SCRUM-463.
