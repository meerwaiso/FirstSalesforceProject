# SCRUM-449 — Tester-Notes (first pass)

Start: 2026-10-15. Board read back: SCRUM-449 status "Testen", assignee tester-agent (correct, nothing to fix).
Story: automatic Risk Level (Low/Medium/High) + Risk Reason + Inactive Days + Last Risk Evaluation on Opportunity,
written ONLY by the system. 12 ACs. Counting rule: every AC needs real records, 0 records = untested, not PASS.

## Branch / PR
- branch feature/SCRUM-449-risk-level, head f917d1e (remote)
- PR 168, MERGEABLE / UNSTABLE
- CI on PR 168 head: Lint pass 49s | Metadata, Apex & Session Smoke pass 4m12s | README pass 5s | **Prod-Org Drift Gate FAIL 17m34s** (run 38704231362) — cause not yet read
- worktree ../wt-SCRUM-449 on the ticket branch (shared checkout stays on SCRUM-424, untouched)

## Org facts (VERIFIED 2026-10-15, Test-Org)
- All 6 fields LIVE (FieldDefinition via --use-tooling-api, EntityDefinition.QualifiedApiName='Opportunity'):
  Risk_Level__c Picklist | Risk_Reason__c Text(255) | Inactive_Days__c Formula (Number)
  Last_Risk_Evaluation__c Date/Time | Last_User_Change__c Date/Time | Highest_Stage_Reached__c Picklist
- FieldPermissions: each of the 6 granted by SCRUM449OpportunityRisk (read=true edit=false)
  and by SCRUM449OpportunityRiskWrite (read=true edit=true). Inactive_Days__c only ONE row (formula, no edit).
- Assignments (via scripts/fls-check.sh Opportunity Risk_Level__c Test-Org — the tool, not my SOQL):
  SCRUM449OpportunityRisk -> 2 users: devops-agent@cline.test + meerwais.osmani@resourceful-bear-6f1u4j.com
  SCRUM449OpportunityRiskWrite -> 1 user: devops-agent@cline.test
  URTEIL of the tool: "Sichtbar für devops-agent@cline.test"
- CLI quirk: `SELECT ... FROM PermissionSetAssignment` returns 0 rows for EVERY filter (even WHERE Assignee=...)
  — plain SOQL cannot reach it. fls-check.sh step 3 does. Do NOT conclude "assigned to nobody" from that query.
- CLI quirk: FieldDefinition columns are QualifiedApiName/DataType/EntityDefinition.QualifiedApiName.
  `FieldAPIType`/`FieldTypeName`/`Object_API_Name` do NOT exist (INVALID_FIELD).

## Open questions to settle
- Stage__c picklist order in the org (needed for C2 "early stage" = first half, and C4 setback) — describe call
  returned nothing on first try; settle with the right call.
- ScheduledJob for OpportunityRiskScheduler: PR says NOT created by deploy, DevOps creates it at runtime.
  AC6/AC8 recalculation may depend on it -> must check whether a ScheduledJob exists in Test-Org.
- AC9 negative test: SCRUM449OpportunityRiskWrite grants edit=true on all 6 fields to devops-agent@cline.test.
  Is that user a "Sales Representative"? AC9 says a rep and a manager must be REFUSED. Test both shapes.

## Findings (measured 2026-10-15, Test-Org)
- Apex 17/17 pass (RunSpecifiedTests, both classes). Verified from
  scratch/apex449.json: status Succeeded, numberTestsTotal 17 /
  numberTestsCompleted 17 / numberTestErrors 0, op id 0AfWU00000cEkjT0AS,
  completedDate 2026-10-15T10:52:56Z. The CLI reports NO job id for
  RunSpecifiedTests via deploy start — never quote a job id for this run.
  All 12 ACs have a named Apex method (see coverage table on SCRUM-449).
- Org data: 42 assessed records; 14 High+open; 54 closed with 0 assessed;
  40 open with Inactive_Days__c > 14, ALL assessed (27 Low + 13 High) -> 0 stale.
- AC1 UI RED: record page renders none of the 6 risk fields (probe on
  006WU00000Q2RZqYAN: label absent, value absent, reason text absent).
  Org layout 39 fields / 0 risk fields; branch layout identical; no Layout
  entry in any manifest/scr449-*.xml. -> SCRUM-450 filed, linked, assigned.
