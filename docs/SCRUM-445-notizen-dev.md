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
- Probe cleanup: all 17 Probe445* Opportunities deleted; 0 records with Discount_in_Pct__c > 25 remain in Test-Org.

## Rework after the Architect's rejection (2026-10-13)
- AC13 exposed a real handler gap: `needsApproval()` ignored the stage, so a Closed Lost
  record with a 20 % discount landed on the waiting list forever. Fixed with `alreadyClosed()`
  (Closed Won / Closed Lost never get a request) and a `Rejected` guard so a later rep edit
  cannot silently overwrite the manager's decision.
- AC6 (rejection) had ZERO coverage before — grep 'Reject' in both test classes: 0 hits.
  New test `ac6_rejectionBlocksClosedWon`: manager sets Rejected + Rejection_Reason__c,
  Closed Won stays refused, decision by/on recorded, Approved_Discount_Value__c stays null.
- AC13 new test `ac13_closedRecordsUntouched`: seeds Closed Lost (needs Loss_Reason__c —
  house ValRule LossReason_PflichtBeiClosedLost rejects the insert without it, measured) and
  Closed Won, asserts no approval fields set, stage unchanged, and a later rename does not
  activate the approval path; counted 0 of 2 closed records on the waiting list.
- AC4 was WEAK (only assertion was trivially true). `notify()` now RETURNS the per-manager
  grouping, and the test asserts: 1 mapping SOQL + 1 enqueueJob for the batch, both records
  carry a manager, 1 group with 2 records. The FeedItem insert itself is `!Test.isRunningTest()`
  guarded and can only be proven by the Playwright E2E spec.
- Counter gotcha: two separate `insert` statements are TWO trigger invocations (mappingSoqlCount
  delta 2). Bulkification asserts need ONE bulk insert.
- Test run 707WU00001NVMCS: 17/17 green. Coverage Handler 95 % (88/93), Trigger 100 % (4/4),
  Notification 77 % (27/35) — the uncovered lines are the doc comment, closing braces and
  the constructor/execute() wrapper; every executable line of notify() is covered.
- grantPS (User insert then PermissionSetAssignment insert, both setup-class DML) verified
  green in 12 methods — no MIXED_DML between them; the earlier failures were PSA vs CMOM
  insert (non-setup), which is the documented Cause E, not a grantPS defect.

## Rework for the Tester's Bugs SCRUM-446 / SCRUM-447 (2026-10-13 evening)
- SCRUM-446 (layout): the branch DID carry the layout file — commit adba8f9 added all 8
  fields, and the org read-back proves it is live: `sf project retrieve start --metadata
  "Layout:Opportunity-Opportunity Layout" -o Test-Org` -> 39 <field> entries, all 8 SCRUM-445
  fields present. The Tester's `git diff --stat origin/master...origin/feature/...` was EMPTY
  because they diffed against an origin/master they had not fetched after our push; the
  layout is in origin/feature/SCRUM-445-discount-approval at head 19bdceb.
- SCRUM-447 (AC4 notification): root cause found by measurement, not theory. The ONLY
  difference between the working direct notify() call and the failing enqueued job was the
  SOQL re-read inside the Queueable — that query returned 0 rows in the Queueable context.
  Fix: the handler renders the bullet lines where the records are already in hand
  (`DiscountApprovalNotification.lineFor(o)`) and passes them into the job (2-arg
  constructor); the Queueable does no SOQL at all.
- SCRUM-447 second leg: the try/catch in notify() was the reason the failure stayed
  invisible (Completed / NumberOfErrors=0, no FeedItem). Removed — a failing Queueable
  now carries the cause in the AsyncApexJob (NumberOfErrors=1, ExtendedStatus) and never
  rolls back the Opportunity save.
- Deploy order (house rule, memory "helper ALONE first"): helper alone via
  manifest/scr447-helper-first.xml (commit ad6ec31), THEN the consumer (Handler + test
  pair) via manifest/scr447-consumers.xml. Consumer+helper in one batch would have compiled
  the Handler against the OLD 1-arg Queueable.
- Measured after the consumer deploy (job 0AfWU00000cBi4g0AC): RunSpecifiedTests
  SCRUM445DiscountApprovalTest + SCRUM445DiscountFlsTest = 17/17 green.
- Org read-back after deploy: `ApexClass:DiscountApproval*` retrieve — Handler and
  Notification byte-identical to the branch files (only a trailing newline differs).
- Probe cleanup: SCRUM447Probe deleted from the org (ApexClass WHERE Name LIKE 'SCRUM447%'
  -> 0 rows) and its file/manifest removed from the tree.
