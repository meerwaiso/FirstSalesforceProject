# SCRUM-457 — Notizen (Architect, 2026-10-31)

Hard-won findings; one line each. Read this first after any compaction.

- Surveyed `origin/master` @ `dc94b0bd5b3764d867b2892cedc3d4fddf6cfd9c`; worktree `../wt-scrum-457`, branch `feature/scr457-absence`.
- `Account.AccountAccess` absent in Test-Org — 2 routes: `sf sobject describe --sobject Account` (no *Access*/*Share* field) + SOQL `No such column 'AccountAccess'`.
- Org custom objects (Test-Org): CaseRebuildRun__c, CustomerTransfer__c, DiscountApprovalManager__c, OpenOpportunityHistory__c — no absence object.
- `User` has exactly one custom field: SCRUM428_Verfuigung__c (boolean). Lookup/Reference on User rejected by platform (skill §7b) => absence must be its own object with Lookup->User.
- House shape for Lookup->User: CustomerTransfer__c (SCRUM-410) — From_User__c/To_User__c, relationshipName, required=false; object Private + AutoNumber nameField.
- `Role` object exists (tooling API) but ALL 8 Test-Org users have `UserRoleId = null` — PO assumption 5 not testable in Test-Org.
- 197 Accounts in Test-Org; owners Meerwais Osmani + devops-agent + Automated Process.
- OWD of Account/Opportunity/Case is NOT exposed by any API: `sobject describe`, `ui-api/object-info/<Obj>`, `sobjects/<Obj>/describe` all lack a sharing field. Setup read-back only.
- No FlexiPage on Account in Test-Org (only BetreuungsuebergabePage on User) => Account record page follows the Account layout (repo-tracked).
- AccountList report type: `ACCOUNT.NAME`, `USERS.NAME`=Account Owner (Account.Owner.Name); scope values user/team/**organization**/scopingRule, default user.
- Report filter shape: `<filter><criteriaItems><column/><operator/><value/></criteriaItems></filter>` — `<criteria>`, `<field>`, `<reportFilters>` all rejected; schema in `@salesforce/types/lib/metadata.d.ts`. Dry-run-validated.
- Reports are inFolder=true: a report under `reports/<Folder>/` needs `reports/<Folder>.reportFolder-meta.xml`, else "Incomplete folder path".
- Dry-run 9/9 Created (Test-Org): Absence__c + Absent_User__c/Deputy__c Lookup->User + Start__c/End__c Date + Account.Absence_Start__c/Absence_End__c Date + Account.Absence_Deputy__c Text(80) + Account.Absence_In_Window__c Text-formula with `&&` and `Absence_Start__c - TODAY() <= 14`.
- Deploy order matters: PS referencing a new field fails `no CustomField named ... found` until the field is deployed. fields -> PS -> report.
- `System.runAs` is refused outside test methods (`sf apex run` -> "System.runAs can only be used within a test method") — OWD/visibility probes need an @isTest class, not a script.
- `Role` is not a valid Apex sObject type (compile error "Invalid type: Role"); query it via `--use-tooling-api` SOQL only.
- PSA house shape: `insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);` (from *FlsTest classes). Cross-object bulk update idiom: `update accounts;` (CustomerTransferJob).
