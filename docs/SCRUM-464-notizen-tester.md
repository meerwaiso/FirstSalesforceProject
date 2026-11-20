# SCRUM-464 — Tester notizen (E2E layer, 2026-11-20)

Every fact below was read back by me on 2026-11-20; command named where it is not obvious.

## Org data (measured, Developer's fixtures — leave them untouched)
- `Fabrikant__c`: Siemens `a07WU00001VNfeUYAT`, Miele `a07WU00001VNl6AYAT` (`sf data query -o Test-Org --query "SELECT Id, Name FROM Fabrikant__c"`).
- 4 closed third-party Cases (`SELECT Id, OwnerId, Subject, ClosedDate, Customer_Satisfaction__c, Ursache__c, Closed_Last_12M__c FROM Case WHERE IsClosed = true AND Ursache__c = 'DrittpartyProdukt'`): all OwnerId `005WU000017tEKLYA2` (the CLI session user). Siemens: 1450.00 known + 1 blank; Miele both blank. AccountId of all four: null — seeding without AccountId is fine.
- `Customer_Satisfaction__c` on the two Miele cases is literally `'3'`, not a legal fullName (`Score_1..Score_5`) — pre-existing org data, outside this ticket, noted only.
- Report IDs: `SELECT Id, Name FROM Report WHERE Name = 'Faelle_Drittparty_Fabrikante'` → `00OWU00000RgRnR2AV`; `..._Meine` → `00OWU00000RgRnS2AV` (plain SOQL works; `--use-tooling-api` on Report fails `sObject type 'Report' is not supported`).

## Case object field names (sobject describe Case, 2026-11-20)
- Subject = `Subject` (NOT `CaseName` — SOQL refuses it). Owner = `OwnerId` (`Owner`/`Owner__User` do NOT exist on this Case).
- `Ursache__c` is the house's custom cause picklist (SCRUM-434); the 6th value `DrittpartyProdukt` carries the UI label `Drittparty / Fremdfabrik Produkt`.
- Field labels (UI): `Fabrikant (Drittparty-Produkt)`, `Fixkosten (Teile + Spesen + Zusathre)`, `Fixkosten known`, `Kundansatisfaction`, `Ursache`.

## Record-page locators (AX-tree probe, Case 500WU000031cANeYAM, Details tab)
- Full inline edit: button named exactly `Edit` → change form with comboboxes named exactly `Ursache`, `Fabrikant (Drittparty-Produkt)`, `Kundansatisfaction`, … + buttons `Save`, `Save & New`, `Cancel`, `Cancel and close`. ONE Save applies multiple fields — needed because AC2 refuses any intermediate state (cause without Fabrikant) and AC4 refuses Fabrikant without cause.
- Per-field quick edits also exist (`Edit Ursache`, `Edit Fabrikant (Drittparty-Produkt)`, `Edit Fixkosten (Teile + Spesen + Zusathre)`, `Edit Subject`) but single-field saves can never get from cause=third to Fabrikant in two steps — each step alone is refused.
- Picklist options shadow-root: ariaSnapshot('option "X"') only (house SCRUM-417/461).

## Fixtures and quirks (measured)
- `OwnerId` reassignment on an existing Case works: create (session user owns) → `sf data update record -s Case -i X -v "OwnerId='005WU000017tBhRYAU'"` → success (needed for AC9 user-scope discrimination; all 25 foreign CLOSED cases are unscored or older than 12 months, and every scored closed case within the 12-month window is session-owned).
- Re-saving a historical closed Case without `Customer_Satisfaction__c` is refused by the SCRUM-442 rule — old house rule, not a SCRUM-464 defect; no scored historical closed Case exists in Test-Org. AC10 re-save therefore runs on my own fixture (closed, scored, no new data).

## Run 1 (2026-11-20, `scratch-run464b.log`, 10.8 min, 5 tests → 1 pass / 4 fail)
- T1 `openEditForm`: `edit.click()` timed out — the "Try the new Salesforce Setup" guidance dialog covers the Edit button; fixed by calling `dismissGuidance` before the click (patched, committed).
- Report column order (rendered, `tr.locator('td, th').allTextContents()`): `[label, total, count, average]`.
- AC8 org report render during run: Siemens `["…","1.450,00 €","3","1.450,00 €"]` (3 = 2 dev + my saved CLOSE-PATH; average still 1.450,00 → unknown costs EXCLUDED from total/avg ✓), Bosch `["…","0,00 €","3","-"]` → **DEFECT: total cell renders 0,00 € although no cost is known** (PO rule: never zero); average "-" is fine.
- AC9 `_Meine` render: Siemens `["…","1.450,00 €","2","1.450,00 €"]`, Miele `["…","0,00 €","2","-"]` → same zero in the user variant. Open point (unexplained, re-measure after fix): `_Meine` Siemens shows 2 although the session-owned CLOSE-PATH was saved with Fabrikant Siemens — org report counts it (3), `_Meine` does not.
- T5 AC10 failed at `soql()`: `SELECT Id, Subject, Cause__c FROM Case WHERE Subject = 'TEST-SCRUM-464-OLD-SAVES'` — CLI threw (exact error not captured); rerun will reveal whether the standard `Cause__c` names are the issue.
- afterAll cleanup verified green: after the run the org holds only `Fabrikant__c` Siemens+Miele and 0 TEST-SCRUM-464-* records (measured).
- CI on fix head 9fd94b7 (run 44768789585) measured via gh api: all 4 jobs `completed success` (Prod-Org Drift Gate / Lint & Format / README / Metadata, Apex & Session Smoke). PR = #185 (`gh api repos/.../pulls/185` → open, head = my branch).

