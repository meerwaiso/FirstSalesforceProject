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

## Round-3 addendum (measured 2026-10-16, Test-Org)

- Open 75; levels 14 High / 1 Medium / 27 Low / 33 none. Closed 54, 0 with a level.
- Reason categories over the 42 levelled open records: inactivity 40, close-date-passed 14, unrealistic-close-date 2, **stage setback 0**.
- Highest_Stage_Reached__c populated on all 75 open records and EQUAL to StageName on all 75 -> the tracking field is live, but 0 records ever moved backwards. AC4 untested on real data.
- Nightly sweep confirmed: 36 open records share Last_Risk_Evaluation__c 2026-10-15T21:49:31, 3 at 22:04:44, 1 at 22:27:54. Round-2 gap 1 closed.
- Open with Inactive_Days__c > 14: 40 (matches the 40 inactivity reasons exactly).
- Open with a level but no warning applicable: 0 (no stale levels).
- Medium record: TEST-DBG, Id 006WU00000SGHxeYAH, Inactive_Days 21, CloseDate 2026-10-19, StageName Prospecting, reason names both clauses.
- FLS: all four visible fields read-only for 2 users; the write-capable PS is assigned to the CLI user only.
- Prod-Org: still 0 of the four fields (FieldDefinition query, -o Prod-Org). No release note.
- master head 41705cb; CI runs 38887500138 and 38889069341 both success on all four jobs (Prod-Org Drift Gate success).
- Verdict: NOT accepted. AC4 untested -> handed to developer-agent, column Implementierung.

## Round-4 acceptance (measured 2026-10-16 22:3x, Test-Org) — ACCEPTED, moved to Release

- Open 75: 15 High / 1 Medium / 26 Low / 33 none (sums to 75). Closed 54, 0 with a level.
- AC4 now real: 006WU00000SdQE4YAN, StageName Id. Decision Makers vs Highest_Stage_Reached__c Proposal/Price Quote, level High, Inactive_Days 0, reason names the setback and quotes the high-water stage.
- Trap: `StageName <> Highest_Stage_Reached__c` in a WHERE returns 0 rows even though the record above differs. Picklist-to-picklist comparison in WHERE is not a reliable filter — read the records back instead of counting them this way.
- Open with Inactive_Days__c > 14: 52 (was 40 before the sweep ran; the sweep re-evaluated without saves).
- Stale levels: 0. My filter (no setback clause) returned 2 candidates; both carry a real warning (the setback record + SCRUM449_live_proof close-date-within-7-days).
- Residual: 0 records with a setback of exactly 1 position -> that AC4 half is Apex-only. Data gap, not a release blocker.
- Prod-Org: 0 of the six fields. No release note yet; write it on the green Prod deploy report.
- Board after acceptance: status Release, assignee devops-agent (read back from the update response).

## Prod release measured 2026-10-17 09:5x — NOT closed, release incomplete

DevOps reported a green Prod deploy (job 0Afg500000FvGc6CAF, 17/17 components, tag release/2026-10-17-SCRUM-449 -> bb6f3d8, master head bb6f3d8, both read back via git ls-remote). Components are live and permitted. The business outcome is not observable:

- Prod-Org open records: 13. **0 carry a Risk_Level__c.**
- Open with Inactive_Days__c > 14: **13 of 13** (all 18 days). Open with CloseDate already past: **13 of 13** (2026-03-12..2026-06-20).
- Last_Risk_Evaluation__c and Last_User_Change__c: **null on all 13** — nothing has ever been evaluated in Prod.
- Sample: Dickenson Mobile Generators, 18 days, close 2026-05-03, no level, no reason.
- CronTrigger 08eg500000MJiK3AAL live, State WAITING, **TimesTriggered 0**, next fire 2026-10-17T11:00Z.
- FLS step 3 in PROD verified: read PS assigned to 2 users (CLI + real end user), write PS to CLI only; real session SOQL returns values. So this is NOT the deployed-not-assigned trap — the fields are readable, they are just empty.

Rule this establishes: a green Prod deploy proves components exist. It does not prove the feature shows anything on a record. Before closing a story released to Prod, count the records the feature should have flagged and compare with the count it actually flagged. 0 flagged while N qualify = release incomplete; no release note (an entry claims observability, not deployment).

Trap: `Risk_Level__c <> NULL` returned 0 rows while the field is readable — 0 rows here was real data, not a permission wall. Distinguish by reading the field values of a known record, not by the count alone.

## Merge round 2026-10-18 08:1x — repo green, Prod still incomplete, NOT closed

- origin/master 4816da9 carries the sweep guard (foreignVisible + isAccessible, lines 74-97) and the race-free spec (ORDER BY Id, header-count assertions). Verified with git show origin/master:<path>, not the PR title.
- CI read back on exactly the merged heads: 426ff81 -> run 39067579440 success; c14710f -> run 39071420937 success.
- PROD: retrieved the deployed ApexClass OpportunityRiskService from Prod-Org -> 0 occurrences of the guard. The org runs the old class. A merge deploys nothing.
- PROD counts: 13 open; 1 with a level, 1 with an eval stamp; 13/13 over 14 inactive days; 13/13 close date already past. 12 records show nothing.
- Not verifiable from my position: the Tester-named failed AsyncApexJob (by ID and by status both 0 rows in Prod). Stated, not claimed.
- Trap: `sf project retrieve start` writes into the CURRENT working tree. In the shared checkout, delete the retrieved file after reading; never commit it.
- Board after handback: Release + devops-agent (read back from the update response).
- No release note: an entry claims the manager sees the level; 12 of 13 qualifying records show nothing.
