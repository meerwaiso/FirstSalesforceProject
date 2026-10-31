# SCRUM-459 — Developer notizen (2026-10-31)

Hard-won findings for this ticket; the build spec is `docs/SCRUM-459-design.md`.

- Deploy order used: phase1 object+fields -> phase2 PSs -> phase2b list view -> phase3 handler ALONE -> phase3b triggers -> phase4 test classes. Helper-before-consumer rule (a trigger deployed with its handler in one batch compiles against the OLD live handler).
- `sf project deploy start --manifest <file>` only; `-m` misparses Field types (house).
- Validation: `sf project deploy validate` always runs tests — the org's 24 h Apex budget applies.
- Test-Org users for the PS assignment: see handoff comment (CLI user + human account).

## Deploy results (measured 2026-10-31, Test-Org)

- phase1 fields+object OK, phase2 both PSs OK, phase2b list view OK, phase3 handler OK, phase3b both triggers OK.
- ListView manifest member must be FOLDER-QUALIFIED: `<members>Opportunity.Follow_up_Monitoring</members>`. Bare `Follow_up_Monitoring` -> "No source-backed components present in the package" (exit 1, empty result).
- `bulk` is a RESERVED token in the Apex parser: `List<Followup_Obligation__c> bulk = ...` -> "Unexpected token 'List'" + "Unexpected token 'bulk'". Renamed to `obligations`. Verified with a scratch probe class (dry-run compile, 0 errors with `l`, 10 errors with `bulk`).
- `User.Alias` max length 8: `fls459neg` -> STRING_TOO_LONG. Shortened to `fls459n` / `fls459p`.
- `sf org assign permset -n <PS> -o Test-Org -b <username>` is the assignment command (there is no `org permset add/remove`; PS deletion needs Apex DML).
- `PermissionSetAssignment` has no `PermissionSetName`/`Assignee` column — query `PermissionSetId`/`AssigneeId` (measured: "No such column 'PermissionSetName' on entity 'PermissionSetAssignment'").
- `FieldPermission` is not a queryable sObject; use `scripts/fls-check.sh <Object> <Field__c>` for the three-query chain.

## The blocker: trigger writes need Edit, no PS grants it

- 11 of 13 Apex tests fail at `FollowupMonitoringHandler.recalculate` line 187 = `update toUpdate;`
  -> `System.DmlException: Operation failed due to fields being inaccessible on Sobject Opportunity`.
- Trigger code runs in USER mode, so FLS applies to its writes. `scripts/fls-check.sh Opportunity Followup_Required__c` after deploy:
  granted ONLY by `SCRUM459_FollowupMonitoring_Read` with `read=true edit=false`, assigned to both Test-Org users.
  No PS in Test-Org grants edit on the six monitoring fields -> the trigger can never write for any non-System-Administrator user.
- House precedent for the same shape (SCRUM-449): `SCRUM449OpportunityRisk` (read=true edit=false) PLUS a separate
  `SCRUM449OpportunityRiskWrite` (read=true edit=true), assigned to the CLI user only. That is the shape that makes a trigger write work.
- The SCRUM-459 design says "exactly two PSs" and gives the six fields editable=false in both -> not implementable as written.
  Escalated to the Architect; no third PS created by me.
