# SCRUM-440 — Rückrufwunsch bei Opportunities: Architecture Design

Status: freigegeben für Developer-Agent. Authoritative Build-Spec — alle Namen hier sind byte-exakt; Jira-Kommentare mutieren Markup, die Repo-Files are the source of truth.

## Ziel
Two FLS-protected custom fields on Opportunity („Rückruf gewünscht“ checkbox + „Rückruf am“ DateTime) with a validation rule pair and an Apex trigger-handler that creates/updates/cancels exactly one open callback Task per Opportunity, owned by the Opportunity owner.

## 1. Data Model (before implementation)

### 1.1 New Opportunity fields

| DeveloperName | API Name | Type | Label | Notes |
|---|---|---|---|---|
| Rückruf_desired | Rückruf_desired__c | Checkbox | Rückruf gewünscht | required=false |
| Rueckruf_am | Rueckruf_am__c | DateTime | Rückruf am | required=false |

Naming decision: API developer names stay ASCII (`Rückruf` → `Rueckruf`, umlaut dropped; house pattern SCRUM-430 `Rueckruf_Zeitfenster__c` on Contact). The German spelling lives in the `<label>` only. `desired` instead of an umlaut-compound: `Rückruf_desired__c` keeps the label German, the developer name ASCII. Alternative `Callback_Wanted__c` — decision: keep `Rueckruf_desired__c` for grep-ability with the SCRUM-430 sibling. **Developer: if you rename, update PS + layout + ValRule + Handler in one commit; the PS field entries must match byte-exact.**

Files:
- `force-app/main/default/objects/Opportunity/fields/Rueckruf_desired__c.field-meta.xml`
- `force-app/main/default/objects/Opportunity/fields/Rueckruf_am__c.field-meta.xml`

XML shape (house: SCRUM-430 field file):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Rueckruf_desired__c</fullName>
    <description>SCRUM-440: Rueckruf requested by the customer on this Opportunity. Paired with Rueckruf_am__c (ValRule pair).</description>
    <externalId>false</externalId>
    <label>Rückruf gewünscht</label>
    <required>false</required>
    <trackFeedHistory>false</trackFeedHistory>
    <type>Checkbox</type>
