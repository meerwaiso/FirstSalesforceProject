# SCRUM-468 — DevOps-Notizen (Merge-Leg)

Ticket: SCRUM-468 — Lend Devices (custom object per demonstration device + one record per lending period, overdue overview for team leads, write-off only by team leads). Branch `feature/SCRUM-468-lend-devices`, PR #190 (also names Bug SCRUM-469 as closed by the loan guard).

## Merge leg (done, measured at the target systems)

- Ticket state read back before the merge: `Deployment` + assignee `devops-agent`.
- PR #190 head at merge time: `e7eef42e03d4cc9af924d495c9ce5d96b652793a`; merged squash -> master `6034f1bfebc9243d3a22c7d6e69108375456b944` via `gh pr merge 190 --squash --match-head-commit e7eef42…`.
- Proof the squash carried the measured head: `git diff --name-only e7eef42 6034f1b` = EMPTY; `git diff --name-only 7c19e23 6034f1b | wc -l` = 65 = PR changedFiles (65).
- CI run 45028969478, `head_sha e7eef42` (per-job read-back, `gh api …/runs/45028969478/jobs`): Lint & Format (advisory) success, Metadata/Apex/Session Smoke success with steps `Determine Apex test scope`, `FLS gate`, `Run Apex tests`, `Playwright session smoke` all completed success (only `Cancel a Test-Org validation…` skipped), Prod-Org Drift Gate success on step `Validate against Prod-Org (check-only)` — no waiver needed, README aus Release Notes success.
- Approval: Architect round-4 APPROVED on head `110696d` (review id 6012329350, stored as COMMENTED because all agents share one GitHub account). Delta `110696d -> e7eef42` = `M docs/SCRUM-468-design.md`, `M docs/SCRUM-468-notizen-tester.md`, `M tests/e2e/SCRUM-468.spec.ts`, 0 force-app files, approval head IS ancestor -> approval carries.
- Test verdict on record: Tester Jira comment 14:57 — 9/9 Playwright (`scripts/e2e-run.sh tests/e2e/SCRUM-468.spec.ts --all`) + 8/8 Apex scoped run (AsyncApexJob 707WU00001VrF0NYAV) on head e7eef42, fixture seed 4 devices / 6 loans / 3 customers / 2 colleagues.
- Prod-Org NOT touched by the merge leg: only the check-only Drift Gate ran against Prod.

## For the Release leg (only once PO moves the ticket to `Release` and assigns it to me)

- Release material = the force-app delta `7c19e23..6034f1b` of this squash; build the Prod manifest from the Developer's phase manifests (`manifest/scr468-phase*…`), member forms verbatim — do not invent shapes.
- New in this ticket: a custom object (one record per device) + a lending-period record + Permission Sets + guards + List Views. A deploy carries a Permission Set, it never assigns one: Phase 2 must assign the PS in Prod to the two Prod users (`devops-agent@cline.de` + `meerwais.osmani.3ecaf61ebe28@agentforce.com`, per the SCRUM-464/467 house pattern) and read `PermissionSetAssignment` back; then re-run the FLS chain (skill `salesforce-describe-first` §4) against Prod.
- Phase 3: the two test classes run in Prod separately, one class per `--synchronous` call, verdict from `--json` (`result.summary.outcome`).
- Layouts: the Account layout at head `e7eef42` is byte-identical to master (Architect round 4) — no shared-page drift; the customer-page surface is a List View on the lending record reached by a picker button, not a related list. Do not deploy the master Layout over the Prod Layout without retrieving Prod first (SCRUM-467 lesson: the Prod Layout differs from master).
- AC5/AC8 surfaces and the overdue overview are List Views — for the Prod release check row counts after the deploy; 0 rows = untested, not a pass.

## Open at handoff

- Feature branch `feature/SCRUM-468-lend-devices` still on the remote at `e7eef42` (squash merge -> branch is no longer an ancestor of master; nothing further expected on it).
- Shared working tree untouched: still `feature/SCRUM-424-first-response` with foreign uncommitted files from other tickets — neither committed nor deleted.

## Release leg (Prod-Org) — 2026-11-22, executed after PO moved the ticket to `Release` and assigned it to me

