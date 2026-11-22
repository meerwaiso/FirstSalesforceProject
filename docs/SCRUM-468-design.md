# SCRUM-468 — Design: Lend Devices

Author: architect-agent
Date: 2026-11-21
Branch: feature/SCRUM-468-lend-devices

## ADR — Apex, not Flow

The three hard rules (one loan at a time, serial uniqueness, write-off gated on PS
membership) require branching logic plus a bulk SOQL check plus a PermissionSetAssignment
query. Flows have repeatedly caused deploy/schema-validation failures on this project
(AGENTS.md). Decision: Apex guards, one per rule. No Flow, no scheduled task.

---

## Data Model

### Object 1: Demo_Devic__c (one record per physical device)

Developer name: `Demo_Devic`. Plural: `Demo_Devices`. Label: `Demo Device`.
Name field: AutoNumber, format `DEV-{0000}`.
SharingModel: `Private` (internal-only; no Experience Cloud, no public share).
externalSharingModel: `Private`.
deploymentStatus: `Deployed`.
enableFeeds: false. enableHistory: false. enableSearch: true.

| Field | Type | Notes |
|-------|------|-------|
| `Designation_Name__c` | Text (80) | free-text label of the device |
| `Serial_Number__c` | Text (80) | unique — enforced by Apex guard AND platform unique Text field (`<unique>true</unique>`); guard error message names the owning device |
| `Status__c` | Picklist (Restricted) | values: `Available`, `Lent_Out`, `Written_Off`; default `Available` |
| `Current_Customer__c` | Lookup → Account | blank when status ≠ Lent_Out; drives the Related List on the customer record page |
| `Current_Loan_Colleague__c` | Lookup → User | colleague who started the current loan; blank when status ≠ Lent_Out |
| `Current_Loan_Due_Date__c` | Date | blank when status ≠ Lent_Out |
| `Current_Loan_Overdue_Days__c` | Number (formula) | `IF(AND(TEXT(Status__c)="Lent_Out", Current_Loan_Due_Date__c <> NULL, Current_Loan_Due_Date__c < TODAY()), TODAY() - Current_Loan_Due_Date__c, NULL)` — 0 decimal places, blank when not overdue; drives the overdue report sort |

The `Current_Customer__c` Lookup makes the Related List on the Account record page
show exactly the devices that customer currently has. AC5 is met by the Related
List on Account for `Demo_Devic__c`, filtered by the Lookup field.

### Object 2: Loan_Record__c (one record per lending period)

Developer name: `Loan_Record`. Plural: `Loan_Records`. Label: `Loan Record`.
Name field: AutoNumber, format `LOAN-{0000}`.
SharingModel: `Private`.
externalSharingModel: `Private`.

| Field | Type | Notes |
|-------|------|-------|
| `Loan_Devic__c` | Lookup → Demo_Devic__c | the device this loan was for |
| `Loan_Customer__c` | Lookup → Account | the customer |
| `Loan_Colleague__c` | Lookup → User | the colleague who lent it; set by Apex, not by the caller |
| `Loan_Start_Datum__c` | Date | when the loan started |
| `Loan_Due_Datum__c` | Date | when the loan was supposed to come back |
| `Loan_Return_Datum__c` | Date | blank = loan still open; set when returned |
| `Loan_Duration_Days__c` | Number (formula) | `IF(Loan_Return_Datum__c <> NULL, Loan_Return_Datum__c - Loan_Start_Datum__c, NULL)` |

A Lookup to User is valid on a custom object (the skill note forbids Lookup *on*
User, not Lookup *to* User). If the Deploy rejects it, the Developer falls back
to `Loan_Colleague_Name__c` (Text, 80) written from `Loan_Colleague__c.Name` via
the handler.

---

## Apex Components

### 1. DemoDevicGuard.cls — serial uniqueness (AC2)

