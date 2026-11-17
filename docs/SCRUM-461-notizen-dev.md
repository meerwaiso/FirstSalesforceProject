# SCRUM-461 — Developer notizen

Verified findings only, each with the command that produced it. Read this file first after every compaction.

## Org facts (measured 2026-11-17, Test-Org)

- CLI target-org user = `devops-agent@cline.test` (`sf org display`).
- Users in Test-Org (`sf data query -q "SELECT Id, Name FROM User"`): 8 records —
  Meerwais Osmani, Integration User, Automated Process, Data.com Clean, Security User,
  Chatter Expert, Platform Integration User, devops-agent. There is NO user named
  "account manager" or "team lead": the role split is expressed by Permission Sets, not by users.
- House PS assignment convention, read back with `scripts/fls-check.sh Account Wartungsvertrag_Start__c Test-Org`:
  both `SCRUM451_..._Read` and `SCRUM451_..._Teamleitung` are assigned to exactly two users —
  `devops-agent@cline.test` and `meerwais.osmani@resourceful-bear-6f1u4j.com`.
- PSA read-back spelling that WORKS: `SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='<PS>'`.
  `PermissionSetName` / `Assignee` are NOT columns (rejected: "No such column 'PermissionSetName'").
- `User` has no `Role` column (rejected: "No such column 'Role' on entity 'User'").

## House shapes (read from origin/master in this worktree)

- Custom object: `Followup_Obligation__c.object-meta.xml` — AutoNumber nameField, sharingModel ReadWrite.
- Text field: `Followup_Obligation__c.Next_Action__c.field-meta.xml` — element order fullName, description, label, length, required, trackTrending, type, unique.
- Number formula: `Opportunity.Days_Close_Date_Overdue__c` — fullName, label, description, type, precision, scale, unique, formula.
- Checkbox formula: `Account.Wartungsvertrag_Renewal_Soon__c` — comparison operators MUST be XML-escaped (`&gt;=`, `&lt;=`).
- Currency: `Opportunity.Approved_Discount_Value__c` — fullName, label, description, externalId, required, precision, scale, type.
- Lookup on Opportunity: `Opportunity.Approval_Decided_By__c` — referenceTo, relationshipLabel, relationshipName, required, type.
- ValidationRule: `LossReason_PflichtBeiClosedLost` — `AND(ISPICKVAL(StageName, 'Closed Lost'), ISBLANK(TEXT(Loss_Reason__c)))`.
- Report with checkbox-gate filter: `reports/Sales/Wartungsvertrag_Renewals_3M` — `<column>Obj.Field__c</column><operator>equals</operator><value>1</value>`.
- Report grouping on a lookup: `Offene_Werte_Verlauf` uses `OpenOpportunityHistory__c$AccountId__c.Name`.
- Trigger refusing a save: `FollowupMonitoringHandler.refuseTypedValue` uses `System.AssertEquals(false, true, msg)`;
  `AuraHandledException` compiles but is runtime-restricted to Aura/Visualforce — unusable in a trigger.
- Trigger house shape: thin trigger file delegating to a `public without sharing class` handler; apiVersion 62.0 on triggers, 63.0 on classes.

## Deploy state / decisions

- (fill in as deploys land)
