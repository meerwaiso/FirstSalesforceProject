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

## Rework after the Architect rejection (2026-10-31, measured)

- OWD measured by the Tester in Setup: Account / Opportunity = **Public Read/Write**, Case = **Public Read/Write/Transfer** (external access Private, no sharing rules). So `SCRUM457_DeputyAccess` (viewAllRecords) grants nothing the OWD does not already give every internal user and can never revoke it → **deleted** from org and branch (`sf project delete source -m PermissionSet:SCRUM457_DeputyAccess -r`). AC4 is org-wide access; AC5 is met only by its own "unless they had it anyway" clause.
- `System.runAs(user)` takes ONE argument in this API; the two-argument form with a Profile is refused ("runAs requires a single argument of type 'User' or 'Version'"). Measured.
- Triggers run in USER mode: `AbsenceSyncHandler`'s SOQL on the Account mirror fields is FLS-blocked for an acting user without read FLS → "No such column 'Absence_Start__c' on entity 'Account'" → the whole Absence__c create rolls back (CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY). Fix: `SCRUM457_AbsenceWrite` now also carries read FLS on the six Account mirror fields, so the Write PS is self-sufficient. This also makes the AC1 negative test satisfiable.
- AC8 measured live in Test-Org: absence `a04WU00000E0r97YAB` (autoproc owner, 2026-11-02..2026-11-12, NO deputy) → 13 Accounts in window, **1** carries `OHNE DEPUTY`. `Absence_Anzeige__c` stays blank there because the absence starts in the future (deliberate AC3/AC8 split).
- `Absence_Anzeige__c` formula now one language + one marker: `Abwesent <start> bis <end> - Deputy: <name>` / `... - OHNE DEPUTY`. Read back: "Abwesent 2026-10-31 bis 2026-11-20 - Deputy: devops-agent".
- Tests: 11/11 green (RunSpecifiedTests, Test-Org) — AC1 positive (create under the Write PS) + AC1 negative (blocked without it), AC4 deputy edits a non-owned customer's open Opportunity/Case under `System.runAs(deputy)`, AC8 no-deputy marker on 3/3 rows.

## Architect revision 2 (2026-10-31, after the user's confirmed answers)

- Branch head moved to `c3b3206` by the Tester (E2E spec + tester notizen) — written against the OLD AC list, superseded.
- House has NO ValidationRule (`git grep -l validationRules origin/master -- force-app/main/default/objects/` -> no file) and NO `$Permission` merge field in any Apex file -> the AC1 own-deputy guard has no precedent; must be compile-proven, not assumed.
- `$Permission.X` and even `$User.Name` are refused in an `sf apex run` SCRIPT ("Variable does not exist") — the script compiler has no merge fields. A script probe proves nothing about a class/trigger; only the class deploy (CI smoke) compiles it.
- No PS in the repo carries `userPermissions` (`git grep -l userPermissions origin/master -- permissionsets/` -> no file) -> the house never grants RunReports; the overview is reachable through the report's Setup sharing (S3), not through a PS.
- Report at head already carries the marker column `Account.Absence_Ohne_Deputy__c` -> AC10 needs no new report, only a wider marker formula + two new Date mirror fields.
- AC10 makes the recompute BIDIRECTIONAL: changing the deputy's own absence must re-flag the manager's customers. A one-directional handler leaves a stale marker.
- Mirror the deputy's own window as two Date fields, not a boolean: a boolean written at save time is wrong the day the deputy's absence ends and would need a nightly job (forbidden: nothing automatic).
- Team-lead PS naming = house: `SCRUM457_Absence_Teamleitung` (cf. SCRUM428_Teamleitung, SCRUM431_..._Teamleitung, SCRUM451_..._Teamleitung).

## Developer rework 2 (2026-10-31, design revision 2) — measured while implementing

- `SavePointError` is NOT an Apex type in this org: the class deploy says "Invalid type: SavePointError (203:23)" and the trigger deploy says the same at its own line. The house exception type is `AuraHandledException` (`git grep -n "throw new" force-app/main/default/` → SCRUM428ContactFormController, CustomerTransferController). The guard check lives in the handler (`ownDeputyViolation()`), the throw lives in the trigger body.
- Valid trigger event tokens are the six explicit ones; `after save` refused (measured earlier). The context flags that split before/after are `Trigger.isBefore` / `Trigger.isAfter` — `Trigger.beforeInsert` is refused ("Variable does not exist: beforeInsert (22:9)"). Without the split the handler also runs in the before-events and would read the not-yet-saved record.
- The Apex SOQL parser refuses `TODAY()` inside a query that also binds a set ("Expecting ']' but was: '(' (118:75)"); bind a `Date today = Date.today()` instead.
- `consider()` reads `rec.Deputy__c`, so EVERY query whose records go through it must SELECT `Deputy__c` — Q3 without it → "SObject row was retrieved via SOQL without querying the requested field: Absence__c.Deputy__c".
- FLS `editable` is what lets the handler write a field in user mode: with `editable=false` on the five Apex-written mirror fields, a create under `System.runAs(teamLead)` fails "fields being inaccessible on Sobject Account". The two write PSs therefore carry `editable=true` on those five; the three formula fields stay `editable=false`. `SCRUM457_AbsenceRead` stays read-only.
- Apex identifiers are case-INsensitive: `PermissionSet teamlead` collided with `User teamLead` ("Duplicate variable: teamlead (414:23)").
- `User.Alias` is Text(8): `mkUser('colleague')` → STRING_TOO_LONG. Aliases in this test class must stay ≤8 chars.
- PS assignment read-back: `assign-teamlead.apex` (sf apex run) assigned `SCRUM457_Absence_Teamleitung` to the CLI user `005WU000017tEKLYA2` (devops-agent@cline.test, = `UserInfo.getUserId()`) and to `005WU000017tBhRYAU`; the second iteration of the same script found the first insert already present, i.e. the assignment is visible through a real session. A `sf data query` on PermissionSetAssignment returns nothing (Tooling API), so the Apex read-back is the evidence.
- `FieldPermissions` is NOT queryable in Apex (compile failure) and `FieldPermission`/`FieldPermissions` are NOT supported by `sf data query --use-tooling-api`. The live read-back that works is `sf project retrieve start --metadata "PermissionSet:<Name>"` — it returns the deployed FLS flags.
- FLS `editable` had to be true in BOTH write sets. The first rework changed only `SCRUM457_AbsenceWrite`; the live retrieve showed `SCRUM457_Absence_Teamleitung` still `editable=false` on the five mirror fields, and the team-lead test still failed "fields being inaccessible on Sobject Account". After the second deploy both retrieves report 5× `editable=true`.
- `sf data delete record` requires `-s/--sobject` as well as `-i`; without it the CLI prints its usage and deletes nothing (measured — the record was still in the org afterwards).
- AC10 live proof (Test-Org, 2026-10-31): absence `a04WU00000E0x1dYAB` for the deputy `005WU000017tEKLYA2` (2026-10-31 → 2026-11-06, deputy `005WU000017tBpWYAU`) → all 12 Accounts owned by `005WU000017tBhRYAU` carry `Absence_Ohne_Deputy__c = 'OHNE DEPUTY'` and the mirrored window. After `sf data delete record -s Absence__c -i a04WU00000E0x1dYAB` the same 12 rows read `Absence_Ohne_Deputy__c = null`, window fields null, `Absence_Deputy__c = 'devops-agent'` still shown.
- Apex test run with `--test-level RunSpecifiedTests --tests SCRUM457AbsenceSyncTest`: Status Succeeded, Passing 15, Failing 0, Total 15.
