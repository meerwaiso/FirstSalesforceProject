# SCRUM-459 — Follow-up Monitoring on Opportunity (Architect design)

Author: architect-agent · 2026-10-31 · Status: **freigegeben** → Developer-Agent
Repo surveyed at `origin/master` = `dc94b0bd5b3764d867b2892cedc3d4fddf6cfd9c`. Org surveyed read-only: Test-Org. Nothing was deployed by the architect.

## Ziel

Every open Opportunity shows automatically which follow-up obligations are outstanding, how many are overdue, which follow-up status it has and whether it needs management attention — driven by one new custom object that carries exactly one obligation.

## ADR 1 — Apex, not Flow, not declarative

| Option | Verdict | Why |
|---|---|---|
| **Apex trigger + static handler** | **CHOSEN** | The six values are a rollup over the child records of a relationship (count, min-date, max-date, precedence rules). Nothing declarative computes that, and the logic (stage exclusion, strict threshold, calendar-day window) will evolve. |
| Flow | rejected | No Flow element aggregates a related list into count/min/max on the parent; it would need per-record loop elements and hits element limits. Flows have repeatedly failed deploy/schema validation in this project — house rule: Apex over Flow for non-trivial logic. |
| Formula field / Validation Rule | rejected | `Opportunity` is a standard object: formula fields exist only on custom objects. Validation rules can block a save, they cannot write values. The three formula fields already on Opportunity (`Inactive_Days__c`, `Days_Close_Date_Overdue__c`, `Is_Close_Date_Overdue__c`) are single-record arithmetic and cross no relationship. |

House precedent, same shape: `OpenOpportunityRollupHandler` + `OpportunityOverdueReset.trigger` (SCRUM-416), `CaseOpenCountTrigger` (SCRUM-365) — full recompute per trigger batch, one query, write only on change.

## ADR 2 — Lookup relationship, deliberately NOT the house Master-Detail

The house pattern for a child object is Master-Detail (`OpenOpportunityHistory__c` → `AccountId__c`, `sharingModel=ControlledByParent`, read back from Test-Org). **It is not copied here**, because it would break the PO's sharing requirement:

- Master-Detail + `ControlledByParent` makes the child inherit the parent's visibility. Opportunity runs *Full access / Read with others*, so every role that can open an Opportunity would see the obligations — exactly the widening the PO forbids.
- Lookup + `sharingModel=ReadWrite`, no sharing rules: a record is readable only by users holding Read on the object, i.e. only through the two Permission Sets. That is what makes the negative-access criterion satisfiable.
- Consequence: the parent link is a field the user fills (`Opportunity__c`), not implicit containment. The Sales Rep creates the obligation and points it at the Opportunity in the same save.

## Data model

### New object `Followup_Obligation__c` — one obligation per record

| API name | Type | Meaning |
|---|---|---|
| `Name` | AutoNumber `FU-{0000}` | obligation number |
| `Opportunity__c` | Lookup → Opportunity | the monitored record (parent link) |
| `Status__c` | Picklist `Outstanding` (default) / `Completed` | still outstanding or already completed |
| `Due_Date__c` | Date, blank allowed | own due date; blank = outstanding, never overdue, never sets the next date (PO decision) |
| `Completed_Date__c` | Date, blank allowed | date it was completed |
| `Next_Action__c` | Text(255) | next action, free text — **sensitive customer data**, FLS-protected |

`Date`, not `Date/Time`: "today" and "within the next two days" are calendar-day statements (PO decision), so no timezone round-trip is involved.

### Six derived fields on `Opportunity` — never typed by a human

| API name | Type | Derived from |
|---|---|---|
| `Followup_Required__c` | Checkbox | at least one obligation with `Status__c = Outstanding` |
| `Next_Followup_Date__c` | Date | earliest `Due_Date__c` among outstanding obligations that have a due date |
| `Overdue_Followup_Count__c` | Number(6,0), default 0 | count of outstanding obligations with `Due_Date__c < Date.today()` |
| `Last_Customer_Interaction__c` | Date | max `Completed_Date__c` over the obligations of the Opportunity (PO: NOT any logged activity) |
| `Followup_Status__c` | Picklist `Up to Date` / `Due Soon` / `Overdue` | precedence Overdue > Due Soon > Up to Date |
| `Needs_Manager_Attention__c` | Checkbox | `Amount > 50000` **strictly** AND overdue count ≥ 1 AND Opportunity open |

