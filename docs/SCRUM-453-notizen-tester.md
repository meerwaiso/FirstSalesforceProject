# SCRUM-453 — Tester-Notizen (hard-won findings, 2026-10-22)

Every line names the command that produced it. Read before re-deriving.

## Org state read back by the Tester (Test-Org, 2026-10-22)

- Permission Set holders: 4 sets × 2 users = 8 rows — `sf data query --target-org Test-Org --use-tooling-api -q "SELECT Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM453%'"`. Users: `devops-agent`, `Meerwais Osmani`. **Both hold `SCRUM453_ContactLeft_Undo`** → a UI-negative undo test is unsatisfiable in this org (2/2 licences, skill §4c).
- Field labels as live in the org (`sf sobject describe --target-org Test-Org --sobject Contact`): `Has_Left_Company__c` → "Austritt", `Left_Company_Date__c` → "Austritt am", `Contact_Status_Anzeige__c` → "Austritt-Anzeige", `NewsletterConsent__c` → "Newsletter-Einwilligung", `ConsentDate__c` → "Einwilligung am". Case: `Contact_Left_Anzeige__c` → "Contact person left".
- Formula values render with a **plain hyphen**, not the design doc's en-dash: `Austritt - not there any more` (SOQL read-back). Assert the substring "not there any more", never the design-doc string.
- Report Id: `SELECT Id, Name FROM Report WHERE Name = 'Kunde_ohne_Kontaktperson'` → `00OWU00000R5J2T2AV`. (`ReportId` is NOT a column on `Report`; `SELECT FROM Report` works with plain `data query`, not `--use-tooling-api`.)
- List views: `Kritische_Kontakte` filters `Open_Cases_Rating__c = 'Kritisch'`; `Letzter_Real_Kontakt` and `Letztes_Anliegen` are `filterScope=Everything` (649 contacts → only 14 rows in the DOM, prove scope from the header count).
- `FeedItem` links a record via **`RelatedRecordId`** (`sf sobject describe --sobject FeedItem`); `ReferenceObjectName` does not exist. `Task` links via `WhoId`.

## Report DOM shape (measured via a [PROBE] dump, 2026-10-22)

`/lightning/r/Report/00OWU00000R5J2T2AV/view` → cross-doc frame `lightningReportApp`, ONE tbody, 4 `tr` for 1 matching Account:

1. header row (cells contain "Column Actions") — the header is in the SAME tbody, `thead` is empty
2. group row: `["V453 Fixture Beta, unchecked, Select row for Drill Down.V453 Fixture Beta(1)", "devops-agent", "01.10.2026", "2", "0"]`
3. `["Subtotal","","","",""]`
4. `["Total(1)","","","",""]` — the count is TEXT in the first cell, never a numeric cell; the frame body also carries "Total Records 1"

Dates render `DD.MM.YYYY`.

## Apex evidence (the F-9 rule: a claim that leaves no queue row is not evidence)

- My own run: `sf apex run test -o Test-Org -l RunSpecifiedTests -t SCRUM453ContactLeftTest -t SCRUM453ContactLeftFlsTest -r json` → job `707WU00001PD1mUYAT`, 2026-10-22T20:05:59Z, **18 test methods Pass + 2 @TestSetup** (runner summary `testsRan: 20, passing: 20, failRate 0%`).
- Queue rows: `SELECT Id, Status, CreatedDate, ParentJobId FROM ApexTestQueueItem ORDER BY CreatedDate DESC LIMIT 4` → 2 rows `Completed` for parent job `707WU00001PD1mUYAT` (mine) and 2 for `707WU00001PCy3vYAD` (the Developer's 19:24:18Z run).
- Method → AC map: AC-1 `precondition_contactAccessible`, `mark_setsDateDefault_consentUntouched`; AC-2 `dateCorrectableLater`; AC-3 `historyStaysReachable_afterMarking`; AC-5 `mark_setsDateDefault_consentUntouched`; AC-6 `withoutPS_markInvisible`, `readPS_readableNotEditable`, `readPS_cannotSetMark`, `setPS_setsMark`, `setPSWithoutUndo_cannotClearMark` (negative), `undoPS_clearsMark` (positive); AC-8 `allMarked_customerWithoutContactPerson`, `partialMark_customerStillHasContacts`; AC-9 `nothingAutomatic_noSideEffects`. Regression: `bulk_marking_staysWithinLimits`, `recompute_isIdempotent`, `reParenting_healsBothAccounts`, `deleteHealsAggregates`.

## Fixtures the spec depends on (all resolved by NAME at runtime)

- Accounts: `V453 Fixture Alpha` (Contacts_Without_Mark__c=1, Contacts_Left_Count__c=1, Last=2026-10-01) and `V453 Fixture Beta` (0 / 2 / 2026-10-01) → the overview filter matches exactly 1 Account (Beta).
- Marked Contacts (3, all `NewsletterConsent__c=true`, `ConsentDate__c=2026-06-30`): `V453 Fixture A1` (Alpha), `V453 Fixture B1`, `V453 Fixture B2` (Beta).
- Created by the Tester for AC-3/AC-4/AC-7 (CLI `sf data create record`): Case `SCRUM-453-e2e-Case-B2` on B2 (indicator renders `Austritt - not there any more (2026-10-01)`), Opportunity `SCRUM-453-e2e-Opp-B2` + `OpportunityContactRole` on B2, and 5 open Cases `SCRUM-453-e2e-Kritisch-B1-*` on B1 so B1 reaches `Open_Cases_Rating__c = 'Kritisch'` and lands in `Kritische_Kontakte`.
- `sf data create record --values` splits on SPACES — a value containing a space needs inner double quotes (house note SCRUM-412); `Subject=SCRUM-453 e2e Case B2` failed with "Malformed key=value pair".

## Session / tooling

- Worktree `../wt-SCRUM-453` on `feature/scr453-kontakt-austritt`; `node_modules` is symlinked from the main checkout (a worktree copies tracked files only) — **remove the symlink before handing off**, it is not gitignored here.
- `sf project retrieve start --metadata ...` rewrote `layouts/Contact-Contact Layout.layout-meta.xml` and `reports/Sales/Kunde_ohne_Kontaktperson.report-meta.xml` in the worktree (round-trip drift). Discarded with `git checkout --` before committing; they are the Developer's files, not mine.
- `waitForLoadState('networkidle')` never used; smoke gate `npm run test:e2e:smoke` green in 13.5 s before any spec work.
