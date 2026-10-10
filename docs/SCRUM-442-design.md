# SCRUM-442 — Kundansatisfaction bei Schliessen + Reminder + Account-Übersicht

**Status:** freigegeben → Developer-Agent · **Author:** Architect-Agent
**Repo-Referenz:** `origin/master @ d21d380` (2026-10-10, `git fetch origin` + `git ls-tree origin/master` — alle House-Referenzen unten verifiziert auf diesem Commit)
**Kein Org-Zugriff des Architects.** Org-Fakten, die unten behauptet `Case.Status`- oder `Task`-Picklisten, sind **Reused-Belege** from `docs/SCRUM-436-design.md` (Case.Status = New/Working/Escalated/Closed, live `sf sobject field get -s Case -f Status`) and `docs/SCRUM-440-design.md` (Task describe, Test-Org, api v68.0). They are **not** re-read for this ticket — Developer/Tester must re-verify before the first deploy.

---

## Ziel

Auf dem geschlossenen Servicefall ein 1–5 Kundansatisfaction-Score wird **mandatory** (Speichersperre, alle Closing-Pfads), a low score (1/2) creates **exactly one** follow-up obligation for the responsible representative within 2 Werktag, and the customer (`Account`) carries a read-only satisfaction average plus a three-state Ärger-Indicator — visible to Sales, writeable by Service only.

---

## 1. Data Model (before implementation)

### 1.1 New field on `Case`

| DeveloperName | API Name | Type | Label | Notes |
|---|---|---|---|---|
| `Customer_Satisfaction` | `Customer_Satisfaction__c` | **Picklist** (5 Values) | Kundansatisfaction | `required=false` |

**Picklist, not Number** (ADR-2, see below). Value-Set — API-Names ASCII, Labels carry the scale:

```xml
<type>Picklist</type>
<valueSet>
    <valueSetDefinition>
        <sorted>false</sorted>
        <value><fullName>Score_1</fullName><default>false</default><label>1 – sehr dissatisfied</label></value>
        <value><fullName>Score_2</fullName><default>false</default><label>2 – dissatisfied</label></value>
        <value><fullName>Score_3</fullName><default>false</default><label>3 – neutral</label></value>
        <value><fullName>Score_4</fullName><default>false</default><label>4 – satisfied</label></value>
        <value><fullName>Score_5</fullName><default>false</default><label>5 – sehr satisfied</label></value>
    </valueSetDefinition>
</valueSetDefinition>
```

`required=false` is deliberate: the obligation comes from the ValidationRule, **not** from the field flag — a required field would block open Cases too (AC3-shape, house SCRUM-434 `Ursache__c`, which is deployed and green).

Collision check (verified against `origin/master @ d21d380`): `force-app/main/default/objects/Case/fields/` carries 40 fields, none named `Customer_Satisfaction*`, `Satisfaction*`. 0 Treffer.

### 1.2 New fields on `Account` (all system-maintained, read-only for every user)

| DeveloperName | API Name | Type | Label | Semantik |
|---|---|---|---|---|
| `Satisfaction_Durchdurch` | `Satisfaction_Durchdurch__c` | Number(3,1) | Satisfaction Ø (3 Monate) | Ø of `Customer_Satisfaction__c` over Cases with `IsClosed=true AND CloseDate >= window_start`. **null** = no closed Case in the window (PO-Decision). |
| `Satisfaction_Min` | `Satisfaction_Min__c` | Number(1,0) | Satisfaction min (3 Monate) | Minimum over the same window; null = no data. Needed to express the PO-rule "at least one Case with score 1 or 2". |
| `Satisfaction_Fenster_Start` | `Satisfaction_Fenster_Start__c` | Date | Ø-Fenster seit | `today.addMonths(-3)` — the window the average was measured over (AC6 demands the period be visible). |
| `Satisfaction_Anzahl` | `Satisfaction_Anzahl__c` | Number(6,0) | Cases in Ø-Fenster | Count behind the average; makes "no data" countable and guards the AC-criterion-against-zero rule. |
| `Satisfaction_Arger` | `Satisfaction_Arger__c` | **Text (Formula)** | Status ärger? | `'Kein Daten'` if Ø is null; `'Ärger'` if Ø < 3.0 **or** min ≤ 2; else `'OK'`. |

Formula field shape (house SCRUM-398 `Eskalationsstufe__c` / SCRUM-394 `Data_Quality__c`): `type=Text`, `required=false`, `trackTrending=false`, **no `<length>`**, **no `precision`/`scale`**.

