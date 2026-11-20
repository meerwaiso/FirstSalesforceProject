# SCRUM-464 — Notizen (hard-won findings, one line each)

Survey base: `git fetch origin`; origin/master @ `3eb2ac1`; live org read via `sf ... --target-org Test-Org` on 2026-11-20.

- Cause concept already on Case: `Ursache__c` Picklist, deployed **5/5** values, `restrictedPicklist=false` — `sf sobject describe --sobject Case --target-org Test-Org` (picklistValues read from the describe JSON).
- Active rule `Ursache_PflichtBeiGeschlossen` refuses closed + empty cause — `git show origin/master:force-app/main/default/objects/Case/validationRules/Ursache_PflichtBeiGeschlossen.validationRule-meta.xml`. NOTE: file name has TWO 's' (Geschlossen); the design notizen wrote it with one — `ls objects/Case/validationRules/` was the answer.
- SCRUM-461/462 is the sibling for list+role-gate+overview: `Competitor__c` object, Lookup, Currency 18/2, `*_Price_Known__c` 0/1 denominator, rule with `errorDisplayField`, guard `CompetitorNameGuard`, PS pair `_List_Read`/`_List_Teamleitung`, report pair scope organization/user — `git ls-tree -r origin/master`.
- No name collision: custom objects matching fabrik/manuf = none; Case 82 fields, none matching drittp/fabrik/fixkosten/last_12 — `sf sobject list` + `sf sobject describe`.
- Test-Org baseline 2026-11-20: Cases 675 · closed 46 · closed with cause 4 · third-party 0 · manufacturer records 0 — `sf data query --query "SELECT COUNT() FROM Case WHERE IsClosed = true"`. NOTE: `--use-tooling-api` + `COUNT() FROM Case` → "sObject type 'Case' is not supported"; without the flag it works.
- `PermissionSetAssignment` columns: `Assignee.Username` works, `Assignee.Profile.Name` does NOT ("No such relation 'Profile'") — measured live.
- Existing service PSs are assigned to exactly 2 users: `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com` (SCRUM434_Ursache, SCRUM428_ServiceTeam, SCRUM428_Teamleitung, SCRUM461_Competitor_List_*) — SOQL above.
- Schema facts from `/usr/lib/node_modules/@salesforce/cli/node_modules/@salesforce/types/lib/metadata.d.ts`:
  - `PermissionSetFieldPermissions = {editable, field, readable?}` (line 10262) → FLS has NO set-vs-clear distinction.
  - `ReportGrouping = {aggregateType?, dateGranularity?, field, sortByName?, sortOrder, sortType?}` (line 11286) → ONE sort key only.
  - `UserDateInterval` (line 586) has no rolling last-12-months value → formula gate + `INTERVAL_CUSTOM`.
- `analytics/reportTypes/CaseList` (reduced beta endpoint) lists only 7 detail columns + RowCount — custom fields are NOT listed there, yet deployed reports group/filter on them; the report-token oracle is deploy-validate, not that endpoint (house SCRUM-432/434).
- Case record page = legacy layout `layouts/Case-Case Layout.layout-meta.xml` blob `5394823d913cb3de0f46d93bebeeb6cdce37c02`; already has a `Rückschau` section with `Ursache__c`.
- Repo's Apex never inspects permissions (all role logic = Permission Sets) — `git grep -iE "PermissionSetApi|checkPermission|PermissionCheck"` over classes hits only test classes creating `PermissionSetAssignment`. So a runtime "does this user hold PS X" guard is NEW code, not reuse.

## Developer-phase findings (2026-11-20, measured by me)

