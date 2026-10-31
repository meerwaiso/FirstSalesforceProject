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

## Developer ergbnungen (2026-10-31, alle measured in Test-Org)

- `after save` is NOT an Apex event token ("Unexpected token 'save'") — one block `(after insert, after update, after delete)`; `Trigger.new`/`Trigger.oldMap` are SObject AND null on the event that does not apply — unguarded `Trigger.oldMap.values()` threw NullPointerException and rolled the whole insert back. Guard for null.
- Apex Map method is `put`, not `set`. `Map<Id, Absence__c>` value type is refused ("no set(Id, Absence__c)") — keep plain Date/Id values in separate maps.
- `rec.Deputy__c.Name` → "A non foreign key field cannot be referenced in a path expression". Display names: one `SELECT Id, Name FROM User WHERE Id IN :ids`.
- SOQL column for the Account owner is `OwnerId`; `Owner` is only the relationship alias (report token `USERS.NAME`). `WHERE Owner IN :users` → "No such column 'Owner' on entity 'Account'".
- PS `<tabSettings><tab>Absence__c</tab>` → "no CustomTab named Absence__c found" (the object carries no customTab) → element removed.
- PS/report `<description>` must be ≤255 characters.
- Deploy manifest shape: `<types><members>X</members><name>ApexClass</name></types>` with xmlns `http://soap.sforce.com/2006/04/metadata`. The `<Types name=... members=...>` shape → "NothingToDeploy".
- Test class: `@isTest` on the CLASS and on every method; assertions are `System.assertEquals(exp, act, msg)` / `System.assert(cond, msg)`; `end` and `from` are reserved identifiers.
- Live state Test-Org: Absence `a04WU00000E0qWPYAZ` (Meerwais Osmani, 2026-10-31..2026-11-20, deputy devops-agent) mirrored on all 12 Accounts; PSA: AbsenceRead/AbsenceWrite → 005WU000017tEKLYA2 + 005WU000017tBhRYAU, DeputyAccess → nobody (per-absence grant). SCRUM457AbsenceSyncTest 7/7 green (RunSpecifiedTests).
- OWD of Account/Opportunity/Case NOT read back: no API exposes it, browser vault holds no saved login → not verifiable by the Developer. UNVERIFIED, assumed Private.
