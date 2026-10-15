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

## Findings (fill in)
-