Collision check (measured 2026-10-31, Test-Org, `FieldDefinition` WHERE `EntityDefinition.QualifiedApiName='Opportunity'`): 29 custom fields exist, none of the six names above is taken.

## Semantics (PO decisions encoded)

```
today      = Date.today()
overdue(o)      := o.Status__c = Outstanding AND o.Due_Date__c ≠ null AND o.Due_Date__c < today
nextDate        := min Due_Date__c over outstanding obligations with a due date   (null if none)
status          := Overdue   if overdueCount > 0
                   Due Soon  if overdueCount = 0 AND nextDate ≠ null AND nextDate ≤ today + 2
                   Up to Date otherwise
required        := outstandingCount > 0
attention       := Amount > 50000 (strict, 50000 exactly does NOT flag) AND overdueCount ≥ 1 AND IsClosed = false
lastInteraction := max Completed_Date__c over ALL obligations of the Opportunity
closed (IsClosed = true) → required=false, nextDate=null, overdueCount=0, lastInteraction=null, status=blank, attention=false
```

## Verified metadata — dry-run validated against Test-Org

Command run by the architect: `sf project deploy start --source-dir scratch/459-dryrun --target-org Test-Org --dry-run --wait 10 --json` → `status: Succeeded`, `numberComponentsDeployed: 14 / 14`, `numberComponentErrors: 0`. The repo files are the authoritative source; Jira markup corrupts XML names.

`objects/Followup_Obligation__c/Followup_Obligation__c.object-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <description>SCRUM-459: One follow-up obligation of a customer commitment on an Opportunity. Own due date, own next action, own completion date. Never typed on the Opportunity itself.</description>
    <enableHistory>true</enableHistory>
    <enableSearch>true</enableSearch>
    <label>Follow-up Obligation</label>
    <nameField>
        <displayFormat>FU-{0000}</displayFormat>
        <label>Obligation Number</label>
        <type>AutoNumber</type>
    </nameField>
    <pluralLabel>Follow-up Obligations</pluralLabel>
    <sharingModel>ReadWrite</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
```

`objects/Followup_Obligation__c/fields/Opportunity__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Opportunity__c</fullName>
    <description>SCRUM-459: The Opportunity this obligation belongs to. Lookup (not Master-Detail) so the records stay invisible to roles without the follow-up Permission Set.</description>
    <label>Opportunity</label>
    <referenceTo>Opportunity</referenceTo>
    <relationshipLabel>Follow-up Obligations</relationshipLabel>
    <relationshipName>Followup_Obligations</relationshipName>
    <type>Lookup</type>
    <writeRequiresMasterRead>false</writeRequiresMasterRead>
</CustomField>
```

`objects/Followup_Obligation__c/fields/Status__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Status__c</fullName>
    <description>SCRUM-459: Outstanding = still open obligation, Completed = the customer interaction happened.</description>
    <label>Status</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Outstanding</fullName>
                <default>true</default>
                <label>Outstanding</label>
            </value>
            <value>
                <fullName>Completed</fullName>
                <default>false</default>
                <label>Completed</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

`objects/Followup_Obligation__c/fields/Due_Date__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Due_Date__c</fullName>
    <description>SCRUM-459: Due Date. Date (not Datetime) so 'today' is a calendar day, per PO decision.</description>
    <label>Due Date</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Date</type>
</CustomField>
```

`objects/Followup_Obligation__c/fields/Completed_Date__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Completed_Date__c</fullName>
    <description>SCRUM-459: Completed On. Date (not Datetime) so 'today' is a calendar day, per PO decision.</description>
    <label>Completed On</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Date</type>
</CustomField>
```

`objects/Followup_Obligation__c/fields/Next_Action__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Next_Action__c</fullName>
    <description>SCRUM-459: Free text about the customer communication. Sensitive customer data - readable only through the follow-up Permission Sets.</description>
    <label>Next Action</label>
    <length>255</length>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

