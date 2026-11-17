# SCRUM-461 — Verloren Chancen: welcher Wettbewerber gewann

Authoritative build spec. Architect-Agent, 2026-11-17.
Repo surveyed: `origin/master` @ `f4fb858bf5f23776c93ff46f1348e62c49712878` (git fetch before survey).
Org queried: Test-Org (`sf sobject describe`, `sf data query`, Analytics `reportTypes/Opportunity`).

## Ziel

Record on a lost Opportunity which competitor won it (name from a controlled, role-gated list),
optionally the competitor's price, and show a monthly, per-competitor overview of the last
twelve months to the sales director — without any automation.

## 1. Verified facts (measured, not assumed)

| # | Fact | How verified |
|---|---|---|
| F1 | The loss-reason field on Opportunity is **`Loss_Reason__c`**, type Picklist, filterable/sortable/createable | `sf sobject describe --sobject Opportunity --target-org Test-Org` |
| F2 | Its deployed values are `ZuTeuer`, **`Wettbewerber`** (label "An einem Wettbewerber verloren"), `KeinBudget`, `ZeitpunktNichtPasst`, `KeinBedarfMehr`, `KontaktAbgebrochen`, `Sonstiges` | `git show origin/master:force-app/main/default/objects/Opportunity/fields/Loss_Reason__c.field-meta.xml` |
| F3 | A "deal lost on" date **already exists**: `CloseDate` (type date, sortable, filterable). The Opportunity reportType's own date column is `CLOSE_DATE` | same describe + `analytics/reportTypes/Opportunity` → `CLOSE_DATE` = `Opportunity.CloseDate` |
| F4 | Opportunity already carries a Lookup field (`Approval_Decided_By__c` → `referenceTo: User`) — the house shape for a Lookup on a standard object | `git show origin/master:.../Opportunity/fields/Approval_Decided_By__c.field-meta.xml` |
| F5 | **No `Competitor__c` exists in Test-Org.** The only competitor things are the standard child object `OpportunityCompetitor` and the standard free-text field `MainCompetitors__c` (Text 100) | `sf sobject list --target-org Test-Org` |
| F6 | Grouping on a lookup field is expressible in report XML: a deployed report groups by `OpenOpportunityHistory__c$AccountId__c.Name` | `git show origin/master:.../reports/Sales/Offene_Werte_Verlauf.report-meta.xml` |
| F7 | `ReportGrouping` carries `sortType` (`Column`/`Aggregate`/`CustomSummaryFormula`) and `aggregateType` (`…RowCount…`); `ReportColumn.aggregateTypes` (`Sum`/`Average`/…/**no** RowCount) | `@salesforce/types/lib/metadata.d.ts` |
| F8 | `UserDateInterval` has **no rolling 12-month value** (…`INTERVAL_LAST90`, `INTERVAL_LAST120`, `INTERVAL_PREVCURY`…) → the window must be a formula gate field | same file |
| F9 | House pattern for a rolling window: `Account.Wartungsvertrag_Renewal_Soon__c` = `AND(NOT(ISBLANK(x)), x >= TODAY(), x <= ADDMONTHS(TODAY(), 3))`, Checkbox | `git show origin/master:.../Account/fields/Wartungsvertrag_Renewal_Soon__c.field-meta.xml` |
| F10 | A Number formula **can return NULL**: `Days_Close_Date_Overdue__c` = `IF(…, NULL, …)` | same |
| F11 | Rollup `summaryOperation` enum is `count`/`sum`/`min`/`max` — **no average** → the average gap cannot be a rollup field; it must be the report's `Average` aggregation | `metadata.d.ts` `SummaryOperations` |
| F12 | House trigger `apiVersion` is `62.0`; house PS pairs are `_Read` / `_Teamleitung` (SCRUM-428, SCRUM-451) | trigger + PS files on master |
| F13 | Opportunity record page is the legacy layout `layouts/Opportunity-Opportunity Layout.layout-meta.xml` | `git ls-tree origin/master -- force-app/main/default/layouts` |

**Counts in Test-Org, measured 2026-11-17 (carry these into the implementation note and the coverage table):**

| Measure | Count |
|---|---|
| Opportunities total | **130** |
| Closed Lost | **16** |
| Closed Lost with any `Loss_Reason__c` | 16 |
| Closed Lost with `Loss_Reason__c = Wettbewerber` | **0** |
| Closed Lost with `CloseDate >= 2025-11-17` (inside the 12-month window) | 16 |
| Closed Lost with `Amount` filled | 15 |
| Competitor records / competitor prices | 0 / 0 (object does not exist yet) |

⚠️ **AC2, AC5, AC7 and AC8 currently match ZERO records.** Per the PO's counting rule they are
*untested* until the Tester creates Closed-Lost test data with `Loss_Reason__c = Wettbewerber`,
a competitor and (for some) a price, and states the created counts.

## 2. Components

| # | Component | Path | Responsibility |
|---|---|---|---|
| C1 | Competitor object (the controlled list) | `force-app/main/default/objects/Competitor__c/Competitor__c.object-meta.xml` | One record per competitor; Name = company name |
| C2 | Competitor on the deal | `force-app/main/default/objects/Opportunity/fields/Competitor_Lost_To__c.field-meta.xml` | Lookup to `Competitor__c`; the picker IS the controlled list |
| C3 | Competitor's price | `force-app/main/default/objects/Opportunity/fields/Competitor_Price__c.field-meta.xml` | Currency, optional |
| C4 | Gap | `force-app/main/default/objects/Opportunity/fields/Competitor_Gap__c.field-meta.xml` | Formula, blank when price unknown |
| C5 | 12-month gate | `force-app/main/default/objects/Opportunity/fields/Lost_Last_12M__c.field-meta.xml` | Checkbox formula, rolling window |
| C6 | Conditional requirement | `force-app/main/default/objects/Opportunity/validationRules/Competitor_PflichtBeiWettbewerber.validationRule-meta.xml` | Competitor mandatory only when the reason names a competitor |
| C7 | FLS, deal fields | `force-app/main/default/permissionsets/SCRUM461_Competitor_Lost.permissionset-meta.xml` | Read+Edit on C2/C3, Read-only on C4/C5 |
| C8 | FLS, list (all internal sales roles) | `force-app/main/default/permissionsets/SCRUM461_Competitor_List_Read.permissionset-meta.xml` | `Competitor__c` read only |
| C9 | FLS, list (team leads) | `force-app/main/default/permissionsets/SCRUM461_Competitor_List_Teamleitung.permissionset-meta.xml` | `Competitor__c` create/edit/delete |
| C10 | Overview, org-wide | `force-app/main/default/reports/Sales/Verloren_Chancen_je_Wettbewerber.report-meta.xml` | `scope: organization` |
| C11 | Overview, own deals | `force-app/main/default/reports/Sales/Verloren_Chancen_je_Wettbewerber_Meine.report-meta.xml` | `scope: user` |
| C12 | Duplicate guard on the list | `force-app/main/default/triggers/CompetitorNameGuard.trigger` + `classes/CompetitorNameGuard.cls` | Refuses a second record with the same Name |
| C13 | Record page | `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml` (existing file) | Add C2/C3/C4 to the detail section |
| C14 | Test artifacts | `classes/SCRUM461CompetitorLossTest.cls`, `classes/SCRUM461CompetitorFlsTest.cls`, `tests/e2e/SCRUM-461-verloren-chancen-je-wettbewerber.spec.ts` | See §6 |

### C1 — Competitor__c

```xml
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <description>SCRUM-461: controlled list of competitors. One record per company; the Name IS the company name. Team leads add entries, all internal sales roles read them.</description>
    <enableSearch>true</enableSearch>
    <label>Competitor</label>
    <nameField>
        <displayFormat>C-{0000}</displayFormat>
        <label>Competitor Number</label>
        <type>AutoNumber</type>
    </nameField>
    <pluralLabel>Competitors</pluralLabel>
    <sharingModel>ReadWrite</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
```

Plus one field:

`force-app/main/default/objects/Competitor__c/fields/Company_Name__c.field-meta.xml`
— `type=Text`, `length=80`, `required=true`, `unique=true`, `caseSensitive=true`,
`externalId=true`, `description`: "SCRUM-461: Name of the company, exactly once in the list."

**Why Name is AutoNumber and the company name is a separate field:** the house uses
AutoNumber names (`Followup_Obligation__c` → `FU-{0000}`), and `unique=true` +
`caseSensitive=true` + `externalId=true` on a Text field is the only declarative way to
demand one record per company. `unique` exists in the CustomField schema
(`@salesforce/types/lib/metadata.d.ts`) — **its runtime enforcement is NOT verified here**;
C12 is the guard that makes it hold regardless. If the Developer's deploy-validate rejects
`unique`/`externalId` on this shape, drop both and keep C12 alone — the design does not
depend on `unique`.

### C2 — Competitor_Lost_To__c

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Competitor_Lost_To__c</fullName>
    <description>SCRUM-461: which competitor won this deal. Only meaningful with Loss_Reason__c = Wettbewerber; enforced by Competitor_PflichtBeiWettbewerber. Never free text.</description>
    <relationshipLabel>Verloren Chancen</relationshipLabel>
    <relationshipName>Opportunities_Lost_To_Competitor</relationshipName>
    <relationshipOrder>0</relationshipOrder>
    <reparentableMasterDetail>false</reparentableMasterDetail>
    <referenceTo>Competitor__c</referenceTo>
    <required>false</required>
    <trackFeedHistory>false</trackFeedHistory>
    <trackHistory>false</trackHistory>
    <type>Lookup</type>
</CustomField>
```

Free text is structurally impossible: the UI offers only existing `Competitor__c` records → AC3.

### C3 — Competitor_Price__c

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Competitor_Price__c</fullName>
    <description>SCRUM-461: roughly what the competitor offered. Commercially sensitive third-party figure; readable only through SCRUM461_Competitor_Lost.</description>
    <precision>18</precision>
    <required>false</required>
    <scale>2</scale>
    <trackFeedHistory>false</trackFeedHistory>
    <trackHistory>false</trackHistory>
    <type>Currency</type>
</CustomField>
```

### C4 — Competitor_Gap__c (PO decision: our Amount − competitor price, negatives kept)

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Competitor_Gap__c</fullName>
    <description>SCRUM-461: Amount minus Competitor_Price__c. Positive = we were more expensive. Blank when the price is unknown, so the report average ignores the deal (AC5). Negative = we lost despite being cheaper; still counted.</description>
    <formula>IF(ISBLANK(Competitor_Price__c), NULL, Amount - Competitor_Price__c)</formula>
    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
    <precision>18</precision>
    <required>false</required>
    <scale>2</scale>
    <type>Number</type>
</CustomField>
```

`formulaTreatBlanksAs` is set to `BlankAsZero` but the `IF(ISBLANK(...), NULL, ...)` guard
makes the result NULL before the blank-treatment applies — this is exactly the shape of
`Days_Close_Date_Overdue__c` (F10). The Developer must read the field back after deploy:
for a deal with a competitor and no price, `Competitor_Gap__c` has to come back **blank, not
0**. If it comes back 0, the guard is the bug, not the report — fix the formula, do not
filter in the report.

### C5 — Lost_Last_12M__c

```xml
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Lost_Last_12M__c</fullName>
    <description>SCRUM-461: rolling twelve-month window on CloseDate (the date the deal was lost). House pattern Wartungsvertrag_Renewal_Soon__c. Deals without CloseDate are outside the window and are not retro-fixed.</description>
    <formula>AND(ISPICKVAL(StageName, "Closed Lost"), NOT(ISBLANK(CloseDate)), CloseDate >= ADDMONTHS(TODAY(), -12))</formula>
    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
    <label>Lost in last 12 months</label>
    <required>false</required>
    <type>Checkbox</type>
</CustomField>
```

### C6 — Validation rule

```xml
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Competitor_PflichtBeiWettbewerber</fullName>
    <active>true</active>
    <description>SCRUM-461 AC2: a deal lost to a competitor must name the competitor. AC1: any other loss reason stays free. Fires only on records being saved, so historical deals are untouched (AC6).</description>
    <errorConditionFormula>AND(ISPICKVAL(StageName, "Closed Lost"), ISPICKVAL(Loss_Reason__c, "Wettbewerber"), ISBLANK(Competitor_Lost_To__c))</errorConditionFormula>
    <errorDisplayField>Competitor_Lost_To__c</errorDisplayField>
    <errorMessage>Was denn fuer ein Wettbewerber? If the deal went to a competitor, the competitor must be chosen from the list.</errorMessage>
</ValidationRule>
```

`errorField` names the missing field so the message points at it (AC2 "the message names
the missing competitor"). House shape: `LossReason_PflichtBeiClosedLost` (same object, same
`AND(ISPICKVAL(...), ISBLANK(...))` form).

⚠️ **The one formula the Developer has to deploy-validate first:** `ISBLANK()` on a Lookup
field inside a validation rule. It is the only construct in this design that is not already
proven in the repo. If deploy-validate rejects it, the fallback is an Apex guard on
`Opportunity (before save)` — but try the rule first, it is declarative and bulk-safe.

### C7/C8/C9 — Permission Sets

A Permission Set is an **upper bound assigned per user**, so "team leads write, everyone
else reads" cannot be one artifact — assigning a PS with `allowCreate=true` to an account
manager would let them create. The house splits it the same way (SCRUM-428
`_ServiceTeam`/`_Teamleitung`, SCRUM-451 `_Read`/`_Teamleitung`).

C7 — deal fields, assigned to **all internal sales roles** (account managers, team leads,
sales director):

```xml
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Opportunity.Competitor_Lost_To__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>true</editable>
        <field>Opportunity.Competitor_Price__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Competitor_Gap__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Lost_Last_12M__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM461_Competitor_Lost</label>
    <description>SCRUM-461 FLS for the competitor fields on Opportunity. Read+Edit on Competitor_Lost_To__c and Competitor_Price__c; the two derived fields are read-only. Competitor_Price__c is commercially sensitive third-party data: it is readable ONLY through this PS, so users outside the internal sales roles never see it. No Profile is touched.</description>
</PermissionSet>
```

C8 — `Competitor__c` read-only, assigned to **all internal sales roles**:

```xml
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <objectPermissions>
        <allowCreate>false</allowCreate>
        <allowDelete>false</allowDelete>
        <allowEdit>false</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Competitor__c</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM461_Competitor_List_Read</label>
    <description>SCRUM-461: every internal sales role can read the competitor list, which is what makes the lookup picker work for account managers (AC4 second half). No write access.</description>
</PermissionSet>
```

C9 — `Competitor__c` full CRUD, assigned to **sales team leads only**:

```xml
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <objectPermissions>
        <allowCreate>true</allowCreate>
        <allowDelete>true</allowDelete>
        <allowEdit>true</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>false</modifyAllRecords>
        <object>Competitor__c</object>
        <viewAllRecords>false</viewAllRecords>
    </objectPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM461_Competitor_List_Teamleitung</label>
    <description>SCRUM-461 AC4: only sales team leads may add or clear a competitor. Assigned to team leads only.</description>
</PermissionSet>
```

**Assignment is part of the handoff contract.** Deploying a PS grants nothing. The Developer's
handoff comment must carry the `PermissionSetAssignment` read-back for all three PSs and one
`Competitor_Price__c` value read back through a real session — otherwise the first symptom
downstream is a `No such column` that reads like a missing field, not like a permission.

### C10/C11 — Reports

```xml
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>
        <aggregateTypes>Sum</aggregateTypes>
        <field>AMOUNT</field>
    </columns>
    <columns>
        <aggregateTypes>Average</aggregateTypes>
        <field>Opportunity.Competitor_Gap__c</field>
    </columns>
    <description>SCRUM-461 AC7: last 12 months, per competitor — deals lost, total value of those deals, average gap where the price is known; most business lost first. Window = Lost_Last_12M__c gate (no rolling 12-month interval exists in the report metadata).</description>
    <filter>
        <criteriaItems>
            <column>Opportunity.Lost_Last_12M__c</column>
            <columnToColumn>false</columnToColumn>
            <isUnlocked>false</isUnlocked>
            <operator>equals</operator>
            <value>1</value>
        </criteriaItems>
        <criteriaItems>
            <column>Loss_Reason__c</column>
            <columnToColumn>false</columnToColumn>
            <isUnlocked>false</isUnlocked>
            <operator>equals</operator>
            <value>Wettbewerber</value>
        </criteriaItems>
    </filter>
    <format>Summary</format>
    <groupingsDown>
        <aggregateType>RowCount</aggregateType>
        <field>Opportunity$Competitor_Lost_To__c.Name</field>
        <sortOrder>Desc</sortOrder>
        <sortType>Aggregate</sortType>
    </groupingsDown>
    <name>Verloren_Chancen_je_Wettbewerber</name>
    <reportType>Opportunity</reportType>
    <scope>organization</scope>
    <showDetails>false</showDetails>
    <showGrandTotal>true</showGrandTotal>
    <showSubTotals>false</showSubTotals>
</Report>
```

C11 is the same file with `name` = `Verloren_Chancen_je_Wettbewerber_Meine` and
`<scope>user</scope>` — that is the whole AC8 mechanism: `scope` is source-persistable
(`user | team | allusers | queue | organization`), the Opportunity sharing model is not
touched.

Notes for the Developer:
- `Opportunity$Competitor_Lost_To__c.Name` follows the deployed token
  `OpenOpportunityHistory__c$AccountId__c.Name` (F6). The `$` form is the house's; if
  deploy-validate rejects it, the alternative is a Text formula field on Opportunity
  mirroring the competitor name and grouping on that — do **not** invent a third spelling.
- `RowCount` is valid on `groupingsDown.aggregateType` (F7) but **not** in
  `columns.aggregateTypes`; the deal count per competitor is the RowCount aggregate of the
  grouping, not a column.
- Report-level *sharing* ("who may open this report") is not in the source — it is an
  Org step (Report → Settings). DevOps owns it; it is not a CI gate.

### C12 — Duplicate guard

```
CompetitorNameGuard.trigger            on Competitor__c (before insert, before update)
CompetitorNameGuard.cls                apiVersion 62.0 (house value, F12)
```

`before insert`: collect all Names of the batch, ONE `SELECT Name FROM Competitor__c`
against the batch's names (never a query per record), throw
`ApexMessages`-style `UserError` naming the duplicate. `before update`: only when the Name
changed. Batch size is a list of companies — single digits — so one query per batch is
trivial.

## 3. ADR — the four decisions the PO owns back

**ADR-1: the competitor list is a custom object with a Lookup, not a picklist.**
- *Chosen:* `Competitor__c` + `Competitor_Lost_To__c` (Lookup).
- *Rejected — static Picklist on the Opportunity field:* adding a value edits the field
  definition for every user; there is no per-role gate, so AC4 is unsatisfiable.
- *Rejected — `OpportunityCompetitor` (standard child object, F5):* free-text names typed
  per Opportunity, no shared list, no uniqueness, no role gate. Reusing it reproduces
  exactly the "Müller GmbH / Mueller / Müller Group" problem the PO describes.
- *Rejected — `MainCompetitors__c` (standard Text 100, F5):* free text, no control.
- *Rejected — Metadata type (`__mdt`, house uses `SCRUM428_*__mdt`):* editable only in Setup,
  not assignable through a Permission Set, and cannot be the target of a Lookup.
- *Consequence:* the picker IS the list (AC3), the PS gate IS the role rule (AC4), and the
  overview groups on the record, so one company is one row.

**ADR-2: Apex over Flow, and declarative wherever it is expressible.**
No Flow anywhere. The conditional requirement is a `ValidationRule` (the house already has
five on Opportunity, one of them on this very field), the overview is a `Report`, the
derived numbers are formula fields. The only imperative logic is the duplicate guard, and it
is **Apex, not Flow** — per the house rule, because Flow XML schema strictness and
`apiVersion` drift have repeatedly failed deployment here. This keeps the Apex surface at
one small trigger and leaves the rest declarative, which is what the Tester's CI gate can
actually validate.

**ADR-3: the twelve-month window is anchored on the standard `CloseDate`, no new date field.**
- *Chosen:* `CloseDate` (F3) + `Lost_Last_12M__c` formula gate (F8/F9).
- *Rejected — a new `Lost_On__c` date field:* every existing lost deal would have it blank,
  so all 16 Closed-Lost deals in Test-Org would sit outside the window and the sales
  director's question about *this year* would still be unanswerable. `CloseDate` is
  populated for all 16.
- *Rejected — `timeFrameFilter` with a relative interval:* `UserDateInterval` has no rolling
  12-month value (F8); `INTERVAL_CUSTOM` would need editing every month, which is
  automation-adjacent and drifts.
- *Rejected — `LastStageChangeDate`:* not a report date column, and it moves on any later
  stage change.
- *PO decision kept verbatim:* deals without the date are outside the window, not retro-fixed.

**ADR-4: two Permission Sets for the list, not one.**
The PO asked for "one PS for the list entries". A Permission Set is an upper bound per
assigned user, so one PS cannot be both "team leads write" and "everyone else reads" —
the bound is per assignment, not per role. The house splits it identically (F12). Three
PSs total: one for the deal fields, one read-only for the list, one full CRUD for team
leads. No Profile is edited anywhere.

## 4. Data model, sharing, governor limits

**Data model:** one new object (`Competitor__c`, 1 record per company, expected order of
magnitude: tens), three new fields + one formula field on Opportunity, one lookup
relationship `Competitor__c` → `Opportunity` (relationshipName
`Opportunities_Lost_To_Competitor`, so the lost deals appear as a related list on the
competitor record — that is how a team lead inspects one competitor in the sales meeting).

**Sharing model:** Opportunity sharing is **unchanged** — no OWD change, no sharing rule,
no ADR needed. AC8's "own deals vs all deals" is report `scope`, not sharing (scope and
sharing are two different things; scope is source-persistable, report-level sharing is an
Org step). `Competitor__c` uses `sharingModel: ReadWrite` with the PS bounds of C8/C9 on
top.

**Governor limits:**
- Validation rule: per-record formula, no SOQL → bulk-safe, no 10k-record problem.
- Formula fields: evaluated at read time, no limits.
- Duplicate guard: one query per batch, never per record; batch is a company list.
- Report: no Apex, no limits.
- No `System.runAs` needed in production code; the FLS test class does need it (house rule,
  fls-gate.py reddens a test class touching new fields without it).

**Nothing automatic (AC9):** no Flow, no email, no task, no feed post, no alert, no push.
The only trigger fires on `Competitor__c` insert and only throws; nothing fires on the
Opportunity save except the validation rule.

## 5. Technical acceptance criteria (on top of the PO's nine)

| ID | Criterion | Artefact |
|---|---|---|
| TAC1 | `Competitor_Gap__c` reads back **blank** (not 0) for a deal with a competitor and no price | Apex test, read-back assertion |
| TAC2 | `Competitor_Gap__c` is negative for a deal where we were cheaper, and that deal is still in the count and the sum | Apex test + report row |
| TAC3 | `Lost_Last_12M__c` is FALSE for a deal with `CloseDate` older than 12 months, TRUE for one inside | Apex test |
| TAC4 | Saving a Closed-Lost deal with `Loss_Reason__c = Wettbewerber` and no competitor throws a `ValidationError` whose message names the competitor | Apex test |
| TAC5 | Saving the same deal with `Loss_Reason__c = KontaktAbgebrochen` and no competitor succeeds | Apex test |
| TAC6 | A user holding only C8 cannot create a `Competitor__c` record; a user holding C9 can, and the new record is immediately selectable by a user holding C8 | Apex test with `System.runAs` + E2E |
| TAC7 | `Competitor_Price__c` is invisible (field not readable) to a user holding none of the PSs | Apex test, negative probe |
| TAC8 | A historical Closed-Lost deal without a competitor is openable, listable and saveable unchanged | E2E |
| TAC9 | The report row count equals the number of competitors that have at least one lost deal in the window, and the top row has the highest deal count | E2E |
| TAC10 | A second `Competitor__c` record with an existing Name is refused | Apex test |

## 6. Test coverage the PR must carry (PR gate, not a bonus)

- `classes/SCRUM461CompetitorLossTest.cls` — TAC1–TAC5, TAC10 (behaviour).
- `classes/SCRUM461CompetitorFlsTest.cls` — TAC6, TAC7, negative access against a restricted
  user, `System.runAs` mandatory.
- `tests/e2e/SCRUM-461-verloren-chancen-je-wettbewerber.spec.ts` — AC7/AC8/AC9/AC3 in the UI,
  frontdoor.jsp auth only, no `networkidle` on Lightning.
- Test data has to be **created** for AC2/AC5/AC7/AC8 (0 records match today, §1) and the
  created counts belong in the coverage table.

## 7. Org steps (DevOps owns, not CI gates)

| Step | Where | Read-back required |
|---|---|---|
| Assign C7 to account managers, team leads, sales director | Setup → Permission Sets | `PermissionSetAssignment` rows |
| Assign C8 to all internal sales roles, C9 to team leads only | same | same |
| Report-level sharing of C10 (who may open) | Report → Settings | screenshot or API read |
| Place C11 where the account manager opens it | App Builder / tab | — |

## 8. Open points (non-blocking)

- [ ] `ISBLANK()` on a Lookup field in a validation rule — deploy-validate decides; fallback
      is an Apex guard (owner: @developer-agent).
- [ ] `Opportunity$Competitor_Lost_To__c.Name` grouping token — deploy-validate decides;
      fallback documented in C10 (owner: @developer-agent).
- [ ] `unique=true` / `externalId=true` on `Company_Name__c` — schema element exists, runtime
      enforcement unverified; C12 covers it either way (owner: @developer-agent).
- [ ] Report-level sharing for C10 (owner: @devops-agent).
- [ ] Test data for the four zero-count criteria (owner: @tester-agent).
