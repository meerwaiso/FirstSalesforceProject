# SCRUM-449 — Developer-Notizen

Verfahrt: own worktree `scr449-wt`, Branch `feature/SCRUM-449-risk-level`.
Shared checkout sits on feature/SCRUM-424-first-response with SCRUM-424/442/445
leftovers — not mine, neither commit noch delete.

## PO round-2 (2026-10-16 17:31) — AC4 setback: SEEDED, count now 1

PO's one gap: 0 open records had Highest_Stage_Reached__c != StageName, so the
setback rule was only proven on Apex-created records. Instruction: seed a record
that reaches an advanced stage and is moved back two positions, re-measure.

- Seed record: 006WU00000SdQE4YAN (open, CloseDate 2026-12-31, outside the 7d
  window, not passed) — chosen so the ONLY warning left is the setback.
- Two saves (each recomputed by the before-update trigger):
  1. StageName Prospecting -> Proposal/Price Quote (pos 7). MID read-back:
     high=Proposal/Price Quote, level=null (no warning yet).
  2. StageName -> Id. Decision Makers (pos 5). READBACK: stage=Id. Decision
     Makers, high=Proposal/Price Quote (high-water mark KEPT), level=High,
     days=0, eval=2026-10-16 17:03:41,
     reason="Stage setback: 2 positions below the highest stage reached
     (Proposal/Price Quote)".
- AC4 High branch proven on a REAL record; the tracking field does NOT move
  backwards — exactly the thing the Apex test could not see.
- Re-measure (scratch/measure449setback.apex, no DML):
  OPEN=75, high populated=75, TRACKING DIFFERS=1, setback>1=1, setback=1=0.
  LEVELS open -> High=15, Medium=1, Low=26, none=33 (was 14/1/27/33).
- PITFALL that cost the first attempt: my seed block ended with a count loop
  that read o.Risk_Level__c without querying it ->
  System.SObjectException "SObject row was retrieved via SOQL without
  querying the requested field" at line 38. An unhandled Apex exception rolls
  back the WHOLE transaction, so both saves were lost and the org still showed
  Prospecting. Symptom: seed looks successful in the log, org unchanged.
  Fix: scratch/seed449setback2.apex queries every field it reads.
- Worktree note: `scr449-wt` was gone; `git worktree add` refused because a
  plain dir of that name existed (my write_file re-created it), and `rm -rf`
  is denied. Used a fresh path: ./scr449b-wt (inside the main repo folder).

## Org-Facts (gemessen, nicht assumed)

- `sf sobject describe -s Opportunity --target-org Test-Org` → StageName picklist
  in configured order: 1 Prospecting, 2 Qualification, 3 Needs Analysis,
  4 Value Proposition, 5 Id. Decision Makers, 6 Perception Analysis,
  7 Proposal/Price Quote, 8 Negotiation/Review, 9 Closed Won, 10 Closed Lost.
  `restrictedPicklist: False`, groupable/sortable true. Early = 1–5.
- Opportunity: NO `Status`, NO `Owner` (OwnerId exists). `IsClosed` = house SoT.
- 127 Opportunities, 73 open (`SELECT COUNT() FROM Opportunity WHERE IsClosed=false`).
- `ScheduledJob` (Tooling API): 0 jobs in Test-Org today → CRON 04:00 collides with nothing.
- FieldDefinition (Tooling API): none of the six risk fields exists yet.
- CLI target-org user = `devops-agent@cline.test` (alias Test-Org).

## Decisions / deviations from the design doc

- Picklist XML: house pattern `<valueSet><valueSetDefinition>` (verified in
  `Loss_Reason__c`, `Servicebereich__c`) — the design's `<picklist><picklistValues>`
  sketch is NOT the repo's shape. Same semantics (fixed value set, no default).
- Formula `Inactive_Days__c` falls back to `LastModifiedDate` while
  `Last_User_Change__c` is still blank → AC1 measurable on legacy records
  immediately, not only after the first nightly seed.
