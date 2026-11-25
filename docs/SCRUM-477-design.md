# SCRUM-477 — Chance: Days in Current Stage · Build Design

## Goal
Show on every open Opportunity how many whole days it has sat in its current Stage (anchor = last real Stage change, not ModifiedDate), and give one list of the open Opportunities stuck more than 30 days in that Stage, longest first.

## ADR — Implementation vehicle (build vs customize)

**Decision: declarative formula field + Permission Set + Report. No Apex, no Flow, no Trigger.**

| Option | Verdict | Why |
|---|---|---|
| **Formula field (chosen)** | yes | The requirement is pure arithmetic on fields the platform already maintains (`LastStageChangeDate`, `StageName`, `CreatedDate`). A formula field is recomputed by the platform on every read → satisfies "always up to date, nobody maintains it by hand" with zero code, and is structurally unwritable → satisfies AC9/AC10 without a guard. House precedent, same object, same shape: `Days_Close_Date_Overdue__c` (master, SCRUM-414) and `Approval_Waiting_Days__c` (Case, SCRUM-390). |
| Apex trigger + field | rejected | AC10 says nothing else may happen: no emails, no tasks, no automatic changes to the Opportunities. A before/after-save trigger that writes a counter mutates records on save and on import, needs bulkification and a nightly recompute, and is writable by anyone with edit rights until an FLS rule is added. Strictly worse for the same requirement. |
| Flow | rejected | The house rule (AGENTS.md + Architect SOUL): Apex over Flow for any non-trivial logic, Flows have repeatedly failed on strict XML schema, `apiVersion` drift and xmllint. Nothing here needs a Flow at all — a Flow cannot display a per-record number when somebody opens a record; display is metadata. No `apiVersion`/naming decision owed because no Flow is created. |

## Data model (decided before implementation)

Standard object **Opportunity** — no new object, no relationship, no record type change.
Fields read: `StageName` (Stage), `LastStageChangeDate` (DateTime, platform-maintained), `CreatedDate`, `Amount`, `OwnerId`.
Note: the PO's word "Status" is not a field on Opportunity — open/closed is derived from `StageName` (`Closed Won` / `Closed Lost`), and the describe call returns `IsClosed`, not `Status`. All closed-tests in this build use the house form `OR(ISPICKVAL(StageName,"Closed Won"), ISPICKVAL(StageName,"Closed Lost"))`.

**One new field:** `Opportunity.Stage_Days_In_Current_Stage__c` (Label `Tage jetzige Stage`)

```xml
<type>Number</type><precision>10</precision><scale>0</scale><unique>false</unique>
<formula>IF(OR(ISPICKVAL(StageName, "Closed Won"), ISPICKVAL(StageName, "Closed Lost")),
           NULL,
           TODAY() - DATEVALUE(IF(ISBLANK(LastStageChangeDate), CreatedDate, LastStageChangeDate)))</formula>
```

