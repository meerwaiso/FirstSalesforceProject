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
