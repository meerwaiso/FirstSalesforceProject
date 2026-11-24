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
