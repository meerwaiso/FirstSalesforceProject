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
