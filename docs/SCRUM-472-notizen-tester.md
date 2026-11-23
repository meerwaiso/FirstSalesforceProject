# SCRUM-472 — Tester notizen (measured in Test-Org, command beside every fact)

Verified 2026-11-23 (Tester session). Every value below was read back by me, not quoted.

## Org baseline (measured before any fixture was seeded)

| Fact | Value | Command |
|---|---|---|
| default org | `Test-Org` / `resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com`, user `devops-agent@cline.test` | `sf org display --json` |
| `Lead.Company_Size__c` exists | 1 row, `FieldDefinition` | `sf data query --use-tooling-api --query "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Lead' AND QualifiedApiName='Company_Size__c'"` |
| total Leads | 66 | `sf data query --query "SELECT Id FROM Lead" --json` → totalSize |
| Leads carrying a size | 0 (PO expectation) | `SELECT Id, Company_Size__c FROM Lead` — every row null |
| `SCRUM472_CompanySize` assigned to | 2 users: `devops-agent@cline.test`, `meerwais.osmani@resourceful-bear-6f1u4j.com` | `SELECT Id, Assignee.Name, Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name = 'SCRUM472_CompanySize'` (`--use-tooling-api`) |

## Side-effect table sizes (AC8 falsifiability)

| Object | rows | note |
|---|---|---|
| `EmailMessage` | 0 | queryable, guard is 0-vs-0 → NOT falsifiable |
| `Task` | 0 | queryable, guard is 0-vs-0 → NOT falsifiable |
| `FeedItem` | 885 | `FROM Feed` → INVALID_TYPE; `FROM FeedItem` works → the "no chatter post" guard IS falsifiable at 885 |
| `OutboundMessage` | INVALID_TYPE | not reachable from SOQL at all |

## UI measurements (Lead record page, frontdoor storageState, Details tab clicked)

Probe scripts: `scratch/t472/probe472e|f|g.mjs` (git-ignored).

Record page `/lightning/r/Lead/00QWU00000iUSYb2AO/view`, Details tab, view mode:

- aria rows, in DOM order: `- text: Company TEST-Probe-Corp` → `- text: Fax` → `- text: Company Size 11 to 50 employees` → `- text: Email`.
  **The renderer puts `Fax` between Company and Company Size** — the layout XML has
  `Company_Size__c` directly after `Company` (line 26 vs 22) and `Fax` at line 60
  (other layoutColumn). Same Details section, no heading between the two rows.
- `getByText('Company Size', {exact:true})` → 1 · `getByText('11 to 50 employees', {exact:true})` → 1
- `getByText('Company', {exact:true})` → **2** (ambiguous, never use it alone)
- `getByLabel('Company Size')` → 0 in view mode (no `<label for=>`) → use getByText
- `getByRole('button', {name:'Edit Company Size', exact:true})` → 1
- geometry: Company row x=120 y=250, Company Size row x=49 y=617 (viewport 1280, scrollWidth 1280)

Edit mode, after clicking that Edit button:

- `getByRole('combobox', {name:'Company Size', exact:true})` → 1
- `getByRole('listbox', {name:'Company Size', exact:true})` → 1; chained `[role=option]` inside → **exactly 5**, `data-value` = `''`, `up_to_10`, `11_to_50`, `51_to_250`, `more_than_250`
- scoped `[role=option][data-value=""]` inside that listbox → 1 (the `--None--` clearing slot)
- unscoped `[role=option][data-value=""]` → 1 here too, but scope inside the listbox anyway: other picklists (`Salutation`, `Lead Source`, `Industry`, `Product Interest`) also render `option "--None--"`, and `option` `textContent` is empty — the label only exists in the aria name
- `getByRole('textbox', {name:'Company Size', exact:true})` → **0** → no free-text entry point
- other picklists in the same section must never be touched; `No. of Employees` (= standard `Lead.NumberOfEmployees`, `spinbutton`) stays null — never compare it with the band

New-record form `/lightning/o/Lead/new`: textbox `Last Name` → 1, textbox `Company` → 1,
combobox `Company Size` → 1, `button "Save"` exact → 1. UI locale renders German labels
(`Letzter Versuch`, `Doppelt zu`) — our field label stays English: `Company Size`.

## AC5 below the UI — measured by me (second route, not the Developer's)

