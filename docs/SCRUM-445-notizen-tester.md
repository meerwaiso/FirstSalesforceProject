# SCRUM-445 — Tester-Notizen

## Org-Facts (org-verifiziert, 2026-10-13)
- Target: `Test-Org` = `resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com`, CLI user `devops-agent@cline.test` (Alias `devo`, Id 005WU000017tEKLYA2).
- Alle 8 Opportunity-Fields live (FieldDefinition, `--use-tooling-api`):
  Approval_Decided_By__c Lookup(User) | Approval_Decided_On__c DateTime | Approval_Requested_On__c DateTime |
  Discount_Approval__c Picklist | Discount_in_Pct__c Percent(3,2) | Rejection_Reason__c Text(120) |
  Approval_Waiting_Days__c Formula(Number) IsCalculated=true | Approved_Discount_Value__c Percent(3,2)
  (Letzter via separate query — `DeveloperName LIKE 'Approv%'` MISSES it, it starts "Approa".)
- Picklist values not yet read — TODO read via FieldDefinition ValueTypeId/describe.
- ListView `Opportunity.Discount_Approval_Waiting` live (retrieve Created). `sObject type 'ListView' is not supported` for SOQL — use retrieve.
- 6 PSs live, ALL assigned to BOTH org users (PSA query, 12 rows):
  SCRUM445_DirectManager_Map, DirectManager_Read, Discount_Manager, Discount_Owner, Discount_Read, Discount_System
  -> assignees: 005WU000017tEKLYA2 (devo) + 005WU000017tBhRYAU (MOsma / Meerwais Osmani).
  => NO user in the org lacks the discount PSs. AC14 negative test only via System.runAs (Apex), as designed.
- DiscountApprovalManager__c: 0 records in Test-Org. Tester must create mapping records (design open point).
- Users in org: MOsma, devops-agent, Integration User, Automated Process, Data.com Clean, Security User, Chatter Expert, Platform Integration User. No `Role` column on User.
- Apex budget: 330 ApexTestQueueItem rows / rolling 24h. Ceiling = max(500, 10 x 100 test classes) = 1000. OK, 670 left.

## CI on PR #166 (head cbd677ae, 2026-10-13 15:53:57 +0200)
- run 488 (13:54:04Z): Lint&Format pass, "Metadata, Apex & Session Smoke" pass, README pass, **Prod-Org Drift Gate FAIL**.
- Drift-Gate reason (job log 115335260574): `FailedValidationError`, message names
  `SCRUM445DiscountApprovalTest.ac10/ac13/ac2/ac3... - System.QueryException: No such column 'Discount_Approval__c' on entity 'Opportunity'`
  + several `List has no rows for assignment to SObject`. => Prod-Org runs the Test-Org test classes; fields absent in Prod.
  Gate's own fallback fired: "Validation produced no usable result — this run cannot show the change is free of drift." exit 1.
- NOT my fix (CI/.github/workflows not mine, Prod-Org deploy not mine). Report as own line in coverage table.

## Developer evidence (PR #166 body)
- Apex test run 707WU00001NO8nZ: 15/15 green. Coverage Handler 95%, Trigger 100%, Notification 76%.
- Percent fields in ValRule formulas are FRACTIONS: formula says `Discount_in_Pct__c > 0.25` / `> 0.15`; Apex/SOQL see whole numbers (20 = 20 %).
- `SCRUM445_Discount_System` PS needed for handler writes; `Discount_Approval__c` deliberately EXCLUDED from it.
- Queueable body extracted into `notify()`; FeedItem insert guarded by `!Test.isRunningTest()` -> NOT covered by Apex.

## Apex coverage of the Developer pair (read from branch, 2026-10-13)
SCRUM445DiscountApprovalTest: ac2, ac3, ac5, ac7, ac8, ac9, ac10(record-wise), ac6, ac13, notification_executeBothPaths, bulk_200.
SCRUM445DiscountFlsTest: precondition_opportunityReadable, withoutPS_discountInvisible (AC14 NEG), readPS_readableNotUpdateable (AC11), ownerRep_cannotSetApproved, ac12a_ownerEditsDiscount, ac12b_managerShapeSetsApproved.
=> NOT covered by Apex: AC1 via UI, AC4 FeedItem actually on manager feed, AC10 the VIEW itself, AC11/AC12 in the UI, AC13 no-retroactive in UI.

## Session / infra
- Worktree: shared checkout sits on feature/SCRUM-424-first-response with foreign dirty files -> never switched.


## AC4 — FeedItem: VERIFIED 2026-10-13, inconclusive-to-defect
- FeedItem insert works in the org: scripts/apex-probe.sh scratch/feedprobe.apex -> "INSERTED 0D5WU00000fmpLZ0AY".
- DiscountApprovalNotification.notify() called DIRECTLY creates a FeedItem (rows 6->7,
  scratch/notifyprobe2.apex on TEST-445-AC4-INS). So the class body is fine.
- Real saves above 15% DO enqueue: 37 AsyncApexJob JobType=Queueable class=01pWU00000SwnDAYAZ
  (DiscountApprovalNotification) creator=005WU000017tEKLYA2 between 16:40-16:57 UTC, all
  Status=Completed NumberOfErrors=0.
- BUT the FeedItem is missing for most of them: FeedItem WHERE CreatedDate=TODAY -> 5 rows,
  none naming TEST-SCRUM445-E2E-* (the spec's own 12 creates) and none naming
  TEST-445-AC4-CLEAN / AC4-CLEAN2 (fresh CLI inserts, waited 4 min).
  Only AC4-FEED (16:11:58) and AC4-UPD (16:22:06) got items.
- try/catch in notify() swallows the cause; System.debug not readable (getDebugLogs POST
  returned no usable body).
=> AC4 NOT proven; needs a real automated test. Not asserting "defect" beyond the measurement.

## Layout gap — VERIFIED, primary defect
- Org Opportunity layout: 29 fields, 0 of the 8 new discount/approval fields
  (sf project retrieve start --metadata "Layout:Opportunity-Opportunity Layout" -o Test-Org).
- Branch never touched layouts/: git diff --stat origin/master...origin/feature/SCRUM-445-discount-approval
  -- force-app/main/default/layouts/ -> EMPTY.
- Differential proof via Playwright probe on 006WU00000TUBYQYA5: 'Ruckruf gewunscht' text=3,
  'Discount in %' text=0, 'Discount Approval' text=0; 'Edit Discount in %' button count=0,
  'Edit Stage' button count=1.
=> AC1 FAILS: the record does not show the discount. AC9/AC12 UI paths unreachable.

## Spec run results (2026-10-13, test-report/playwright-results.json)
- smoke: 2 passed (12.0s) -> session healthy.
- SCRUM-445-discount-approval.spec.ts: 5 passed / 1 failed.
  PASS: AC3 (Closed Won refused, stage stays Prospecting), AC9 (org-level refusal + value stays),
        AC10 (ariaSnapshot: 7 items, 'Waiting days (approval)' header, row carries Pending + duration),
        AC12 (update success + 12% persisted), AC13 (14 closed records, 0 with Approval_Requested_On).
  FAIL: AC1 — getByText('Discount in %') element(s) not found on the Details tab.
- Apex: SCRUM445DiscountApprovalTest + SCRUM445DiscountFlsTest 17/17 pass, job 707WU00001NVutbYAD.
- CI on PR 166 head cbd677ae: Prod-Org Drift Gate RED (FailedValidationError from Prod-Org).