Shape: house `CompetitorNameGuard` / `FabrikantNameGuard` (origin/master, measured
2026-11-21). BeforeInsert + BeforeUpdate on `Demo_Devic__c`. Collect all
`Serial_Number__c` values from the batch; one SOQL
`SELECT Id, Name, Serial_Number__c FROM Demo_Devic__c WHERE Serial_Number__c IN :serials`;
refuse duplicates with `System.AssertEquals(false, true, "...Serial \"<nr>\" already on <DeviceName>...")`.
Self-match excluded by `Id` for the Update branch.

### 2. LoanRecordGuard.cls — one loan at a time + no loan on written-off (AC4, AC9)

BeforeInsert on `Loan_Record__c`. Collect all `Loan_Devic__c` Ids. One SOQL:
`SELECT Status__c, Current_Customer__c FROM Demo_Devic__c WHERE Id IN :devicIds`.
If status = `Written_Off`: reject, message names the device.
If status = `Lent_Out`: reject, message names the device and the current customer.
If status = `Available`: proceed.

AfterInsert on `Loan_Record__c`: for each newly created loan, bulk-populate the
device: set `Status__c = Lent_Out`, `Current_Customer__c`, `Current_Loan_Colleague__c = <loan.Loan_Colleague__c>`,
`Current_Loan_Due_Date__c`. One bulk update via `Record__c.update()` list, no per-record DML.

### 3. LoanReturnGuard.cls — record return, clear device (AC6)

BeforeUpdate on `Loan_Record__c`: when `Loan_Return_Datum__c` transitions from null
to non-null, bulk-update the device: set `Status__c = Available`, clear
`Current_Customer__c`, `Current_Loan_Colleague__c`, `Current_Loan_Due_Date__c`.

### 4. DemoDevicWriteoffGuard.cls — write-off only for team leads (AC9n)

BeforeUpdate on `Demo_Devic__c`: when `Status__c` transitions to `Written_Off`
from anything other than `Written_Off`, check PS membership. Bulk approach:
collect the distinct `User` Ids from `Loan_Colleague__c` … actually the
saving user is `$User`. One SOQL:
`SELECT Id FROM PermissionSetAssignment WHERE PermissionSet.Name = 'SCRUM468_Writeoff' AND Assignee.Id = $User.Id`.
Zero rows → reject with `System.AssertEquals(false, true, "…only team leads may write off a device…")`.
One query per transaction; `$User` is identical for all records in a batch.

Note: when the device is written off, its open loan records keep `Loan_Return_Datum__c = null`
(PO decision: the device reads written off while the open loan still reads lent out).
No handler clears the loan records on write-off.

---

## Permission Sets

Three sets as required by the PO. All assigned to real users and read back (step 3 of
salesforce-describe-first §4).

### SCRUM468_Loan (Sales employees — lending and returning)

`objectPermissions` for `Demo_Devic__c`:
- allowCreate=true, allowEdit=true, allowDelete=false, allowRead=true

`objectPermissions` for `Loan_Record__c`:
- allowCreate=true, allowEdit=true, allowDelete=false, allowRead=true

`fieldPermissions` (editable=true, readable=true):
- `Demo_Devic__c.Designation_Name__c`
- `Demo_Devic__c.Serial_Number__c`
- `Demo_Devic__c.Status__c`
- `Demo_Devic__c.Current_Customer__c`
- `Demo_Devic__c.Current_Loan_Colleague__c`
- `Demo_Devic__c.Current_Loan_Due_Date__c`
- `Loan_Record__c.Loon_Devic__c` (Lookup) — note: use the real field name after deploy
- `Loan_Record__c.Loan_Customer__c`
- `Loan_Record__c.Loan_Colleague__c` (or fallback `Loan_Colleague_Name__c`)
- `Loan_Record__c.Loan_Start_Datum__c`
- `Loan_Record__c.Loan_Due_Datum__c`
- `Loan_Record__c.Loan_Return_Datum__c`

Formula fields `Current_Loan_Overdue_Days__c` and `Loan_Duration_Days__c` get
readable=true, editable=false.

Assigned to: all Sales employees (not Service). Read back via
`SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM468_Loan'`.

### SCRUM468_Read (Sales employees AND Service employees — read all)

`objectPermissions` for both objects: allowRead=true, allowEdit=false, allowCreate=false, allowDelete=false.