- Apex `inactiveDays` = `Math.round((now - anchor)/86400)` — same rounding the
  formula does at scale 0, so Apex C1 and the visible number never disagree.

## Verified during implementation (2026-10-14, each line names its command)

- Stage positions: `Id. Decision Makers` is position **5**, not 4 — an AC4
  "setback of 1" fixture must seed `Highest_Stage_Reached__c = 'Value Proposition'`
  against a `Needs Analysis` record (position 4 vs 3). A wrong picklist position
  in a test fixture reads as a service bug; it was one.
- Apex APIs that do NOT exist (each rejected by `scripts/apex-probe.sh` against
  Test-Org): `Map.Entry` as an iteration type, `Date.before()/after()`,
  `List.subList`, `Date.format()`, `instanceof Scannable`,
  `System.cancelJob/deactivateJob/unschedule/cancelScheduledJob/removeJob`.
  `System.abortJob(Id)` DOES exist. Date comparison = operators; date display
  = `String.valueOf(Date)`; chunking = buffer+flush.
- `DateTime.time()` returns ms-since-midnight but arithmetic with Integer/Long
  is rejected. Working elapsed-days: parse `format('HH')`/`format('mm')` to
  Integers, delta in minutes, floor + half-up.
- `FieldPermission` is NOT a queryable sObject (`sf data query -t` rejects it).
  Use `scripts/fls-check.sh <Object> <Field>` — it answers existence, grant,
  assignment in one call.
- `PermissionSetAssignment` columns are `AssigneeId`/`PermissionSetId` — there
  is no `Assignee` and no `PermissionSetName` to join on.
- TestSetup statics are NOT visible from helper methods (fresh static context
  per test method): a `@testVisible` Id set in `@TestSetup` reads null inside a
  helper. Look the record up by a stable field (Alias) and cache it — the
  bulk test (200 records) blew the SOQL limit with an uncached lookup per row.
- `bulk` is a reserved word in Apex (compile error on `List<Opportunity> bulk`).
- `User.Alias` is max 8 chars; `LanguageLocaleKey`/`LocaleSidKey` = `en_US` and
  `TimeZoneSidKey` = `America/Los_Angeles` in this org (`de_DE`/`UTC` rejected).
- A test user without the read-PS cannot SELECT the risk fields at all — an
  FLS test's positive read-back must run in System context, not inside `runAs`.
- A record with no applying condition has `Risk_Level__c = null`; an FLS test
  asserting "the trigger assessed it" needs a record where a condition applies.
- PS deploy ≠ assignment: both PSs were assigned via `sf data create record -s
  PermissionSetAssignment --values "AssigneeId=... PermissionSetId=..."` (space-
  separated pairs) to `devops-agent@cline.test`, then read back.
- Branch was cut from an OLD master commit: 334 files present in master were
  missing from the branch tree. Fixed with `git rebase --onto origin/master
  36f77ef HEAD`; verified 0 deletions vs master before pushing.
- Live proof record: `006WU00000TWM7zYAH` (SCRUM449_live_proof) — created via
  `sf data create record`, read back with `sf data get record`: Risk_Level__c
  Low, reason names the close-date condition, Inactive_Days__c 0.
- Test results: 14/14 green, deploy `0AfWU00000cDp3f0AC`, RunSpecifiedTests.
- PR #168 (https://github.com/meerwaiso/FirstSalesforceProject/pull/168).

