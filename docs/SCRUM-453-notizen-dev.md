# SCRUM-453 — Developer-Notizen (hard-won findings, 2026-10-22)

Read before re-deriving. Every line names the command that produced it.

## Carried over from the Architect (docs/SCRUM-453-notizen.md, verified there)

- Org `Test-Org`, apiVersion 68.0, CLI user `devops-agent@cline.test` — `sf org display`.
- `UserInfo.getUserId()` compiles + returns the running user Id; `$User`/`$Profile` do NOT compile in `sf apex run`.
- `PermissionSetAssignment` SOQL fields are `AssigneeId` / `PermissionSetId` (not `Assignee`).
- `PermissionSet` is SOQL-queryable by `Name`.
- 649 Contact, 195 Account; 139 Contacts carry an AccountId; 74 Accounts have >=1 Contact (max 4).
- Contact consent fields: `NewsletterConsent__c` (Checkbox), `ConsentDate__c` (Date) — must stay untouched.
- `AccountList` report type: 82 columns, `ACCOUNT.NAME` + `USERS.NAME` present, `OWNER_FULL_NAME` NOT.
- 0 Contacts marked today → AC-8 matches zero records until fixtures exist.

## House shapes read from origin/master (2026-10-22)

- Guard that must refuse a save: `OpportunityLockedAccountGuard` → `addError` per record, `without sharing`, 1 SOQL per batch, no SOQL in a loop.
- Rollup on Account: `OpenOpportunityRollupHandler` + `OpportunityOverdueReset` (after insert/update/delete), full recompute, write only on actual change.
- Read/write PS split: `SCRUM388_AccountReactivation` (readable/editable=false) + `SCRUM388_AccountReactivationWrite`.
- Number field with `<precision>6</precision><scale>0</scale><defaultValue>0</defaultValue>` — `Account.Open_Opportunity_Count__c`.
- Text formula field takes NO `<length>` — `Case.Wartungsvertrag_Anzeige__c` (references the Account lookup as `Account.X__c`).
- ListView columns are prefixed `Contact.Field__c` — `objects/Contact/listViews/Kritische_Kontakte.listView-meta.xml`.
- AccountList report with custom-field columns + filter + `ACCOUNT.NAME` grouping, NO timeFrameFilter — `reports/Sales/Miserable_Kunde_Satisfaction.report-meta.xml`.
- Manifest member for a report must be folder-qualified: `Sales/<Name>` (memory, verified at deploy).

## My own findings this ticket

- (deploy log appended below as it happens)

## Measured during implementation (2026-10-22, all commands against Test-Org)

- **A 4th Permission Set was needed and is NOT in the design**: `SCRUM453_ContactLeft_System`
  (editable+readable on the three Account aggregates). Measured: with only
  `SCRUM453_ContactLeft_Read` the trigger's `update` on Account fails under
  `System.runAs` with "Operation failed due to fields being inaccessible on Sobject
  Account"; granting `SCRUM451_TestObjectAccess` (object-level CRUD on Account) does
  NOT change that. House shape: SCRUM442_Satisfaction_System / SCRUM436_CaseReminderSystem.
  Apex DML checks FLS even in `without sharing` (ADR-5).
- **PS assignment is required before the tests mean anything**: an unassigned PS left
  the handler's aggregate SOQL failing with `No such column 'Contacts_Without_Mark__c'`
  — a permission, not an absent field.
- **Undo PS assigned to the two SCRUM428_Teamleitung holders** (query:
  `PermissionSetAssignment WHERE PermissionSet.Name='SCRUM428_Teamleitung'` -> exactly
  devops-agent@cline.test and the human test account). Consequence: a negative undo test
  in the *functional* class (running user = CLI user) is unsatisfiable by construction;
  AC-6 negative/positive live only in SCRUM453ContactLeftFlsTest with own runAs users.
- `User.Alias` max length 8 -> `STRING_TOO_LONG` for longer fixture tags.
- `Task` has no `ContactId`; the Contact/Lead lookup on Task is `WhoId`
  (FieldDefinition query, DataType `Lookup(Contact,Lead)`).
- SOQL bind must be an Id variable: `WHERE Id = :cs` with a `Case cs` sObject ->
  "Invalid bind expression type of Case for column of type Id".
- `set` and `from` are reserved identifiers in Apex.
- Contact has NO `CompanyName` field (the compiler said so; `LastName` is fine).
- `.cls-meta.xml` / `.trigger-meta.xml` are mandatory: without them the CLI answers
  `ComponentSetError: No source-backed components present in the package`.
- Report: `ACCOUNT.NAME` may only be a grouping, not also a column
  ("You can't include groupings in the selected columns list").
- Report drift: the org adds `<params>co=1` and `timeFrameFilter DUE_DATE/INTERVAL_CUSTOM`
  on its own -> repo file replaced by the retrieved metadata (ADR-7).
- Test result: 17/17 green with `--test-level RunSpecifiedTests --tests <both classes>`.
