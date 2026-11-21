# SCRUM-468 Notizen (developer-agent)

Started 2026-11-21 on branch feature/SCRUM-468-lend-devices. Read this file first
after every compaction; commit it with the ticket.

## Measured against Test-Org / origin/master (command in brackets)

- No lending object existed in Test-Org before this ticket (PO measurement + my
  Tooling-API EntityDefinition read).
- Real users in Test-Org: only `devops-agent@cline.test` (CLI target-org user,
  `sf org display`) and `meerwais.osmani@resourceful-bear-6f1u4j.com`. There is no
  user "sales employee" or "team lead"; the role split lives in Permission Sets
  (house convention, docs/SCRUM-461-notizen-dev.md).
- `UserInfo.getUserId()` compiles and returns the running user Id (scripts/apex-probe.sh
  q3, Test-Org). `$User` is NOT valid Apex (probe p1-p5: "Variable does not exist: $User").
- PermissionSetAssignment SOQL in Apex: queryable columns are `PermissionSetId` and
  `AssigneeId`; `Assignee` is rejected ("No such column 'Assignee' on entity
  'PermissionSetAssignment'", probe q1). `SELECT Id FROM PermissionSet WHERE Name = :x`
  works; the marker lookup + PSA filter returned rows=1 for the CLI user (probe q3).
- `<sharingModel>` enum, read from the CLI's own schema
  (`@salesforce/types/lib/metadata.d.ts:194`):
  `Private | Read | ReadSelect | ReadWrite | ReadWriteTransfer | FullAccess |
   ControlledByParent | ControlledByLeadOrContact | ControlledByCampaign`.
  The design doc said `Private` -> kept it. My first guess `Locked` was rejected by
  validate ("'Locked' is not a valid value for the enum 'CustomSharingModel'").
  `externalSharingModel Private` is the house value (Competitor__c, origin/master).
- Number formula field shape (house Competitor_Gap__c): fullName, label, description,
  formula, precision, scale, type, unique; no <length>.
- Picklist house shape (Customer_Satisfaction__c): required/restricted/trackFeedHistory/
  trackHistory/type/valueSet; default lives on the <value>.

## Deploy order (memory + manifest)

objects -> fields -> guards+tests -> permission sets -> report.

## AC8 carrier (2026-11-21, Architect review §1)

- Formula Checkbox `Overdue_Today__c` on Demo_Devic__c: `<formula>AND(Text(Status__c) = "Lent_Out", NOT(ISBLANK(Current_Loan_Due_Date__c)), Current_Loan_Due_Date__c &lt; TODAY())</formula>`, `<type>Checkbox</type>`. No `formulaType` element — rejected at this location in type CustomField.
- ListView path is `objects/Demo_Devic__c/listViews/SCRUM468_Overdue.listView-meta.xml`; manifest member `Demo_Devic__c.SCRUM468_Overdue` under `<name>ListView</name>`. `<columns>` take bare API names of the object's own fields; `<columns>Name</columns>` is refused ("Could not resolve list view column: Name"). ListView metadata has NO sort element — longest-overdue-first is a UI sort the Tester asserts.
- Manifests: `manifest/scr468-phase5a-ac8-field-listview.xml` (CustomField before ListView), `manifest/scr468-phase5b-ac8-permsets.xml`. Validate then deploy each: 5a job 0AfWU00000dJ9Vl0AK, 2/2 components Succeeded; 5b 2/2 Succeeded. Guards+tests redeployed RunSpecifiedTests → Passing: 8, Failing: 0, Total: 8 (scratch/d5c.log).
- Formula fields DO evaluate in the Apex test sandbox (new assertion `flagged == 2` over `SELECT Overdue_Today__c FROM Demo_Devic__c` passed); trigger-written rollup fields do NOT (stay NULL until a save touches them). Different semantics — do not assert them the same way.
- `sf data create record -s Demo_Devic__c -v "Name='...'"` fails: INVALID_FIELD_FOR_INSERT_UPDATE "Unable to create/update fields: Name" — the name field is AutoNumber, omit Name. Live read-back record SN-RB-468 (Lent_Out, due 2026-10-31) → Current_Loan_Overdue_Days__c 21, Overdue_Today__c true; deleted afterwards, both objects read 0 records.
- `scripts/fls-check.sh Demo_Devic__c Overdue_Today__c Test-Org` → exists "Formula (Checkbox)", read=true edit=false in SCRUM468_Loan and SCRUM468_Read, 2 users each, verdict visible.
- `reportTypes/SCRUM468_Overdue_Devices.reportType-meta.xml` deleted from the branch: a ReportType renders nothing, and the formula field is refused as columns/sortColumn/groupingsDown ("no CustomField named ... found" — a FormulaField is not a CustomField). AC8 does not rest on it.
- CI at head 1e51102 as seen: Lint & Format and README pass; "Metadata, Apex & Session Smoke" and "Prod-Org Drift Gate" still pending — the merge gate needs those verdicts on THIS head, not on 62477a3.

