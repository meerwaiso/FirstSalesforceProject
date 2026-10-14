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

**Waiver granted 2026-10-13 (option 1) → PR #166 squash-merged as `2696e6cf3da41f650267819c7308b9cbf502fa9b`, pinned with `--match-head-commit 52c432b…`.**

## Prod-Org release, 2026-10-14 (station: column `Release` + assignee `devops-agent`, both read back)

- Pre-deploy validate: `sf project deploy validate --manifest manifest/scr445-phase1-fields.xml -o Prod-Org --test-level RunLocalTests` → `FailedValidationError` job `0Afg500000FoZegCAF`, 1 finding, self-trip only (`SCRUM445_Discount_System` names `Opportunity.Approval_Requested_On__c`, not yet in Prod). `NoTestRun` is rejected by `validate` (only `RunAllTestsInOrg|RunLocalTests|RunSpecifiedTests|RunRelevantTests`) — the isolation proof is a manifest that names nothing of the missing dependency.
- Manifest entries vs disk: all 6 SCRUM-445 manifests → **0 missing**.
- Deploy (3 phases, all `--test-level NoTestRun`, all `-o Prod-Org` explicit):
  - `scr445-phase1-fields.xml` → Succeeded, 8 Opportunity fields + CMOM `DiscountApprovalManager__c` + its 2 fields (ids `00Ng500000Ummx…`)
  - `scr445-phase2-referencing.xml` → Succeeded, 12 components created (2 ValRules, ListView, 6 PS, 2 Apex classes, trigger)
  - `scr445-systemps.xml` → `SCRUM445_Discount_System` created; `scr445-rework-446-447.xml` → Layout `Opportunity-Opportunity Layout` changed=True (SCRUM-446 fix), `SCRUM445_Discount_Notice` changed=True
  - `scr445-phase3-apextests.xml` → 2 test classes created
- PS assignment (Phase 2 of the house 3-phase release): 7 PS × 2 users (`devops-agent@cline.de`, `meerwais.osmani.3ecaf61ebe28@agentforce.com`) → **14 `PermissionSetAssignment` rows read back**. `sf org assign permset` has no `-u`; `--on-behalf-of` is the flag.
- Live read-back: `SELECT Discount_in_Pct__c, Discount_Approval__c, Approval_Waiting_Days__c, Approval_Requested_On__c FROM Opportunity` on Prod-Org → **3 rows, fields readable** (31 Opportunities in Prod).
- Prod Apex tests (separate run, per the new-field rule): `707g500000r12brAAA` → **11/17 Pass, 6 Fail**, all 6 `System.QueryException: List has no rows for assignment to SObject` at `orgUser('devops-agent@cline.test')` / `orgUser('meerwais.osmani@resourceful-bear-6f1u4j.com')` — Test-Org usernames hardcoded in the fixture. Filed as **SCRUM-448** (Bug, parent SCRUM-445, assignee tester-agent).
- Drift gate after release: `validate --source-dir force-app -o Prod-Org --test-level RunLocalTests` → job `0Afg500000FoU0hCAF`, exactly those 6 methods, **0 foreign names**. Gate stays red until SCRUM-448 is fixed — tracked, not left as drift.
- Release tag: `release/2026-10-14-SCRUM-445` → tag object `36e78bc4eb6499f0a1a4e8dc881328230bd52e74`, **target `0d5a3795bcc131e278c2781a00d1ba4a6249c6a4`** (master head at tag time = the notizen commit), whose **parent is the SCRUM-445 squash merge `2696e6cf3da41f650267819c7308b9cbf502fa9b`** (`git merge-base --is-ancestor` → yes). Read back with `git ls-remote --tags origin "refs/tags/release/2026-10-14-SCRUM-445*"` — the `^{}` line is the target; a remote tag cannot be re-pointed (`git push -f`/`--delete` are on the deny list), so the sha was passed to `git tag -a … <sha>` before the first push.

## Open: foreign uncommitted files in the shared tree (not mine, untouched)

`git status -sb` at start (branch `feature/SCRUM-424-first-response`): modified SCRUM365/367/370/390/403/410/418/419/420 test classes + `reports/Erstreaktionszeit_Pro_Servicebereich.report-meta.xml`; untracked `docs/SCRUM-424-notizen-devops.md`, `docs/SCRUM-442-notizen-po.md`, `docs/SCRUM-442-release-note.md`, `docs/SCRUM-445-notizen-tester.md`, `objects/Case/Case.object-meta.xml`, `objects/Case/validationRules/`, `objects/Opportunity/listViews/Discount_Approval_Waiting.listView-meta.xml`, `parse_c`. None staged, none deleted.