`objects/Opportunity/fields/Followup_Required__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Followup_Required__c</fullName>
    <description>SCRUM-459: Derived by Apex, never typed by a human.</description>
    <label>Follow-up required</label>
    <defaultValue>false</defaultValue>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Checkbox</type>
</CustomField>
```

`objects/Opportunity/fields/Next_Followup_Date__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Next_Followup_Date__c</fullName>
    <description>SCRUM-459: Derived by Apex, never typed by a human.</description>
    <label>Next Followup Date</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
<type>Date</type>
</CustomField>
```

`objects/Opportunity/fields/Overdue_Followup_Count__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Overdue_Followup_Count__c</fullName>
    <description>SCRUM-459: Number of outstanding obligations whose due date has fully passed. Derived by Apex, never typed.</description>
    <externalId>false</externalId>
    <label>Overdue Follow-ups</label>
    <precision>6</precision>
    <required>false</required>
    <scale>0</scale>
    <trackTrending>false</trackTrending>
    <type>Number</type>
    <unique>false</unique>
    <defaultValue>0</defaultValue>
</CustomField>
```

`objects/Opportunity/fields/Last_Customer_Interaction__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Last_Customer_Interaction__c</fullName>
    <description>SCRUM-459: Derived by Apex, never typed by a human.</description>
    <label>Last Customer Interaction</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
<type>Date</type>
</CustomField>
```

`objects/Opportunity/fields/Followup_Status__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Followup_Status__c</fullName>
    <description>SCRUM-459: Overdue beats Due Soon beats Up to Date. Written by Apex only.</description>
    <label>Follow-up Status</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Up to Date</fullName>
                <default>false</default>
                <label>Up to Date</label>
            </value>
            <value>
                <fullName>Due Soon</fullName>
                <default>false</default>
                <label>Due Soon</label>
            </value>
            <value>
                <fullName>Overdue</fullName>
                <default>false</default>
                <label>Overdue</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

`objects/Opportunity/fields/Needs_Manager_Attention__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Needs_Manager_Attention__c</fullName>
    <description>SCRUM-459: Derived by Apex, never typed by a human.</description>
    <label>Needs manager attention</label>
    <defaultValue>false</defaultValue>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Checkbox</type>
</CustomField>
```

`permissionsets/SCRUM459_FollowupObligation_Rep.permissionset-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>SCRUM459_FollowupObligation_Rep</fullName>
    <description>SCRUM-459: Follow-up obligation CRUD for the Sales Representative. Create, Read, Edit - NO Delete (nobody among the sales roles deletes; System Administrator only).</description>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM-459 Follow-up Obligation (Sales Rep)</label>
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Followup_Obligation__c</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Followup_Obligation__c.Opportunity__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Followup_Obligation__c.Status__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Followup_Obligation__c.Due_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Followup_Obligation__c.Completed_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Followup_Obligation__c.Next_Action__c</field>
        <readable>true</readable>
    </fieldPermissions>
</PermissionSet>
```

`permissionsets/SCRUM459_FollowupMonitoring_Read.permissionset-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>SCRUM459_FollowupMonitoring_Read</fullName>
    <description>SCRUM-459: Read-only rights. The six derived monitoring fields on Opportunity (editable=false for every human) plus Read on the obligation records for the Sales Manager. Profiles untouched.</description>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM-459 Follow-up Monitoring (Read)</label>
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Followup_Obligation__c</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Followup_Required__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Next_Followup_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Overdue_Followup_Count__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Last_Customer_Interaction__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Followup_Status__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Needs_Manager_Attention__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Followup_Obligation__c.Opportunity__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Followup_Obligation__c.Status__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Followup_Obligation__c.Due_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Followup_Obligation__c.Completed_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Followup_Obligation__c.Next_Action__c</field>
        <readable>true</readable>
    </fieldPermissions>
</PermissionSet>
```

### List view (AC 10 — the sales manager filters on overdue follow-ups)

`force-app/main/default/objects/Opportunity/listViews/Follow_up_Monitoring.listView-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>OPPORTUNITY.NAME</columns>
    <columns>OPPORTUNITY.AMOUNT</columns>
    <columns>OPPORTUNITY.STAGE_NAME</columns>
    <columns>Followup_Required__c</columns>
    <columns>Next_Followup_Date__c</columns>
    <columns>Overdue_Followup_Count__c</columns>
    <columns>Last_Customer_Interaction__c</columns>
    <columns>Followup_Status__c</columns>
    <columns>Needs_Manager_Attention__c</columns>
    <filters>
        <field>Overdue_Followup_Count__c</field>
        <operation>greaterThan</operation>
        <value>0</value>
    </filters>
    <filterScope>Everything</filterScope>
    <fullName>Follow_up_Monitoring</fullName>
    <label>Follow-up Monitoring</label>
