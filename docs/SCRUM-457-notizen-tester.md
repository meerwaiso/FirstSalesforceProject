# SCRUM-457 — Tester notizen

Meister die Org 2026-10-31 (Tester). Every value below was read back by a command,
not copied from another agent's report.

## Org / Instance
- Instance `resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com`
  (Lightning `.lightning.force.com`, Setup `.my.salesforce-setup.com`).
- CLI target org = `Test-Org` (alias, capital T), user `devops-agent@cline.test`.

## Sharing model (OWD) — measured, not exposed by any API
Route that works in an automated browser: classic page
`GET https://<instance>/p/own/OrgSharingDetail?setupid=SecuritySharing` (plain HTML).
The Lightning equivalents (`/lightning/setup/SecurityHub/...`, ObjectManager) render
only the nav shell — srcdoc iframe never fills. Verified 2026-10-31.
- Account: Public Read/Write (external Private)
- Opportunity: Public Read/Write
- Case: Public Read/Write/Transfer
=> a `viewAllRecords` Permission Set grants nothing OWD does not already grant and
can never revoke. AC5 ("once the absence is over the deputy loses the extra access")
is a FINDING, not a test — never a PASS row.

## Fixtures in Test-Org (live, 2026-10-31)
- `Absence__c` ABSENCE-0001 `a04WU00000E0qWPYAZ`: Meerwais Osmani (005WU000017tBhRYAU),
  2026-10-31..2026-11-20, deputy devops-agent (005WU000017tEKLYA2).
- `Absence__c` ABSENCE-0002 `a04WU00000E0r97YAB`: Automated Process (005WU000017tBpWYAU),
  2026-11-02..2026-11-12, **no deputy**.
- 13 of 197 Accounts carry `Absence_In_Window__c = 'YES'`; exactly **1** carries
  `Absence_Ohne_Deputy__c = 'OHNE DEPUTY'` = `Sample Account for Entitlements`
  `001WU0000242xNSYAY` (owner Automated Process). 184 customers carry nothing.
- All 13 rows still carry one `OwnerId` (AC7).
- Customer used for the UI tests: `Burlington Textiles Corp of America`
  `001WU0000242xNHYAY` (1 Opportunity, 2 Cases). `Edge Communications`
  `001WU0000242xNGYAY` has 12 Opportunities / 3 Cases.

## Report
- `Fehlzeiten_nach_Kunde` = `00OWU00000RH0qT2AT`, ReportType `AccountList`,
  resolved by Name via `SELECT Id, Name FROM Report WHERE Name = ...` (plain
  `data query`, NOT `--use-tooling-api` — `Report` is not a Tooling sObject).
- Renders in the cross-doc frame `lightningReportApp`; frame states
  `Total Records N`; data rows are `table tbody tr`.

## Apex run (Tester's own measurement, 2026-10-31)
`sf apex run test --test-level RunSpecifiedTests --tests SCRUM457AbsenceSyncTest`
→ 11/11 Pass, Test Run Id `707WU00001R3GZr`.

## DOM facts (probe 2026-10-31)
- Account layout section `Fehlzeit` (`detailHeading: true`) holds exactly ONE field:
  `Absence_Anzeige__c`, label **Absence**. Outside an absence the label renders, the
  value is empty.
- Field VALUES live in closed shadow roots → `ariaSnapshot()` of body is the only
  fast read; `querySelectorAll` sees labels but empty values.
- **The `Absence__c` record page renders ONLY `Lauf-Nr.`, `Owner`, `Created By`,
  `Last Modified By`** — on `/view` AND on `/edit`. Probe 2026-10-31: AXTree of the
  edit form = 369 nodes, zero hits for the detail fields; `records-record-layout-item`
  elements carry `field-label` only for those four. `Layout:Absence__c.*` cannot be
  retrieved from the org ("Entity of type Layout ... cannot be found") and the repo
  has no layout file for it. => there is NO UI entry point for recording/changing an
  absence; every house custom object in the repo HAS a layout file, Absence__c does
  not. FINDING for the Developer, not a locator problem.
- `Absence_Anzeige__c` renders verbatim: `Abwesent 2026-10-31 bis 2026-11-20 - Deputy: devops-agent`.

## Report cache + fixture drift (2026-10-31, second run)
- The report frame said **Total Records 9** while SOQL said 13 — mid-run, because an
  earlier test had left `ABSENCE-0001.End__c = 2026-12-05` and the throwaway record
  still in the org. With the fixtures restored the frame renders **13 rows** and they
  match the 13 SOQL rows one-for-one, incl. `Sample Account for Entitlements |
  Automated Process | 02.11.2026 | 12.11.2026 | - | OHNE DEPUTY`. Report results are
  cached: measure the report only from a restored fixture state.
- Every test that mutates `End__c` must restore it, otherwise the next test's fixture
  precondition fails and the run looks red for the wrong reason.
- A **new** absence for a colleague who owns many customers (devops-agent, 184) is
  the wrong cancel fixture: it mirrors onto all 184 and every later test then reads a
  polluted window (AC8 saw 185 rows / a cached 145). The cancel cycle runs ON the
  deputy-less fixture ABSENCE-0002: delete it, assert the marker + window drop, re-record
  it byte-identical, assert they come back. `Absence__c.Name` is AutoNumber, so the
  restored record has a new name — the PO measures the ROWS, and 13/1 still holds.
- For a deputy-less absence the mirror writes `Absence_Ohne_Deputy__c = 'OHNE DEPUTY'`
  and leaves `Absence_Anzeige__c` EMPTY — the marker is the whole display there.

## Playwright / SOQL quirks hit while fixing this spec
- This Playwright release has **no `notToContain` and no `notToBe`** on `expect`
  (`TypeError: not a function`). Use `mustNotContain(text, needle, why)`
  (= `expect(text.includes(n), why).toBe(false)`) and explicit `!==` comparisons.
- SOQL **Date literals are unquoted**: `WHERE Start__c = 2026-11-05`. The quoted
  form is a syntax error and surfaces as `Command failed` from `execSync` — it looks
  like a platform fault, it is not.
- `sf data create/update record --values` takes SPACE-separated pairs, not commas.
- `Post` is NOT SOQL-queryable (`INVALID_TYPE`); `Task`, `EmailMessage`, `FeedItem` are.
- `SELECT ... FROM Opportunity WHERE Status = ...` → "No such column 'Status'";
  Opportunity uses `StageName`.
- `Absence__c.Name` is AutoNumber → a recreated fixture gets a new name, so the
  cancel is exercised on a throwaway record resolved by its dates, never on the
  two fixtures the PO measures.
