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
- `sharingModel` values on a CustomObject are FullyReadWrite/ReadWrite/ViewOnly/Locked/
  ControlledByParent; the design doc said "Private", which is only valid for
  `externalSharingModel`. Built with `Locked` + `Private` (internal-only, matches the PO
  intent: no Experience Cloud, no customer-facing access).
- Number formula field shape (house Competitor_Gap__c): fullName, label, description,
  formula, precision, scale, type, unique; no <length>.
- Picklist house shape (Customer_Satisfaction__c): required/restricted/trackFeedHistory/
  trackHistory/type/valueSet; default lives on the <value>.

## Deploy order (memory + manifest)

objects -> fields -> guards+tests -> permission sets -> report.
