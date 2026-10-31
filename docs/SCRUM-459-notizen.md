# SCRUM-459 — Architect notizen (2026-10-31)

Hard-won findings; the design itself lives in `docs/SCRUM-459-design.md`.

- Dry-run validation command: `sf project deploy start --source-dir scratch/459-dryrun --target-org Test-Org --dry-run --wait 10 --json` → 14/14 components `Succeeded`, 0 errors. Probe dir stays in `scratch/459-dryrun/` (gitignored).
- Lookup relationship field: `reparentableLookupDepartment` is REJECTED (`Element ... invalid at this location in type CustomField`); `relationshipOrder` is REJECTED for type Lookup (`Can not specify 'relationshipOrder' for a CustomField of type Lookup`). Working shape = fullName/description/label/referenceTo/relationshipLabel/relationshipName/type=Lookup/writeRequiresMasterRead.
- Checkbox custom field REQUIRES `<defaultValue>` (`Must specify 'defaultValue' for a CustomField of type Checkbox`).
- Number field house shape = `<precision>6</precision><scale>0</scale><unique>false</unique><defaultValue>0</defaultValue>` (from `Contact/fields/Open_Cases_Count__c.field-meta.xml`).
- ListView: `<filterList>` REJECTED (`Element filterList invalid at this location in type ListView`) → house `<filters><field/><operation/><value/></filters>` + `<filterScope>Everything</filterScope>`. Column shape that resolves: standard columns as tokens `OPPORTUNITY.NAME` / `OPPORTUNITY.AMOUNT` / `OPPORTUNITY.STAGE_NAME`; custom fields as BARE API names (`Followup_Required__c`). `Opportunity.Name`, `Opportunity.NAME`, bare `NAME` all fail with `Could not resolve list view column`.
- Org counts measured 2026-10-31 Test-Org: 130 Opportunities, 76 open, 13 open with Amount>50000, **0 open with Amount exactly 50000** → the strict-threshold boundary AC matches zero records, needs a fixture.
- `FieldDefinition WHERE EntityDefinition.QualifiedApiName='Opportunity' AND QualifiedApiName LIKE '%__c'` → 29 custom fields, no collision with the six new names.
- `AssignmentRule` in Test-Org: only Case and Lead — none on Opportunity → no second save cycle.
- `sf project retrieve start --metadata "CustomObject:OpenOpportunityHistory__c"` → the house child object uses a MasterDetail FIELD (`AccountId__c`, `<type>MasterDetail</type>`, `relationshipOrder 0`) + `sharingModel=ControlledByParent`; the repo's committed object-meta carries NO relationship element (the relationship lives in the org).
- `System.runAs` is refused outside test methods (measured 2026-10-31, SCRUM-457) → FLS/negative-access questions need an @isTest class, `sf apex run` cannot answer them.

- Writing the six Opportunity fields fires `OpportunityFollowupMonitorTrigger` again; the relevance filter (IsClosed/Amount changed) is the termination guard. Unlike SCRUM-416 (Account write → no Opportunity trigger), here the trigger DOES fire.

## PR round 1 review (2026-10-31, head ce6fb99c5e467f7af0a8b54733521ccf9d5e86e3)