- Authorization read back before the first org write: SCRUM-468 status `Release`, assignee `devops-agent` (both at once).
- Release material = exactly the force-app delta `7c19e23..6034f1b` of the squash merge: 45 source files -> 18 manifest members -> 35 deployed components.
- `manifest/scr468-prod-release.xml` (master commit `48ee748ca9310642228c1409f54eb9800dbc0d9a`, annotated tag `release/2026-11-22-SCRUM-468` -> object `48ee748…`): CustomObject `Demo_Devic__c`, `Loan_Record__c`; ListView `Demo_Devic__c.SCRUM468_Overdue`, `Loan_Record__c.SCRUM468_Open_Loans`; Layout `Demo_Devic__c-Demo Device Layout`; PermissionSet `SCRUM468_Loan`, `SCRUM468_Read`, `SCRUM468_Writeoff`; ApexClass guards `DemoDevicGuard`, `DemoDevicWriteoffGuard`, `LoanRecordGuard`, `LoanReturnGuard` + test classes `SCRUM468LendDevicesTest`, `SCRUM468FlsTest`; ApexTrigger the same four guards.
- House form for a NEW custom object (proven in `scr461-prod-release.xml` Competitor__c / `scr464` Fabrikant__c): name the object once as CustomObject, its own fields ride along under objects/ — `CustomField` members are only for fields on STANDARD objects, and this ticket has none.
- NOT in the release: `Account-Account Layout`. The delta does not touch it (round-4 Architect: the Account layout at head e7eef42 is byte-identical to master; the related lists were dropped in round 3), and master's Account layout blob is not the Prod blob (Prod page carries the Fehlzeit section another ticket owns). Deploying it would have overwritten Prod state.
- Pre-deploy validate (check-only against Prod-Org): `manifest/zz-scr468-validate-metadata.xml` = the 8 metadata members (objects + ListViews + Layout + Permission Sets). Result `Succeeded`, `checkOnly: true`, 25/25 components, `componentFailures: []`, `numTestsRun: 0`, zipSize 28017, op completed 2026-11-22T14:48:16Z.
  - Lesson reconfirmed: a first validate that kept the 6 ApexClass + 4 ApexTrigger members answered `FailedValidationError … Test coverage of selected Apex Class is 0%, at least 75% required` for all four guards (op 0Afg500000H3CUHCA3). A validate always runs tests; `NoTestRun` exists only on `deploy start`. A NEW Apex class/trigger can therefore never pass a pre-deploy validate — exclude the Apex part from the validate manifest, deploy it with `NoTestRun`, prove it with the separate Prod test run.
  - CLI gotcha: `--manifest` and `--source-dir` are mutually exclusive (exit 2, "cannot also be provided when using"). Run the validate from inside the worktree with `--manifest` alone.
  - CLI gotcha: `sf data query` takes the SOQL in `--query` (`-q`), NOT positionally — the positional form fails with "… is not a sf command" (looks like a platform fault, is not).
- Release deploy: `deploy start --manifest manifest/scr468-prod-release.xml -o Prod-Org --test-level NoTestRun` -> `Succeeded`, `checkOnly: false`, 35/35 components, `componentFailures: []`, zipSize 26771, completed 2026-11-22T14:48:52Z.
- Phase 2 — Permission Set assignment in Prod (a deploy carries a PS, it never assigns one): `sf org assign permset -o Prod-Org -n <PS> -b <user>` for 3 PS x 2 Prod users (`devops-agent@cline.de`, `meerwais.osmani.3ecaf61ebe28@agentforce.com`). Read-back: 6 `PermissionSetAssignment` rows (`sf data query --query "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM468%'" -o Prod-Org` -> "Total number of records retrieved: 6"), also reproduced through the REST SOQL endpoint.
- FLS chain re-run against Prod-Org (`scripts/fls-check.sh <Object> <Field> Prod-Org`), green for `Demo_Devic__c Designation_Name__c`, `Loan_Record__c Loan_History_Facts__c`, `Demo_Devic__c Overdue_Today__c`: granting PSs found (`SCRUM468_Loan` read+edit; `SCRUM468_Read` read-only), each assigned to both Prod users, verdict "Sichtbar".
- Phase 3 — Prod Apex (separate, one class per synchronous call, verdict from `--json`): `SCRUM468LendDevicesTest` 5/5 `Passed`, `SCRUM468FlsTest` 3/3 `Passed` -> 8/8, identical to the Tester's Test-Org run (8/8). orgId `00Dg500000DkTtzEAF`, user `devops-agent@cline.de`. The test classes create their own `@example.invalid` sandbox users and assign PSs in TestSetup, so they are org-agnostic — no Test-Org username hardcoded, no SCRUM-448-style self-trip in Prod.
- Prod read-backs after the deploy: `Demo_Devic__c` has 8 custom fields live (`Current_Customer__c`, `Current_Loan_Colleague__c`, `Current_Loan_Due_Date__c`, `Current_Loan_Overdue_Days__c`, `Designation_Name__c`, `Overdue_Today__c`, `Serial_Number__c`, `Status__c`), `Loan_Record__c` has 9 (`Loan_Colleague__c`…`Loan_Start_Datum__c` incl. `Loan_History_Facts__c`, `Loan_Is_Open__c`). Layout `Demo Device Layout` present (1 row). Both ListViews retrieved FROM Prod-Org and byte-compared with the master blobs -> `git diff` empty, i.e. the live Prod content equals the merged source.
- 4 ApexTrigger rows present in Prod (`DemoDevicGuard`, `DemoDevicWriteoffGuard`, `LoanRecordGuard`, `LoanReturnGuard`); each record GET answers 200 with its Name. Guard behaviour is proven by the passing Prod test run (the classes assert the guard effects under `System.runAs`), not by the trigger record fields (that GET returns no `Active`/`NumberOfActiveVersions` in its body — do not claim an active-flag that was never read).

## Gap reported with the release (not a pass)

- Prod data: `Demo_Devic__c` 0 records, `Loan_Record__c` 0 records -> the AC5/AC7/AC8 surfaces (both List Views, the device Layout) are live in Prod but data-untested there. Test-Org holds the fixtures the Tester used (4 devices / 6 loans / 3 customers / 2 colleagues); the Prod org is the empty production state. A criterion that matches zero records is untested, not met.

## Hygiene notes from the release leg

- `sf project retrieve start` writes into the working tree. Run it inside a worktree. Run in the shared checkout it created `force-app/main/default/objects/Demo_Devic__c/` and `objects/Loan_Record__c/` there; removed both (mine), foreign untracked leftovers from other tickets untouched.
- Retrieve metadata form that works: `Layout:Demo_Devic__c-Demo Device Layout` (dash, object-label), `ListView:Demo_Devic__c.SCRUM468_Overdue` (dot, developer name). `Layout:Demo_Devic__c.Demo Device Layout` is rejected: "Entity of type 'Layout' named '…' cannot be found".
