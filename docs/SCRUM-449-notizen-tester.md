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
- Apex 17/17 pass, job 707WU00001P3gHVkzT (RunSpecifiedTests, both classes).
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
