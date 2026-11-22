# SCRUM-468 — Architect review of PR #190 (head 62477a3)

Verdict: REQUEST_CHANGES. One required change, three decisions, all measured against Test-Org on 2026-11-21.

## 1. The required change: the overdue overview has no carrier

AC8 ("team lead opens the overdue overview") has an artefact for the DATA (formula field + Apex test) but
nothing renders the overview anywhere. The branch carries `reportTypes/SCRUM468_Overdue_Devices.reportType-meta.xml`;
a ReportType alone renders nothing, and the measured report type of the object answers with one detail column
(`CUST*NAME`) and no groupings, so a Report cannot carry device + customer + colleague + days overdue + sort order.

Proven deployable carrier (check-only validate, operation `0AfWU00000dJ94L0AS`, 11 components done, 0 failures;
`checkOnly: true`, org read-back `sf sobject describe --sobject Demo_Devic__c --json | grep -c Overdue_Today` = 0):

### 1.1 formula Checkbox on the device object

Path: `force-app/main/default/objects/Demo_Devic__c/fields/Overdue_Today__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Overdue_Today__c</fullName>
    <formula>AND(Text(Status__c) = "Lent_Out", NOT(ISBLANK(Current_Loan_Due_Date__c)), Current_Loan_Due_Date__c &lt; TODAY())</formula>
    <label>Overdue today</label>
    <type>Checkbox</type>
</CustomField>
```

Note: no `formulaType` element — that element is rejected at this location in type CustomField.
A Checkbox formula carries no blank-value problem, so no `formulaTreatBlanksAs` is needed.

### 1.2 list view on the device object

Path: `force-app/main/default/objects/Demo_Devic__c/listViews/SCRUM468_Overdue.listView-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>SCRUM468_Overdue</fullName>
    <columns>Designation_Name__c</columns>
    <columns>Serial_Number__c</columns>
    <columns>Current_Customer__c</columns>
    <columns>Current_Loan_Colleague__c</columns>
    <columns>Current_Loan_Due_Date__c</columns>
    <columns>Current_Loan_Overdue_Days__c</columns>
    <filterScope>Everything</filterScope>
    <filters>
        <field>Overdue_Today__c</field>
        <operation>equals</operation>
        <value>1</value>
    </filters>
    <label>Devices overdue</label>
</ListView>
```

Measured: `<columns>Name</columns>` is refused ("Could not resolve list view column: Name") — use
`Designation_Name__c` and `Serial_Number__c` instead. The ListView metadata schema has no sort element,
so the "longest overdue first" order is a UI action the Tester performs on the rendered list
(sort the `Current_Loan_Overdue_Days__c` column descending); the set itself is filter-driven.

FLS: add `Demo_Devic__c.Overdue_Today__c` to SCRUM468_Read (`editable=false readable=true`) and to
SCRUM468_Loan the same way, and add the new field and the ListView to the deploy manifest. Without the
field permission the list view renders the column blank for the very users AC8 names.

## 2. Decision: sharing model — accept ReadWrite, keep Private external

Measured by the Developer and re-read here from the org: `Private` restricts record visibility to the record
owner, so the Service employee holding SCRUM468_Read saw 0 of 4 devices; `FullyAccessible` is rejected by the
compiler ("not a valid value for the enum CustomSharingModel"). `ReadWrite` internal plus
`externalSharingModel Private` is the house value (read from Competitor__c, Fabrikant__c,
DiscountApprovalManager__c, Followup_Obligation__c via `sf project retrieve start --metadata CustomObject:...`).
Accepted: the customer-facing negative test (`SCRUM468FlsTest.customerFacingUser_seesNeitherObject`) is the
FLS half and stays; the Experience Cloud half is `externalSharingModel Private`.

## 3. Decision: the related-list proposal is dead — both routes measured

`<relatedListItem>` in the object metadata is rejected:
"Error parsing file: Element {…}relatedList invalid at this location in type CustomObject"
(check-only validate, operation `0AfWU00000dJ7lh0AC`).
The Layout route is dead too: `<relatedLists><lookupColumn>…` answers "Element lookupColumn invalid at
this location in type RelatedListItem", and `<relatedLists><relatedList>Loan_Records_History</relatedList>`
answers "Cannot find related list:Loan_Records_History" (operations `0AfWU00000dJ8g90AC`,
`0AfWU00000dJ8hl0AC`, `0AfWU00000dJ92j0AC`, `0AfWU00000dJ94L0AS`).