`fieldPermissions` (readable=true, editable=false) for every field on both objects
including formula fields.

Assigned to: all Sales employees + all Service employees. Read back via
`SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM468_Read'`.

### SCRUM468_Writeoff (Sales team leads only — marker set, AC9n discriminator)

Carries **no field rights and no object rights** — it is a pure marker. The
`DemoDevicWriteoffGuard` queries `PermissionSetAssignment WHERE PermissionSet.Name='SCRUM468_Writeoff'`.
The set has `hasActivationRequired=false` and a `label` only.

Assigned to: Sales team leads only. Read back via
`SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM468_Writeoff'`.

This is the skill's pitfall resolution (SCRUM-467, 2026-11-21): a marker PS with a
bulkified guard inside the changed-branch, not a second grant set. Sales employees hold
`SCRUM468_Loan` (edit on device), but they do not hold `SCRUM468_Writeoff`, so the guard
rejects `Written_Off` for them. Team leads hold `SCRUM468_Loan` AND `SCRUM468_Writeoff`.

---

## Overdue Report (AC8)

Report: `SCRUM468_Overdue_Devices.report-meta.xml`
- reportType: to be determined by `sf api request rest '/services/data/v62.0/analytics/reportTypes' --target-org Test-Org` — the developer queries the type for `Demo_Devic__c` before writing the XML; never guess.
- filter: `Status__c = 'Lent_Out'` AND `Current_Loan_Due_Date__c < TODAY()`
- columns: `Name`, `Serial_Number__c`, `Current_Customer__c`, `Current_Loan_Colleague__c`, `Current_Loan_Overdue_Days__c`
- sort: `Current_Loan_Overdue_Days__c` Desc
- scope: org-wide (value `org` or `organization` depending on report type — developer queries `scopeInfo` before specifying)

Report scope source element `<scope>` is persistable in XML (skill: salesforce-describe-first §7).
The report-level sharing (who may open it) is not in source — DevOps sets it in the org.

---

## Layout / Record Page

**Classic layout (repo):** Not needed for the PO's requirements. Skip.

