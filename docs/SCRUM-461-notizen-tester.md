# SCRUM-461 — Tester notizen

Verified facts only; each line names the command that produced it.

## Org state (measured 2026-11-17, Test-Org)

| Fact | Command |
|---|---|
| `Competitor__c` deployed (Label "Competitor") | `sf data query --query "SELECT QualifiedApiName, Label FROM EntityDefinition WHERE QualifiedApiName LIKE 'Competitor%'"` |
| Opportunity fields deployed: `Competitor_Lost_To__c` = Lookup(Competitor), `Competitor_Price__c` = Currency(16,2), `Competitor_Gap__c` = Formula(Number) | `sf data query --use-tooling-api --query "SELECT QualifiedApiName, DataType, MasterLabel FROM FieldDefinition WHERE EntityDefinitionId='Opportunity' AND QualifiedApiName LIKE 'Competitor%'"` |
| `Lost_Last_12M__c` = Formula(Checkbox) deployed | same query, exact name |
| Reports deployed: `Verloren_Chancen_je_Wettbewerber` = 00OWU00000RbBRZ2A3, `Verloren_Chancen_je_Wettbewerber_Meine` = 00OWU00000RbBRa2AN | `sf data query --query "SELECT Id, Name FROM Report WHERE Name LIKE 'Verloren_Chancen%'"` |
| All 3 PSs exist: `SCRUM461_Competitor_List_Read` 0PSWU00000Xz4ex4AB, `..._Teamleitung` 0PSWU00000Xz4ey4AB, `SCRUM461_Competitor_Lost` 0PSWU00000Xz4ez4AB | `sf data query --query "SELECT Id, Name, Label FROM PermissionSet WHERE Name LIKE 'SCRUM461%'"` |
| 6 PS assignments: devops-agent@cline.test (005WU000017tEKLYA2) holds ALL THREE; Meerwais Osmani (005WU000017tBhRYAU) holds all three | `sf data query --use-tooling-api --query "SELECT PermissionSetId, AssigneeId, IsActive FROM PermissionSetAssignment WHERE PermissionSetId IN (...)"` |
| CLI target-org user = `devops-agent@cline.test`; only aliases are Test-Org and Prod-Org | `sf org display`, `sf org list` |
| Competitor records in org before my seeding: 0 | `sf data query --query "SELECT Name FROM Competitor__c"` |
| Closed Lost Opportunities: 16, ALL owned by devops-agent@cline.test; 0 with `Loss_Reason__c=Wettbewerber` | `sf data query --query "SELECT Id, OwnerId, ... FROM Opportunity WHERE StageName='Closed Lost'"` |
| 130 Opportunities: 97 owned by devops-agent, 33 owned by Meerwais Osmani (sample data, none Closed Lost) | `SELECT OwnerId FROM Opportunity` + Counter |

## Consequences for the test plan

- The Playwright session authenticates as devops-agent@cline.test, who holds all three PSs
  → the UI can prove the POSITIVE half of AC4 (team-lead rights) only. The negative half
  (a user without `_Teamleitung` cannot create) has no second licensed session: only two
  sf aliases exist (Test-Org, Prod-Org) and re-authenticating is the user's action.
  Negative half = Apex `System.runAs` (house default).
- AC8's "own deals vs all deals" needs a competitor-lost deal owned by a DIFFERENT user.
  OwnerId cannot be set on create. Route taken: flip one sample Opportunity owned by
  Meerwais Osmani (Closed Won → Closed Lost + `Wettbewerber` + competitor). Chosen after
  grepping every spec: no suite asserts an org-wide Closed Lost Opportunity count
  (SCRUM-449 filters `IsClosed = false`, SCRUM-381/416 use their own TAG fixtures).

## CLI / platform quirks hit this ticket

- `SELECT COUNT FROM ...` is not SOQL in CLI 2.150.6 — use `--json` + count records.
- `FieldDefinition` has `DataType`, not `Type`; `PermissionSetAssignment` has
  `PermissionSetId`/`AssigneeId`, not `AssignedUser`; `Report` has no `Scope` column.
- `sf apex run test` flags: `--class-names`, `--tests`, `--test-level` (no `--async`).

## Platform finding — a Lookup needs a readable target object

- `Competitor_Lost_To__c.getDescribe().isAccessible()` is **false** for a user holding
  ONLY `SCRUM461_Competitor_Lost` (C7); it is **true** once `SCRUM461_Competitor_List_Read`
  (C8) is assigned as well. `Competitor_Price__c` was readable in both cases.
  Command: `SCRUM461TesterFlsGateTest` (System.runAs over a synthetic User + PS
  assignment), first run failed at the lookup assertion, second run 19/19 green.
