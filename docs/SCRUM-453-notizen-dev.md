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
