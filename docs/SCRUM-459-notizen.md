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
- `System.runAs` refused outside test methods (measured 2026-10-31, SCRUM-457) → FLS/negative-access questions need an @isTest class, `sf apex run` cannot answer them.
- Writing the six Opportunity fields fires `OpportunityFollowupMonitorTrigger` again; the relevance filter (IsClosed/Amount changed) is the termination guard. Unlike SCRUM-416 (Account write → no Opportunity trigger), here the trigger DOES fire.
