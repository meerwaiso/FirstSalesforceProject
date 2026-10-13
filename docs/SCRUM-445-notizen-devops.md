# SCRUM-445 — DevOps-Agent Notizen (Deployment-Station)

Ticket state at start: column `Deployment`, assignee `devops-agent` — both read from the tracker (jira_get_issue, 2026-10-13 23:1x CEST). Station = merge PR #166 into master. Prod-Org deploy NOT authorized (not in `Release`).

## Gate measurement (all read back, not from reports)

- PR #166: state OPEN, base `master`, head `52c432bfa4cd515fa858cf8b61f63aaeee351673`, `mergeStateStatus=UNSTABLE`, `reviewDecision=""` (shared account → empty is expected, approval is on record in Jira comments 23472/23478/23479).
- CI run for that exact head: `38464186963`, headSha `52c432b…` — verified via `gh run view 38464186963 --json headSha`.
  - `Metadata, Apex & Session Smoke` job 115527385602 → success (not skipped)
  - `Lint & Format (advisory)` 115527385887 → success
  - `README aus Release Notes` 115527385165 → success
  - `Prod-Org Drift Gate` job 115527385630 → **failure** → run conclusion `failure`
- Test verdict on record: Tester comment 23482 (2026-10-13 23:05) — 14/14 AC PASS, Playwright 7/7, smoke 2/2, Apex 17/17 (run 707WU00001NZA8i).

## Drift Gate cause — measured from the artifact, not the log tail

Artifact `prod-validate` id 11848153322 (downloaded via `curl -H "Accept: application/zip" api.github.com/repos/…/actions/artifacts/11848153322/zip`; `gh api` refuses that Accept header, 415).
Deploy validate job id `0Afg500000FnywrCAB`. All 13 findings, verbatim:

- 5x `No such column 'Discount_Approval__c' on entity 'Opportunity'` (ac2, ac5, ac8, +2)
- 3x `No such column 'Discount_in_Pct__c' on entity 'Opportunity'` (ac7, ac9, SCRUM445DiscountFlsTest.ac12a)
- 5x `System.QueryException: List has no rows for assignment to SObject` (ac10, ac13, ac3, ac6, bulk_200, notification_executeBothPaths)

**Foreign-name grep = 0 hits** (`FeedItem.RypplePost`, `SCRUM319`, `Case.Rueckruf`, `VIP_Customer__c`). This is the documented SELF-TRIP shape (skill `pr-merge-approval-gate`, "pre-release self-trip"; measured before on SCRUM-436 comment 22316→22317 merge `afc2693`, SCRUM-442 comments 23459→23460 merge `2546856`).

## Org facts (read back 2026-10-13)

- `sf sobject describe --sobject Opportunity --target-org Prod-Org` → 54 fields, **0 of the 8 SCRUM-445 fields present** (Discount_in_Pct__c, Discount_Approval__c, Approval_Requested_On__c, Approval_Decided_On__c, Approval_Decided_By__c, Approved_Discount_Value__c, Rejection_Reason__c, Approval_Waiting_Days__c). Prod-Org alias `devops-agent@cline.de`, orgId 00Dg500000DkTtzEAF.
- Smoke job ran the 17 tests in **Test-Org**: junit `username devops-agent@cline.test`, orgId 00DWU00000oibVJ2AY, run 707WU00001NZA8i, 17/17 Pass, testRunCoverage 80 %, orgWideCoverage 88 %.
- Delta between the approved head `86da0ec` (Architect approval 23479) and the head to merge `52c432b` = only `docs/SCRUM-446-447-notizen-tester.md` + `tests/e2e/SCRUM-445-discount-approval.spec.ts` — no force-app change after approval.

## Precedent for the waiver

- PR #165 (SCRUM-442 release note, docs-only) → Drift Gate **pass** 13m0s, run 38267454821.
- PR #164 (SCRUM-442 feature, metadata released to Prod) → Drift Gate **fail** 9m57s, run 38231845114.
- So the gate is not permanently broken; it reddens while a feature's metadata is Test-Org-only.

## Decision

Gate red → no merge on my own authority. Posted measurement + waiver request to Jira; waiting for @user Einzel-Waiver (the two precedents were both granted by @user).

## Open: foreign uncommitted files in the shared tree (not mine, untouched)

`git status -sb` at start (branch `feature/SCRUM-424-first-response`): modified SCRUM365/367/370/390/403/410/418/419/420 test classes + `reports/Erstreaktionszeit_Pro_Servicebereich.report-meta.xml`; untracked `docs/SCRUM-424-notizen-devops.md`, `docs/SCRUM-442-notizen-po.md`, `docs/SCRUM-442-release-note.md`, `docs/SCRUM-445-notizen-tester.md`, `objects/Case/Case.object-meta.xml`, `objects/Case/validationRules/`, `objects/Opportunity/listViews/Discount_Approval_Waiting.listView-meta.xml`, `parse_c`. None staged, none deleted.