Semantics fixed here (PO's business decision, do not re-derive):
- anchor = `LastStageChangeDate` (never `ModifiedDate`) → forward **and** backward Stage changes re-anchor, i.e. the counter restarts at 0 (AC3/AC4).
- fallback while no Stage change happened after creation: `CreatedDate` → a record created 200 days ago that never moved shows 200 and belongs in the stuck list. **Open point (PO to correct, not blocking)**: if the other reading is wanted, replace the `IF(ISBLANK(...))` fallback with `NULL` — one line, no other artefact changes.
- whole days, integer (`scale 0`): a Stage change today yields 0 (AC5/AC6 boundary).
- closed (`Closed Won`/`Closed Lost`) → `NULL`, so a closed deal can never satisfy the > 30 filter even a second time (AC2).
- `DATEVALUE(...)` is required: `LastStageChangeDate` and `CreatedDate` are DateTime, `TODAY()` is Date — Date minus DateTime is a type error (measured in the SCRUM-459 probe: `Error at Character 142-151 in expression: TODAY()-CreatedDate ...`).

## Permission Set (CRUD/FLS — never a Profile edit)

`permissionsets/SCRUM477_CurrentStageDays_Read.permissionset-meta.xml`

```xml
<fieldPermissions>
    <editable>false</editable>
    <field>Opportunity.Stage_Days_In_Current_Stage__c</field>
    <readable>true</readable>
</fieldPermissions>
<hasActivationRequired>false</hasActivationRequired>
<label>SCRUM477CurrentStageDays</label>
```

- Read-only: `readable=true`, `editable=false` → nobody can create/edit/delete the value (AC9/AC10).
- FLS is **never** inherited from object-level CRUD: this one field-level entry must exist, be deployed **and assigned**. Assigning is half the work: `PermissionSetAssignment` to the Test-Org CLI user and to the human test account, then read the field back once through a real session. A field granted to nobody looks like a missing field at runtime (`No such column`), not like a permission.
- Do **not** extend an existing Read-PS whose label claims another ticket (SCRUM-445/449), and do not touch any Profile.

## Record page (AC1: the number is visible when the record is opened)

Delta to the **existing** file `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml` (master version + one `<layoutItem>`, never an org-retrieved copy — an org-retrieved Layout carries Test-Org-only fields and reddens the Prod-Org Drift Gate):

```xml
<layoutItems>
    <behavior>Readonly</behavior>
    <field>Stage_Days_In_Current_Stage__c</field>
</layoutItems>
```

House pattern: `Is_Overdue__c`, `Value_Tier__c` sit in the same section with `behavior=Readonly` (SCRUM-381/402/415 commits). Deploy order inside one commit: field → PS → layout → report (a Report referencing a field that does not exist yet fails the deploy).

## The list (AC7/AC8) — Salesforce Report, not a ListView

`reports/Sales/Chancen_Over_30_Tage.report-meta.xml` (Sales folder, house pattern of `Hoeh_Risk_Chancen` / `Ueberfaellige_Chancen`). The Developer may rename the report; the shape is fixed.

```xml
<columns><field>OPPORTUNITY_NAME</field></columns>   <!-- the opportunity -->
<columns><field>FULL_NAME</field></columns>          <!-- its owner (User.Name) -->
<columns><field>STAGE_NAME</field></columns>         <!-- current stage -->
<columns><field>AMOUNT</field></columns>             <!-- amount -->
<filter>
  <criteriaItems><column>STAGE_NAME</column>...<operator>notEqual</operator><value>Closed Won,Closed Lost</value></criteriaItems>
  <criteriaItems><column>Opportunity.Stage_Days_In_Current_Stage__c</column>...<operator>greaterThan</operator><value>30</value></criteriaItems>
</filter>
<format>Summary</format>
<groupingsDown><dateGranularity>Day</dateGranularity><field>Opportunity.Stage_Days_In_Current_Stage__c</field><sortOrder>Desc</sortOrder></groupingsDown>
<timeFrameFilter><dateColumn>CREATED_DATE</dateColumn><interval>INTERVAL_CUSTOM</interval><startDate>2000-01-01</startDate><endDate>2099-12-31</endDate></timeFrameFilter>
<reportType>Opportunity</reportType><scope>organization</scope><showDetails>true</showDetails>
```

Two oracle findings that bind the Developer's file (both were real rejections, both repaired here):
- `<columns>TOKEN</columns>` (flat form) → `Required field is missing: field`. House form is nested `<columns><field>TOKEN</field></columns>`.
- `<operator>greater</operator>` → `'greater' is not a valid value for the enum 'FilterOperation'`. Strictly-above-30 is `greaterThan` (31 and up, AC6 exact).

Column tokens were read from the org, not guessed: `GET /services/data/v62.0/analytics/report-types/Opportunity` → `detailColumnInfo` contains `OPPORTUNITY_NAME`, `STAGE_NAME`, `AMOUNT` and `FULL_NAME` (label "Opportunity Owner", `fullyQualifiedName: User.Name`); there is **no** IsClosed/status token for the Opportunity report type → closed exclusion goes through `STAGE_NAME`.

Sorting: the row grouping is the day count with `sortOrder Desc` → longest-stuck first (AC8). This is the house-proven mechanism (`Hoeh_Risk_Chancen`, `Ueberfaellige_Chancen` both sort by a field via `groupingsDown`). A ListView cannot do it: no `force-app/main/default/listsViews/*` file in master carries any sort element, and the ListViews schema has none (verified in SCRUM-432/449) — ListView sorting is an org-side UI setting, not a deployable artefact. If the PO wants a ListView as an extra convenience column set, it can carry the days column but must not be cited as the proof of AC8.

## Sharing model
No impact. Opportunity is not a shared object, no OWD change, no sharing rule, no role-hierarchy change. Data classification: operational metric, no PII → no field-category/object-sharing entry owed.

## Governor limits
- Formula field: platform-evaluated on read, no SOQL, no Apex → no 100/50k-query risk, bulkification N/A.
- Report: one aggregate query at open-time; `INTERVAL_CUSTOM` 2000…2099 keeps it record-independent (open records have no meaningful `CloseDate`; using `CLOSE_DATE` silently drops them — measured in SCRUM-449's oracle runs).
- No new DBIndex is needed for the > 30 filter (report scope stays inside the org's normal index behaviour at current record volume; not a selective index candidate because the threshold is a computed value).

## Technical acceptance criteria — artefact per AC

| AC | Artefact | Test vehicle |
|---|---|---|
| AC1 visible on the record | Layout `<layoutItem>` Readonly | E2E (Playwright, record home) |
| AC2 closed never listed | Report filter `STAGE_NAME notEqual Closed Won,Closed Lost` + field `NULL` branch | E2E on the report + Apex on the NULL branch |
| AC3 forward change restarts | formula anchor | Apex (set `StageName`, re-read `LastStageChangeDate`) |
| AC4 backward change restarts | formula anchor | Apex |
| AC5 change today → 0 | `scale 0`, `TODAY() - DATEVALUE(...)` | Apex |
| AC6 30 days not listed, 31 is | `greaterThan 30` | Apex on the field value + one report assertion |
| AC7 the five columns | Report `<columns>` block | E2E on the report |
| AC8 longest first | `groupingsDown ... Desc` | E2E on the report |
| AC9 read for all, writable by nobody | PS `readable/editable` | Apex `System.runAs()` on a restricted profile: assert `describe().isAccessible()==true`, `isUpdateable()==false` |
| AC10 nothing else happens | no trigger/Flow/Process/WebLink/task in the delta | Apex: no side effects reachable |

Test-vehicle warnings the Tester must respect (house findings, do not re-discover):
- `CreatedDate` cannot be backdated through the UI or a normal insert → age-based ACs cannot be E2E-proven on a freshly built record; they are Apex-constructed with `LastStageChangeDate` set.
- Negative FLS probes must be falsifiable: assert `getDescribe().isAccessible()/isUpdateable()` under `runAs`; inside a try/catch SELECT probe keep **only** the SELECT inside the try (`System.assert(false)` inside the try can never fail).
- Mixed DML: a PSA insert may not join Account/Case inserts — split the business-DML proof from the FLS-negative proof into separate transactions.
- A new ValidationRule on a standard object would redden every class that can save the blocked state — none is added here, so nothing to count.

## Counts that must travel
The PO could not measure (no org access) → the expected row count of the stuck list is **not** stated by the PO. The Tester must publish an Observed number, and a row whose Observed value is 0 is **untested, not PASS**. Test-Org currently holds no `Stage_Days_In_Current_Stage__c` (verified: `sobjects/Opportunity/describe` → 87 fields, none matching) — so before the deploy the stuck list is definitionally empty and any 0-count report from the Tester is a build problem, not a fact about the org.

## Verified against the org / CLI (2026-11-25, check-only)
- `sf project deploy validate --source-dir scratch/shape477/force-app --test-level RunRelevantTests --async` → **Succeeded, 4/4 components** (field + PS + report + folder): the exact shapes above are deployable, and the two rejections named in this doc were reproduced and repaired in the same loop.
- `LastStageChangeDate`, `Amount`, `IsClosed` present in `sobjects/Opportunity/describe` (87 fields); `Status` is not.
- No duplicate work: field, PS and report names absent from Test-Org and from the repo (grep 0 hits for days/current-stage names).
- `PermissionSet` query for the new PS: 0 records → nothing to reuse.

## Open decisions for the Developer (blockers: none)
- [ ] PO's never-changed-stage fallback: adopted `CreatedDate`; PO may amend (one line in the formula).
- [ ] Closed records: `NULL` adopted (not `0`) — tell the Tester both readings must be green in the Apex class, since AC2 is about the list, not about the cell.
- [ ] Report file name/label: Developer's choice; the shape and the filter operators are fixed.
- [ ] `sf project deploy validate` never runs zero tests: use `--test-level NoTestRun` for a shape check only; a shape check must never consume the Test-Org 24 h test budget.

## Deployment duty for the Developer (handoff must carry the read-back)
Branch `feature/SCRUM-477-...` cut fresh from `master`; deploy to Test-Org only; manifest per component, per deploy command (house rule: `--manifest <own>/x.xml` and `--target-dir` both). Handoff comment must carry the `PermissionSetAssignment` read-back for **both** the CLI user and the human test account plus one field read back through a real session.

## Review resolution (Architect, PR #197, head 6b67d49)

The shape in this doc shipped unchanged: 4 detail columns plus the day counter as the **group label** of a `groupingsDown ... Desc` row group. The org rejects the counter in both lists ("You can't include groupings in the selected columns list"), so AC7's fifth value and AC8's sort share one mechanism — a Details-format report would show five columns per row but cannot sort. Accepted: AC7 is read as "the day count is visible per group header, the four other values per row"; the E2E spec must assert the group header label, not a fifth detail column.

Data state measured in Test-Org after the deploy (2026-11-25): 157 Opportunities total, 68 closed and exactly 68 with a NULL day counter (so no open record loses the number, AC1), 89 open of which 76 above 30 days and 13 below. Near the threshold there is a data gap: highest value below 30 is 4, lowest above is 34, and 0 records sit at 30 or at 31. AC6's exact boundary therefore has no rows in this org — it is proven by the `greaterThan` operator only, and the Tester reports it as its own coverage line, never as a PASS row.

Nothing in the delta writes records, sends emails or creates tasks: the branch adds one test class and four metadata artefacts, no trigger, no Flow, no production Apex (AC10 holds structurally).

## Grant set and assignment duty (Architect, after the AC9 finding on head 7e586ee)

AC9 is a two-part requirement and only one part is a repo artefact:

1. **Grant (in the branch):** the field is read-only in exactly one Permission Set, `SCRUM477_CurrentStageDays_Read` (read=true, edit=false). No Profile edit, no second Permission Set.
2. **Assignment (org-side only):** the Permission Set meta deliberately carries **no** `userAssignments` block — Test-Org usernames do not exist in Prod-Org, so a hard-coded list would fail the Test-Org deploy. That makes the assignment invisible to the branch, to review and to CI: `gh pr checks` can be green while the field is granted to nobody. `scripts/fls-gate.py` closes that hole in Test-Org only — `.github/workflows/ci.yml` calls it with `--org Test-Org`, and the Prod-Org Drift Gate validates metadata check-only, never `PermissionSetAssignment`.

Policy that must travel with this ticket, not with a username list:

- After **every** deploy of the field, in **both** orgs, the Permission Set is assigned to every active user that can read `Opportunity`. `scripts/fls-check.sh Opportunity Stage_Days_In_Current_Stage__c <org>` is the read-back: the field must come back granted **and** with a non-zero assignee count.
- Measured in Test-Org on 2026-11-25: granted by the PS, assigned to 4 users — the CLI user, the human test account, plus two org-internal Analytics Cloud users (`integration@…`, `insightssecurity@…`) that can read `StageName` but could not read the counter until the Developer assigned them. Safe (read-only operational metric, no PII) and it satisfies the literal criterion; whether those two *should* see the number is the PO's line to take, and a veto removes exactly those two assignments.
- Gate proposal for the user to decide (nobody edits `.github/workflows/`): the existing assignment gate is already parameterised — `python3 scripts/fls-gate.py --base "$BASIS" --org Test-Org`. A Prod-side run of the same script after the Prod deploy would have caught this failure mode, which the project has shipped six times (SCRUM-382/386/388/390/394/398). It is not part of this ticket and must not be pushed as a side effect.

The read-back class `SCRUM477StageDaysReadTest` is now the falsifiable witness for AC9: it loops every active user and compares `Opportunity.StageName` access against the counter's, so it fails the moment one viewer is blind (Expected 0, Actual 2 on head 7e586ee). It belongs in the Tester's regression suite unchanged.
