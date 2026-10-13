# SCRUM-446 / SCRUM-447 — Tester-Notes (Review-Durchgang)

Start: 2026-10-13 21:30 CEST. Both bugs were filed by me on 2026-10-13 19:08/19:09 and are now
assignee=tester-agent, status="In Überprüfung". Story: SCRUM-445 (was "In Bearbeitung",
assignee=developer-agent).

## Board state (read back 21:3x)
- SCRUM-446: status "In Überprüfung", assignee tester-agent, labels [layout, tester-found]
- SCRUM-447: status "In Überprüfung", assignee tester-agent, labels [chatter, tester-found]
- Transitions available on SCRUM-446: 7=Release, 11=Zu erledigen, 21=In Bearbeitung,
  31=In Überprüfung, 41=Erledigt, 5=Testen

## Branch movement (the fix landed while I was away)
- feature/SCRUM-445-discount-approval: my last head 4c0b5f3 -> 86da0ec (Developer rework)
  -> 4211221 (my re-test spec, pushed 2026-10-13 20:3x)
- Rework commits: adba8f9 layout fields + FeedItem PS + no swallowed cause; 30f6e78/19bdceb
  Notification carries its payload; 4ba9fb1 lineFor() no '/null' link on before-insert
- PR 166 head = 4211221; CI on it: Lint pass, README pass, "Metadata, Apex & Session Smoke"
  and "Prod-Org Drift Gate" still pending at 20:3x

## Facts from the earlier run (verified 2026-10-13, Test-Org)
- Org layout "Opportunity Layout" had 29 fields, 0 of the 8 SCRUM-445 fields (SCRUM-446)
- 37 Queueable AsyncApexJobs class=DiscountApprovalNotification (01pWU00000SwnDAYAZ) Status=Completed
  NumberOfErrors=0, but only 2 FeedItems that day (SCRUM-447)
- notify() called DIRECTLY inserts a FeedItem; the enqueue leg produced none
- Apex 17/17 pass, job 707WU00001NVutbYAD; Playwright 5/6 green, AC1 red
- CLI user devo = 005WU000017tEKLYA2; second user 005WU000017tBhRYAU; Automated Process 005WU000017tBpWYAU
- Opportunity account 001WU0000242xNGYAY

## Findings (this review) — VERIFIED 2026-10-13 20:30, Test-Org

### SCRUM-446 (layout gap) — FIXED, verified at the org
- `sf project retrieve start --metadata "Layout:Opportunity-Opportunity Layout" -o Test-Org`
  -> 39 fields; all 8 SCRUM-445 fields present (grep "<field>X__c</field>" = 1 each).
- UI proof: ariaSnapshot of the Details tab body carries "Discount in % 20,00 %" and
  "Discount Approval Pending" — label AND value in ONE text node of the listitem.
  NOTE: the value renders with a COMMA decimal (locale). getByText(label) matches the
  INNER element that holds only the label -> asserting the value on it measures the
  label alone. Assert on the body ariaSnapshot instead.

### SCRUM-447 (AC4 notification) — FIXED, verified end-to-end
- Fresh CLI insert at 20 % (TEST-446-AC4-INS) -> FeedItem 0D5WU00000fn3s10AA,
  ParentId = 005WU000017tBhRYAU (the mapped manager), Body names the record + "20.00 %".
- Automated test added to the spec: AC4 polls FeedItem (budget 5 min, 15 s steps) —
  the enqueue is async, a fixed wait measured red once.
- Mapping DiscountApprovalManager__c: 2 entries live (Rep=devo -> Manager=MOsma and back).
  Query the object directly: `SELECT Id, Name, Rep__c, Manager__c FROM DiscountApprovalManager__c`
  (sObject 'Mapping__c' / 'MappingFieldEntry__c' NOT supported — the mapping object IS its own sObject).

### Spec state after re-test
- tests/e2e/SCRUM-445-discount-approval.spec.ts: 7 tests, 7 passed (1.6 min), stats
  expected 7 / unexpected 0 / flaky 0. Smoke 2/2 (17 s).
- Apex SCRUM445DiscountApprovalTest + SCRUM445DiscountFlsTest after the rework: 17/17 Pass.
- AC10 locator made robust: rows polled with 60 s budget (a fixed 5 s wait measured
  0 rows while the org held 8 Pending).
- Pushed: branch head 421122115858599f88395fcb7a3d81766d99dc79.

### Cleanup
- 0 Opportunity records matching TEST-446% / TEST-SCRUM445% left.
- 29 FeedItems naming my test records deleted (all CreatedById = CLI user, deletable).