**Lightning record page (org step):** DevOps sets up the related lists on both record
pages:
- `Demo_Devic__c` record page → Related List `Loan_Record__c` (shows the device's whole history, AC7)
- `Account` record page → Related List `Demo_Devic__c` filtered to `Current_Customer__c` (shows current devices on loan, AC5)

The Related List on Account for `Demo_Devic__c` uses the `Current_Customer__c` Lookup
field. It shows exactly the devices that customer has right now; returned devices have
their Lookup cleared and disappear.

**AC5 note:** The Tester verifies the Lightning record page for the Account
shows exactly the right number of current devices via a Playwright spec,
not via Apex test (record-page visibility is an org artefact, not a deploy-gated assertion).

---

## Data Classification

| Field | Classification |
|-------|---------------|
| Designation_Name__c, Serial_Number__c, Status__c | Internal business data, no personal data |
| Current_Customer__c, Loan_Customer__c | Sensitive business partner data, internal only |
| Current_Loan_Colleague__c, Loan_Colleague__c | Internal employee data |
| Loan dates | Internal business data |

No data-category meta is in source XML for custom fields in this SDR format;
data classification is set on the field in the org (DevOps at release time).

---

## Governor-limit risks and mitigation

| Risk | Mitigation |
|------|-----------|
| SOQL-in-loop for serial uniqueness | One `SELECT WHERE Serial_Number__c IN :set` per batch |
| SOQL-in-loop for one-loan check | One `SELECT Status__c, Current_Customer__c WHERE Id IN :devicIds` per batch |
| Per-record update after loan insert | One `updList` bulkified in AfterInsert |
| Per-record update on return | One `updList` bulkified in BeforeUpdate |
| PS-assignment query on write-off | One query per transaction ( `$User.Id` is same for all records) |

---

## Sharing model impact

- Both objects: `sharingModel=Private`, `externalSharingModel=Private`.
- No Experience Cloud, no customer-facing access, no public sharing rules.
- Sales and Service employees get read access via `SCRUM468_Read` PS (object + field FLS).
- Customer-facing users have no access: no PS grant, Private sharing model, no object access.

---

## FLS — three-query chain per field (salesforce-describe-first §4)

For every field on both objects the developer must verify:
1. `FieldDefinition` exists (Tooling API)
2. `FieldPermissions` grants read/write (plain query, no `-t`)
3. `PermissionSetAssignment` shows the intended assignee (step 3 is the one that historically fails)

`scripts/fls-check.sh Demo_Devic__c Status__c Test-Org` — run this before the handoff.
CI's `scripts/fls-gate.py` will redden if a changed field names no PS or a PS assigned to nobody.

---

## AC-to-artefact map

| AC | Artefact | Test class |
|----|---------|-----------|
| AC1 Device recorded | `Demo_Devic__c` object + `Designation_Name__c` + `Serial_Number__c` fields | `SCRUM468LendDevicesTest` — positive AC1 |
| AC2 Serial unique | `DemoDevicGuard` (Apex guard, house shape) | `SCRUM468LendDevicesTest` — AC2 duplicate serial, assert throws with name |
| AC3 Lending | `LoanRecordGuard` AfterInsert populates device fields | `SCRUM468LendDevicesTest` — AC3 device state + loan record created |
| AC4 One customer at a time | `LoanRecordGuard` BeforeInsert (status=Lent_Out → reject) | `SCRUM468LendDevicesTest` — AC4 second loan attempt rejected, still one open loan |
| AC5 Customer view | `Current_Customer__c` Lookup on device + Related List on Account (org step) | Playwright E2E `SCRUM-468_customer-view.spec.ts` |
| AC6 Return | `LoanReturnGuard` BeforeUpdate on Loan_Record__c | `SCRUM468LendDevicesTest` — AC6 return date, device status back |
| AC7 History on device | Related List `Loan_Record__c` on `Demo_Devic__c` record page (org step) + `Loan_Duration_Days__c` formula | Playwright E2E `SCRUM-468_device-history.spec.ts` + `SCRUM468LendDevicesTest` AC7 counts |
| AC8 Overdue report | `SCRUM468_Overdue_Devices.report-meta.xml` | Playwright E2E `SCRUM-468_overdue-report.spec.ts` + row-count assertion |
| AC9 Write-off by team lead | `DemoDevicWriteoffGuard` + `SCRUM468_Writeoff` PS | `SCRUM468LendDevicesTest` — AC9 positive (runAs team-lead user) |
| AC9n Negative write-off | Same guard, PS membership check | `SCRUM468FlsTest` — AC9n: Sales employee (no PS) and Service employee (no PS), both rejected |
| AC11 Service read | `SCRUM468_Read` PS (editable=false on all fields) | `SCRUM468FlsTest` — Service employee reads, cannot lend or return |
| AC12 Nothing automatic | No trigger, no Flow, no scheduled task — only on-save guards | `SCRUM468LendDevicesTest` — AC12: save overdue device, run time check, status unchanged |

---

## House patterns cited (origin/master, measured 2026-11-21)

- **Custom object house shape**: `Competitor__c.object-meta.xml` (SharingModel=ReadWrite, visibility=Public, externalSharingModel=Private). Override here to `Private` / `Private` per PO.
- **Duplicate guard shape**: `CompetitorNameGuard.cls` / `FabrikantNameGuard.cls` (both on origin/master, measured 2026-11-21) — `System.AssertEquals(false, true, msg)` refuses the save, carries the name.
- **PS marker discriminator**: `SCRUM461_Competitor_List_Teamleitung` carries CRUD rights; SCRUM468 `SCRUM468_Writeoff` carries **no** rights, it is a pure marker checked by the guard. This is the resolution from the `architect-design-workflow` pitfall (measured 2026-11-21, SCRUM-467).
- **Read-only PS house shape**: `SCRUM461_Competitor_List_Read.permissionset-meta.xml` — `allowEdit=false, allowCreate=false, allowDelete=false`.
- **Formula field shape**: Text formula takes no `<length>` (verified SCRUM-394, deploy-validated). Number formula: `type=Number`, `precision/scale` optional.
- **Lookup field on custom object**: `required=false` mandatory; never `unique` on a lookup (verified SCRUM-461).

---

## Open points (not blocking implementation)

- [ ] ReportType and scope value for `Demo_Devic__c`: developer queries `sf api request rest '/services/data/v62.0/analytics/reportTypes' --target-org Test-Org` before writing the report XML.
- [ ] `Loan_Colleague__c` as Lookup-to-User: if deploy rejects (INVALID_DATA_TYPE), fallback to `Loan_Colleague_Name__c` (Text, 80) set by handler; PO AC3/AC8 satisfied by the name.
- [ ] Lightning related-list placement on record pages: DevOps at deploy time in Test-Org and Prod-Org (org step, not CI-gated).

---

## Round-3 decision (Architect, 22.11.2026, head 4044534)

### Measured platform facts (every link read back, job ids re-readable)

- A related list on a STANDARD object's record page renders only from a MasterDetail relationship.
  House precedent: Account-Account Layout relatedList OpenOpportunityHistory__c.AccountId__c, that field's
  type element is MasterDetail, 9 rows rendered live (SCRUM-417). SCRUM-468 shipped Loan_Customer__c as a
  Lookup, so the section heading renders and 0 rows come with it (Tester run 22.11.2026, head 7094fee).
- A related list on a CUSTOM object's record page renders from a Lookup (device page Loan_Record__c.Loan_Devic__c,
  2 rows live in the same run).