- Consequence: C8 is not an optional extra for the picker — every role that has to fill
  the picker needs C8. The design already assigns C8 to all internal sales roles, so this
  is a confirmation, not a defect. If a future role gets C7 without C8, the picker
  silently disappears.

## Test data seeded (idempotent, by Name)

| What | Names | Command |
|---|---|---|
| 3 Competitor__c records | `Nordwind Solutions`, `Alpha Ventures`, `Beta Build` | `sf data create record -s Competitor__c -v "Name='...'"` + `SELECT Id, Name FROM Competitor__c` |
| 8 own Closed-Lost competitor deals | `TEST-SCRUM-461-N1..N4`, `A1`, `A2`, `B1`, `OUT` | `sf data create record -s Opportunity ...` |
| 1 deal owned by ANOTHER user (for AC8) | sample `Opportunity` renamed `TEST-SCRUM-461-FOREIGN`, Closed Won → Closed Lost + Wettbewerber, Amount 80000, price 60000, CloseDate 2026-06-01 | `sf data update record -s Opportunity -i 006WU00000Q2RZsYAN -v "..."` — read back: `Competitor_Gap__c = 20000`, `Lost_Last_12M__c = true` |

- `sf data update record` on a record owned by another user of the org SUCCEEDS — the
  foreign deal for AC8 is therefore reachable without a second licence.
- Fixture names avoid `Müller GmbH` / `Müller Group`: the duplicate guard on `Competitor__c.Name`
  refuses an insert whose Name already exists in the org.

## UI locators (probed 2026-11-17, `scripts/tmp-probe461g.js` / `h.js`)

- New-Form `/lightning/o/Opportunity/new`: textbox `Opportunity Name`, combobox
  `Stage`, combobox `Verlustgrund`, combobox `Lost to competitor` (the Lookup picker),
  button `Save`. `Competitor price` is NOT reachable as a combobox by that name
  (probe H: count 0) — the UI never fills it, so the spec never touches it.
- **The loss-reason label is dative: `An einen Wettbewerber verloren`.** `An einem …`
  (which the design notes used) matches nothing. Full label set read from the opened
  picker via `ariaSnapshot()`: `--None--`, `Zu teuer`, `An einen Wettbewerber verloren`,
  `Kein Budget`, `Zeitpunkt passte nicht`, `Kein Bedarf mehr`, `Kontakt abgebrochen`,
  `Sonstiges`.
- Picklist options are in a shadow root: `[role=option]` elements exist, but
  `getByRole('option', {name})` finds nothing — only `ariaSnapshot()` shows the name
  (same trap as SCRUM-417). `pickOption()` in the spec clicks the element whose
  snapshot contains `option "<label>"` and THROWS if it never appears.
- Refused save renders `dialog "We hit a snag."` → `strong: Review the …` →
  `listitem` naming the offending field. With Stage=Closed Lost and no reason the
  listitem is `Bitte wählen Sie einen Verlustgrund, bevor Sie die Chance als verloren
  markieren.` — i.e. a missing reason is a DIFFERENT message than a missing competitor.
- Report rows (`lightningReportApp` iframe): first `<td>` of a group row is
  `<name>, unchecked, Select row for Drill Down.<name>`; numbers render in the user's
  locale (`490.000,00 €`), so the spec parses German and US separators.

## Apex trap — the org ran a stale version

- Run `707WU00001Udo0N` failed at `dealPermissionSet_makesPriceReadableAndEditable`
  with stack `line 107`, but line 107 of the deployed source is a
  `PermissionSetAssignment` insert — the assertion is at line 114. The reported line
  only exists in the PRE-patch source, so that run executed the old bytecode.
- Re-running the same class after `sf project deploy start` (which reported
  `Unchanged`) gives **4/4 pass**, run `707WU00001Ue4lE`. Lesson: when an Apex failure
  quotes a line that is not an assertion in your file, redeploy and re-run before
  calling it a defect.

## Apex run tally (Test-Org, 2026-11-17)
- Tester classes: `SCRUM461TesterSaveTest` (AC2/AC6 save paths, AC9 silence), `SCRUM461TesterFlsGateTest` (positive + negative CRUD/FLS via `System.runAs`).

## Org side effects left by the Tester (read back 2026-11-17)

`SELECT ... FROM Opportunity WHERE StageName='Closed Lost' AND Loss_Reason__c='Wettbewerber'` → 10 records:
9 inside the window (`Lost_Last_12M__c = true`), 1 outside (`TEST-SCRUM-461-OUT`, false).
Closed Lost overall went 16 → 26.

