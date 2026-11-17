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

Phase 1 `manifest/scr461-phase1-fields.xml` — deployed (NoTestRun).
Phase 2 `manifest/scr461-phase2-referencing.xml` — deployed (validation rule, 3 PS, 2 reports, layout).
Phase 2b `manifest/scr461-phase2b-reports.xml` — deployed (reports with explicit timeFrameFilter).
Phase 3 `manifest/scr461-phase3-guard.xml` — deployed (guard class + trigger + 2 test classes).

Measured findings that changed the shape:

- Lookup CustomField: `<relationshipOrder>` / `<reparentableMasterDetail>` are rejected
  ("Can not specify relationshipOrder for a CustomField of type Lookup") — house
  `Approval_Decided_By__c` carries neither.
- Report grouping: `Opportunity$Competitor_Lost_To__c.Name` → "Invalid field name";
  a Text formula mirror `Competitor_Lost_To__c.Name` is rejected by deploy-validate.
  Grouping directly on `Opportunity.Competitor_Lost_To__c` validates and deploys.
- Manifest member names use `<members>`/`<name>`; a `<member>`/`<type>` block is
  rejected ("Invalid types definition in manifest file").
- ValidationRule manifest member must be entity-qualified: `Opportunity.Competitor_PflichtBeiWettbewerber`.
- `sf data create record`: the object is `-s/--sobject`; `-t` is `--use-tooling-api`,
  which PermissionSetAssignment needs. Field pairs separated by SPACES.
- The org adds a `timeFrameFilter` CLOSE_DATE / INTERVAL_CURRENT to a new report on its
  own; deploying without the element does NOT clear it. Set explicitly to
  INTERVAL_CUSTOM 2000-01-01..2099-12-31 (house Hoeh_Risk_Chancen), so
  Lost_Last_12M__c is the rolling twelve months.
- Apex `insert` of a typed custom object is NOT blocked by object-level create
  permissions: `isCreateable()` reported false for a read-only user, yet the insert
  saved. The enforceable assertion is the describe() flag (the Setup picker and the
  API read that); the UI half of AC4 belongs to the Tester.
- User `Alias` max length is 8 characters.
- A SOQL row must select every field a test reads, otherwise
  "SObject row was retrieved via SOQL without querying the requested field".
- `cloneIdOnly()` does not exist on a typed sObject — build `new Competitor__c(Id = x.Id)`
  before `update` (AutoNumber Name is not writeable).
- RunRelevantTests requires >= 75% coverage on the deployed class; the update half of
  the guard needed its own test method.

PSA read-back (2026-11-17, `sf data query`): all 6 assignments exist — both
`devops-agent@cline.test` and `meerwais.osmani@resourceful-bear-6f1u4j.com` hold
SCRUM461_Competitor_Lost, SCRUM461_Competitor_List_Read, SCRUM461_Competitor_List_Teamleitung.
Field read-back through that session: `SELECT Competitor_Lost_To__c, Competitor_Price__c,
Competitor_Gap__c, Lost_Last_12M__c FROM Opportunity` returns 3 rows.
`scripts/fls-gate.py --base origin/master --org Test-Org` → green (4 fields ok,
Company_Name__c skipped because required=true).

## Rework 2026-11-17 (Architect rejection: Name = company name)

- A custom object's `Name` can be `Text` with a `<length>`; the org echoes
  `<nameField><label>Competitor Name</label><type>Text</type></nameField>` and drops
  the length element — retrieve the org version and commit that (ADR-7).
- While `Name` is still `AutoNumber` in the org, Apex cannot assign it:
  `Field is not writeable: Competitor__c.Name`. Deploy the object with the Text
  `nameField` FIRST, then the classes that write it.
- `sf project delete source` refuses a field that deployed Apex still references:
  "This custom field is referenced elsewhere in Apex Class - …". Redeploy the classes
  without the reference, then delete the field. Order: object → classes → delete.
- `sf project delete source -m` wants the SDR component form `CustomField:Obj.F__c`;
  the bare `Obj.F__c` is a RegistryError.
- `deploy start` takes `-d/--source-dir`, not `-p` (that flag belongs to
  `delete source`).
- `deploy validate` rejects `--test-level NoTestRun` (only the four test levels);
  `RunRelevantTests` ran 0 tests for this manifest — use
  `--test-level RunSpecifiedTests --tests <TestClass>` once per class to actually run
  them. Measured: 15/15 green over the three SCRUM-461 classes plus the fixed
  SCRUM381LostReasonTest.
- A new blocking ValidationRule reddens existing test classes of other tickets that
  save the blocked state — `SCRUM381LostReasonTest` inserted Closed Lost +
  `Loss_Reason__c = Wettbewerber` with no competitor. Fixed by moving its fixture to
  `ZuTeuer` (rule not weakened), and the class now travels in
  `manifest/scr461-phase3-guard.xml`.