- AC12 GREEN: list view Hoeh_Risk_Chancen = 15 rows for 14 org records;
  cells render VALUE BEFORE LABEL ("24 Locked Inactive Days High Locked Risk
  Level"), so no adjacency regex works — assert label presence + value presence
  separately.
- TRAP: Test-Org reuses record names across closed and open records
  (3 collisions: 'Edge Emergency Generator', 'United Oil Installations',
  'United Oil Refinery Generators'). A name-based leak check is a data
  artifact, not a defect. Use exact row count vs the org query instead.
- Report Hoeh_Risk_Chancen carries <scope>organization</scope> -> the SCRUM-390
  "My Cases" default is NOT present here.
- 0 ScheduledJob records in Test-Org: the design's nightly recalculation is
  not scheduled. Not AC-blocking (AC6/AC8 pass via the trigger path), but
  DevOps has to create the job before the nightly sweep works.
- Verdict: 11/12 pass, AC1 FAIL -> SCRUM-449 back to developer-agent,
  column "Implementierung" (transition_id 21). SCRUM-450 linked with "Relates".
- Spec committed 49f8cc7 + final AC7 fix pushed on feature/SCRUM-449-risk-level.

## Re-test after the Developer's SCRUM-450 fix (2026-10-15, head 52c61ab)
- Fix commits: 02ce6a1 (layout) + 52c61ab (dev notes). Diff a40eaff..52c61ab
  touches ONLY: the layout file (+35 lines), manifest/scr449-phase5-layout.xml
  (+10), docs/SCRUM-449-notizen-dev.md. NO Apex, no trigger, no PS -> the
  17/17 Apex result from above still stands, no re-run needed.
- ORG layout re-retrieved (scratch/l449c): 45 fields (was 39), all four
  asserted fields present: Risk_Level__c / Risk_Reason__c / Inactive_Days__c /
  Last_Risk_Evaluation__c each grep-count 1.
- Playwright re-run on the new head: smoke 2/2, spec SCRUM-449-risk-level
  3/3 green (28.5s) -> AC1 now PASS. Log: scratch/spec449c.log.
- CI on PR 168 head 52c61ab (run 38776090054): Lint pass 51s | Metadata,
  Apex & Session Smoke pass 2m54s | README pass 6s | Prod-Org Drift Gate
  fail 13m7s = the same pre-existing INCONCLUSIVE cause (test classes vs
  Prod-Org), not drift on this change.
- STILL 0 ScheduledJob records in Test-Org: the nightly recalculation remains
  unscheduled. Not AC-blocking; DevOps has to create the job.
- VERDICT ROUND 2: 12/12 PASS -> SCRUM-449 to devops-agent, column
  "Deployment" (transition_id 4). SCRUM-450 resolved (fix verified in org +
  UI) -> "Erledigt" (transition_id 41).

## Re-test round 3 (2026-10-16, head ccfc773)
- Board read back: SCRUM-449 "Testen", assignee tester-agent. PO handed back with 2 gaps; dev closed both (head ccfc773).
- Diff 52c61ab..ccfc773 touches: ci.yml (from the SCRUM-448 merge), SCRUM445DiscountApprovalTest (SCRUM-448 fixture fix), docs. SCRUM449 Apex classes UNCHANGED -> the 17/17 Apex result (op 0AfWU00000cEkjT0AS) still stands, not re-run (test budget).
- Org counts re-measured 2026-10-16: open 75; High 14, Medium 1, Low 27, none 33; closed-with-level 0.
- AC5 Medium now measurable on REAL data: record 006WU00000SGHxeYAH, Medium, Inactive_Days 20, reason names Inaktivity + close-date situation.
- New E2E describe block AC2/AC5 added (Medium on the real record, count>0 asserted). Suite: smoke 2/2, spec 4/4 green (48.8s).
- ScheduledJob: NOT queryable by me. `SELECT ... FROM ScheduledJob` -> INVALID_TYPE via plain AND --use-tooling-api SOQL; Apex `List<ScheduledJob>` -> compile failure "Invalid type". The dev's 0-jobs figure came from their own Tooling call; I could not reproduce it. Report as open item for DevOps (design sec. 11 puts System.schedule on DevOps), not as a defect.
- Verdict: 12/12 PASS -> handoff to devops-agent, column "Deployment".

## Round 4 (2026-10-16, head 9162c3f reviewed by Architect round 5)

- AC4 setback now has an E2E block (the Architect's open item: the spec had none).
  Measured on real org data: 006WU00000SdQE4YAN, stage Id. Decision Makers (pos 5),
  high-water Proposal/Price Quote (pos 7), setback 2, Risk_Level__c High,
  Risk_Reason__c names the setback and quotes the high-water stage.
- Org re-read 2026-10-16: 75 open; High 15 / Medium 1 / Low 26 / none 33;
  54 closed, 0 with a level; open records whose high-water differs from current
  stage = 1 (the seeded setback).
- LIST-VIEW CAP, VERIFIED: Lightning renders only the first page. The Account
  list view with 50 items also renders exactly 14 data rows. So `rowCount ==
  orgCount + 1` is a platform assertion, not a feature assertion — it was RED
  on master's spec (15 rows vs 16 expected). Organisation-wide scope is asserted
  via the header's own "Select N items" count instead; a user-scoped filter or a
  leaking closed record still reddens the run.
- Suite: 5/5 green, 44.2s (smoke 2/2 green).
- Repo gap found: PR #168 was already MERGED (squash 384635a, head 406833e), so
  the round-3 spec is what master carries. My round-4 spec went to branch
  test/SCRUM-449-e2e-round4 -> PR #172 (head 599e578), CI 4/4 green
  (Lint 48s, Smoke 1m35s, Drift Gate 8m45s, README 6s, run 38951695951).
  DevOps merges PR #172; without it master keeps a red spec.

## Round 5 (2026-10-17, Architect round-8 approval at head 426ff81, PR #173)

Production code changed this round (the sweep guard), so the Apex classes changed and ran again.

- Apex: `sf apex run test --test-level RunSpecifiedTests --tests SCRUM449OpportunityRiskTest --tests SCRUM449OpportunityRiskFlsTest`
  -> **21/21 green, run 707WU00001OIttE**, incl. the two new methods
  `sweep_survivesForeignFieldInvisibleToActingUser` Pass and `userEditOfGrantedForeignField_movesAnchor` Pass.
- E2E: smoke 2/2; spec **5/5 green twice** (48.4 s, 43.8 s). One earlier run flaked red on AC1 —
  see below, it was a test-design race, not a finding.
- AC1 RACE, root-caused: the block compared the record PAGE against an exact SOQL snapshot of
  Risk_Reason__c / Inactive_Days__c. The nightly sweep re-writes both WHILE the test runs
  (measured: 51 open records share eval timestamp 2026-10-17T15:01). LIMIT 1 without ORDER BY
  also returned a different record per run. Fix: ORDER BY Id + assert the page's OWN rendered
  values (High, a condition clause, days as rendered > 14). PR #174, head a4185ec, CI 4/4 green
  (Lint 35s, Smoke 1m39s, Drift Gate 8m44s, README 4s, run 39070552273).
- Org re-read 2026-10-17 (Test-Org): 75 open — High 15 / Medium 1 / Low 39 / none 20
  (round 4 was 15/1/26/33: the sweep levelled 19 more records, AC6 working org-wide);
  0 records carry a level with no condition applicable (no stale levels);
  0 records whose level disagrees with their own data.
- Nightly sweep in Test-Org PROVEN org-wide: 51 records share one eval timestamp;
  AsyncApexJob since 2026-10-16: 144 jobs, **0 Failed** since 2026-10-15
  (the only Failed job in Test-Org is 707WU00001NXc2ZYAT from 2026-10-13).
- AsyncApexJob field names: `ObjectName`, `TotalNumberOfRecords`, `DateStarted` are NOT
  queryable — `SELECT Id, Status, CreatedDate` works. `sf sobject describe --sobject AsyncApexJob`
  returns no queryable field list; the error message names the bad column.
- Prod-Org (read-only, not my deploy): 1 Failed job 707g500000ryLVDAA2 at 2026-10-16T22:02;
  13 open records, only 1 re-evaluated on 2026-10-17 -> the Prod nightly sweep is still dead
  because master head 08be8a4 carries the UNGUARDED comparison. DevOps' step at Release
  (merge PR #173 + redeploy), not a Tester defect.
- Handoff: 12/12 PASS -> devops-agent, column Deployment. DevOps merges PR #173 (production)
  AND PR #174 (my race-free spec).
