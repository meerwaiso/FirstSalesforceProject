# SCRUM-442 — Tester-Notizen (2026-10-11)

Verfied by the Tester in this session; every line names the command it came from.

## Org facts
- Case field label: `Customer_Satisfaction__c` → Label `Kundansatisfaction`
  (`sf data query -q "SELECT QualifiedApiName,Label FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Case' AND QualifiedApiName='Customer_Satisfaction__c'"`)
- Account rollup labels (FieldDefinition.Label, same query with Account):
  `Satisfaction_Arger__c`="Status ärger?", `Satisfaction_Durchdurch__c`="Satisfaction Ø (3 Monate)",
  `Satisfaction_Min__c`="Satisfaction min (3 Monate)", `Satisfaction_Anzahl__c`="Cases in Ø-Fenster",
  `Satisfaction_Fenster_Start__c`="Ø-Fenster seit"
- Picklist option names carry an EN-DASH (U+2013): `--None--`, `1 – sehr dissatisfied`,
  `2 – dissatisfied`, `3 – neutral`, `4 – satisfied`, `5 – sehr satisfied`
  (probe442aw ariaSnapshot of getByRole('option'))
- `Case.CloseDate` is NOT a SOQL column on Case — use `ClosedDate`
  (`sf data query ... SELECT CloseDate FROM Case` → INVALID_FIELD "No such column")

## Picklist edit mechanics (the Developer's UNVERIFIED locator)
- There is NO `input[name="Customer_Satisfaction__c"]`. The picklist renders
  `BUTTON[role=combobox]` with `aria-label="Kundansatisfaction"`; options are
  `role=option` inside shadow roots — raw `querySelectorAll` misses them,
  Playwright locators pierce (probe442aq/aw).
- Verified flow: `getByRole('button',{name:'Edit Kundansatisfaction'})` → click
  → `getByRole('combobox',{name:'Kundansatisfaction',exact:true})` → click
  → `getByRole('option',{name:'4 – satisfied',exact:true})` → click → combobox
  ariaSnapshot now contains the value → Save → SOQL read-back `Score_4`.

## Closing path (org quirk, NOT a test bug)
- Status picklist on the Lightning record page offers only `--None--/New/Working/Escalated`;
  `Closed` is absent (probe442aq/ai/am; SCRUM-434 tester notes confirm 2026-09-30).
- The `Close` action button exists (`getByText('Close',{exact:true})` count 1) but
  renders `vis:false`, box null, not clickable even after `Show more actions`
  (aria-expanded false→true) — probe442bt/bf/bj.
- ⇒ UI closing is not reachable from the record page; AC1/AC2/AC4 closing is
  exercised on the REST/CLI path (the AC demands "every closing path") + Apex
  System.runAs tests.

## AC6 DEFECT (measured, org-wide)
- Report `Miserable_Kunde_Satisfaction` (Id 00OWU00000QqteB2AR) renders
  `Total Records 0 / No Results` for the whole org (probe442br, 2026-10-11).
- Ground truth: 1 Account flagged `Ärger` (our seeded PROBE-442), and 0 of 188
  Accounts have `Satisfaction_Fenster_Start__c` within the last 90 days
  (`sf data query ... Satisfaction_Fenster_Start__c>=2026-07-13` → 0).
- Cause: `<timeFrameFilter>` uses `INTERVAL_LAST90` on
  `Account.Satisfaction_Fenster_Start__c`, but the Rebuilder window is
  `today.addMonths(-3)` → Fenster_Start is 92 days back, outside the 90-day
  window. The report filter can never match the data it is built on.
- `INTERVAL_LAST3MONTHS` is not a valid token (CLI metadataRegistry lists
  LAST7/30/60/90/120, LASTMONTH, LASTWEEK, CURRENT, CUSTOM — no 3-month token).

## Apex run (this session)
- Job 707WU00001NAmsC: 19/19 Pass, 0 Fail (SCRUM442SatisfactionTest,
  SCRUM442SatisfactionFlsTest, SCRUM442AccountRollupTest)
- Rebuilder driver `scratch/SCRUM442-rebuilder-driver.cls` → processed=188 updated=1

## Seeds
- Account PROBE-442 = 001WU00002GEhiqYAD; Case 500WU00002vEBUnYAO; Task 00TWU00000GcHOP2A3
- DELETED at end of run (sf data delete record, 5 records, all success) — org-wide
  Satisfaction_Arger__c='Ärger' count back to 0 (verified via SOQL after cleanup).

## Run 2026-10-11 evening (this session)
- Apex rerun: deploy job 0AfWU00000c8IZl0AM — 19/19 pass, 0 fail, 3 comps (RunSpecifiedTests).
- E2E run1: 1/6 — 5 failures were SPEC bugs, not org bugs:
  1) execSync THROWS when the CLI refuses a save (exit!=0) — the refusal payload
     (ValRule messages) comes off the thrown error's stdout; a plain sfJson() aborts the test.
  2) SELECT Id without OwnerId, then reading .OwnerId → undefined.
  3) Tooling-API `SELECT ... FROM Report` → INVALID_TYPE (not supported; house SCRUM-434
     uses a constant report id; retrieve via sf project retrieve start --metadata works).
  4) Playwright BDD: each test.describe block gets its OWN beforeAll seed — AC4/AC5
     blocks saw 0 Tasks / unseeded rollups because their block's Case was fresh.
- After fixes: run2 and run3 both 5/6 — only AC6 red (Report rows 0 vs org count 2).
- AC1 org-verified directly: close without score refused with exact message
  "Customer satisfaction score is required when closing a Case."; Case stays open.
- CI on head bdb6c7d: Lint green, Smoke green, Prod-Org Drift Gate RED —
  PRE-EXISTING (run 471 on previous head 71802fa also red; cause: validation
  "produced no usable result" + test failures of SCRUM-434/436 classes, not my change).

## Re-test after SCRUM-443 fix (2026-10-12)
- Developer fix (option a): timeFrameFilter removed; org stores platform default
  DUE_DATE/INTERVAL_CUSTOM (read back via sf project retrieve start) — the
  LAST90 restriction is gone, INTERVAL_CUSTOM without bounds = no restriction.
- AC6 needed a self-contained seed: block-local Account+Case closed Score_2 +
  Rebuilder driver -> org-wide AErger count 2 (PROBE443-A/B), report Total(2).
- Report DOM structure (scratch/probe-report-rows.js, 2026-10-12): 6 tbody tr
  for 2 Accounts = header + 2 group rows + 2 Subtotal + "Total(2)". Group rows'
  LAST cell is the indicator text, not a count -> house SCRUM-434 numeric reader
  skips them; names come off the FIRST cell ("NAME, unchecked, Select row...").
  Spec now reads the Total row as the record count + asserts seeded name present
  and 3 non-dissatisfied (Kein Daten) accounts absent.
- Seeds now tracked in `seeds[]` and deleted in afterAll (Task by WhatId, then
  Case, then Account) — earlier runs leaked one Account per test.describe block.
- Final run: smoke 2/2 (12s), spec 6/6 green (1.6m). PROBE443 seeds deleted,
  org-wide AErger count back to 0.
- Apex NOT re-run this round: no Apex class changed, budget 441/500 last 24h.