```xml
<formula>IF(ISBLANK(Satisfaction_Durchdurch__c), "Kein Daten", IF(OR(Satisfaction_Durchdurch__c &lt; 3, Satisfaction_Min__c &lt;= 2), "Ärger", "OK"))</formula>
<formulaTreatBlanksAs>BlankAsNull</formulaTreatBlanksAs>
```

⚠️ `formulaTreatBlanksAs` must **not** be `BlankAsZero` — the house value would turn "no data" into `0`, which is `< 3` → every customer without closed Cases would read `Ärger`. That contradicts the PO decision explicitly. **Deploy-verified by the Developer; if the Org rejects `BlankAsNull` on this formula, the fallback is a system-maintained Picklist `Satisfaction_Arger__c` written by the Rebuilder (three Values, same semantics) — not a BlankAsZero formula.**

### 1.3 Reminder artefact — `Task`, not a new Case field

The follow-up obligation is a **standard `Task` record**, not another Case field:

| Task-Attribute | Value |
|---|---|
| `WhatId` | the Case Id (links Task → Case; Task is not a child of Case — SCRUM-440 house, `RueckrufTaskHandler`) |
| `OwnerId` | the Case `OwnerId` = responsible customer representative |
| `Subject` | `'Nachbetreuung: ' + Case.Subject` — byte-exact prefix `Nachbetreuung: ` (with trailing space), the idempotency key |
| `Status` | `Not Started` |
| `Priority` | `High` |
| `ActivityDate` | due date = 2nd Werktag after `CloseDate` (Task has **no** `DueDate` — verified in SCRUM-440 §1.2) |

Why not a Case field: AC4 ("not reminded several times for the same Case") and AC3 ("the representative gets a reminder") both name an *obligation with an owner and a due date*. A Checkbox cannot express due-date, owner, or "worst first" ordering; a Task does, and it is the house artefact for exactly this (SCRUM-440).

**Naming collision avoided deliberately:** SCRUM-436 already owns `Reminder_Required__c`, `Reminder_Due_Date__c`, `Reminder_Count__c` on Case — those mean *Wiedervorlage of an OPEN Case* (SCRUM-436 ADR). SCRUM-442 must not touch, read, or reuse them; the semantics differ (open-case churn vs. closed-case follow-up). Same lesson the SCRUM-436 design recorded against SCRUM-418's `Reactivation_Count__c`.

---

## 2. Components (exact paths)

1. **Custom Picklist field** — `force-app/main/default/objects/Case/fields/Customer_Satisfaction__c.field-meta.xml`
2. **ValidationRule (mandatory at closing)** — `force-app/main/default/objects/Case/validationRules/Customer_Satisfaction_PflichtBeiClosed.validationRule-meta.xml`
3. **Permission Set — Read** — `force-app/main/default/permissionsets/SCRUM442_Satisfaction_Read.permissionset-meta.xml`
4. **Permission Set — Write** — `force-app/main/default/permissionsets/SCRUM442_Satisfaction_Write.permissionset-meta.xml`
5. **Case-Layout section** — `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` (new `<layoutSection>` label `Kundansatisfaction`, before `System Information`; house: SCRUM-434 added `Rückschau` at line ~335, SCRUM-438 `SLA` at ~388)
6. **Account-Layout items** — `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml` (the 5 Account fields, `behavior=Readonly`; house: SCRUM-431 added `Wartungsvertrag__c` into the Account Information section)
7. **`SatisfactionTaskHandler.cls`** — creates/repairs the follow-up Task, called from the Case trigger
8. **`CaseSatisfactionTrigger.trigger`** — `on Case (after update, after insert)` → one handler call per operation (house: "ein Trigger pro Objekt", SCRUM-440)
9. **`AccountSatisfactionRebuilder.cls`** — nächtlich Vollrecompute of the 4 system Account fields over the whole Account stock (house: `OpenOpportunityHistoryRebuilder` SCRUM-417, `AccountReactivationBatch` SCRUM-388)
10. **`AccountSatisfactionScheduler.cls`** — `Schedulable`, starts only the Rebuilder (house: `OpenOpportunityHistoryScheduler`, `CaseReminderScheduler`)
11. **Report (overview AC6)** — `force-app/main/default/reports/Sales/Miserable_Kunde_Satisfaction.report-meta.xml`
12. **Apex tests + FLS test** — `force-app/test/classes/SCRUM442SatisfactionTest.cls`, `SCRUM442SatisfactionFlsTest.cls`, `SCRUM442AccountRollupTest.cls` (+ `-meta.xml`), manifest `manifest/scr442-phase1-fields.xml`, `manifest/scr442-phase2-referencing.xml`, `manifest/scr442-apextests.xml`
13. **E2E spec** — `tests/e2e/SCRUM-442-kundansatisfaction.spec.ts` (house: `SCRUM-440-rueckruf-opportunity.spec.ts`, `SCRUM-378_lead-nachfassliste.spec.ts`)

