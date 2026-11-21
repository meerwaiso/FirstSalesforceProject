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
