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

## AC9/AC10 layout + profile read-back 2026-11-24 (org Test-Org, `sf data query` standard API)

- `SELECT Id, Name FROM Layout WHERE Name LIKE 'Account%'` -> 4 layouts: Account (Marketing) Layout,
  Account (Sales) Layout, Account (Support) Layout, Account Layout. Org-retrieved metadata
  (`sf project retrieve start --metadata "Layout:Account-…" -o Test-Org -r …`): Company_Size\_\_c hits
  = 1 in `Account Layout`, 0 in each of the three branded layouts.
- `SELECT Id, Username, Alias, ProfileId FROM User` -> 8 users. The two Permission-Set assignees
  (`meerwais.osmani@resourceful-bear-6f1u4j.com`, `devops-agent@cline.test`) both carry
  ProfileId 00eWU00000NzbYTYAZ = **System Administrator**. No user in Test-Org carries
  `Custom: Sales Profile` (00eWU00000NzbZ7YAJ) / Support / Marketing (the 41 profiles exist, unused).
  So the "visible to every sales + service user" leg has ZERO exercisable users in Test-Org -> the
  row is NOT COVERED (0 records), not PASS. The branded layouts are the risk: 0 hits means a user
  whose profile opens one of them never sees the band.
- UI API for profile->layout assignment is dead on this org: `/services/abi/layoutAssignments/<pid>/-1`
  and `/tour/layoutAssignments/<pid>/-1` both -> "URL No Longer Exists" (classic ABI removed in Lightning).
- `SELECT … FROM User` works on the STANDARD api only (tooling API -> INVALID_TYPE), same trap as Account.
- Playwright BDD has no `toBeOneOf`; and `locator.evaluateAll((es) => es.map(e => e.inner()))`
  throws "e.inner is not a function" — ariaSnapshot() is the working aria read (probes 476h/476n).
- Spec fixes landed this round (commits on feature/SCRUM-476-company-size): feed windows split per
  conversion; `seen` labels via ariaSnapshot; toBeLessThanOrEqual(1) instead of toBeOneOf; attach via
  the search-results record LINK (fill+submit alone created a SECOND customer, probe476j R2 measured).

## Resume 2026-11-25 (session resumed after an interruption)

- g7 (full suite, new picker helper) was **killed mid-run** by the interruption: log `run-476-e2e-g7.log` reached only 2/11 tests -> no verdict taken from it.
- org fixture sweep before reseeding: Lead leftovers 12, Account leftovers 5 deleted; re-query 0/0 twice (delete-result JSON parse printed 0 because my success detection was wrong; the re-query proof is what counts).
- Apex run evidence (measured 2026-11-25, Tooling API `ApexTestRunResult WHERE CreatedDate > 2026-11-20`): newest run **05mWU000002dQ9ZYAU @2026-11-24T15:00:06Z, Status Completed, MethodsEnqueued 16, MethodsFailed 0**. 16 = the two SCRUM-476 classes on the branch: `SCRUM476CompanySizeTest.cls` (13 methods) + `SCRUM476CompanySizeFlsTest.cls` (3: withoutPS invisible+unwritable / readPS visible-not-writable / bothPS editable) -> `@isTest` line counts 14 and 4 incl. the class-level marker.
- ApexTestResult field names: `MethodFullName`/`MethodNumber`/`MethodParameterInfo` are NOT columns; use `sf api request rest "/query/?name=ApexTestResult" -o Test-Org -X GET` for the field list (needs `-o`, `-X GET`).
- `ApexTestPackage` refuses `Namespace` as a WHERE column (INVALID_TYPE line) — namespace filtering must be client-side.
- g8 = full 11-test run with the idempotent picker helper (started 15:18, log run-476-e2e-g8.log), AC9 block added afterwards (commit 90ca34b) -> covered by g9 targeted run, never concurrent with g8 (shared TEST-SCRUM-476 fixture names).

## g8 measured failures + spec fixes (2026-11-25 15:2x-15:36)

- g8 (idempotent-picker version, killed at 15:32 during the session interruption) had THREE red tests; all three measured from their error-context.md:
  1. AC1/AC3 (`spec.ts:403`) — `combobox "Converted Status"` count **0** while the `Convert Lead` heading was already visible => the form paints its pickers AFTER the heading. Fix: poll statusCombo 10x2 s; also the old `if (convOpt.count()==1)` had no failing branch -> now polled + `expect(...).toBe(1)`.
  2. AC10/AC11 (`spec.ts:609`) — precondition `BANDS).toContain(orgBand)` got **null**: ONE file-level `test.beforeAll` (verified: 1 beforeAll / 1 afterAll in the file) => all 11 tests share ONE seed, so AC8's clear left C-HAND empty for the later block. Memory rule (c) ("each describe has its own beforeAll seed") is WRONG for a file-level beforeAll — correct it. Fix: measure AC10 on C-EXIST-SIZED (no block clears it).
  3. AC13 (`spec.ts:664`) — aria showed `combobox "Company Size": 51 to 250 employees` and NO Edit button, NO listbox (SELECTION state left by an earlier picker). Third route added to openBandPicker: no listbox + no button + combobox present -> click the combobox, poll for the listbox.
- org fixture sweep after the kill: 12 Lead leftovers deleted (rc 0 each), re-query 0 twice; Account 0/0.
- g9 = full 11-test suite on spec head 32408d7 (fixes above), started 15:36.

## g9 + probe476p (2026-11-25 15:37-16:0x)

