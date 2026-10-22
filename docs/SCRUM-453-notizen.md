# SCRUM-453 — Notizen (hard-won findings, Architect 2026-10-22)

Read these before re-deriving anything. Every line names the command that produced it.

## Org facts (Test-Org)

- Org alias `Test-Org`, apiVersion 68.0, CLI user `devops-agent@cline.test` — `sf org display`.
- Role hierarchy: 18 roles, standard sample tree — `sf data query --use-tooling-api --target-org "Test-Org" --query "SELECT Name, ParentRole.Name FROM Role ORDER BY Name"`.
- `SCRUM428_Teamleitung` exists, **2 holders**: `devops-agent@cline.test`, `meerwais.osmani@resourceful-bear-6f1u4j.com` — `sf apex run` probe (PermissionSet + PermissionSetAssignment query).
- `UserInfo.getUserId()` compiles and returns the running user Id (`005WU000017tEKLYA2`) — `sf apex run` probe.
- `$User` and `$Profile` do **NOT** compile in `sf apex run` — probe, same day. Do not plan on them.
- `PermissionSetAssignment` SOQL fields are `AssigneeId` / `PermissionSetId` (not `Assignee`) — UI-API describe `/services/data/v60.0/sobjects/PermissionSetAssignment/describe` + house test classes.
- `PermissionSet` is SOQL-queryable: `[SELECT Id, Name, Label FROM PermissionSet WHERE Name = '<ApiName>']` — probe.
- Counts: 649 Contact, 195 Account; 139 Contacts have an AccountId, 74 Accounts have ≥1 Contact (11×1, 62×2, 1×4) — `sf data query ... --result-format csv --output-file` + count.
- Contact has 82 fields; consent fields are `NewsletterConsent__c` (boolean) and `ConsentDate__c` (date), both plain (no formula) — Contact describe.
- Case has 5 formula fields, **none references a Contact lookup**; `ContactId` exists on Case — Case describe. ⇒ the cross-object Contact reference in a Case formula is unverified here.
- `AccountList` report columns (Analytics API `/services/data/v60.0/analytics/reportTypes/AccountList`): 82 columns; `ACCOUNT.NAME`, `USERS.NAME` present; `OWNER_FULL_NAME` NOT present for this report type; scope values `user|team|organization|scopingRule`, default `user`.

## Repo facts (origin/master @ 3d65b136508315912c5fa0212c396782bee5cc9b)

- No Salesforce Flow in the repo (only `.github/workflows/` matched `flows/`).
- No `sharingRules` artefact → sharing is OWD-only.
- No `Rollup`-type field anywhere; Account aggregation is Apex (`OpenOpportunityRollupHandler`, SCRUM-416).
- House read/write PS split: `SCRUM388_AccountReactivation` + `SCRUM388_AccountReactivationWrite`.
- Report filter shape: `<filter><criteriaItems><column>…</column><columnToColumn>false</columnToColumn><isUnlocked>false</isUnlocked><operator>equals</operator><value>1</value></criteriaItems></filter>` — `Morgen_UEbersicht_Vertragskunden.report-meta.xml`.
- Text formula fields take **no `<length>`** — SCRUM-451/394.

## Tool quirks hit today

- `sf data query`: target org flag is `-o/--target-org`; `-t` is `--use-tooling-api` (boolean). `-t Test-Org` → "Unexpected argument".
- `sf sobject describe` uses `-s/--sobject`, not `--object-name`.
- SOQL `SELECT COUNT() FROM Contact GROUPBY AccountId` → "unexpected token: GROUPBY" (aggregate COUNT() with GROUPBY not supported); fetch the lookup column and count locally.
- `sf api request rest` has no `--output-file`; redirect stdout.
