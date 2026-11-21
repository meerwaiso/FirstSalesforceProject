# SCRUM-468 — Developer notizen (measured in Test-Org, 2026-11-21)

Every value below was read back from the org or a deploy report; the command is named.

## Object sharing model (AC11)
- `<sharingModel>Private</sharingModel>` = owner-only record visibility. Measured: a
  Service user holding SCRUM468_Read saw 0 of the 4 devices (AC11 assertion failed),
  and a team lead's `WHERE Id = :deviceId` answered "List has no rows".
- `FullyAccessible` is rejected: "Error parsing file: 'FullyAccessible' is not a
  valid value for the enum 'CustomSharingModel'".
- House value read from the org with `sf project retrieve start --metadata
  CustomObject:Competitor__c CustomObject:Fabrikant__c CustomObject:Absence__c`:
  Competitor__c / Fabrikant__c / DiscountApprovalManager__c / Followup_Obligation__c
  carry `<sharingModel>ReadWrite</sharingModel>`, Absence__c / CustomerTransfer__c
  carry `Private`. Both SCRUM-468 objects now ship `ReadWrite`
  (`externalSharingModel` stays Private - no Experience Cloud exposure, AC: no
  customer-facing surface).

## ReportType (AC8) - NOT implementable from source, measured
- `analytics/report-types/CustomEntity%24Demo_Devic__c` on Test-Org returns
  detailColumnInfo = { CUST_NAME -> Demo_Devic__c.Name } only, aggregateColumnInfo
  = RowCount, groupingColumnInfo = null. The joined variant
  `CustomEntity$Demo_Devic__c@Demo_Devic__c.Current_Customer__c` adds one column
  (FK_NAME -> the joined Account's Name) and still has no groupings.
- Consequence: the report the design asks for (device, customer, lending colleague,
  days overdue, longest overdue first) cannot be built on the auto-generated
  CustomEntity$ type. Measured rejections in deploy validate: the formula field
  `Current_Loan_Overdue_Days__c` is refused as `<columns>`, as `<sortColumn>` and as
  groupingsDown ("no CustomField named ... found" - a FormulaField is not a
  CustomField); `Demo_Devic__c$Name` as sortColumn gives "Invalid field name".
- Therefore the report file and the ListView were removed from the branch
  (`git rm`, manifests phase5/phase6 dropped). The overdue overview needs an
  Architect decision: which carrier (a joined reportType built in the UI, a ListView
  with `<sortInfo>`, or the formula field in the object's related-list) carries AC8.
  The data behind it is live and tested: 2 devices Lent_Out past due (30 and 15 days),
  read back by AC8's Apex test.

## Trigger phase semantics (cost 8/8 red tests)
- `Trigger.isInsert` is true in BOTH the before-insert and the after-insert event.
  A trigger on `(before insert, after insert)` must pin each handler with
  `Trigger.isBefore` / `Trigger.isAfter`, otherwise the write-back runs in the
  before phase and the second half of the same batch trips the one-loan check
  (symptom: "device ... is already on loan" on the fixture insert).
- Verified working: `sf apex run` probe - loans inserted -> devices flip to Lent_Out,
  DML statements 3 -> 4.

## Refusing a save in production Apex
- `record.addError('...')` (house: OpportunityLockedAccountGuard). `System.assert`
  is not production code; the message arrives as
  FIELD_CUSTOM_VALIDATION_EXCEPTION.