- Closing via UI is NOT reachable (house SCRUM-442 probe: Status picklist never offers `Closed`, Close button vis:false). UI close-path = inline edit on an already-closed Case; the combined save is one `Edit`-form Save.
- My fixtures (deleted in afterAll): Fabrikant `Bosch` (3 cases, all cost unknown) + `Atlas` (1 case, foreign-owned) + `TEST-SCRUM-464-CLOSE-PATH`, `OLD-SAVES`, `B1..B3`, `FOREIGN`. During the run the org reports Siemens 2 / Miele 2 / Bosch 3 / Atlas 1 (8 third-party cases); after cleanup back to 2 manufacturers / 4 cases.

## Tester measurement 2026-11-20 (post-rebase run)

- Apex run 707WU00001VPhl8 (started 2026-11-20T19:23:04Z): 18 tests, 18 pass, 0 fail —
  SCRUM464TesterCoverageTest 4, SCRUM464DrittpartyTest 8, SCRUM464DrittpartyFlsTest 3.
  `sf apex run test --json` returns ONLY `{"result":{"testRunId":...}}`; the verdict comes
  from `sf apex get test -o Test-Org -i <runId> --json` (summary.outcome / tests[].Outcome).
- Apex has no `savepoint()` / `Savepoint.save()` in this org (scripts/apex-probe.sh, exit 1
  "Method does not exist or incorrect signature: void savepoint()"). No rollback in the class:
  a refused save throws and is asserted via the throw; nothing persists.
- Aggregate SOQL `Integer x = SELECT Count() FROM X` is refused by the Apex parser
  ("Unexpected token 'SELECT'"). Side-effect counts use `FeedItem[]`/`EmailMessage[]`
  with `WHERE CreatedDate = TODAY` and `.size()`.
- `User` entity: no `Profile`/`ProfileId` column (SOQL), `Alias` max length 8
  (STRING_TOO_LONG), and creating a User on an Experience Cloud profile throws
  FIELD_INTEGRITY_EXCEPTION ("Allow using standard external profiles..." off) => no
  customer-facing System.runAs and no second UI session in this Developer Edition org
  (2 licences, both held by admins). AC12 = FLS boundary + org read-back, licence gap named.
- A restricted user's `SELECT` of an invisible field does NOT throw — it returns rows
  (measured in ac13_negative). The falsifier is therefore the VALUE: the new fields must
  come back null.
- Org layout read-back: `SELECT Id, Name FROM Layout` (209 layouts, Tooling SOQL), per-layout
  fields via `sf data get record -o Test-Org -s Layout -i <id> --use-tooling-api`.
  `RelatedList` is NOT a valid sObject ("sObject type 'RelatedList' is not supported") and
  `project retrieve` rejects Layout/RelatedList (not in metadataRegistry).
  The SCRUM464 fields appear on the internal `Case Layout` only — not on Account layouts.
- Reports under test: `Faelle_Drittparty_Fabrikante` (00OWU00000RgRnR2AV) and
  `Faelle_Drittparty_Fabrikante_Meine` (00OWU00000RgRnS2AV); groupingDown
  `Case.Drittparty_Fabrikant__c` by RowCount desc, showGrandTotal=true, showSubTotals=false,
  FORMULA1 = `IF(Case.Drittparty_Fixkosten_Known__c:SUM = 0, NULL, Case.Drittparty_Fixkosten__c:SUM)`,
  FORMULA2 = the same over known costs only.
- Playwright in a worktree: `npm run test:e2e*` fails ("unknown command 'test'") and
  `npx playwright` installs a temp 1.65.1 CLI whose config load throws MODULE_NOT_FOUND.
  Fix that works: symlink the main checkout's node_modules
  (`ln -sfn .../FirstSalesforceProject/node_modules node_modules`, @playwright/test 1.61.0)
  and run `node_modules/.bin/playwright test -c playwright.config.ts <spec>`.