- **`Case` is NOT a report type** — `GET /analytics/reportTypes/Case` → `BAD_REQUEST: Case is not a report type`. The Case family has only `CaseList`, `CaseHistory`, `CaseContactRole`, `CaseAsset`, `CaseEmail`, `CaseSolution`, `CaseMilestone`, `CaseActivity`. All six deployed Service reports of this house use `<reportType>CaseList</reportType>` → use CaseList, the design's `Case` was the wrong guess (its open point assumed the other fallback direction).
- `analytics/reportTypes/CaseList` `reportMetadata.aggregates` = `["RowCount"]` only (the Opportunity report of SCRUM-461 had more). So whether `<aggregateTypes>Sum</aggregateTypes>` on `Case.Drittparty_Fixkosten__c` and the FORMULA1 aggregate deploy is a deploy-validate question, answered by the deploy report, not by this endpoint.
- Report filter tokens that this house already deploys: `CLOSED` = 1, `CLOSED_DATE` as `dateColumn`, custom Case fields written `Case.X__c` in `<column>` and in `<field>` of `groupingsDown` — copied verbatim from `reports/Service/Faelle_Nach_Ursache.report-meta.xml`.
- Guard duplicate check: the house `CompetitorNameGuard` puts `existing.Name` (DB casing) into the Set and compares `taken.contains(name)` — Apex String comparison is case-SENSITIVE, so `"SIEMENS"` vs `"Siemens"` would NOT be refused there. AC5 says the drift must be closed → my `FabrikantNameGuard` stores/compares `toLowerCase()` (SOQL `WHERE Name IN :names` is case-insensitive, so the lookup already finds the record). Measured by the `duplicateManufacturer_refused_anyCasing` test, not assumed.
- Test-local PS needed for Case fixtures under `System.runAs`: `SCRUM451_TestObjectAccess` (object CRUD on Case/Account — a Standard User in this org has none, house finding in that PS file) + the PSs that own the OTHER Case fields a closer writes: `SCRUM434_Ursache` (read+edit on `Ursache__c`), `SCRUM442_Satisfaction_Write` (read+edit on `Customer_Satisfaction__c`) — verified via `FieldPermissions WHERE SobjectType='Case' AND Field='Case.X'`: those are the only rows, `IsOwnedByProfile=false`.
- `sf project deploy start --test-level` accepts `NoTestRun` (its --help); `sf project deploy validate` does NOT (only the four test-running levels) — memory fact, re-read in --help 2026-11-20.
- `Field.getDescribe().isEditable()` does NOT compile ("Method does not exist or incorrect signature: void isEditable() from the type Schema.DescribeFieldResult") — probed with `scripts/apex-probe.sh` on `Case.Dedupliziert__c`. Read gate = `isAccessible()`; the write gate is proven by the refused DML, not by a flag.
- `ClosedDate` is system-written: an Apex test that closes a Case always closes it TODAY, so the "closed more than 12 months ago" half of `Closed_Last_12M__c` cannot be built in a test — measure it on the org's 46 historical closed cases instead (SOQL below).
- Test method order must not matter: Apex rolls back per test method, so never assert a cross-method record total; assert a lower bound and count what THIS method created.

## Deploy-phase measurements (2026-11-20, each from the deploy report or an org read)

- `ClosedDate` is a **DateTime**, `CloseDate` (house Opportunity) is a Date: the gate formula `ClosedDate >= ADDMONTHS(TODAY(),-12)` fails with `Incorrect parameter type for operator '>='. Expected Date/Time, received Date (3:13)` → `DATEVALUE(ClosedDate) >= ADDMONTHS(TODAY(), -12)` deploys.
- `<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>` on the 0/1 denominator is WRONG: BlankAsZero turns a blank Currency into 0, so `ISBLANK(...)` reads false and the flag came out 1 for an unknown cost (test: Expected 0, Actual 1). The house file omits the element — omit it.
- Description limits at 255 chars hit THREE artifact kinds: ValidationRule ("cannot be longer than 255 characters"), PermissionSet ("data value too large"), Report ("Value too long for field: Description maximum length is:255") — and a Report file has TWO descriptions (column-level + report-level); replacing only the first still fails.
- `User.Alias` max length 8 (`STRING_TOO_LONG, Alias: data value too large: fls464lead (max length=8)`).
- A fixture User must be `insert`ed before its `PermissionSetAssignment` is created, else `INVALID_CROSS_REFERENCE_KEY, Invalid assignee ID: {0}`.
- `SCRUM451_TestObjectAccess` carries objectPermissions for Account and Case only — a created User holding it reads **0 rows** for a Contact (no error, empty list). SCRUM-464 fixtures need Contact CRUD, so a SCRUM464_TestObjectAccess was added (Account/Case/Contact, test-local, never a released PS).
- Report retrieve token must be FOLDER-qualified: `--metadata "Report:Service/Faelle_Drittparty_Fabrikante"` works; `"Report:Faelle_Drittparty_Fabrikante"` → "Entity of type 'Report' named ... cannot be found". `--output-dir` must be INSIDE the project root (dot-prefixed dirs outside? a path outside the project → OutputDirOutsideProjectError).
- Org normalised the deployed reports: added `<dateGranularity>Day</dateGranularity>` in the grouping and `<params>units=m</params><params>co=1</params>`; the repo files are now the retrieved ones (ADR-7), diff is otherwise identical.
- Stored (read back from the org, not assumed): `reportType=CaseList`, `scope=organization` / `scope=user`, `dateColumn=CLOSED_DATE`, `interval=INTERVAL_CUSTOM` 2000-01-01..2099-12-31, down grouping `Case.Drittparty_Fabrikant__c` `aggregateType=RowCount` `sortByName=RowCount` `sortOrder=Desc`, filter `CLOSED equals 1` + `Case.Ursache__c equals DrittpartyProdukt` + `Case.Closed_Last_12M__c equals 1`, aggregate FORMULA1 as sent. So AC8's "most cases first" IS enforced by the report (single sort key = RowCount desc; tie-break stays unenforced).
- `PermissionSetAssignment` is NOT queryable with `PermissionSetName`/`Assignee.Username` in the Tooling API; query `SELECT Id FROM PermissionSet WHERE Name='<PS>'` (standard API) first, then `SELECT AssigneeId, Assignee.Username FROM PermissionSetAssignment WHERE PermissionSetId='<id>'` (standard API). Measured: house PSs SCRUM428_Teamleitung, SCRUM461_Competitor_List_Teamleitung, SCRUM434_Ursache are each held by exactly 2 users: `devops-agent@cline.test` and `meerwais.osmani@resourceful-bear-6f1u4j.com`.
- Assigned all three released SCRUM464 PSs to BOTH users (`sf org assign permset -n <PS> -b <user> -o Test-Org`); fls-check.sh then reads: existence yes Lookup(Fabrikant), granted by SCRUM464_Drittparty_Team read/edit true, 2 users assigned.
- Real-session read-back after the assignment (`sf data query -o Test-Org`): two created closed third-party Cases for Siemens read `ClosedDate=2026-11-20T15:10`, `Closed_Last_12M__c=true`, `Drittparty_Fabrikant__c=a07WU00001VNfeUYAT`, cost `1450` with `Drittparty_Fixkosten_Known__c=1` and blank cost with `Known=0`.
- Org data now for the Tester: Fabrikant__c "Siemens" (a07WU00001VNfeUYAT) + 2 closed third-party Cases (500WU000031aaiqYAA cost 1450 known, 500WU000031bSZaYAM cost unknown) → the report row must read Siemens: 2 cases, Sum 1450.00, average 1450.00 (average over known costs only — 725.00 would prove the denominator is ignored).

