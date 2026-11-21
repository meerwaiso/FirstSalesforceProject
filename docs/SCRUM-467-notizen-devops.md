# SCRUM-467 — DevOps-Notes (Deployment-Phase, 2026-11-21)

Jeden Befund: wie obtained, plus de Command dat produced it. Prod-Org is NOT reached in this phase.

## Merge state (verified by me)
- Merge commit `d5f071499cf8878067e4f0363d699564e07f69df` on master; PR #188 head `c39b9115f83a687daccc1e1d8f5779658e654d4a`; previous master `dc0e41183a166ece8dca43e9127f52798731ce3c`.
- Squash carried the measured head: for all 41 changed files the blob in `c39b911` == the blob in `d5f0714` (compared each file with `git ls-tree <ref> -- <path>`, 0 mismatches); `git diff --name-only dc0e411 d5f0714 | wc -l` = 41.
- `git diff --name-status c39b911 d5f0714` = 3 entries (`.gitignore` M, `scripts/e2e-run.sh` A, `tests/e2e/preflight.ts` A) — these come from master's newer TOOLING commit `dc0e411` (PR #189), both files already sit in `dc0e411`; nothing of SCRUM-467 lost.
- Feature branch `feature/SCRUM-467-offer-validity` still sits on the remote at `c39b911` and is NOT an ancestor of master (`git merge-base --is-ancestor` exit 1, squash merge). A later push there reaches nobody → worktree-merge remedy (skill `pr-merge-approval-gate`).
- CI belongs to the merged head: run `44913870579`, `head_sha c39b911`; per-job read-back `gh api repos/.../actions/runs/44913870579/jobs` → all 4 jobs `status=completed conclusion=success`.
- Smoke job steps actually ran (not skipped): `Run Apex tests`, `FLS gate (…)`, `Validate metadata (check-only)`, `Playwright session smoke` all `completed success`; only `Cancel a Test-Org validation the run left behind` was `skipped`.
- Prod-Org Drift Gate step `Validate against Prod-Org (check-only)` = `completed success` → Prod-Org currently equals master, no foreign drift before this release.
- No CI run on master is expected: `ci.yml` triggers on `pull_request` (branches master) + `workflow_dispatch` only.

## Prod release material (for the Release column)
- Deploy-sequencing manifests are already in master: `manifest/scr467-phase1-fields.xml` (7 fields) → `manifest/scr467-phase2-referencing.xml` (2 ValidationRules + PS + 2 Reports) → `manifest/scr467-phase3-layout.xml` (record-page section) → `manifest/scr467-phase4-apextests.xml` (test classes). Read them before deploying; do not re-derive the order.
- 13 production components: 7 CustomFields on Opportunity (`Offer_Sent_On__c`, `Offer_Valid_Until__c` recorded; `Offer_Expires_On__c`, `Offer_Days_Left__c`, `Offer_Status__c`, `Offer_Expired__c`, `Offer_Expiring_14D__c` derived), 2 ValidationRules (`Offer_Won_With_Expired_Offer`, `Offer_Dates_Kept_When_Closed`), PS `SCRUM467_Offer_Dates`, 2 Reports (`SCRUM467_Offer_Renewals_Due_14D`, `SCRUM467_Offer_Expired_Renewals`), 1 layout section on `Opportunity-Opportunity Layout`.
- Test-local artefacts that must NOT slip into Prod unnoticed: PS `SCRUM467_TestObjectAccess` + Apex classes `SCRUM467OfferExpiryTest`, `SCRUM467OfferFlsTest`. Decide explicitly at Release whether the test classes are carried; the test-local PS follows the house SCRUM-442/451/464 pattern.
- PS deployment is not assignment: `sf org assign permset -o Prod-Org -n SCRUM467_Offer_Dates -b <user>` for the CLI target-org user AND for @user (`meerwais.osmani.3ecaf61ebe28@agentforce.com`, the only real Prod end-user). Read-back: `SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM467%'` → expects 2 rows per assigned PS. `-o Prod-Org` is mandatory — the default org is Test-Org.
- Unverified by me (from the Developer/Architect comments 23714/23715, extern defect, do not work around): an Opportunity save that flips `IsClosed` under `System.runAs` dies in Test-Org with `QueryException: Variable does not exist: tmpVar1` in `FollowupMonitoringHandler.recalculate` — relevant for a Prod Apex test run.

## Counts that must travel
- Untouched org: 76 open / 63 closed Opportunities, 0 with offer data (Architect, Test-Org 2026-11-21).
- Tester fixtures in Test-Org: open WITHOUT offer data 68, expiring within 14 days 4, already expired and open 3. AC9/AC10 rest on 4 and 3 records, not on zero.

## Open, not mine
- Architect's two non-blocking cleanups still stand on the branch: PS file probe header comment + description naming `Account Manager`/`Sales Team Lead` profiles that do not exist; `docs/SCRUM-467-design.md` rows 12/13 and the Overview section still describe the rejected pre-probe Report shape with a sort column (section 11 wins). `force-app/` + docs content = Developer/docs domain.