## CI-gate findings on the PR head (2026-10-14, run 38646627875, both reproduced)
- Prod-Org Drift Gate red: `OpportunityRiskService | Variable does not exist: MeinNeuesFeld__c (95:41)` — read from the CI artifact prod-validate.json (gh run download 38646627875). Field exists in NEITHER org: `sf data query -t -q "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinitionId = 'Opportunity' AND QualifiedApiName = 'Opportunity.MeinNeuesFeld__c'"` -> 0 rows in Test-Org AND Prod-Org; no field file in origin/master. Fix: drop the comparison (a field that exists in no org can never change).
- Apex gate red: real MIXED_DML, not the budget — `ApexTestQueueItem WHERE CreatedDate = LAST_N_DAYS:1` = 14 rows vs ceiling max(500, 10 x 78 test classes) = 780. Failure: 'DML operation on setup object is not permitted after ... Account, original object: PermissionSetAssignment' at FlsTest line 124. Fix: Account insert moved to @TestSetup (own transaction), looked up by Name in the method.
- `FieldDefinition` needs `EntityDefinitionId` as a filter (reified column); `QualifiedApiName` alone is rejected. `ApexTestQueueItem` columns: Id, CreatedDate, ApexClassId, Status, ExtendedStatus, ParentJobId, TestRunResultId (no TestClass.Name, no NumberOfTests).
- `sf project deploy validate --tests <non-test class>` -> 'Test coverage of selected Apex Class is 0%' and status Failed with ZERO component failures. Name the covering TEST class in --tests, never the class being deployed.
- AC12 artefacts verified org-first: `sf project retrieve start --metadata 'ListView:Opportunity.Hoeh_Risk_Chancen'` and 'Report:Sales/Hoeh_Risk_Chancen' -> byte-identical to the repo files (ADR-7). Retrieve output-dir must be INSIDE the project (scratch/), /tmp is rejected.
## Rejection round 2 (2026-10-15) — report time frame
- Blocking item: report timeFrameFilter INTERVAL_CURRENT is fiscal-year based; the 13 C3 records carry CloseDate 2024-06-12, so they were excluded (report showed 1 row, not 14).
- Measured: deploying WITHOUT the <timeFrameFilter> element does NOT clear the existing one — deploy ID 0AfWU00000cEbrS0AS reported 'Changed', retrieve still returned INTERVAL_CURRENT. Fix therefore sets the frame explicitly: INTERVAL_CUSTOM 2000-01-01..2099-12-31 (deploy ID 0AfWU00000cEhvF0AS / 0AfWU00000cEbrS0AS with -c).
- Read back: org report metadata == repo file (comments ignored, python diff True); org timeFrameFilter = INTERVAL_CUSTOM 2000-01-01..2099-12-31.
- AC12 count now: Risk_Level__c = 'High' AND StageName NOT IN (Closed Won, Closed Lost) -> 14; identical to Risk_Level__c = 'High' AND IsClosed = false -> 14. 13 of them CloseDate 2024-06-12, 1 at 2026-09-01.
- Open finding (not the blocking item): OpportunityRiskService.recomputeAll() threw 'Operation failed due to fields being inaccessible on Sobject Opportunity' once, when 73 records still needed assessment (batch = DML_CHUNK_SIZE 2000, so one update statement). Single-record updates of the same records (with and without AccountId in the SELECT) and a 2-record batch all succeeded. After the first pass the trigger assesses records on DML, so later recomputeAll calls find dirty=0 and save 0. Cause NOT pinned — do not claim it fixed.
## SCRUM-450 layout gap (2026-10-15) — record page showed no risk fields
- Org layout 'Opportunity-Opportunity Layout' retrieved: 39 fields, 0 risk fields; branch file identical; no manifest on the branch had a Layout member (grep Layout manifest/scr449-*.xml -> none).
- Fix: new <layoutSections> 'Risk Level' inserted after 'Ueberschrittene Abschlusses', shape copied from the house sections (customLabel true, detailHeading true, editHeading true, TwoColumnsLeftToRight). Left column: Risk_Level__c, Risk_Reason__c, Inactive_Days__c. Right: Last_Risk_Evaluation__c, Last_User_Change__c, Highest_Stage_Reached__c. All behavior=Readonly (the mechanism writes them; AC9 forbids hand edits).
- Manifest manifest/scr449-phase5-layout.xml, house pattern scr440-phase3-layout.xml (Layout member = 'Opportunity-Opportunity Layout').
- Deploy: validate then start, ID 0AfWU00000cFfIn0AK, Status Succeeded, Layout Changed, 15/15 tests green.
- Read back: retrieve -> org layout 45 fields (39+6), all six risk fields present, org == repo (comments ignored).
- Same layout member was used by SCRUM-440 for the same object/gap and rendered on the record page.
## PO round 5 (2026-10-15 late) — nightly path + Medium on real data
- PR #168 is MERGED (squash 384635a in origin/master); branch head 406833e is a merge of master back into the feature branch. No production-code change in this round.
- Gap 1, the nightly entry point run end-to-end: scratch/run449scheduler.apex -> new OpportunityRiskScheduler().execute(null) -> log 'OpportunityRiskScheduler: 0 Opportunities re-evaluated', success=true, no exception. recomputeAll() completed over the org.
- Gap 1, the recomputeAll defect: NOT reproducible. Six probes, all pass: per-record 39/39 OK (scratch/pin449sweep4.apex, SELECTED=75 DIRTY=39 bad=0); batched same-value n=42 with flag=true OK; batched changed-value n=2 OK; batched changed-value n=39 OK; batched changed-value n=75 OK (scratch/pin449all75.apex); batched anchor Last_User_Change__c n=39 OK. The failing call was never reached again because the org is consistent (dirty=0), so the batched update at line 339 has nothing to write.
- Why probe 8 (seed 3 records to null level+reason, then recomputeAll) returned saved=0: the before-update trigger recomputes on EVERY save, so the seed was healed inside the same save. The trigger path and the sweep path cannot be separated by seeding through DML.
- Gap 2, the two-warning count measured with the rule contract (scratch/measure449warnings.apex, pure Apex, 0 DML): open=75, c1(>14 days inactive)=40, c2(CloseDate within 7 days while early stage)=1, c4w(setback exactly 1)=0, c3(CloseDate passed)=14, setbackAny=0, TWO-OR-MORE-WARNINGS=0. Stage order read from the org: Prospecting=1 Qualification=2 Needs Analysis=3 Value Proposition=4 Id. Decision Makers=5 Perception Analysis=6 Proposal/Price Quote=7 Negotiation/Review=8 Closed Won=9 Closed Lost=10, earlyStageCutoff=5.
- So Medium is unmeasurable on the org as it stands: 0 records carry two warnings. Levels measured over the org: High=14 Medium=0 Low=27 none=33, drift vs stored levels = 0.
- Gap 2, real Medium data seeded (Test-Org, reversible, one record 006WU00000SGHxeYAH, Prospecting): STEP1 CloseDate 2027-03-01 -> 2026-10-19 (a user-editable change, so the anchor moved to now), STEP2 Last_User_Change__c = now-20d written alone (not user-editable, so the value survives). Read back from the org: Risk_Level__c=Medium, Inactive_Days__c=20, Risk_Reason__c='Inaktivity: 20 days without user change;Unrealistic close date: CloseDate 2026-10-19 within the next 7 days while still in an early stage (Prospecting)'. Re-measure after seeding: High=14 Medium=1 Low=27 none=33, drift=0.
- ScheduledJob creation NOT done by me: design section 11 puts System.schedule(...) on DevOps; Test-Org still holds 0 ScheduledJob records for OpportunityRiskScheduler.
- FLS note found while probing: PermissionSetAssignment WHERE Field LIKE '%Last_User_Change%' -> 0 rows, yet the anchor writes succeed for the CLI user. The anchor field is written by the mechanism, not by users; the read/write grants come from the object CRUD on the profile, not from a field-level grant.