- g9 = 12 tests on head 32408d7: EVERY conversion test failed at the same new assertion `the Converted Status picker never offers "Converted"` (5+ identical errors, 0 OBSERVED lines) -> my polled `option "Converted"` was a phantom locator.
- probe476p (measured 2026-11-25, form aria): `dialog "Convert Lead"`, `heading "Convert Lead" [level=1]`, `text: "*Converted Status"`, `combobox "Converted Status": Closed - Converted`, `button "Convert"`, `button "Cancel"`, `button "Cancel and close"`, `textbox "Account Name *"`, `combobox "Account Search"`, section buttons `Account`/`Contact`/`Opportunity`. `getByRole listbox/option name~Converted Status -> 0`, `any option count -> 0`. => NO listbox/option children until the picker is expanded; do NOT click it (probe476k: fill+submit converts on the default). Fixed in head 1f9f9ba: assert the combobox + an aria line containing "Converted Status"; conversion proven by org read-back.
- `sf data create record --json` -> `result.id` (NOT `result.recordOutput.records[0].Id`).
- sweep before g10: see counts below.

## g10 (full 12, head 1f9f9ba, 15:5x-16:1x): 9 passed / 3 failed (16.1 m)

9 OBSERVED lines captured — AC1/AC3/AC12 (lead more_than_250 -> customer more_than_250, page renders it 1 row under Account Name), AC2 (null + page renders no band), AC4 (51_to_250 kept, delta 0), AC5 (null -> more_than_250 same record), AC6 (stays null), AC10/AC11 (**272 customers, 0 real customers outside the run carry a band**, 4 fixture customers, page renders "51 to 250 employees" 1 row under the name), AC12 (deltas equal feed 3/email 0/task 0/contact 1/opp 1/case 0; Account 1 vs 0 across the two paths), AC13 (old lead 51_to_250 unchanged, ConvertedAccountId set, **UI offered 0 Edit controls on the converted lead** -> platform refused the edit, customer stayed 51_to_250), batch (3 conversions -> 3 own bands, Account delta 3).
3 failed = AC7, AC8, AC9, all at spec line 300: `TypeError: expect(...).isNotEqualTo is not a function` — not a platform issue, a Playwright BDD API mistake. Fixed in head 9714222 (`expect(route === 'none', ...).toBe(false)`); g11 targeted -g "AC7/AC8|AC9" to confirm.

- Org sweep before g11: 0/0 leftovers, re-query 0 twice.

## g11/g12 (2026-11-25 16:0x-16:4x) + two real test bugs found by measurement

- g11 targeted AC7/AC8 + AC9: 2 passed, 1 failed — AC9 red only because C-HAND had been rewritten by AC7/AC8 (one FILE-level seed). Re-anchored AC9 to C-EXIST-SIZED (51_to_250) -> head 6dbe692.
- g12 full (head 6dbe692): 10 passed / 2 failed (14.6 m). 10 OBSERVED lines captured; new org counts: **275 customers, 0 real customers outside the run carry Company_Size\_\_c** (backfill invariant held), 7 fixture customers.
  - AC12 red at spec:331 `"Convert" action button not on the lead page` (count 0 after openLead) — flaky paint, every other block found it. Fixed: poll 10x2 s before the assertion (head a512f16).
  - AC9 red at spec:753 `locator.fill: Element is not an <input>, <textarea> or [contenteditable]` — the aria (g12 error-context) shows the picker is `<button role=combobox aria-haspopup=listbox data-value="51 to 250 employees">`. fill() is refused on a button. Fixed: read `data-value` baseline + `locator.type(bogus, {delay:90})` (keyboard), then re-read the offered options.
- Push to GitHub hiccuped once (remote rejected: Internal Server Error, Request ID 3EDF:23746:...); retried after 20 s -> `6dbe692..a512f16` landed. Remote branch head read back: a512f16.
- CI measured: run 45639461938 on head **32408d7** = 4/4 pass (Lint 42 s, Smoke 5m58s, Drift Gate 14m4s, README 5 s). Runs on 9714222/a512f16 not yet listed -> DevOps must read CI on the FINAL head; both are test-artifact-only commits.
- Apex evidence unchanged: run 05mWU000002dQ9ZYAU (2026-11-24T15:00:06Z) Completed, 16 enqueued / 0 failed (13 + 3 FLS methods: withoutPS invisible+unwritable, readPS visible-not-writable, bothPS editable).
- g13 = full suite on head a512f16 (the final spec head) — the verdict run.

## g14 (full, head ddaf133, 17:0x-17:2x): 11 passed / 1 failed (16.0 m)

- AC12 green after the de-shared fixture; new OBSERVED line: sized create-new vs band-less attach — feed 3/email 0/task 0/contact 1/opp 1/case 0 equal both ways, Account 1 vs 0.
- AC13 red at `tests/e2e/record-page.ts:118` `expect(getByRole('button',{name:'Save & New'})).toBeVisible(5000)` — the shared helper's 5 s poll missed the edit-mode save bar (it paints late; g13 had no edit control at all, so the branch never ran). Fixed in head ca75366: AC13 polls the save control 8x2.5 s, records `saveOffered` in OBSERVED, and the criterion (customer band unchanged) is asserted after BOTH outcomes.
- probe476q (measured 2026-11-25 17:3x): the form submit is NOT always a second `button "Convert"` — with only 1 Convert button found, my probe never converted (IsConverted=false, ConvertedAccountId null), so probe476q cannot prove the converted-lead edit state; the spec's own convertLeadForm (heading-box + below-heading candidate) is the working route. SOQL trap: `WHERE Id=00Q...` -> MALFORMED_QUERY "unexpected token"; query by `LastName = '...'` instead. Probe leftovers TEST-476Q-L/CUST cleaned by name before re-run.
- g15 = final full-suite verdict run on head ca75366.