---

## 3. AC → Artefact (Review-Kontrakt — every criterion needs a named artefact)

| AC | Behauptung | Beweise, muss existieren |
|----|-----------|--------------------------|
| AC1 | Closing without score refused, Case still open | **ValidationRule** (harte Block, not a warning) + Apex-Test: `Status='Closed'` with blank score → `System.Exception` / DML rollback, record unchanged |
| AC2 | Score 4 stored together with CloseDate, visible to Sales | Apex-Test (score + `CloseDate` non-null after save) + FLS-Test `isAccessible()` in the Sales-shaped profile |
| AC3 | Low score → automatic reminder due within 2 Werktag | Apex-Test: Task created, `OwnerId == Case.OwnerId`, `ActivityDate == nthWorkingDayAfter(CloseDate, 2)`; **plus** E2E that the Task is visible in the rep's To-Do list (not an email) |
| AC4 | Reopen + reclose → no second reminder | Apex-Test: second closing, `Task WHERE WhatId = caseId AND Subject LIKE 'Nachbetreuung:%'` count **stays 1** |
| AC5 | Average over last 3 months + Ärger-Indicator at the customer | Apex-Test on the Rebuilder (avg/min/count/window for a seeded Account) + E2E on the Account detail page |
| AC6 | Overview lists exactly the dissatisfied customers, shows customer/score/period | `.report-meta.xml` (grouping `ACCOUNT.NAME`, filter on low score, timeFrameFilter) + E2E on the Report |
| AC7 | Sales cannot change a rating | FLS-Test: `isUpdateable() == false` in the Sales shape, write attempt throws, value unchanged |
| AC8 | Non-Service person not offered the rating | FLS-Test: without `SCRUM442_Satisfaction_Write` the field is not `isAccessible()`/`isUpdateable()` → not offered on the closing form; E2E on a Sales-shaped user |

**Coverage rule for the Tester:** AC5/AC6 need a **non-zero** record count. A Test-Org without any closed Case carrying a score matches zero records → that row is `UNTESTED`, not `PASS` (AGENTS.md, SCRUM-394/398). The Rebuilder test must seed its own Cases; the Report E2E must assert a row count > 0.

---

## 4. ADR — Apex vs. Flow vs. declarative

**ADR-1: Apex for the reminder and the Account rollup; declarative for the block and the field.**
- The block (AC1) is declarative: a **ValidationRule** rejects the save on *every* DML path — console UI, REST/CLI, queue paths (SCRUM-421/422), Apex, data import. That is exactly the PO's "must hold for every closing path". An Apex `try/throw` would be path-dependent and would not cover import. House: SCRUM-434 `Ursache_PflichtBeiGeschlossen`, SCRUM-440 ValRule pair — both deployed and green.
- The reminder is **not** declarative-expressible: it creates a record on a *different* object (`Task`) with computed due-date arithmetic and an idempotency lookup → Apex (branching + bulk + likely to evolve).
- **Flow is not used anywhere.** Flows fail repeatedly here (strict XML schema, `apiVersion` drift, xmllint) and a Flow runs per-record, not over the Account stock at night. No Flow → no `apiVersion`/naming decision to specify; the `apiVersion` of every artefact is the target's `sfdx-project.json` value (currently 62.0 in the repo, 67.0/68.0 in the org reads — Developer: take it from the target, do not hardcode).

**ADR-2: Picklist, not Number, for the score.**
- Picklist refuses `0`, `6`, `3.5` at the platform level — a Number field would need a second ValidationRule for the range.
- It is the deployed house shape (`Ursache__c`, `Loss_Reason__c`).
- The average is computed in Apex (`VALUE(TEXT(s))`), so the numeric loss costs nothing.
- Cost: the Report cannot `Avg` a Picklist column. Mitigated by the Account Number fields (§1.2) — the Report groups on those, not on the Picklist.

