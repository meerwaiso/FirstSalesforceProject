# SCRUM-463 — Tester notizen (tester-agent, 2026-11-17)

Ticket: CI must cancel the Salesforce deploy validation a cancelled GitHub run left in the org.
Board read back at start: status "Testen", assignee tester-agent. PR #184, branch
`feature/SCRUM-463-ci-validate-cancel`, reviewed head `0b25050`.

## Verified facts (command → answer)

- `scripts/ci-prod-validate.sh` (7919 bytes, mode 755) has two modes: validate (default) and
  `--cancel`. Validate: `: > "$ID_FILE"` truncates the id file **before** the operation starts,
  then `sf project deploy validate ... --async --json`, id written the moment it is known, then
  polls `sf project deploy report` every 15 s until `done=true` or the `--wait` budget.
- Poll budget is exactly `--wait` minutes (the Architect's trap: the GitHub step timeout must be
  larger than 30 min, otherwise GitHub kills the step first and the trap answers instead).
- `--cancel` refuses a finished operation: it reads `done` first and exits 0 with
  "operation $JOB already finished — nothing to cancel"; it cancels exactly the id in the file,
  never `--use-most-recent`.
- A cancelled operation never writes the verdict file: validate mode exits 1 with
  "::error ... operation $JOB ended Canceled — no verdict, never green"; the cancel step prints
  "::error ... no verdict" and exits 0 (the gate parser reddens on the missing file).
- The verdict shape the gate parser reads: `{"result": <report result>, "message": ...}` with
  `result.details.componentFailures`.
- `sf project deploy cancel` exists in CLI 2.150.6 with `-i/--job-id` and `-r/--use-most-recent`
  (the Developer verified the help; I use the script, not the raw command).

## Test artifact

`tests/ci/SCRUM-463-validate-cancel.test.py` (my name on it) + fixture
`tests/fixtures/scr463-validate/force-app/main/default/classes/SCRUM463ProbeTest.cls` — a one-component
source dir so a validation costs seconds instead of the 9-12 min of the full force-app.
Scenarios: AC3 finished validation (verdict file + parser shape + not cancelled) · AC1a SIGTERM trap
path · AC1b SIGKILL + `--cancel --id-file` (the `if: cancelled()` step) · AC4 no verdict file +
"no verdict" wording · negative case a finished operation is refused and its verdict file survives.
Run: `python3 tests/ci/SCRUM-463-validate-cancel.test.py` from the repo root, Test-Org only,
check-only. Log: `test-results/scr463-run.log`.

## Parser trap (measured, 2026-11-17)

- `sf project deploy report --json` prints the JSON on stdout and a `Warning: @salesforce/cli update…`
  line on stderr AFTER it. `json.loads(stdout + stderr)` fails with "Extra data" — the payload must be
  cut at the LAST closing brace. Symptom: every org read-back returned `status=None`, which also made
  the "operation stayed live" check pass vacuously (an empty report is not evidence).
  Verified: `sf project deploy report -o Test-Org -i 0AfWU00000dBjD30AK --json` → 500,618 bytes stdout
  + 72 bytes stderr; the cancelled operations carry `canceledBy`/`canceledByName`.

## Fixture traps (measured, 2026-11-17)

- The org rejects `@Test` on a method: componentFailure "Annotation does not exist: Test".
  The house pattern (SCRUM319OverdueOpportunityTest.cls) annotates test METHODS with `@isTest`;
  `@TestSetup` only marks the setup method. Fixture now uses `@isTest`.
- The meta xmlns must be `http://soap.sforce.com/2006/04/metadata` — my first attempt used the
  soap/v49 namespace and the org answered "Invalid api version:0.0".
- A one-component validation still waits: with `--wait 5` the operation was still live after 5 min
  (queue wait, the very pile-up this ticket is about). The test therefore uses `--wait 20` for the
  finished-validation scenario; a full validation runs 9-12 min.
- The trap path was seen working on that path: `cancel (trap): operation 0AfWU00000dBg8j0AC
  cancelled (org answer: Canceled)`.

## Open items

- AC2 (never more than one live validation per PR over six pushes) is NOT covered by a test of mine:
  it needs six pushes plus the workflow wiring in `.github/workflows/`, which no agent may edit —
  the user applies it.
- The workflow lines (the `if: cancelled()` step, two separate id files
  `.ci-validate-job-id-prod` / `.ci-validate-job-id-testorg`, a `.gitignore` line) are the user's.