- CI on the PR head (`gh pr checks 181`): Lint & Format pass, Prod-Org Drift Gate pass, **Metadata, Apex & Session Smoke FAIL**, README pass. Merge state UNSTABLE — no merge possible.
- `scripts/fls-check.sh Opportunity Followup_Required__c` → granted ONLY by `SCRUM459_FollowupMonitoring_Read` (read=true edit=false), 2 users. No PS grants edit on the six fields.
- Handler read at head: typed Opportunity records, one `update toUpdate` at line 187. Triggers run in user mode → FLS applies → 11/13 Apex tests fail with `fields being inaccessible on Sobject Opportunity`.
- Probe: `System.runAs_Use(String)` does not exist (`Method does not exist or incorrect signature: void runAs_Use(String) from the type System`) — a trigger cannot borrow a Permission Set.
- House precedent verified in repo + org: `SCRUM449OpportunityRiskWrite` = 5x editable=true (assigned to 1 user, the CLI user), `SCRUM449OpportunityRisk` = 0x editable=true (2 users). The SCRUM-449 sentence "the trigger path needs no Write-PS" does NOT reproduce for a user holding only the Read PS — measured opposite today.
- Apex test coverage at head: `SCRUM459FollowupMonitorTest` covers AC1, AC2, AC3, AC4, AC5, AC7, AC8, AC9, AC11 + obligation-delete recompute + read-back under rep permissions; `SCRUM459FollowupFlsTest` covers AC12 + the read-only assertion. AC6 (typing refused) and AC10 (list-view filter) have no artefact yet — AC10 belongs to the Tester's E2E, AC6 to the new guard + an Apex test.
- Verdict: **REJECTED** — the write path is not implementable as designed. Amendment written into `docs/SCRUM-459-design.md` (three PSs + Apex guard for AC 6).

## PR round 2 review (2026-10-31, head ee5a0e86cd64314922d0ddf8ea05ee6d0d75558c)

- CI on this head (`gh pr checks 181` + job list via `gh api .../actions/runs/41235053024/jobs`): Lint & Format pass, README pass, **Metadata, Apex & Session Smoke FAIL** (job 124637002432), **Prod-Org Drift Gate in_progress**. Not mergeable.
- The smoke job's log IS readable: `gh api repos/.../actions/jobs/<id>/logs` works with the current token (`gh auth status`: scopes gist, read:org, repo, workflow). No need to reproduce the gate locally.
- Smoke log: Tests Ran 15, Pass Rate 93 %, Fail Rate 7 %. Single failure: `SCRUM459FollowupMonitorTest.readBackUnderSalesRepPermissions` — `MIXED_DML_OPERATION ... Followup_Obligation__c, original object: PermissionSetAssignment`, line 307 col 1. The dev's local 13/13-green claim does not reproduce at the pushed head.
- Cause: lines 303-304 insert `PermissionSetAssignment` (setup object), line 307 inserts the obligation (non-setup) in the SAME transaction. Split into separate transactions (house SCRUM-438/442). Fix is a test artifact only.
- Write path verified correct at this head: `scripts/fls-check.sh` on all six fields → Read PS (read/edit=false) + Write PS (read/edit=true), each assigned to 2 users.
- AC 6 artefact now exists and is green: `ac6_userTypedMonitoringValue_refusedAndStoredValueUnchanged` (1962 ms). Guard = `OpportunityFollowupGuardTrigger` → `assertNoUserTypedValues(newRecs, oldMap)`; compares proposed vs stored, no SOQL.
- Exception-type matrix measured via `sf apex run` probes: `ApexException`, `InsufficientAccessError`, `ClientUserError`, `InsufficientFglAccess`, `AssertionFailure`, `InsufficientAccessException`, `UserOperationException` all → `Invalid type`. `AuraHandledException` compiles but is runtime-restricted to Aura/Visualforce. `System.AssertEquals(false, true, msg)` is the available refusal.
- ListView `Follow_up_Monitoring` is LIVE in Test-Org (`Id 00BWU000016re3N2AQ`), retrieved back with `sf project retrieve start --metadata "ListView:Opportunity.Follow_up_Monitoring"`. Round-0 column blocker closed by the house token form.
- Static skip-flag `systemWriteInFlight` reviewed: set/cleared around the single `update`; termination comes from the monitor trigger's relevance filter (IsClosed/Amount), NOT from the flag. Nit: if the update throws, the flag stays true for the rest of the transaction.
- Verdict: **REJECTED (round 2)** — one test method + a green CI run. Second rejection on this artifact; a third cycle would go to the user.