- A Lookup cannot be converted to MasterDetail: check-only validate job 0AfWU00000dJnPx0AK, component error
  "Test only deployment cannot update a field from a Lookup to MasterDetail".
- A NEW MasterDetail field on Loan_Record__c to Account is accepted and coexists with the Lookup: check-only
  validate job 0AfWU00000dJnGH0A0, 1/1 components, failures only from the new field being required
  (REQUIRED_FIELD_MISSING: [Loan_Account_Md__c] in the FLS test setup).
- The device history list declared 5 columns and rendered 4 data columns plus an Action column; the missing
  one was the formula field declared last. The cause (column cap vs formula type) is still open; the
  discriminator experiment (duration declared second) is deployed at head 4044534, not yet measured.

### AC7 — decided here (presentation is the Architect's)

History related list ships exactly four declared columns:
Loan_Customer__c, Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_History_Facts__c.

Loan_History_Facts__c is a real Text field, not a formula, on Loan_Record__c:
LoanRecordGuard writes it at lend time ("open / due 07.10.2026"), LoanReturnGuard rewrites it at return time
("returned 23.10.2026 / 16 Tage"). FLS: explicit entries in SCRUM468_Loan and SCRUM468_Read; SCRUM468_Writeoff
stays a marker set that grants nothing.

Why this shape: it renders under BOTH open causes (a four-column cap and a formula-column rule) and it keeps
all five values the PO names in AC7 — customer, start, due, actual return, duration — inside four columns.
Rows still equal loans created for that device, so the counting half of AC7 is unchanged.
If the PO insists on five separate columns, AC7 is undeliverable under the cap and becomes a PO decision.

### AC5 — routed to the PO, not decided here

The criterion names the surface (the internal record page of the customer shows the devices that customer
currently has), and the platform answer says that surface carries a Lookup related list with no rows.
Three shapes, two deliverable, the choice changes the requirement, so the PO owns it:

- (a) new MasterDetail field on Loan_Record__c to Account — deployable (job 0AfWU00000dJnGH0A0), required,
  duplicates the customer reference already held in Loan_Customer__c, and the page lists EVERY loan of that
  customer including returned ones, so the AC5 half "the returned device is not listed as current" has to be
  re-worded.
- (b) ListView on Loan_Record__c filtered to open loans, reached by a Setup picker button from the record page
  (the AC8 house pattern, measured live in this org).
- (c) drop the customer-page list from this story: the content stays provable at org level and on the device page.

Neither the Architect nor the Developer picks one of the three before the PO answers.
