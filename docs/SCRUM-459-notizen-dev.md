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

## Rework round 2 (measured 2026-10-31, after Architect comment 23584)

- CI smoke failed with `Process completed with exit code 100` (annotations carry no test detail):
  `gh api ".../check-runs/<jobId>/annotations"` is the way to read a red CI job when the run log is
  still unavailable - the run log needs the WHOLE run to finish, the annotations do not.
- Cause was a race, not the code: CI runs `sf apex run test --test-level RunSpecifiedTests --class-names ...`
  against the ORG, and it started while my phase3/3b/4 deploys were still in flight, so it executed the
  OLD test class (the one with the MIXED_DML failure). Reproducing CI's exact command after the deploys
  landed: 15 tests, Pass Rate 100%, Outcome Passed.
- MIXED_DML_OPERATION in `readBackUnderSalesRepPermissions`: `PermissionSetAssignment` is a setup object;
  creating a `Followup_Obligation__c` in the same transaction fails in either order. Fix: the fixture moved
  into `setup_fixtures` (own transaction), assertions unchanged.
- Guard skip narrowed from a static Boolean to `Set<Id> systemWrittenIds` + `try/finally` clear: a throw at
  the update statement no longer leaves the guard skipped for the rest of the transaction (round-2 nit).
- `sf apex run test` counts 15 tests for the two classes (deploy `--test-level` reported 13); the number
  CI prints is not the number the deploy prints - compare outcome, not counts.

- Third PS `SCRUM459_FollowupMonitoring_Write` (six fields read=true edit=true, NO objectPermissions) deployed and
  assigned to BOTH Test-Org users; `scripts/fls-check.sh` then shows all six fields granted edit=true by it.
- That grant alone did NOT fix the tests. Measured with a scratch probe (`sf apex run`):
  * handler `recalculate` still failed at the `update` line with "fields being inaccessible on Sobject Opportunity";
  * the same six fields written inline by the same user succeeded;
  * with the guard trigger INACTIVE the handler write succeeded.
- Root cause: `update` writes EVERY field in the record's cache. The Q1 record carries `IsClosed`, and the
  compiler rejects it outright - `o.IsClosed = true;` -> "Field is not writeable: Opportunity.IsClosed".
  Fix: the handler and the AC8 test now update FRESH sObjects whose cache holds only Id + the written fields.
- Exception types for a save refusal, measured by dry-run compile: `Salesforce.ErrorException`,
  `ApexException`, `UserOperationException`, `InternalError`, `UnknownError`, `Custom`, `Range`, ... are all
  "Invalid type". Only `AuraHandledException` compiles - and at runtime it is restricted
  ("Can only throw this exception type from VisualForce or Aura context"). A trigger therefore refuses a save
  with `System.AssertEquals(false, true, msg)` (AssertionError), which also carries the message.
- Reserved Apex identifiers hit twice in this ticket: `bulk` and `after` ("Unexpected token").
- Anonymous Apex (`sf apex run`) parser quirks measured: a query cannot be assigned to a single sObject
  (`Opportunity x = [SELECT ...]` -> "Unexpected token"), and `WHERE Id IN someId` needs the bind form `IN :set`.
- Final state: 13/13 Apex tests green (`RunSpecifiedTests`, both classes), including
  `ac6_userTypedMonitoringValue_refusedAndStoredValueUnchanged` and `readBackUnderSalesRepPermissions`.
- AC6 is now an Apex contract, not an FLS property: `OpportunityFollowupGuardTrigger` (before update) calls
  `FollowupMonitoringHandler.assertNoUserTypedValues(Trigger.new, Trigger.oldMap)`; the handler's own write is
  skipped by a static flag (house shape: static `hasFired` in `OpportunityOverdueResetHandler`).

## SCRUM-460 — record pages (measured 2026-11-01, dry-run + deploy + retrieve)
- FlexiPage record pages live in `force-app/main/default/flexipages/`. `objects/<Obj>/flexiPages/` is rejected
  by SDR type inference for BOTH a custom object and a standard one:
  `TypeInferenceError: Unexpected child metadata [...] found for parent type [CustomObject]`.
  The house User page sits in that folder but this CLI version never deploys it from there.
- Field instance shape, taken from the official `forcedotcom/salesforcedx-templates` RecordPage template
  (rendered, no template tags): `<fieldInstance>` with `fieldInstanceProperties` `uiBehavior`
  (`none` | `readonly` | `required`), `<fieldItem>Record.<ApiName></fieldItem>`, `<identifier>`;
  the fields sit in a Facet -> `flexipage:column` (property `body`) -> facet -> `flexipage:fieldSection`
  (properties `columns`, `horizontalAlignment`, `label` = section heading) -> `detailTabContent` facet.
- `Record.<field>` takes the API name from `sf sobject describe`, not the Apex shorthand:
  Opportunity has `AccountId`, `StageName`, `OwnerId` — `Account`, `Stage`, `Owner` do not exist as fields.
- `<description>` of a FlexiPage is capped at 255 chars ("Value too long for field: Description maximum length is:255").
- Org read-back after deploy (`sf project retrieve start --metadata "FlexiPage:<Name>"`) proves the artefact EXISTS,
  not that it renders. Both FlexiPages existed; neither rendered (see below).
- **A deployed FlexiPage RecordPage is never activated as the record page.** Measured 2026-11-01 with
  `sf api request rest "/services/data/v62.0/ui-api/record-ui/<recordId>?layoutTypes=Full&modes=View" --target-org Test-Org`:
  for a User record the org returns the default layout (About/Contact/Background), not the house
  `BetreuungsuebergabePage`; for a `Followup_Obligation__c` record it returns the auto default (Name, Owner),
  not my RecordPage. FlexiPage is the wrong mechanism for record pages here.
- **The record page of an object is its Layout, and the default layout of a custom object is named
  `<ObjectName>-<object label> Layout`.** House proof: `CaseRebuildRun__c` label "Korrekturlauf Offene Faelle"
  -> file `CaseRebuildRun__c-Korrekturlauf Offene Faelle Layout.layout-meta.xml`, deploy state Changed, renders.
  A differently named file creates a SECOND, inactive layout (deploy state Created; the rendered page keeps
  the old default). `Followup_Obligation__c` label is "Follow-up Obligation" -> file
  `Followup_Obligation__c-Follow-up Obligation Layout.layout-meta.xml`.
- `/ui-api/record-ui` is the verification tool for "what does the user see": sections + fields + apiNames.
  `modes=Modify` is rejected (`ILLEGAL_QUERY_PARAMETER_VALUE`); `modes=View` works.
- Org read-back after the layout fix: Opportunity page = 9 sections incl. "Follow-up Monitoring" with the six
  fields (Discount Approval 8, Risk Level 6 and the rest intact); obligation page "Information" carries
  `Opportunity__c`, `Status__c`, `Due_Date__c`, `Next_Action__c`, `Completed_Date__c`.
- Deleting org metadata: `sf project delete source -o Test-Org -m "Layout:<name>" -r` (`--check-only` first).
  Used to drop both FlexiPages and the stray second layout.
