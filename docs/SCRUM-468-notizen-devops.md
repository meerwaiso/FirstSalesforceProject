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