## Round 7 (2026-10-17) — Architect round-6 rejection: the sweep must survive an invisible field
The Prod nightly sweep failed: `System.DmlException: Operation failed due to fields being inaccessible on Sobject Opportunity`
- Route 1 (DevOps, Prod): AsyncApexJob 707g500000ryLVDAA2, CronTrigger 08eg500000MJiK3AAL fired, 13/13 open Prod records still null.
- Route 2 (DevOps, Prod, synchronous): recomputeAll() as the CLI user -> same DmlException.
Root cause read from the org: line 94 `if (now.TestFeld__c != was.TestFeld__c) return true;` — TestFeld__c is SCRUM-315's field.
FLS read-backs with scripts/fls-check.sh (canonical 3-query chain):
- Test-Org  TestFeld__c: exists Text(255), granted by 28 PROFILES (incl. Standard User) -> visible. That is why the sweep ran there.
- Prod-Org TestFeld__c: exists Text(255), FieldPermissions KEINE, no PS and no Profile -> invisible to ALL users incl. Sys-Admin. That is the wall.
- Rueckruf_desired__c / Discount_in_Pct__c / Rejection_Reason__c: granted by PSs (SCRUM440_Rueckrufwunsch; SCRUM445_Discount_Owner/_Read; SCRUM445_Discount_Manager/_Read), 2 users in BOTH orgs.
Fix (NOT the per-org drop the round-6 rejection called out): guard every foreign comparison by the ACTING user's accessibility.
- Service: `refreshForeignVisibility()` fills Map<String,Boolean> foreignVisible with `Opportunity.<Field>.getDescribe().isAccessible()`; `foreignVisibleToUser(apiName)` reads it. Handler calls refreshForeignVisibility() ONCE per transaction before the record loop (accessibility belongs to the acting user; the acting user differs between UI save, API call and the scheduler).
- getDescribe() on a typed Field reference does NOT throw for an invisible field -> isAccessible()=false (house pattern, SCRUM449OpportunityRiskFlsTest). `Opportunity.Field f = Opportunity.X__c;` compiles for a granted field; it does NOT compile for Is_Inactive__c (0 grants) -> a name with no grant anywhere cannot even be referenced, so the guard is for per-user invisibility, not for org-absence.
- MeinNeuesFeld__c stays unreferenced: exists only in Test-Org, a reference is a COMPILE error in Prod (Drift Gate "Variable does not exist").
Design doc: new section 5b "Changed by a user — org-independent definition" (Blocking 3 asked for the reason in the design/ADR, stated once and org-independently).
Deploys (Test-Org, house order: helper ALONE first, then consumers):
- validate manifest/scr449-phase2a-service.xml --test-level RunRelevantTests -> Succeeded 0AfWU00000cIzgf0AC, 127/127 tests.
- deploy start same -> 0AfWU00000cIzlV0AS, Succeeded, 127/127.
- new manifest/scr449-round7-fix.xml (Handler only; Scheduler+Trigger bodies unchanged, PSs unchanged and already assigned) -> 0AfWU00000cJ0EX0A0, Succeeded, 127/127.
- Read-back that the NEW class is live: `sf project retrieve start -m ApexClass:OpportunityRiskService -o Test-Org -t scratch/retrieve2 --unzip` -> org source has refreshForeignVisibility 3x, TestFeld__c guarded at line 143 (org 16,7xx chars vs Prod 15,9xx with the live comparison).
New tests in SCRUM449OpportunityRiskFlsTest (Blocking 4):
- sweep_survivesForeignFieldInvisibleToActingUser: user with ONLY the two SCRUM449 PSs; preconditions assert Rueckruf_desired__c/Discount_in_Pct__c/Rejection_Reason__c INVISIBLE and Risk_Level__c visible (so the run cannot pass vacuously), then recomputeAll() under runAs(u) must not throw, and open/stamped/anchored counts must be equal (counted, not assumed).
- userEditOfGrantedForeignField_movesAnchor: Standard User edits TestFeld__c in Test-Org (precondition: accessible AND updateable there) -> Last_User_Change__c must move. The guard must not swallow a real user change.
License note: `insert u` for a fresh User can hit LICENSE_LIMIT_EXCEEDED in Test-Org (measured twice in scratch probes); inside the test runner the same inserts work (the existing FLS test does them).
