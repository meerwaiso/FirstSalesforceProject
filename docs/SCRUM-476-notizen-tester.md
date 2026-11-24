# SCRUM-476 — Tester notizen

Alle Befunde measured in Test-Org (`sf ... --target-org devops-agent@cline.test`) am 24.11.2026, not recalled.

## Org baselines (before any fixture)

- `SELECT COUNT() FROM Account` = 268, `Lead` = 66, `Contact` = 680, `Opportunity` = 157, `Case` = 681, `FeedItem` = 900, `EmailMessage` = **0**, `Task` = **0**
- `Account WHERE Company_Size__c != null` = **0** (go-live baseline, AC11)
- `Lead WHERE Company_Size__c != null` = 0; `Lead WHERE IsConverted = true` = 1
- `Account WHERE Name` shared: 268 Accounts / 106 distinct Names / 19 Name-groups with duplicates (worst 35)

## Feld-Metadata (measured)

- `Account.Company_Size__c` exists, Picklist; values `up_to_10 / 11_to_50 / 51_to_250 / more_than_250`, labels `up to 10 employees … more than 250 employees`
- granted by `SCRUM476_CompanySize_Read` (read) + `SCRUM476_CompanySize_Set` (read+edit), **2 users each** (`devops-agent@cline.test`, `meerwais.osmani@…`); third grant `AncCrmIntegrationUser` (read, edit=false) assigned to **nobody** → inert
- `scripts/fls-check.sh Account Company_Size__c devops-agent@cline.test` = the above

## Layout / Visibility

- Only `Account Layout` carries `Company_Size__c` (behavior Edit) in the branch; `Account (Marketing|Sales|Support) Layout` do NOT
- `sf data query --use-tooling-api --query "SELECT Layout.Name, Profile.Name FROM ProfileLayout WHERE TableEnumOrId='Account'"` → 43 rows, **every profile resolves to `Account Layout`** — settles F-3 (the named layouts are not opened by any profile)

## Record page (`/lightning/r/Account/<id>/view`), measured locators

- tabs present, Details tab clicked like house `openRecordDetails`; guidance dialog handled by `dismissGuidance`
- `button "Edit Company Size"` = 1 · `getByText('Company Size',{exact:true})` = 1 · combobox = 0 in view mode
- Details edit-order of the first section: `Edit Account Name`, `Edit Phone`, `Edit Company Size`, `Edit Fax`, `Edit Key Account`, … → adjacency to the name confirmed
- edit mode: combobox "Company Size" = 1 → click → listbox "Company Size" = 1 with **5** `[role=option]`, data-values `'' , up_to_10, 11_to_50, 51_to_250, more_than_250`, labels only in the aria name (identical to the SCRUM-472 Lead pattern)

## Convert-Lead form (`button "Convert"` on the Lead record page), measured

