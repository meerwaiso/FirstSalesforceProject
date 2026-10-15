# SCRUM-449 — DevOps-Station Notizen (Merge-Gate, 2026-10-15)

Nicht: Ticket still in "Deployment", Assignee devops-agent — read back via jira_get_issue before any work.

## Gate measurement (PR #168)

- PR #168 head on the remote: `338227e57f5c27da522c2088a8f4050234c2a051` (`git ls-remote origin feature/SCRUM-449-risk-level`). Commit 2026-10-15 20:15:21 +0200, "[TESTER][SCRUM-449] re-test green after SCRUM-450 layout fix".
- CI run for exactly that head: `38784110825` (`gh run view 38784110825 --json headSha` → headSha == 338227e). Jobs:
  - Lint & Format (advisory) — success, job 116591549770
  - Metadata, Apex & Session Smoke — success, job 116591549774 (NOT skipped)
  - README aus Release Notes — success, job 116591549674
  - Prod-Org Drift Gate — failure, job 116591549252
- `mergeStateStatus: UNSTABLE`, `mergeable: MERGEABLE`, `reviewDecision: ""` (shared account → empty is expected, see skill pr-merge-approval-gate).
- Approval on record: Architect round 4 APPROVED, GitHub review id 5537512300, reviewed head `52c61ab`; Jira comment 2026-10-15T19:46. Head 338227e adds only the Tester's spec/notes commit.
- Test verdict on record: Tester re-test 2026-10-15T20:15, 12/12 AC PASS, head 52c61ab.

## Drift Gate findings — read off the artifact, not the log

Artifact: prod-validate of run 38784110825, artifact id 11996729614
(`curl -sL -H "Authorization: Bearer $(gh auth token)" .../actions/artifacts/11996729614/zip`).
Validate job id `0Afg500000FsTXSCA3`. 21 distinct test-method findings, 0 component findings:

- 6x `SCRUM445DiscountApprovalTest.*` — `System.QueryException: List has no rows for assignment to SObject`
  → FOREIGN, pre-existing, = SCRUM-448 (hardcoded Test-Org usernames in the SCRUM-445 fixtures).
- 15x `SCRUM449OpportunityRiskTest.*` / `SCRUM449OpportunityRiskFlsTest.*` — `No such column 'Risk_Level__c' on entity 'Opportunity'`
  → SELF-trip: this ticket's own fields, not in Prod-Org before the release. Expected pre-release.
- grep for foreign component names (FeedItem/RypplePost/SCRUM319/Case.Rueckruf/VIP_Customer): **0 hits**.

## Why the PR-head gate says "no usable result"

The PR-head run aborted with `##[error]Validation produced no usable result — this run cannot show the change is free of drift.`
That is the gate's own parser defect on the bare `FailedValidationError` shape; PR #169 fixed it and merged to master at `b4ca485` (2026-10-15 18:16:11).

## Master CI after PR #169 (the gate reading correctly)

Run `38784223691`, head `b4ca485`: Smoke success, Lint success, README success, Drift Gate failure.
Verdict line: `##[error]6 test(s) fail in Prod-Org for a reason the release will not fix — they will still fail after deployment.`
→ the 6 SCRUM-448 findings. The gate is red on EVERY PR until SCRUM-448 is fixed; it is not red because of SCRUM-449.

## Decision

Held, no merge, no waiver on my own authority. Blocker = SCRUM-448 (Bug, assignee tester-agent, status Zu erledigen, 0 comments).

## Open items for PO/Release (not mine to close)

- Test-Org holds 0 ScheduledJob for OpportunityRiskScheduler (Tester notes) — the nightly path has never run end to end.
- `recomputeAll()` threw `fields being inaccessible on Sobject Opportunity` once with 73 records to assess (Developer, 19:17); cause not pinned. In the Prod validate the same error class appears for 6 SCRUM449 methods — expected there (fields absent in Prod), so it proves nothing about the Test-Org case.

## Untouched in the shared tree

Foreign uncommitted files from other tickets (SCRUM-424 classes, SCRUM-442/445 docs, SCRUM-449 design, Case/Opportunity objects, reports, list views, validation rules) left exactly as found; nothing of mine staged outside this notizen file.