## Round 2 (rework after the Architect rejection, 2026-11-20)

- **SCRUM-434 pin re-anchored (the drift gate was red on head 894503f).**
  `SCRUM434UrsacheTest.test_AC1_Picklist_ExaktFuenfWerte` pinned `assertEquals(5, size())`
  plus the exact five-label set. Reproduced on the org, not inferred: `sf apex run test
  -o Test-Org -l RunSpecifiedTests -n SCRUM434UrsacheTest` → "AC1: genau 5 Picklist-Werte
  erwartet, gefunden: 6", Outcome Failed, Tests Ran 6 / Pass Rate 83%.
  Replaced by `test_AC1_Picklist_POLabelsIntact`: the 5 PO labels must still exist, at
  most ONE value beyond them, that value must be exactly `Drittparty / Fremdfabrik Produkt`,
  and PO-labels + foreign must equal the size. After deploying the class: 6/6 Passed in
  Test-Org (6 values); it also holds with 5 values (Prod-Org, not released yet — 0 foreign).
  Only this one class pins the cause picklist (git grep getPicklistValues: every other hit
  is another object's field).
- `sf apex run test` runs the ORG's deployed copy and is async by default (prints a TestRunId;
  use `--synchronous` or `sf apex get test -i <id>`). A changed test class must be deployed
  before the re-run can show the new code.
- `AggregateResult` is not a usable type in an anonymous `sf apex run` script
  (`List<AggregateResult>` → "Unexpected token '<'", `AggregateResult x` → "Unexpected token");
  it compiles only inside a class. SOQL also accepts ONE aggregate per query
  (`SELECT COUNT(), SUM(x)` → "unexpected token ','"). Measurement route: `sf data query`, one query per aggregate.
- Closed-case fixtures also carry the SCRUM-442 rule: creating a closed Case without
  `Customer_Satisfaction__c` is refused ("Bitte wählen eine Kundansatisfaction (1–5) …").
- **AC7 measured for an all-unknown manufacturer (the gap the Architect named).**
  Added org data: `Fabrikant__c` "Miele" = `a07WU00001VNl6AYAT` (it already existed — the
  guard refused a second one: `"Miele" is already on the list`), plus 2 closed third-party
  Cases for it, both with blank cost: `500WU000031cANeYAM` "464 Org Miele washing machine",
  `500WU000031c0XyYAI` "464 Org Miele dryer". Measured with SOQL aggregates:
  COUNT() = 2 · `SUM(Drittparty_Fixkosten__c)` = **null** · `SUM(Drittparty_Fixkosten_Known__c)` = 0
  → the FORMULA1 average hits its NULL branch. So the Miele row shows 2 cases and TWO EMPTY
  cost cells; a zero is not what the platform feeds those cells.
  Siemens (unchanged): COUNT 2, SUM 1450, KNOWN 1 → average 1450.00, not 725.00.
  NOT verifiable from the CLI: the rendered cell. `GET /services/data/v62.0/reports` → NOT_FOUND
  (no report-instance API at v62), and a Currency aggregate column cannot carry the literal
  text "cost not known" — that wording would need a Text column of its own (PO decision).
- CI on the new head `eea690e`: all four jobs SUCCESS — Lint & Format, README aus Release Notes,
  Metadata/Apex/Session Smoke, Prod-Org Drift Gate (run 44766274613, conclusion success).