</CustomField>
```
DateTime field: same shape, `<type>DateTime</type>`, no valueSet, no precision/scale.

Collision check (verified): Opportunity custom fields on origin/master (eac7cee) = Days_Close_Date_Overdue__c, Is_Close_Date_Overdue__c, Is_Overdue__c, Loss_Reason__c, TestFeld__c, Value_Tier__c. Opportunity describe in Test-Org shows no Rueckruf*/Callback* field. No collision.

### 1.2 Task usage — VERIFIED against Test-Org

`Task` describe (Test-Org, api v68.0):
- `Subject` combobox, `Status` picklist: **Not Started / In Progress / Completed / Waiting on someone else / Deferred**
- `Priority` picklist: **High / Normal / Low**
- **There is NO `DueDate` on Task.** `SELECT Id,DueDate FROM Task` → "No such column". The due date is **`ActivityDate`** (Date). → „due date = the callback date“ = `ActivityDate = date(Rueckruf_am__c)`.
- **There is NO „Abgebrochen“ status.** The PO's criterion 5 („set to Abgebrochen“) cannot be expressed on the standard picklist. See §6 Open Point OP-1.
- Owner of a Task = `OwnerId`; the Task is linked to the Opportunity via **`WhatId`** (not a relationship on Opportunity — Task is not a child of Opportunity; SCRUM-294 house pattern uses exactly this).

Automation Task shape (house pattern from SCRUM-294 ChurnDetectionService, commit 7457838):
```apex
new Task(
    WhatId: opp.Id,
    OwnerId: opp.OwnerId,
    Subject: 'Rückruf: ' + opp.Name,
    Priority: 'High',
    Status: 'Not Started',
    ActivityDate: dateOfRueckruf_am
)
```
Subject prefix is byte-exact `Rückruf: ` (with trailing space) per AC 3.

## 2. Components

1. **Fields** (2 files above) — phase 1.
2. **Validation rules** (Opportunity, 2 files — house: SCRUM-359 pair on Contact):
   - `force-app/main/default/objects/Opportunity/validationRules/Rueckruf_am_PflichtBeiGesetzer.validationRule-meta.xml`
     errorConditionFormula: `AND(Rueckruf_desired__c = true, ISBLANK(Rueckruf_am__c))`
   - `force-app/main/default/objects/Opportunity/validationRules/Rueckruf_am_KeineNichte.validationRule-meta.xml`
     errorConditionFormula: `AND(Rueckruf_desired__c = true, NOT(ISBLANK(Rueckruf_am__c)), Rueckruf_am__c <= NOW())`
     errorMessage (both, per AC 2): `Bitte einen Rückruftermin in der Zukunft angeben.`
   - ⚠️ `NOW()` vs DateTime: formula comparison of a DateTime field against `NOW()` is the intended shape; if the deploy validator rejects it (check-only run), fallback is `Rueckruf_am__c < TODAY() + 1` semantics via a helper — Developer reports the actual rejection, does not guess.
3. **Trigger handler** `force-app/main/default/classes/RueckrufTaskHandler.cls` (+ `-meta.xml`) — new class, no existing equivalent (verified: no Task-creating class on origin/master).
   - `handleAfterUpdate(List<Opportunity> after, Map<Id,Opportunity> beforeMap)` — after-update context: the ValRules have already passed, so every record here has a valid state; and the Task-write does not recurse into the Opportunity trigger.
   - Per record, decide by end-state vs old-state:
     - checkbox false→true: create Task (shape above), unless an open callback Task already exists (then update its ActivityDate/Subject-owner untouched).
     - checkbox true→true with changed `Rueckruf_am__c`: update the existing open Task's ActivityDate (AC 4 — no second Task).
     - checkbox true→false: close/cancel the open callback Task (see OP-1 decision).
     - checkbox false→false or untouched: no-op.
   - **Bulkification (governor limits):** collect Opportunity ids in ONE pass; then exactly 2 SOQL queries per invocation: (a) `SELECT Id,Subject,ActivityDate,IsClosed FROM Task WHERE WhatId IN :ids AND Subject LIKE 'Rückruf:%' AND IsClosed = false`, (b) none else. All Task inserts/updates batched into single `insert`/`SaveResult` calls. No SOQL in loops.
   - **Recursion guard:** house pattern `hasFired` static flag (OpportunityLossReasonClearHandler).
4. **Trigger wiring:** extend the EXISTING `force-app/main/default/triggers/OpportunityOverdueReset.trigger` with the handler call in `after update` (it already has after update for SCRUM-416). **One trigger per object is the house rule** — do NOT create a second Opportunity trigger.
5. **Permission Set** `force-app/main/default/permissionsets/SCRUM440_Rueckrufwunsch.permissionset-meta.xml` — field-only PS (house: SCRUM430/381):
   ```xml
   <fieldPermissions><editable>true</editable><field>Opportunity.Rueckruf_desired__c</field><readable>true</readable></fieldPermissions>
   <fieldPermissions><editable>true</editable><field>Opportunity.Rueckruf_am__c</field><readable>true</readable></fieldPermissions>
   ```
   - FLS default of the new fields stays OFF (house: SCRUM-430 description states exactly this).
   - Task Read for Vertriebs/Vertriebsleitung (PO note): Task is a standard object already readable via profiles; PO asked for explicit Read. Decision: NO objectPermissions entry in the PS (standard-object CRUD comes from profiles; SCRUM410's objectPermissions entry was for a CUSTOM object). If the negative test shows Vertriebs cannot read the auto-created Task, that is an Org/role finding, not a PS edit — see OP-2.
   - **Deploying the PS is half the work: assign it to the CLI target-org user AND the human test account, then read back one field through a real session (Developer handoff requirement, house rule SCRUM-382/386/388/390/394/398).**
6. **Layout:** add both fields as `<behavior>Edit</behavior>` layoutItems to `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml` (house: Loss_Reason__c / Is_Overdue__c sit in the same file).
7. **Manifests** (house naming): `manifest/scr440-phase1-fields.xml`, `manifest/scr440-phase2-apex-ps.xml`, `manifest/scr440-phase3-layout.xml`, `manifest/scr440-apextests.xml`.
8. **Tests:** `SCRUM440RueckrufwunschTest.cls` (behaviour: create/update/cancel, dedup AC4, uncheck AC5, bulk 200-record path) + `SCRUM440RueckrufwunschFlsTest.cls` (negative FLS via `System.runAs` of a restricted user; house shapes SCRUM382CustomerSinceDaysTest/...FlsTest). Coverage gate ≥85 % per AC 7 — the ≥85 % is measured on the PR, not claimed.

## 3. ADR — Apex vs Flow vs declarative

**Decision: Apex trigger + handler classes; validation via two declarative ValRules.**
- The automation needs branching (create / update / cancel), cross-object lookup (Task by WhatId+Subject), and bulk processing → Flow element limits and schema drift make Flow the wrong tool (house rule: Apex over Flow for non-trivial logic; Flows broke deploy/schema validation repeatedly here). No Flow is introduced.
- The save-rejection (AC 2) stays declarative ValRules, NOT Apex `throw`: house pattern SCRUM-359/381 — ValRules run on the end-state, give the exact errorMessage, and keep the block deterministic for E2E. Apex only does the side-effect (Task), never the validation.
- Trigger-driven side effect in `after update` (not before): the Task write must see the validated end-state and must not be undone by a later validation failure. Consequence accepted: a Task can be created for a record whose save later fails in a mixed-batch — same semantics as house SCRUM-416 rollup; Tester covers the mixed-batch case.

## 4. Governor-limit risks (documented mitigation)

| Risk | Mitigation |
|---|---|
| SOQL per record | 1 Task query per trigger invocation, `IN :ids` bulkified |
| Task insert/update per record | batched single `insert` / `SaveResult` calls |
| Trigger recursion | static `hasFired` guard (house) + after-update context, Task writes never touch Opportunity fields |
| 200-record import | all loops over collections, no field access outside bulk; SCRUM-438 lesson: no Mixed-DML hazard here — Task and Opportunity are different contexts but the handler writes ONLY Task in after-update; no AccountId-keyed System writes |

## 5. Sharing model

- Task is owned by the Opportunity owner (`OwnerId = opp.OwnerId`) → owner sees own Task (default owner access, standard object).
- Teamleitung visibility of foreign Tasks: depends on role OWS access to Task (Full/View All) — **Org read-back step, not source**: DevOps/Tester read back `Task` OWD + role access in Test-Org before E2E asserts visibility. No OWD change is proposed (Task OWD untouched, house).
- Opportunity OWD untouched.

## 6. Open points (non-blocking, owner named)

- **OP-1 (PO, blocking for AC 5 wording only):** „Abgebrochen“ does not exist on the Task status picklist (verified against Test-Org: Not Started / In Progress / Completed / Waiting on someone else / Deferred). Proposal: set the open callback Task to **`Deferred`** and keep it open-but-deferred, OR close it (`IsClosed=true`) — „not deleted“ holds either way. Architect default: `Status = 'Deferred'` + prefix Subject untouched. PO decides; Developer implements the default, PO can flip it at Erledigt without code change if `Deferred` chosen.
- **OP-2 (@tester-agent):** negative-access test must prove Vertriebs/Vertriebsleitung can READ the auto-created Task (PO note). If they cannot, that is a role/OWD finding → report, do not PS-patch a standard object.
- **OP-3 (@devops-agent, Org steps):** Lightning page placement of the two fields (FlexiPages live in Org, repo tracks Classic layout only — house finding SCRUM-378/381) + PS assignment read-back on Prod at Release.

## 7. Technical acceptance criteria (Architect, on top of PO's)

- TAC-1: `SELECT Id,ActivityDate,Subject,Status,Priority,OwnerId,WhatId FROM Task WHERE Subject LIKE 'Rückruf:%'` returns exactly one open Task per Opportunity with checkbox true (count > 0 after test setup — a criterion matching zero records is untested, house rule).
- TAC-2: ValRule pair blocks save with the exact errorMessage; Apex never throws the validation message.
- TAC-3: 200 Opportunity updates in one save → ≤2 Task SOQL queries, ≤1 insert + ≤1 update batch (assert via `SELECT COUNT`? no — via SfDC `TESTI` counters in the Apex test: `ASSERT_EQ_QUERY_COUNT`-style house assertions).
- TAC-4: FLS negative test: a user WITHOUT the PS sees neither field (both invisible), save with fields → error; with PS → Read+Edit works.
- TAC-5: E2E via frontdoor.jsp session (house auth rule), Lightning UI, no `networkidle`.

## 8. Deploy order (Developer, Test-Org, check-only first)

1. phase1-fields (2 fields) → check-only
2. phase2: ValRules + Handler + trigger edit + PS → check-only, then deploy with `--test-level RunSpecifiedTests --tests SCRUM440RueckrufwunschTest,SCRUM440RueckrufwunschFlsTest` (house: one broad run per org at a time, CI owns the full suite)
3. phase3: layout
4. PS assignment + read-back (mandatory handoff element)
