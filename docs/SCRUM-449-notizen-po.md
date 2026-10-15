# SCRUM-449 — PO-Notizzettel (measured 2026-10-15, Test-Org unless stated)

Values below were read back by me with the named command. They are facts about the org at that time, not about the code.

## Field existence — Test-Org (command: `sf data query -o Test-Org -t -q "SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Opportunity' AND QualifiedApiName='<F>'"`)

| Field | Type |
|---|---|
| Risk_Level__c | Picklist (Low/Medium/High) |
| Risk_Reason__c | Text(255) |
| Inactive_Days__c | Formula (Number) |
| Last_Risk_Evaluation__c | Date/Time |
| Last_User_Change__c | Date/Time |
| Highest_Stage_Reached__c | Picklist |

Prod-Org: **none of the six exists** — same query, `-o Prod-Org`, 0 rows. Nothing of this feature is live in production.

## Trap: `Status` is NOT a column on Opportunity

`SELECT COUNT() FROM Opportunity WHERE Status='Open'` fails with `No such column 'Status' on entity 'Opportunity'`. The real columns are `IsClosed` (boolean) and `StageName` (picklist). Verified via `sf sobject describe -o Test-Org -s Opportunity --json` — 70 fields. A WHERE clause on a guessed name returns an error, not 0 rows, but it reads like a missing field if the error is not read.

## Counts — Test-Org, 2026-10-15 (each via `sf data query -o Test-Org --json -q ...`)

- open (`IsClosed = FALSE`): **75**
- open carrying Risk_Level__c: **14 High / 28 Low / 0 Medium / 33 no level**
- open with CloseDate in the past: **14** — identical to the 14 High (all CloseDate 2024-06-12)
- open with Inactive_Days__c > 14: **40**
- closed (`IsClosed = TRUE`): **54**, of which **0** carry a Risk_Level__c → AC7 confirmed in the org
- open with two warnings (Medium candidates): **0** → AC5 untested on real data

## Reason text, read off a real record

`Dickenson Mobile Generators` — Risk_Reason__c: `Inaktivity: 24 days without user change;Close date already passed (CloseDate 2024-06-12)`, Inactive_Days__c 25, Last_Risk_Evaluation__c 2026-10-15T08:02Z, StageName Qualification.

## Report / list view at origin/master (not the shared checkout — it is stale)

`git show origin/master:force-app/main/default/reports/Sales/Hoeh_Risk_Chancen.report-meta.xml` → `<timeFrameFilter>` carries `INTERVAL_CUSTOM`, `startDate 2000-01-01`, `endDate 2099-12-31`. The fiscal-year `INTERVAL_CURRENT` is gone. The file in the shared working tree still shows `INTERVAL_CURRENT` — the checkout is stale, do not read it as the repo state.
`objects/Opportunity/listViews/Hoeh_Risk_Chancen.listView-meta.xml` exists at origin/master.

## FLS read path (command: `scripts/fls-check.sh Opportunity Risk_Level__c Test-Org`)

Granted read-only by `SCRUM449OpportunityRisk` (2 users) and `SCRUM449OpportunityRiskWrite` (1 user); the CLI user `devops-agent@cline.test` can read the field. Plain SOQL on `PermissionSetAssignment` returns 0 rows for every filter in this CLI build — do not read "assigned to nobody" from it; use the script.

## CI on master head 384635a (run 38803689368, read via `gh run view`)

- Prod-Org Drift Gate PASS 8m50s
- Metadata/Apex/Session Smoke FAIL on exactly one test: `SCRUM434Probe.openCaseInRunAs_triggersMustNotBreak` — pre-existing orphan class, tracked in SCRUM-444. Not a SCRUM-449 finding.
- All 18 SCRUM449 test methods Pass in that same run (read off the job log).

## Open gap (why the story is NOT in Release)

The nightly sweep has never run end-to-end: Test-Org holds 0 ScheduledJob records for `OpportunityRiskScheduler`, and `recomputeAll()` threw `fields being inaccessible on Sobject Opportunity` once with 73 records. A deal that only ages — close date passes with nobody touching it — is assessed by that sweep, not by the trigger. Until it runs, "recalculated automatically" is proven only for records that get saved.