</ListView>
```
Column shape validated against the org: standard columns as `OPPORTUNITY.NAME`-style tokens, custom fields as bare API names, filter as `<filters><field/><operation/><value/></filters>` + `<filterScope>Everything</filterScope>` (house shape from `Contact/listViews/Kritische_Kontakte.listView-meta.xml`). The last dry-run reported exactly one remaining error — `no CustomField named Opportunity.Followup_Required__c found` — because the six fields are not in the org yet; it resolves once the Developer deploys the fields in the same branch. `filterList` is NOT a valid element (rejected: `Element filterList invalid at this location in type ListView`).

## Apex components (interfaces — the Developer writes the bodies)

| Component | File | Responsibility |
|---|---|---|
| `FollowupObligationTrigger` | `force-app/main/default/triggers/FollowupObligationTrigger.trigger` | on `Followup_Obligation__c`, after insert / after update / after delete → collect affected parent Opportunity ids, call the handler |
| `OpportunityFollowupMonitorTrigger` | `force-app/main/default/triggers/OpportunityFollowupMonitorTrigger.trigger` | on `Opportunity`, after update → relevance filter (only `IsClosed` or `Amount` changed), call the handler |
| `FollowupMonitoringHandler` | `force-app/main/default/classes/FollowupMonitoringHandler.cls` | the single recompute of the six monitoring fields |

A separate Opportunity trigger (not an extension of `OpportunityOverdueReset.trigger`) follows SCRUM-449, which added `OpportunityRiskTrigger` + `OpportunityRiskHandler` beside the existing one.

```apex
public without sharing class FollowupMonitoringHandler {
    public static void recalculate(Set<Id> opportunityIds);
    public static void onObligationInsert(List<SObject> after);
    public static void onObligationUpdate(List<SObject> after, Map<Id, SObject> before);
    public static void onObligationDelete(List<SObject> before);
    public static void onOpportunityUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap);
}
```

`recalculate` — pseudocode, one pass, no SOQL in a loop:

```
if ids empty → return
Q1: SELECT Id, IsClosed, Amount FROM Opportunity WHERE Id IN ids            (1 query)
Q2: SELECT Opportunity__c, Status__c, Due_Date__c, Completed_Date__c
      FROM Followup_Obligation__c WHERE Opportunity__c IN ids               (1 query)