**ADR-3: Nächtlich Vollrecompute for the Account fields, not an immediate Trigger.**
- The window is *rolling* (`today − 3 months`). It changes every day even without any data change; an immediate Trigger would freeze the window at the last closing and drift silently.
- House: SCRUM-388 `AccountReactivationBatch` (threshold over a rolling period) and SCRUM-417 `OpenOpportunityHistoryRebuilder` (Vollrecompute, idempotent, heals drift).
- Cost: the Account view is up to one day stale after a closing. The **Task** (AC3) is created immediately in the trigger, so the follow-up obligation is never late — only the customer-side average lags. State this to the PO as a decision, not a surprise.
- Alternative (immediate recompute of the affected Account in the Case trigger) is *additive*, not exclusive: the Rebuilder must be idempotent so both can coexist. Default: nächtlich only.

**ADR-4: Working-day arithmetic = Mo–Fr, no holidays, no `BusinessHours` object.**
Same convention as SCRUM-436 ADR-2, so the two tickets agree. Reuse the verified epoch anchor (`1970-01-01` = Thursday, `Math.mod(daysSinceEpoch, 7)`, Mo–Fr = w ∈ {4,5,6,0,1}); Apex `Date` has **no** `dayOfWeek()` (org-verified in SCRUM-436). New helper needed: `nthWorkingDayAfter(Date from, Integer n)` — the inverse of SCRUM-436's `workingDaysBetween`. Counting convention: the closing day itself does **not** count; a Friday closing with n=2 is due **Tuesday**. PO-decision, non-blocking.

**ADR-5: `without sharing` on Handler/Rebuilder, and it does not bypass FLS.**
House SCRUM-436/437/438 lesson: Apex DML checks FLS even in `without sharing` classes. Therefore the Write-PS (§5) is required for the *Handler* path (it writes the score? no — it writes the **Task**) and for the *Rebuilder* (it writes the Account fields). Task FLS is object-level CRUD, not field-level — but the Rebuilder's Account-field writes need the System-PS.

---

## 5. FLS / Permission Sets — per PS, never Profile

Two PS, house model Read-PS + Write/System-PS (`SCRUM436_CaseReminder` + `SCRUM436_CaseReminderSystem`, `SCRUM438_SLA_Read` + `SCRUM438_SLA_System`):

1. **`SCRUM442_Satisfaction_Read`** — `readable=true, editable=false` on `Case.Customer_Satisfaction__c` **and** on all five `Account.Satisfaction_*` fields. → assigned to **Sales / Customer Service staff** (Vertriebsleitung, Account Manager) and to the Service team (they need to read what they wrote).
2. **`SCRUM442_Satisfaction_Write`** — `readable=true, editable=true` on `Case.Customer_Satisfaction__c` only. → assigned to **Service colleagues** (the ones closing Cases).
3. **`SCRUM442_Satisfaction_System`** — `readable=true, editable=true` on the four *system-maintained* `Account.Satisfaction_*` fields (not the formula field — formula fields take no FLS write). → assigned to the **Rebuilder's scheduled/automation user** only.

PO-table mapping: Service = Create/Read/Edit yes, Delete no → `Write` PS grants create+edit via FLS; object-level delete stays out of any PS (never grant `Case` object CRUD in a field PS). Sales = Read only → `Read` PS, `editable=false` everywhere. Customers/external → no PS, and the field's default FLS stays OFF (house SCRUM-440 note: "Standard-FLS for new fields stays OFF").

⚠️ **FLS default of a new SF field is not predictable** (measured: SCRUM-421 read+edit in the standard profile, SCRUM-430 not). Do **not** infer from either. The FLS test must measure its own negative probe in the target profile (`System.runAs()` on a temp user without the PS → `isAccessible()==false`), house `SCRUM440RueckrufwunschFlsTest` / `SCRUM436CaseReminderFlsTest`.

⚠️ **Deploying a PS grants nothing until it is assigned.** The Developer handoff comment must carry the `PermissionSetAssignment` read-back **and** one field read through a real session holding it — for the CLI target-org user *and* the human test account. Six tickets shipped a PS assigned to nobody (SCRUM-382/386/388/390/394/398).

⚠️ `sf data query` refuses `FieldPermission`/`FieldPermissions` ("not supported", also with `--use-tooling-api`) — a 0-row result from such a query proves nothing. Use `scripts/fls-check.sh <Object> <Field>`.

---

## 6. Sharing model