- Lead page: `button "Convert"` = 1 (plus `button "Edit"`, `button "New Case"`)
- after the click the form renders **in place** (URL unchanged): heading `Convert Lead`, `button "Cancel and close"`,
  textbox `Account Name *` (prefilled with the lead's Company), combobox `Account Search` (= the „Choose Existing Account“ picker),
  combobox `Converted Status` with options `Closed - Not Converted` / `Converted`, then `button "Convert"` + `button "Cancel"`
- ⇒ new customer = textbox path; attach to existing customer = `Account Search` combobox path

## Apex / org limits hit by others this ticket

- `CANNOT_UPDATE_CONVERTED_LEAD` on `update` of a converted Lead (AC13 Apex path)
- one `Database.convertLead` over 20 rows dies `LIMIT_EXCEEDED` at row 0; 30 single-record conversions die `Too many SOQL queries: 101` ⇒ a 200-record criterion cannot be green in one Apex transaction
- org test budget: one broad Apex run at a time; CI ran `RunSpecifiedTests SCRUM476CompanySizeFlsTest,SCRUM476CompanySizeTest` → 15/15 (`ApexTestRunResult 05mWU000002dOpJYAU`)

## Trap reminders that bit this ticket before

- `EmailMessage`/`Task` are **empty tables**: a delta assertion on them is `0 == 0` and cannot fail — measure deltas on `FeedItem` (900), `Contact`, `Opportunity`, `Case`
- never assert an org-wide equality on a table the org holds empty (house finding SCRUM-471)

## Shape of the fixture model (measured 2026-11-24, cost one run each)

- `Lead.Company` is TEXT — `sf sobject describe --sobject Lead` → `type: string, length 255, createable`.
  Creating a lead whose Company name matches no Account leaves the `Account` total at 268 and 0 Accounts
  under that name. A lead therefore NEVER references a customer: the relationship is
  `ConvertedAccountId` (reference, `createable: false`) → readable by SOQL, unwritable by CLI/Apex.
- `Company` is REQUIRED on Lead: a lead without it dies `REQUIRED_FIELD_MISSING: [Company]`
  (`sf data create record`, exit 1). Band-less fixture leads still need Company text.
- Consequence for the E2E fixtures: pre-existing customers (AC4/AC5/AC6/AC13) are seeded as Accounts
  and must already exist; customers for the create-new path (AC1/AC2/AC12/batch) must NOT exist before
  the conversion — the conversion creates exactly one and the delta on `Account` is +1.
- Aborted Playwright runs leave their `beforeAll` seeds behind: an aborted run's `afterAll` does not
  always delete. The spec's own sweep at the START of `beforeAll` (delete `TEST-SCRUM-476-E2E*` first)
  is what makes a re-run honest; `sf data query` exits 0 for empty results, so an exit-code check
  never detects the leftovers — count the rows.

## Measured 2026-11-24, second half of the station (all read back from Test-Org)

- `SELECT Id, Name FROM Account WHERE Company_Size__c != null` -> 45 rows: 43 named `TEST-476-*`
  (other agents' fixtures: `TEST-476-LimA/LimB/Limit/Tie`), 2 are this run's (`-C-EXIST-SIZED`,
  `-C-HAND`). `... AND Name NOT LIKE 'TEST%'` -> 0 rows: NO real customer carries a band.
  `Account` total 268 -> 311 (+43 foreign fixture leftovers, not mine to delete).
- `SELECT Id, LastName FROM Lead WHERE Company_Size__c != null` -> 142: 39 of them named literally
  `newSized / keep / attachFill / attachSized / b1 / b2 / b3 / hand / old / newBlank …` — the
  seeding bug where `mkLead` passed the fixture KEY into `-v`. These 44 orphan records (leads +
  their customers) are mine and were deleted with `sf data delete record -s Lead -i <Id>` (44/44
  success, re-query 0 left). 94 `TEST-476*` leads of other agents left untouched.
- Playwright BDD default test timeout is 30 s and a cold Lightning navigation exceeds it
  (`page.goto … Test timeout of 30000ms exceeded` in run-476-e2e-g…/final.log). House pattern
  (SCRUM-445, SCRUM-434): every test carries an explicit `test.setTimeout(…)`. All 11 tests now use 300000.
- The AC11 go-live precondition must ignore foreign fixture namespaces (`TEST-*`), otherwise another
  agent's leftovers turn the baseline red — that is what killed run-476-e2e-final (42 `TEST-476-Limit*`).
- `Company` on Lead is TEXT (string 255, required) and `ConvertedAccountId` is `createable: false`;
  a conversion's customer is named by the Id the picker chose, never by the Company text.

## Measurements 2026-11-24 (round: E2E spec on head 5590c9a, probes 476h..476n)

- Attach path in the Convert-Lead form (probe476k, org read-back): `fill("Account Search", <name>)`
  -> click `option "Search for matching accounts …"` (opens an "Accounts Results" panel) -> click
  `link "<name>"` there -> aria shows `Account Search - Current Selection: <name>` -> press the form's
  own Convert button (the button BELOW the "Convert Lead" heading; the record page carries a second
  one). Result: `IsConverted=true`, `ConvertedAccountId == <existing Account Id>`, accounts named
  = 1 (no second customer), existing band NOT overwritten. Clicking the nested record OPTION instead
  navigates away and converts nothing (measured in probe476i).
- `fill` + submit WITHOUT selecting a record = the create-new path: creates a NEW Account
  (probe476j R2: ConvertedAccountId = the new 001WU…, accounts named = 2).
- Clearing a filled band on the customer (probe476n): `button "Edit Company Size"` = 1 on a painted
  Details tab (also when filled; `Change Company Size` = 0), then `combobox "Company Size"` (exact
  name matches, value shows the current band), click it -> `listbox` with
  `[role=option][data-value=""]` plus the 4 ranges, click the blank slot -> combobox value
  `--None--`, `button "Save"` = 1 -> org `Company_Size__c = null`.
- Picker race: on a fresh record page the body paints AFTER `.slds-global-header`; querying the Edit
  button or the combobox immediately reports 0 (probe476m). Poll up to ~20 s, then assert count==1.
- FeedItem counts are only comparable per actor: `CreatedById = <session user>`; the global count
  carried another run's posts (6 vs 3 for the same conversion pair). Session user:
  `SELECT Id, Username FROM User` -> devops-agent@cline.test.
- Org dirt of my probes cleaned 2026-11-24: 3 Accounts `PROBE-476M-CUST` deleted (3/3 success),
  re-query `Account WHERE Name LIKE 'PROBE-476%'` -> 0. The Architect read them at 15:2x as
  `COUNT(Account WHERE Company_Size__c != null) = 3`.
- FLS read-back via `scripts/fls-check.sh Account Company_Size__c Test-Org`: grants
  `SCRUM476_CompanySize_Read` (read), `SCRUM476_CompanySize_Set` (read+edit), foreign
  `AncCrmIntegrationUser` (read, no edit, assigned to NOBODY = inert). Both of our PSs: 2 users
  (`devops-agent@cline.test`, `meerwais.osmani@resourceful-bear-6f1u4j.com`), IsActive=true,
  IsRevoked=false (PermissionSetAssignment WHERE PermissionSetId = …).
- Org-retrieved Account layouts (`sf project retrieve start --metadata "Layout:Account-…" -o Test-Org
-r …`): `Account Layout` contains Company_Size\_\_c; `Account (Marketing)/(Sales)/(Support) Layout`
  contain it 0 times. Profile->layout mapping NOT verified: UI API `/tour/layoutAssignments/...`
  returns "URL No Longer Exists" on API v68, and `/lightning/setup/LayoutAssignments/home` ->
  "Page not found". Open question for AC9 (which layouts the sales/service profiles actually open).
- Apex org read-back (`sf data query -t … ApexTestRunResult`): newest run
  `05mWU000002dQ9ZYAU` CreatedDate 2026-11-24T15:00:06Z Status Completed, MethodsEnqueued/Completed
  16/16, MethodsFailed 0; `ApexTestResult WHERE ApexTestRunResultId = that` -> 16 rows, 16 Pass.
  Entity fields: ApexTestRunResult has NO `Name`/`Message`; use Status, MethodsEnqueued/Completed/
  Failed, StartTime, EndTime. ApexTestResult outcome column is `Outcome`, name is `MethodName`.
  PermissionSetAssignment fields: `AssigneeId`, `PermissionSetId` (no AssignedUser/PermissionSetName).

## Run g3 verdict 2026-11-24 (16:43->17:01, 11 tests, 18.1 m) — 8 passed / 3 failed

- AC1/AC3 failed at the AC12 pair-check: `dSized.feed` 6 vs `dBlank.feed` 3. Root cause is the
  SPEC, not the org: `beforeSized` window ran up to a `snap()` taken AFTER the second conversion,
  so the sized window contained both conversions' record chatter. Fix: one window per conversion
  (dSized computed before the band-less conversion starts). Commit: "split the feed windows per
  conversion".
- AC7/AC8 (clearing) failed in `openBandPicker`: `button "Edit Company Size"` count 0 after 10x2 s
  polling — probe476n measured that exact button = 1 on a painted Details tab, so this is state-
  dependent, not a layout fact. The helper now also prints every button matching /Company Size/ in
  the failure message, so the next read names the label Lightning used.
- AC13 failed with `TypeError: expect(...).toBeOneOf is not a function` — Playwright BDD has no
  `toBeOneOf`. Replaced with `toBeLessThanOrEqual(1)` (at most one control) + OBSERVED names which
  outcome happened.
- FeedItem fields (describe --json): Id, ParentId, Type, CreatedById, CreatedDate, Title, Body,
  LinkUrl, RelatedRecordId, HasFeedEntity, CommentCount, LikeCount. NO RootItemId, NO Name.
- CLI parse trap (measured twice): `sf data query -t --target-org Test-Org --query ...` ->
  INVALID_TYPE "sObject type 'Account' is not supported"; the SAME query with `-o Test-Org -q`
  returns rows. Tooling API (`-t`) sees custom objects only — use it for ApexTestRunResult etc.,
  never for Account/Lead counts.
- Org counts with the standard (non-tooling) API, 2026-11-24 17:0x: 272 Accounts total (205 not
  named TEST-_, 67 TEST-_, 2 PROBE-384-AC2 from another ticket), 22 TEST-_ Leads, 0 PROBE-476 records
  left of my probes; Leads carrying Company_Size\_\_c: 9, all 9 named TEST-SCRUM-476-E2E-_ (0 organic);
  Accounts carrying Company_Size\_\_c: 2, both TEST-SCRUM-476-E2E-\* (0 organic); converted Leads with
  a non-null ConvertedAccountId: 1 organic (00QWU00000fbQIT2A2 -> 001WU00002CKIAdYAP).
  So the organic pool for the carry-over is ZERO records: every end-to-end proof needs my fixtures,
  and the coverage rows must say so.
