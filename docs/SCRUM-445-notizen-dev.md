# SCRUM-445 — Developer-Notizen (hard findings, verified 2026-10-12)

- Worktree: `scr445-wt` on `feature/SCRUM-445-discount-approval` (shared checkout untouched).
- Branch base: Architect commit 9cb08a4 (design doc). My commits: b254130 (Phase 1), e8ce016 (Phase 2).
- Org: Test-Org only (`devops-agent@cline.test`). apiVersion 67.0 in every cls/trigger-meta
  (`<status>Active</status>` — house CI fact SCRUM-442: `<active>true</active>` = "Invalid api version:0.0" = drift gate red).

## Deploy order (house memory, paid again here)
1. `manifest/scr445-phase1-fields.xml` — CustomObject DiscountApprovalManager__c + its 2 fields
   + the 8 Opportunity fields ALONE (ValRules/PS/ListView/Apex reference them).
2. `manifest/scr445-phase2-referencing.xml` — ValRules, ListView, 4 PS, Handler+Queueable+Trigger.
3. Test classes deploy with Phase 2 (same PR, coverage gate).

## Pitfalls hit this ticket (verified)
- `Approval_Waiting_Days__c`: I wrote `<label>` twice → validate: "Element label is duplicated at
  this location in type CustomField" (job 0AfWU00000cA1GH0A0, 1 component error). One `<label>` only.
- `sf project deploy validate` DEFAULT test level is `RunAllTestsInOrg` → reaches org-only classes
  (SCRUM434Probe) and hangs the job (0AfWU00000cA2CL0A0 sat Pending >10 min, cancelled).
  Use `-l RunSpecifiedTests -t SCRUM445DiscountApprovalTest -t SCRUM445DiscountFlsTest`.
  Note: `-t` is a REPEATABLE flag; a comma list runs 0 tests (house memory, `Total: 0` = wrong call).
- `sf project deploy report` has NO `--concise` flag (validate does). Nonexistent-flag error, not an org error.
- `User` sObject has NO `Role` column via SOQL (`No such column 'Role' on entity 'User'`) — the
  architect's role-hierarchy finding stands; mapping object is the design.

## FLS state after deploy (measured, not assumed — house rule SCRUM-421/430)
(measure with `scripts/fls-check.sh Opportunity Discount_in_Pct__c` AFTER deploy; fill in below)
- [ ] FieldPermissions for the 8 new fields — profile auto-grant? (decides whether the negative
      FLS tests can pass at all; a Permission Set can only GRANT, never revoke)
- [ ] PermissionSetAssignment read-back for all 4 PS (CLI user + human test account)

## Test-execution facts
- MIXED_DML (CI RunLocalTests, house SCRUM-442): setup DML (Account/User/PSA/mapping) strictly
  FIRST in System context, ALL business DML of that test under ONE runAs user. Two different
  runAs users in one test method = red in CI (green locally) → split into ac12a/ac12b methods.
- ValRule refusals are asserted via try/catch(DmlException) + re-read of the record (house
  SCRUM442SatisfactionTest lines 79-94).
- Notification FeedItem guarded `if (!Test.isRunningTest())` (house OpportunityOverdueNotification);
  bulkification asserted via @testVisible counters mappingSoqlCount/enqueueCount.

## Org-Setup preconditions (NOT Apex asserts — house SCRUM-424; read-back in handoff)
- Opportunity OWD >= ReadOnly (non-owner rep sees the record). Not readable via any API (architect verified).
- Mapping records DiscountApprovalManager__c for the test reps (Tester creates).
- ListView visible to sales management (App Builder placement if needed).

## Open points for the Architect review
- `Approval_Decided_By__c`: Salesforce does not expose the acting user in system context; the
  handler writes the MAPPED manager there. If sales management (not the mapped rep-manager) decides,
  the field names the mapped manager — acceptable per design ("who decided, so the rep can see how
  it was decided"), flag if the PO wants the acting user verbatim.
- ListView `Discount_Approval_Waiting` deployed as component; App Builder placement is Org-Setup.

## Final state (2026-12.10., end of implementation)
- Test run 707WU00001NO8nZ: 15/15 green (SCRUM445DiscountApprovalTest + SCRUM445DiscountFlsTest).
- Coverage: DiscountApprovalHandler 95 % (82/86), DiscountApprovalTrigger 100 % (4/4),
  DiscountApprovalNotification 76 % (26/34) — the uncovered lines are comments, closing
  braces and the FeedItem insert inside `if (!Test.isRunningTest())`, which cannot execute
  in a test run. The FeedItem path is for the Tester's Playwright E2E to verify.
- MIXED_DML measured both directions: a PermissionSetAssignment insert is SETUP-class DML,
  the CMOM DiscountApprovalManager__c insert is NOT — neither order works in one transaction
  (house SCRUM-442 Cause E). Mapping tests therefore use orgUser(): the CLI user
  devops-agent@cline.test and the human account meerwais.osmani@resourceful-bear-6f1u4j.com
  already carry all 6 SCRUM445 PSs; the test reads PermissionSetAssignment, no PSA DML.
- `QueueableContext` cannot be constructed ("Type cannot be constructed") — the Queueable
  body was extracted into `DiscountApprovalNotification.notify()` so both paths are coverable.
- PS read-back: 12 rows = 6 PSs x both users (query PermissionSetAssignment AssigneeId/
  PermissionSetId + PermissionSet Name join in code; no name column on the assignment entity).
- Field read-back through the CLI session: Pending rows show Discount_in_Pct__c,
  Approval_Requested_On__c, Approval_Waiting_Days__c — FLS live, not just deployed.
- Probe cleanup: all 17 Probe445* Opportunities deleted; 0 records > 25 % remain in Test-Org.
  (Probe inserts ran in System context, which bypasses ValRules — that is why they existed.)