- **No OWD change, no role-hierarchy change** (PO). `Case` stays owned by Customer Service, `Account` above in Sales.
- The story crosses the boundary **downward-reading**: the rating is created on `Case`, the overview is shown on `Account`. A Sales employee can read the Account fields only for Accounts he can already see — the sharing rules are untouched, so the "never see more" requirement holds by construction.
- The Rebuilder runs `without sharing` — deliberate (house SCRUM-365/388/417): the recompute must be deterministic over the whole stock, independent of the scheduled user's sharing. **`without sharing` does not bypass FLS** → the System-PS (§5.3) stays mandatory.
- ⚠️ **Read-path caveat for the Tester:** a Sales employee who cannot see the `Case` records under OWD will still see the aggregated `Account` numbers. That is the PO's intent (the score is *not* shown to the customer, the aggregate is shown to Sales staff). It is a deliberate disclosure decision — flag it in the review, do not "fix" it by hiding the fields.

---

## 7. Governor limits

- **Trigger/Handler:** 0 SOQL in the trigger; handler = 1 SOQL (`Task WHERE WhatId IN :caseIds AND Subject LIKE 'Nachbetreuung:%'`) + 1 bulk insert + 1 bulk update per batch, no SOQL in loops. Re-entry guard `static Boolean hasFired` in `try/finally` (house SCRUM-440, SCRUM-419, SCRUM-421) — the handler's own Task-write must not re-fire the Case trigger (it does not touch Case fields, so the guard is a safety net, not the mechanism).
- **Rebuilder:** QueryLocator over the **whole Account stock** in 200-chunks (house SCRUM-388/417), one aggregate SOQL per chunk (`AVG`/`MIN`/`COUNT` grouped by `AccountId`), 1 conditional bulk DML per chunk, 0 SOQL in loops. `WHERE Status = 'Closed' AND CloseDate >= :windowStart AND Customer_Satisfaction__c != null` — the date bind is a `Date` literal computed once, not per record.
- ⚠️ SOQL date-bind caveat the house already hit (SCRUM-417): a `Date` bind is cast to midnight of that day — fine here (day-granularity window), but do not pass a `Datetime` expecting sub-day precision.
- ⚠️ `SUM(CASE WHEN …)` aggregate expressions are rejected by the Org compiler (SCRUM-420 deploy error). Compute avg/min/count in Apex from the fetched rows, or use plain `AVG()/MIN()/COUNT()` aggregates.
- **Scheduled job is a runtime object, not metadata** — `System.schedule('SCRUM-442 Satisfaction', '0 0 4 * * ?', new AccountSatisfactionScheduler())` must be created in the Org. Taken slots: 01:00 SCRUM-436, 02:00 SCRUM-388, 03:00 SCRUM-417, 06:00 SCRUM-319/414 → **04:00 proposed, DevOps must check for collision in the Org.** Without this step the code is deployed but never runs.

---

## 8. ⚠️ Befund — Legacy closed Cases