`sf data create record -s Lead -v "LastName=TEST-SCRUM-472-OOB Company=TEST-OOB Company_Size__c=12_employees"`
→ created `00QWU00000iUStZ2AW`; read-back `Company_Size__c: "12_employees"`, totalSize 1.
**An out-of-band value IS stored below the UI** → AC5 is enforceable in the Lightning UI only.
Cleanup: record deleted (`sf data delete record`), org back to 0 sized leads.

## Layout drift note

`sf project retrieve start --metadata "Layout:Lead-Lead Layout"` rewrites the tracked file with the
org version (3 empty `<layoutColumns/>` + trailing newline added). Diffed, then restored with
`git checkout --` so the branch file stays master + one layoutItem (Prod Drift Gate safe).

## Fixtures

TAG `TEST-SCRUM-472-E2E-<base36>`; seeded/deleted by the spec itself (`beforeAll`/`afterAll`).
Idempotent: a file-level `beforeAll` runs again before every `describe` block, so `afterAll`
deletes and the next block re-seeds — each test asserts its own fixture state.

## Apex verdict (Developer's two classes, run by me)

`sf project deploy start -x manifest/scr472-phase3-apextests.xml -l RunSpecifiedTests -t SCRUM472CompanySizeTest -t SCRUM472CompanySizeFlsTest --target-org Test-Org`
→ `scratch/t472/apex-run.json`: `status: Succeeded`, `numberTestsCompleted: 8`,
`numberTestsTotal: 8`, `numberTestErrors: 0`, Deploy ID `0AfWU00000dL7xh0AC`
(my own run — the Developer's was `0AfWU00000dL5iz0AC`; 8/8 reproduced independently).

## CLI / SOQL quirks measured in this session (each cost a suite run)

| Symptom | Cause | Fix used |
|---|---|---|
| `execSync` threw on the **first** `soql()` call | `sf` exits non-zero when it prints the stderr Warning "update available from 2.150.6 to 2.158.7" | `2>/dev/null \|\| true`; "No JSON in sf answer" stays the failing branch |
| `MALFORMED_QUERY: unexpected token 'LastName NOT LIKE'` / `NOT (…)` | `X != null AND NOT (Y LIKE 'a%')` is refused in a compound WHERE; `NOT (Y LIKE 'a%')` alone works, `X != null AND Y LIKE 'a%'` works | foreign-fixture filter runs in JS on plain queries |
| `Malformed key=value pair for value: ACME.` | `sf data create record -v` splits on whitespace, so `Company=TEST ACME One` breaks into two pairs | fixture values are single tokens (`TEST-ACME-One`) |
| `Lead.Phone` read back masked (`+4911**` → `+4911**`) | the org masks Phone (FLS redaction) | every Phone compare stays API-to-API |
| `unknown option: --whole` | `scripts/e2e-run.sh` takes `--all` / `--one <title>` | `--all` for the whole spec; log in `.e2e-run/logs/` |
| side-effect guards | `FeedItem` 885 rows → the no-chatter guard IS falsifiable; `EmailMessage` and `Task` are **0 rows** → those two guards are 0-vs-0 and NOT falsifiable today | stated as partial in the coverage table |

## Picker open is flaky — measured, and how the spec copes

- `Edit Company Size` click → combobox 1, **listbox 0** (probe472k). The listbox with the 5
  options exists only after clicking that combobox.
- That click is not reliable: AC2/AC5/AC8 opened on the first click, AC4 stayed at 0 for 1m30s.
  `openPicker` therefore clicks until the listbox exists (max 3) and asserts after each attempt —
  same shape as `openDetailsTab` in `tests/e2e/record-page.ts`.
- Playwright `fill()` on the combobox does NOT open the picker (probe472e: options 0).
- Typing into a field that already shows a value **appends** to it (AC3 saw
  `TEST-ACME-Three` + typed text) → AC3 edits `Description`, which its fixture leaves blank.
- `SELECT Id, Id, …` → MALFORMED_QUERY: `READ_COLS` already carries `Id`.
- `expect(array).toHaveCount(n)` is invalid → `toHaveLength(n)`.

## Run mechanics (house)

- `scripts/e2e-run.sh <spec> [--grep <regex>] [--one <title>]` — resolves the org host from the
  CLI, writes `test-results/<spec>--<stamp>/` (HTML + `playwright-results.json`), log `.e2e-run/logs/`.
- `--grep` green is **not** a handoff verdict — run `--all`.
- `test-results/` lives INSIDE the worktree → copy the report out before `git worktree remove`.