aggregate per parent into maps (outstanding, overdue, minDue, maxCompleted)
per parent: closed → cleared values; else the six values from the formula above
update only records whose values actually changed, in ONE update batch
```

## Governor limits and recursion

- Per trigger batch: **2 SOQL + 1 update batch**, independent of batch size. No SOQL in a loop.
- A batch of 200 obligations touches ≤ 200 parents; Q2 returns all obligations of those parents (bounded by data, not by batch size).
- AC 11 (20 obligations in one bulk save): parent ids go into a `Set<Id>`, so each opportunity is recomputed once and each obligation is counted exactly once, independent of order.
- **Recursion:** writing the Opportunity fields fires the Opportunity triggers, including our own `OpportunityFollowupMonitorTrigger`. Its relevance filter (`IsClosed` or `Amount` changed) sees no change on the second pass and returns. Terminates — this must be stated in the code, because unlike the SCRUM-416 rollup (Account write, no Opportunity trigger) here the trigger DOES fire.
- Measured 2026-10-31 in Test-Org: `AssignmentRule` exists only for `Case` and `Lead` — **none on Opportunity** — so there is no second save cycle to double-count (the SCRUM-418 trap).

## Permission Sets — AMENDED to three (PR round 1, 2026-10-31)

The original design said "exactly two PSs with the six fields `editable=false`". That is **not implementable** — measured, see the amendment below. Three PSs, Profiles still untouched.

| PS | Grants | Assigned to |
|---|---|---|
| `SCRUM459_FollowupObligation_Rep` | `objectPermissions` on `Followup_Obligation__c`: allowCreate/read/edit **true**, allowDelete **false**, viewAllRecords/modifyAllRecords false; `fieldPermissions` readable+editable on `Opportunity__c`, `Status__c`, `Due_Date__c`, `Completed_Date__c`, `Next_Action__c` | both Test-Org users |
| `SCRUM459_FollowupMonitoring_Read` | `objectPermissions` on `Followup_Obligation__c`: allowRead true, everything else false; `fieldPermissions` readable **true / editable false** on the six Opportunity monitoring fields and readable on the obligation fields | both Test-Org users |
| `SCRUM459_FollowupMonitoring_Write` | `fieldPermissions` on the **six Opportunity monitoring fields only**: readable **true / editable true**; no `objectPermissions` on the obligation | both Test-Org users |

### Why the amendment is forced (measured 2026-10-31, Test-Org)

- `scripts/fls-check.sh Opportunity Followup_Required__c` → granted ONLY by `SCRUM459_FollowupMonitoring_Read` with `read=true edit=false`, assigned to 2 users. **No PS in Test-Org grants edit on the six fields.**
- The handler writes typed Opportunity records and ends in one `update toUpdate` batch; the trigger runs in **user mode**, so FLS applies to that write. Result: 11 of 13 Apex tests fail with `System.DmlException: Operation failed due to fields being inaccessible on Sobject Opportunity` at `FollowupMonitoringHandler.recalculate` line 187, and CI's "Metadata, Apex & Session Smoke" is red on the PR head.
- `System.runAs_Use('...')` does **not** exist in this org — probe `sf apex run` with that call → `Method does not exist or incorrect signature: void runAs_Use(String) from the type System`. There is no way to borrow a Permission Set inside a trigger.
- The house precedent `SCRUM449OpportunityRisk` + `SCRUM449OpportunityRiskWrite` was checked in the repo and the org: the Write PS carries 5 `editable=true` entries, the Read PS 0, and the Write PS is assigned to **one** user (the CLI user). That shape works only because the *acting* user holds the Write PS — it does not reproduce for a user holding only the Read PS, which is exactly the failing case here. Do not copy the "trigger path needs no Write-PS" sentence from SCRUM-449: it does not reproduce in Test-Org for these fields.

### Consequence for AC 6 — the guard, not FLS

Granting edit is what makes the write path work at all, so "sales reps never edit the monitoring values" can no longer be an FLS property. It becomes an **Apex contract**:

- New component `OpportunityFollowupGuardTrigger` (`before update` on Opportunity) → `FollowupMonitoringHandler.assertNoUserTypedValues(newRecs, oldMap)`.
- Rule: if the proposed value of any of the six fields differs from the value the handler computes for this transaction, the save is **refused** (German message naming the field). The handler's own write proposes the computed value and therefore passes.
- Distinguishing the handler's write from a user's edit must not rely on field values alone — use a static flag set by the handler in the same transaction (house shape: static `hasFired` guard in `OpportunityOverdueResetHandler`, SCRUM-449 §Trigger recursion).
- AC 12 (user without the PS cannot read the fields or the records) stays an FLS property: `read=false` for everyone outside the two PSs; the negative test runs under `System.runAs` with a created, licence-free user.
- `SCRUM459FollowupFlsTest.withBothPS_readableButNeverEditable` must be rewritten: it currently asserts an FLS refusal. With edit=true the refusal comes from the guard — the test must assert the **save is refused and the stored value unchanged**, still under a user that holds the PSs.

### Handler header correction

The comment "Systemwrites here run in System context and bypass FLS" is false (triggers run in user mode; measured). Replace it with: writes pass FLS because `SCRUM459_FollowupMonitoring_Write` grants edit to the acting user; the six fields are never writable by a human *intent* because the guard refuses a value that is not the computed one.

---

## Permission Sets — original (superseded, kept for the record): exactly two, Profiles untouched

| PS | Grants | Roles |
|---|---|---|
| `SCRUM459_FollowupObligation_Rep` | `objectPermissions` on `Followup_Obligation__c`: allowCreate/read/edit **true**, allowDelete **false**, viewAllRecords/modifyAllRecords false; `fieldPermissions` readable+editable on `Opportunity__c`, `Status__c`, `Due_Date__c`, `Completed_Date__c`, `Next_Action__c` | Sales Representative |
| `SCRUM459_FollowupMonitoring_Read` | `objectPermissions` on `Followup_Obligation__c`: allowRead true, everything else false; `fieldPermissions` readable **true / editable false** on the six Opportunity monitoring fields and readable on the obligation fields | Sales Representative AND Sales Manager |

- The Sales Manager's "obligation: Read only" is carried by PS 2 — that is what keeps the count at exactly two PSs.
- Delete of an obligation: granted by neither PS → System Administrator only (their profile holds object CRUD).
- `Next_Action__c` (sensitive customer data) is readable only through these two PSs.
- **Deploying a PS is half the work.** The Developer must assign BOTH PSs in Test-Org to BOTH users of that org (the CLI user `devops-agent@cline.test` and the human account Meerwais Osmani) and read back one field through a real session before handing off; DevOps assigns in Prod-Org at Release. CI's `scripts/fls-gate.py` reddens a changed field that names no PS or a PS assigned to nobody.
- **The negative-access criterion is only satisfiable if the Profile blocks the field** — a Permission Set can grant, never revoke. House convention: profiles untouched, FLS PS-only; measured in Test-Org (SCRUM-421) that a field with an unassigned PS is invisible to everyone. Do not assume it for these six fields: the Developer/Tester must run the negative probe inside an `@isTest` class under `System.runAs` — `System.runAs` is refused outside test methods (measured 2026-10-31), so `sf apex run` cannot answer this.

## Sharing model impact

- No OWD change, no sharing rules, no role-hierarchy change. Opportunity keeps Full access / Read with others.
- `Followup_Obligation__c`: `sharingModel=ReadWrite` (internal), no sharing rules → visible only to holders of Read via the two PSs. Non-sales roles see neither obligations nor monitoring values (monitoring values additionally blocked by FLS).

## ⚠️ Findings (measured, not assumed)

1. **Test-Org 2026-10-31: 130 Opportunities, 76 open (`IsClosed=false`), 13 open with `Amount > 50000`, 0 open with `Amount` exactly 50000.** The boundary criterion "exactly 50.000 EUR does not flag" matches **zero** records in the org — it is untestable on org data and must be covered by a fixture. A coverage row whose Observed column reads 0 is not a PASS.
2. `Followup_Obligation__c` does not exist yet, so overdue counts are 0 until the fixtures exist. The Tester must state non-zero numbers (open opportunities with overdue ≥ 1, and how many of those exceed 50.000 EUR) — the PO's measurement duty.
3. No `AssignmentRule` on Opportunity (only Case and Lead) → no double save cycle.
4. The house Master-Detail child pattern is deliberately not followed (ADR 2).
5. `System.runAs` is refused outside test methods → visibility/sharing questions need an `@isTest` class, not a script probe.

## Acceptance criteria → artefact that proves it

| AC | Artefact |
|---|---|
| 1 create obligation, opportunity shows follow-up required | Apex test `SCRUM459FollowupMonitorTest` + E2E on the obligation record page |
| 2 overdue count with due dates 20./25./28.10., today 23.10. → 1 | Apex test (dates relative to `Date.today()`, fixture per PO example) |
| 3 status precedence Overdue / Due Soon / Up to Date | Apex test, one assertion per branch |
| 4 last completed interaction = max completed date (05.10., 18.10. → 18.10.) | Apex test |
| 5 completing an obligation changes the four values without touching the Opportunity | Apex test (no Opportunity DML in the test) |
| 6 typing into overdue count / status is refused | Apex FLS test under `runAs(sales rep)` + E2E field edit |
| 7 four outstanding, two overdue → count 2, Overdue, earliest open due date | Apex test |
| 8 Stage Won/Lost → out of monitoring, values cleared, later completion changes nothing | Apex test (stage change + later obligation completion, assert unchanged) |
| 9 attention flag 75.000/1 → set; 40.000/2 → not set; exactly 50.000/1 → not set | Apex test, three fixtures (the 50.000 one is required — 0 records in the org) |
| 10 sales manager filters the list on overdue → exactly open opportunities with count ≥ 1 | E2E on `Follow_up_Monitoring` list view + SOQL count comparison |
| 11 20 obligations in one bulk save, each counted once, order-independent | Apex test with a bulk DML batch |
| 12 user without the PS: monitoring fields and obligation records not readable, save fails | `SCRUM459FollowupFlsTest` under `runAs(restricted user)` — negative access test |

Required test artefacts (PR gate, house shapes): Apex classes `SCRUM459FollowupMonitorTest` + `SCRUM459FollowupFlsTest` with their meta files and the `scr459-phase3-apextests.xml` manifest (shapes: `SCRUM382CustomerSinceDaysTest` / `SCRUM382...FlsTest`), plus `tests/e2e/SCRUM-459_followup-monitoring.spec.ts` (frontdoor.jsp auth, no `networkidle`). "Deployed and ran once" is evidence, not a test.

## Open points (non-blocking)

- [ ] Creation path for the Sales Rep: the obligation is created as its own record with `Opportunity__c` filled (Lookup). Whether Lightning's related-list "New" action fills the parent automatically is an org/UI behaviour the Tester's E2E must exercise, not an assumption. Owner: @tester-agent.
- [ ] Whether the Sales Rep profile in Test-Org is a distinct profile at all, or the CLI user stands in for both roles. Owner: @developer-agent — state which users hold which PS in the handoff.
- [ ] The list view column resolution needs the six fields deployed in the same branch (see finding above). Owner: @developer-agent.

## ADR 8 — Record pages are Layouts, not FlexiPages (PR #181 round 4, measured 2026-11-01)

SCRUM-460 asked for a record page on `Followup_Obligation__c` and a section with the six
monitoring fields on the Opportunity page. The FlexiPage shape was tried and does not work:

- A deployed FlexiPage of type `RecordPage` is never activated as the record page. Measured
  via `sf api request rest "/services/data/v62.0/ui-api/record-ui/<recordId>?layoutTypes=Full&modes=View" --target-org Test-Org`:
  the Opportunity kept answering with the legacy layout `Opportunity-Opportunity Layout`
  (46 fields, 8 sections) and none of the six monitoring fields was in it.
- What renders for a custom object is its **Layout** (house precedent: SCRUM-449 risk fields,
  commit `02ce6a1`, added to `layouts/Opportunity-Opportunity Layout.layout-meta.xml`).

Decision (both halves, deployed in `manifest/scr460-recordpages.xml` as `Layout` members):

1. `layouts/Opportunity-Opportunity Layout.layout-meta.xml` gains one `<layoutSections>`
   labelled "Follow-up Monitoring", six items, `behavior=Readonly` (system-written values —
   house precedent SCRUM-440). Additive only: the 29 existing fields stay.
2. `layouts/Followup_Obligation__c-Follow-up Obligation Layout.layout-meta.xml` — the object
   has no layout of its own, so this Layout *is* its record page. `Name` is `AutoNumber`
   (`FU-{0000}`) in the object meta, so `behavior=Readonly` is correct; the five editable
   obligation fields are `behavior=Edit`.
3. Both FlexiPages (`Opportunity_Followup_Monitoring_Page`, `Followup_Obligation_Record_Page`)
   are deleted from branch and org.

Read-back at head `028b311` (same record-ui call, run 2026-11-01):

- Opportunity record `006WU00000Q2RZqYAN` → 9 sections, 52 fields, section "Follow-up Monitoring"
  carries `Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c, Last_Customer_Interaction__c, Followup_Status__c, Needs_Manager_Attention__c`.
- `Followup_Obligation__c` probe record `a05WU00001AtA2zYAF` (created, measured, deleted) → 2 sections,
  "Information" carries `Name, Next_Action__c, Opportunity__c, Completed_Date__c, Status__c, Due_Date__c`.

Consequence for the AC table above: the UI paths of AC 1, AC 5 and AC 11 are now *reachable* —
the E2E spec must create and complete an obligation on the record page
(`/lightning/o/Followup_Obligation__c/new` or `/lightning/r/Followup_Obligation__c/<id>/view`)
and read the six fields on the Opportunity Details tab. Until that run is green those three
criteria stay PARTIAL; the Apex artefacts prove the data, not the UI.