| Side effect | Note |
|---|---|
| `Express Logistics Standby Generator` (sample record, owner Meerwais Osmani) is now Closed Lost + `Wettbewerber` + Nordwind, Amount 80000, price 60000 | my **manual probe** before the spec existed; it did NOT rename the record, so the spec flipped a second one |
| `TEST-SCRUM-461-FOREIGN` (another sample record, owner Meerwais Osmani) | the spec's idempotent AC8 fixture |
| `TEST-SCRUM-461-N1..N4 / A1 / A2 / B1 / OUT` | the spec's own deals (owner devops-agent@cline.test) |
| AC6 test bumps one historical Closed Lost deal's `Amount` by 1 | deliberate: it proves the record still saves |

Expected report numbers derived from that SOQL (not from the report): org overview Nordwind 6 / 490000 / avg gap 14000, Alpha Ventures 2 / 130000 / 5000, Beta Build 1 / 70000 / 10000; the "Meine" report shows 4 / 2 / 1 for the same competitors.

## DEFECT: report average gap counts a blank gap as 0 (measured 2026-11-17)

`/lightning/r/Report/00OWU00000RbBRZ2A3/view` renders Nordwind avg gap **11.666,67 EUR** and Alpha Ventures **2.500,00 EUR**; SOQL says 14.000 (5 of 6 deals known) and 5.000 (1 of 2). 11.666,67 = 70.000/6 and 2.500 = 5.000/2, so the blank `Competitor_Gap__c` is in the divisor and counted as 0. Beta Build (no blank) renders 10.000,00 = correct. Counts, sums and the sort order render correctly. Bug ticket SCRUM-462, linked to SCRUM-461 with "Relates".

## Lightning Lookup value cache (measured 2026-11-17, tmp-probe461q.js / r.js)

A Competitor created through the UI is NOT offered by the deal form's Lookup picker in the same browser session, not even after `page.goto` again (3 polls x 2 s, then 3 more after a reload: only "Add New Competitor" and "Search Show more results for ..."). The same entry IS offered from a fresh browser session ~2 min later. So the picker's value list is cached per session with a TTL; a test that creates an entry and then selects it has to poll for up to ~2 min, and the selection belongs in a separate test (fresh context).

## Apex final tally (run 707WU00001UeODt, 2026-11-17)

`sf apex run test --test-level RunSpecifiedTests --class-names SCRUM461TesterSaveTest SCRUM461TesterFlsGateTest SCRUM461CompetitorLossTest SCRUM461CompetitorFlsTest -r human` -> Outcome Passed, Tests Ran 19, Pass Rate 100 %.

## runAs rewrite of SCRUM461TesterSaveTest (measured 2026-11-17, second round)

The CI FLS gate (`scripts/fls-gate.py --base origin/master --org Test-Org`) flagged
`SCRUM461TesterSaveTest.cls` for reading `Competitor_Gap__c`, `Competitor_Lost_To__c`,
`Competitor_Price__c`, `Lost_Last_12M__c` as the executing user without `System.runAs(`.
After the rewrite the gate prints "FLS-Gate grün." with all five fields `ok (SCRUM461_Competitor_Lost)`.

Two measured traps on that path:

- Deploying a changed test class needs `--metadata "ApexClass:<Name>"`; `--component-class`
  and `--no-prompt` do not exist in CLI 2.150.6 ("Nonexistent flags").
- A synthetic `System.runAs` user that only holds the two SCRUM-461 PSs cannot save an
  Opportunity at all: the org's AfterUpdate trigger `OpportunityFollowupMonitorTrigger`
  runs in user mode and dies with `No such column 'Followup_Required__c'`. The user has
  to hold `SCRUM459_FollowupMonitoring_Read` + `SCRUM459_FollowupMonitoring_Write` too —
  the same four PSs a real account manager holds. Apex after that: 19/19 Passed, run 707WU00001UezVW.

## Coverage recount (2026-11-17, `sf data query --json --use-tooling-api`, scratch/recount461.py)

Opportunities total 139, Closed Lost 27, Closed Lost + `Wettbewerber` 11, of those 11 with a
competitor, 8 with a price, 10 inside the rolling twelve months; 10 records named
`TEST-SCRUM-461-*`. `Competitor__c` = Alpha Ventures, Beta Build, Gamma Build, Nordwind Solutions.

Expected rows derived from that SOQL, org overview: Nordwind 6 / 490000 / avg 14000 (price known on 5 of 6),
Alpha Ventures 2 / 130000 / 5000 (1 of 2), Beta Build 1 / 70000 / 10000 (1 of 1),
Gamma Build 1 / 45000 / NO average (0 of 1 — the SCRUM-462 falsifier for "never zero").
The "Meine" report (owner devops-agent@cline.test): Nordwind 4 / 330000 / 10000, Alpha 2, Beta 1, Gamma 1.