The ValidationRule blocks **any** save of an already-closed Case that carries no score. Existing closed Cases in the Org (SCRUM-434's org read: 38 `Closed` of 652 in Test-Org) have no score → after this deploy, editing such a Case (owner change, priority change, closing a related record) throws.

House precedent: SCRUM-434 shipped exactly this shape and CI is green — the house accepts the consequence. Options, in order of preference:
1. **Accept** (default, house-faithful). The Tester must include one negative test: an existing closed Case without score cannot be edited — and that is the *expected* behaviour, not a defect.
2. Gate the rule on `ClosedDate >= <deploy-date>` — excludes legacy Cases but makes the rule time-dependent and silently weak for anything backfilled later. Not recommended.
3. Backfill legacy closed Cases with a neutral score — invents data the PO never asked for. Not recommended.

**PO: confirm option 1.** Non-blocking for the build; blocking for the Tester's interpretation of "editing an old closed Case fails".

---

## 9. Report (AC6) — shape

`reportType=CaseList`, `scope=organization`, `<scope>org</scope>` (source-persistable — house SCRUM-394 ADR-5a; report-level *sharing* is an Org step, not source). Grouping `ACCOUNT.NAME`; columns: `ACCOUNT.NAME`, `Satisfaction_Durchdurch__c`, `Satisfaction_Min__c`, `Satisfaction_Fenster_Start__c`, `Satisfaction_Anzahl__c`, `CASES.CASE_NUMBER`, `CASES.STATUS`. Filter: `Satisfaction_Arger__c equals Ärger`. `timeFrameFilter` on `CLOSED_DATE`, `INTERVAL_LAST3MONTHS` — ⚠️ the interval token must come from the platform, not from memory: Developer, read the CLI's `metadataRegistry.json` / the Report schema before writing it; if `INTERVAL_LAST3MONTHS` is not a valid token, use `INTERVAL_CUSTOM` with the house `timeFrameFilter` shape from `reports/Sales/Betreuungslast_nach_Firma.report-meta.xml`.

⚠️ **ListView is not the vehicle here.** The house `ListView` schema (CLI `metadataRegistry.json`) has no sort element, and standard ListViews are not retrievable via `sf project retrieve` (SCRUM-432). AC6 asks for "sorted worst first" — that is a Report property (Org/UI), not source. State it as an Org step for DevOps, not as a repo artefact.

⚠️ Report column tokens for cross-object fields are only verifiable via deploy-validate (SCRUM-432 finding); the `ACCOUNT.NAME` / `CASES.*` tokens above are the house-verified forms from the deployed reports, the `Satisfaction_*` tokens are this ticket's own custom fields and resolve plainly.

---

## 10. Data classification / exposure

The score is internal and sensitive. It must never reach the customer, an external party, or a public Experience Cloud page.
- No field here is exposed on any public FlexiPage/Experience Cloud artefact; the repo tracks only Classic layouts (Lightning FlexiPages live in the Org). **Org step for DevOps:** if the Customer Service/Service console FlexiPage shows the Case section, the FLS of the viewing user governs visibility — do not add the field to any public-facing page.
- The `Account` fields are aggregates, not the individual score, and are FLS-gated to Sales staff. The individual score stays on `Case`.

---

## 11. Open Points (owner + blocking assessment)

- [ ] **non-blocking, @po-agent** — Labels of the five Picklist values: only the endpoints (1 = very dissatisfied, 5 = very satisfied) are fixed by the PO; the middle labels above are my default. Confirm or replace.
- [ ] **non-blocking, @po-agent** — "last 3 months" = `today.addMonths(-3)` (calendar-month arithmetic, stored in `Satisfaction_Fenster_Start__c`). Alternative: fixed 92 days. Default: calendar months.
- [ ] **non-blocking, @po-agent** — Legacy closed Cases without score (§8): option 1 (accept) is the default.
- [ ] **non-blocking, @devops-agent** — Org steps: `System.schedule` CRON entry (04:00 proposed, collision-check), Report folder sharing for the Sales overview, Report sort "worst first" (UI property), Lightning/Customer-Service console placement of the Case section.
- [ ] **blocking-for-Review, Developer handoff must carry** — the PS read-back: `PermissionSetAssignment` list for all three PS plus one `Account.Satisfaction_Durchdurch__c` and one `Case.Customer_Satisfaction__c` read through a real session holding them.
- [ ] **not verifiable by me** — every Org fact in this doc (Picklist value sets, Task picklists, interval tokens) is Reused from SCRUM-436/440 or flagged as needing a fresh read. I ran no command against any Org for this ticket; the Developer must read back before the first deploy.

---

## 12. Für @user

- **Was beim Speichern eines geschlossenen Fall happens:** once a Service colleague closes a Case, the system refuses the save as long as no satisfaction score 1–5 was entered — the Case stays open and gets a message that the score is missing. This holds in the console, in the mobile/queue paths and via API/import alike, not only in the one UI form.
- **What the customer representative sees:** a low score (1 or 2) creates one to-do item ("Nachbetreuung: …") assigned to the representative who owns the Case, with a due date two working days after the closing (a Friday closing is due Tuesday). It is a real to-do record in the org, not an email — it cannot be lost in a mailbox, and it is created only once per Case even if the Case is reopened and closed again.
- **What the Sales department sees at the customer:** on the customer page four new, read-only figures — the average satisfaction of the Cases closed in the last three months, the lowest score in that window, the window start and how many Cases were measured — plus one word: `OK`, `Ärger` or `Kein Daten`. A customer without any closed Case in the window reads `Kein Daten`, never `OK`.
- **What the Sales management sees:** a Sales overview report listing exactly the customers that read `Ärger`, with the score and the period it was measured over.
- **Who can change what:** Service colleagues can enter the score, Sales staff can only read it — enforced per field via Permission Sets, no profile was touched.

---

*Autoritative Build-Spec. Repo-Dateien are the source of truth, not the Jira comment (Jira-Markup corrupts `__c`, XML tags and `+`). Survey basis: `origin/master @ d21d380`.*
