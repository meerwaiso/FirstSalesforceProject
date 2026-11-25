# SCRUM-477 — Tester notizen

Verified by the commands named on each line (Test-Org, 2026-11-25). Read this file
before re-asking anything.

## Org facts (measured 2026-11-25, `sf data query -o Test-Org --json`)

- Field exists: `SELECT QualifiedApiName FROM FieldDefinition ... Stage_Days_In_Current_Stage__c` -t → 1 row.
- Opps total 157 · open 89 · closed 68 · counter NULL 68 = exactly the closed → **0 open records without a number** (AC1).
- `Stage_Days_In_Current_Stage__c > 30` → 76; with the open clause → 76 (0 closed can satisfy it).
- Boundary: `= 30` → 0 rows, `= 31` → 0 rows (nearest 4 below, 34 above) → AC6 boundary NOT data-testable.
- Records with non-null `LastStageChangeDate` → 9. Exactly ONE is open: `TEST-SCRUM-416-AK2-open-200`
  Id 006WU00000SdQE4YAN, stage `Id. Decision Makers`, last change 2026-10-16, created 2026-09-15,
  counter **40** = today − LastStageChangeDate (CreatedDate would give 70) → this is the AC5/AC4 anchor proof.
- Closed records whose stage-age anchor is >30 days ago → 52 (AC7 negative cases exist).
- ApexTestQueueItem rows in 24 h → 57, ceiling max(500, 10 × classes) → budget free, runs allowed.
- Report `Sales/Chancen_Over_30_Tage` metadata Id = **00OWU00000RnrLN2AZ**
  (from `sf project retrieve start --metadata "Report:Sales/Chancen_Over_30_Tage" --json` → fileProperties.id).
- Stage values proven on OPEN org records: Prospecting, Proposal/Price Quote, Qualification, Needs Analysis,
  Negotiation/Review, Value Proposition, Perception Analysis, Id. Decision Makers. (`FieldValueSet` -t → 0 rows,
  table unusable here; `sf api get` does not exist in this CLI, `Command api:get not found`.)

## Test records in the TEST-namespace, days > 30 (safe to mutate)

- TEST-DBG Id 006WU00000SGHxeYAH stage Prospecting days 84 anchor=CreatedDate 2026-09-02
- TEST-DBG2 Id 006WU00000SGfjpYAD stage Qualification days 84 anchor=CreatedDate 2026-09-02
- TEST-SCRUM-416-AK2-open-200 Id 006WU00000SdQE4YAN days 40 lastStageChange 2026-10-16 (only open record with a real change)
- TEST-SCRUM-416-AK1-open-200 Id 006WU00000SdUHxYAN Prospecting days 71; P2-open2 006WU00000SdURdYAN Qualification 71

## Org automatisation already on Opportunity (not this ticket's, but it runs on stage saves)

`SELECT Name FROM ApexTrigger` -t → OpportunityOverdueReset, OpportunityRiskTrigger,
OpportunityFollowupMonitorTrigger, OpportunityFollowupGuardTrigger, DiscountApprovalTrigger.
`FlowRecord` -t → 0 rows. No SCRUM-477 trigger/flow exists → AC10 structural part.
Consequence (memory i): a synthetic runAs user must hold every PS the real profile holds before
saving an Opportunity — my AC9 negative test stays DML-free (getDescribe only).

## Worktree

- `git worktree add ../wt-SCRUM-477 feature/SCRUM-477-current-stage-days` — worktree was already there
  (Developer's), pulled to head 779d4e0. Reports/…report-meta.xml got org-overwritten by
  `sf project retrieve start` → restored with `git checkout -q --`, tree clean.

## CLI/Playwright traps hit in this session

- `sf project retrieve start --metadata "Report:Sales/..."` rewrites the file on disk (state "Changed") →
  restore before committing, else the drift gate sees an org-retrieved copy.
- `SELECT Id, Name FROM Report` -t → INVALID_TYPE ("sObject type 'Report' is not supported");
  read the Id from the retrieve manifest instead.
- FieldDefinition has no `FieldDataType` column on this org -> ask with fewer columns.

## SCRUM-478 (Drift Gate red on head 5368b7f) - measured 2026-11-25 18:5x

- Root cause confirmed: SCRUM477StageDaysReadTest.cls:14 hardcoded
  `FROM User WHERE Username = 'meerwais.osmani@resourceful-bear-6f1u4j.com' LIMIT 1` +
  `System.assertEquals(1, users.size(), ...)` -> in Prod-Org 0 rows ->
  'List has no rows for assignment to SObject'. DevOps' reading was right.
- Fix applied (commit 12304c4, pushed to feature/SCRUM-477-current-stage-days):
  no username named any more; loop over `SELECT Id, Username FROM User WHERE IsActive = true`
  with System.runAs per user. runAs consumes no licence -> no licence problem in either org.
- Test-Org after the change: 3 tests, 1 failure. The failure is NOT a locator problem:
  8 active Users, 2 of them read StageName on Opportunity but NOT Stage_Days_In_Current_Stage__c
  (integration@00dwu00000oibvj2ay.com, insightssecurity@00dwu00000oibvj2ay.com).
  PS SCRUM477_CurrentStageDays_Read exists (Id 0PSWU00000YFgTB4A1), not assigned to those two.
- PS assignment is NOT readable via Apex/SOQL here: PermissionSetAssignment as Tooling sObject
  returns only Id + attributes (no field names); `AssignedPermissionSetApiName`,
  `PermissionSetName`, `PermissionSet__Id`, `User__Id`, `ProfileId`, `ApiName` all INVALID_FIELD.
  Read the assignees from the .permissionset-meta.xml on the branch instead.
- CI on new head 12304c4 = run 45670266619 (event pull_request, started 2026-11-25T17:58:09Z).
- gh quirks hit: `gh run watch <id> --json` does NOT exist (only --exit-status/--interval);
  `gh run view <id> --json jobs` needs the fields arg; `gh api .../actions/runs` returned runs=null
  while `gh run list --branch ...` works; wrong repo name guessed from the PS/PR text
  (remote is meerwaiso/FirstSalesforceProject).