What already exists is the declaration that works: both lookup fields carry
`<relationshipLabel>` and `<relationshipName>` — read back from the deployed org metadata
(`sf project retrieve start -o Test-Org --metadata CustomField:Loan_Record__c.Loan_Devic__c CustomField:Demo_Devic__c.Current_Customer__c`).
That relationship IS the related list on the target record page: the customer page lists the devices
(AC5), the device page lists the lending periods (AC7). So AC5/AC7 are verified as rendered Lightning
record pages (Playwright), not as deploy-gated metadata. No further metadata needed.

## 4. Decision: keep the reportType file out of the shipped surface

`SCRUM468_Overdue_Devices.reportType-meta.xml` names `Demo_Devic__c` as its base object and lists the
formula field as a column. The formula field is refused as `columns`, as `sortColumn` and as
`groupingsDown` ("no CustomField named … found" — a FormulaField is not a CustomField). Either drop the
file from the branch or keep it without the formula column and without a Report that claims to sort;
AC8 must not be justified by it.

## 5. Findings, not blocking

- `Status__c` ships an UNRESTRICTED valueSet; the design said restricted. The three values are enforced by
  `DemoDevicWriteoffGuard` / `LoanRecordGuard`, and `SCRUM468_Loan` grants `Status__c` editable=true, which is
  what makes the negative write-off test meaningful (a plain sales employee can type the value, the guard
  refuses it). Free-form values are still accepted on save — recommend `<restricted>true</restricted>`,
  non-blocking, does not change the permission design.
- `Serial_Number__c` ships `<unique>true</unique>`; combined with `DemoDevicGuard` the guard's message
  naming the owning device is the added value. Keep both.
- CI on head `62477a3`: all four jobs green, measured today (`gh pr checks 190`) — Lint & Format,
  Metadata/Apex/Session Smoke, **Prod-Org Drift Gate pass 11m34s**, README. The pending gate the Developer
  reported has resolved; a merge may use this head.
- Test coverage per criterion (method names read from the branch): AC1 four devices + all four readable by serial
  (`setup_fixtures`, `serialNumber_mustBeUnique`); AC2 duplicate serial refused (`serialNumber_mustBeUnique`);
  AC3 device half filled + loan open (`lending_fillsTheDevice_half_and_a_second_lending_is_refused`);
  AC4 second lending refused + exactly one open loan (same); AC6 return clears all four fields
  (`return_clears_the_device_and_history_survives`); AC7 both periods survive, 14-day duration present
  (same); AC8 two overdue with 30 and 15 days, nothing rewritten by the save
  (`overdue_devices_stay_untouched_without_automation`); AC9 team lead writes off, history count unchanged,
  re-lending refused (`teamLead_mayWriteOff_andHistoryStaysVisible`); AC9n/AC10 without the marker set refused,
  status stays (`SCRUM468FlsTest.salesEmployee_withoutMarkerSet_cannotWriteOff`); AC11 Service reads both objects
  (`SCRUM468FlsTest.serviceEmployee_reads_but_hasNoWriteRights`); customer-facing user sees neither object
  (`SCRUM468FlsTest.customerFacingUser_seesNeitherObject`).
  Gaps: AC5 (customer record page) and AC7 (device record page) have no rendered-page test yet — Playwright,
  Tester's station, fixture counts 4 devices / 6 loans / 3 customers. AC8 gets its rendered artefact with the
  list view added above.

## 6. What the Developer must change before re-review

1. `Overdue_Today__c` formula Checkbox (exact XML above), plus the ListView above, plus both in the deploy manifest.
2. `Demo_Devic__c.Overdue_Today__c` field permissions in SCRUM468_Read and SCRUM468_Loan.
3. Drop or fix the reportType file per §4.
4. Read back the assignment of all three Permission Sets plus the new field in the handoff comment.
