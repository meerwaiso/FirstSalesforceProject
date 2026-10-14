# SCRUM-449 — Opportunity Risk Level: Architecture-Design (Build-Spec)

Author: architect-agent · Date: 2026-10-14 · Repo survey: `origin/master` (see Commit below) · Org survey: Test-Org

---

## 0. Ziel

Automatic, never hand-maintained risk assessment on the standard object `Opportunity`:
Risk Level (Low/Medium/High/empty), Risk Reason (names every condition that applies),
Inactive Days, Last Risk Evaluation — event-driven (trigger) plus time-driven
(nightly scheduler), bulkified, FLS read-only for every human user.

---

## 1. Data Model — 6 new fields on `Opportunity` (BEFORE any code)

| # | API Name | Type | Shape | Written by | FLS |
|---|---|---|---|---|---|
| 1 | `Risk_Level__c` | Picklist (restricted) | values `Low`/`Medium`/`High`, **no default, blank = nothing applies** | Apex (trigger + scheduler) | View only |
| 2 | `Risk_Reason__c` | Text, length 255 | German sentence(s), one clause per applying condition | Apex | View only |
| 3 | `Inactive_Days__c` | Number, precision 10, scale 0 | **Formelfield** — `IF(IsClosed, NULL, IF(ISBLANK(Last_User_Change__c), NULL, TODAY() - Last_User_Change__c))` | Formula (system) | View only, never writable |
| 4 | `Last_Risk_Evaluation__c` | Datetime | stamped on every recompute (trigger and scheduler) | Apex | View only |
| 5 | `Last_User_Change__c` | Datetime | **anchor**: last change made by a *user*; seeded once by the scheduler from `LastModifiedDate` | Apex (trigger in user tx, scheduler for seeding) | View only |
| 6 | `Highest_Stage_Reached__c` | Picklist (restricted), same 10 values as `Stage__c` | high-water mark for C4 | Apex | View only |

Fields 5 and 6 are **internal support fields**, not new business information: they exist
because C1 ("no *user* change") and C4 ("highest stage *previously reached*") are state
the org does not keep. They get the same read-only FLS as the four business fields, so
the Tester can read them; no human may edit them either.

All six need their own explicit `fieldPermissions` entry — FLS is never inherited from
object-level CRUD.

### Field XML (house pattern, verified against SCRUM-414/416/417 files in repo)

```xml
<!-- Risk_Level__c -->
<CustomField>
  <fullName>Risk_Level__c</fullName>
  <type>Picklist</type>
  <restricted>true</restricted>
  <picklist>
    <picklistValues>
      <picklistValue><label>Low</label><defaultValue>False</defaultValue></picklistValue>
    </picklistValues>
    <picklistValues>
      <picklistValue><label>Medium</label><defaultValue>False</defaultValue></picklistValue>
    </picklistValues>
    <picklistValues>
      <picklistValue><label>High</label><defaultValue>False</defaultValue></picklistValue>
    </picklistValues>
    <restricted>true</restricted>
  </picklist>
  <label>Risk Level</label>
</CustomField>
```

`Inactive_Days__c` is a **Text/Number formula field**: Number takes
`<precision>10</precision><scale>0</scale>` and **no `<length>`** (house rule from
SCRUM-394: `<length>` is Text-only and is rejected on formula Numbers; SCRUM-414
`Days_Close_Date_Overdue__c` is the working template).

---

## 2. Stage order — read from the org, not assumed

`sf api request rest /services/data/v64.0/sobjects/Opportunity/describe --target-org Test-Org`
returned the `StageName` picklist in configured order (all values active):

| Pos | Value |
|---|---|
| 1 | Prospecting |
| 2 | Qualification |
| 3 | Needs Analysis |
| 4 | Value Proposition |
| 5 | Id. Decision Makers |
| 6 | Perception Analysis |
| 7 | Proposal/Price Quote |
| 8 | Negotiation/Review |
| 9 | Closed Won |
| 10 | Closed Lost |

**Early stage = first half = positions 1–5** (Prospecting … Id. Decision Makers).
10 values → half = 5, no middle-value ambiguity.

Apex cannot read picklist order at runtime → the order lives as a
`static Map<String, Integer> STAGE_ORDER` in the risk service, **and** a test class
asserts the map equals the org picklist (so a later org change fails loudly instead of
silently mis-ranking). The developer must copy the table above, not a remembered list.

---

## 3. "Open" — correction of the PO's wording

The PO wrote `Status = Open`. **Verified against Test-Org:** `SELECT Status FROM Opportunity`
fails with `No such column 'Status' on entity 'Opportunity'` — there is no `Status` field.
The house Single Source of Truth (ADR-3 of SCRUM-416, reused in SCRUM-417) is:

> **open ⇔ `IsClosed = false`** (equivalently `StageName ∉ {Closed Won, Closed Lost}`).

Use `IsClosed` everywhere — trigger, scheduler, formula, tests. This is the one place the
ticket text and the platform disagree; the design follows the platform.

---

## 4. Components

```
OpportunityRiskTrigger            (force-app/main/default/triggers/)
   before insert  -> OpportunityRiskGuard      (block nothing; seeds anchor)
   after insert   -> OpportunityRiskHandler.handleInsert(newRecords)
   after update   -> OpportunityRiskHandler.handleUpdate(newRecords, oldMap)
   after delete   -> no-op (record gone)
   apiVersion 62.0 (house: existing OpportunityOverdueReset.trigger)

OpportunityRiskService            (classes/)  — the ONLY place the rules live
   static evaluate(List<Opportunity>, Map<Id,Opportunity> oldMap) :
     - bulkified: one SOQL for support fields of the batch, never SOQL in a loop
     - computes C1..C4, level, reason, stamps Last_Risk_Evaluation__c
     - updates Highest_Stage_Reached__c and Last_User_Change__c
   static recomputeAll()          — full-scan, chunked DML (scheduler path)

OpportunityRiskScheduler          (classes/, implements Schedulable)
   -> OpportunityRiskService.recomputeAll()
   CRON proposal: 0 0 4 * * ?   (02:00 = SCRUM-388, 03:00 = SCRUM-417, 06:00 = SCRUM-319/414)

SCRUM449OpportunityRisk           (permissionsets/)  READ  — editable=false, readable=true, all 6 fields
SCRUM449OpportunityRiskWrite      (permissionsets/)  WRITE — editable=true, ONLY the system/scheduler user

Tests (house pair, see §7):
SCRUM449OpportunityRiskTest.cls
SCRUM449OpportunityRiskFlsTest.cls
tests/e2e/SCRUM-449-risk-level.spec.ts
```

**No new trigger on top of the existing one is optional** — `OpportunityOverdueReset`
already runs on Opportunity (SCRUM-319/381/384/416). Salesforce does **not** guarantee
ordering between triggers on the same object, so the risk service must not read anything
another trigger wrote in the same transaction. It reads only record data plus its own
support fields. (Alternative — extending the existing trigger — is rejected: it would
couple four tickets' logic into one file and make the ordering assumption invisible.)

---

## 5. Rules → code contract (pseudocode)

```
evaluate(rec, old):
  if rec.IsClosed:                       level = null; reason = null      // AC7
  else:
    anchor = rec.Last_User_Change__c
    if anchor == null: anchor = seed(rec.LastModifiedDate)                // legacy records
    inactiveDays = TODAY - anchor                                        // also the Number formula
    C1 = inactiveDays > 14
    C3 = rec.CloseDate != null && rec.CloseDate < TODAY                  // open & past close date
    C2 = rec.CloseDate != null && TODAY < rec.CloseDate <= TODAY+7
         && STAGE_ORDER[rec.StageName] <= 5                              // early stage
    high = max(STAGE_ORDER[Highest_Stage_Reached__c], STAGE_ORDER[rec.StageName])
    setback = high - STAGE_ORDER[rec.StageName]
    C4 = setback >= 1
    C4_high = setback > 1                                                // AC4: exactly 1 = warning only

    warnings = count(C1, C2, C4 && !C4_high)
    if C3 or C4_high:        level = High
    elif warnings >= 2:      level = Medium                              // AC5
    elif warnings == 1:      level = Low                                 // AC1
    else:                    level = null; reason = null                 // AC8

    reason = join of the German clauses for EVERY applying condition      // AC2/AC4 wording
  Highest_Stage_Reached__c = value at position `high`
  Last_Risk_Evaluation__c  = Datetime.now
```

Reason text (255 chars, German, one clause per condition, must name each):
`"Inaktivity: 21 days without user change; Close date already passed (CloseDate 30.09.2026); Stage setback: 2 positions below the highest stage reached (Value Proposition)."`

---

## 6. ADR — Apex, not Flow, not pure formula

**Decision: Apex (trigger + service + scheduler), with one formula field.**

- **Why not Flow:** branching across four conditions with a high-water mark, counting of
  warnings, German reason text assembled per condition, and bulk import behaviour. Flows
  have repeatedly failed here (strict XML schema, `apiVersion` drift, schema-validation
  failures) and a Flow cannot express a high-water mark or a counted warning set at all.
  AGENTS.md hard rule: no Flow for non-trivial logic without an ADR justifying it — here
  the ADR argues the opposite way.
- **Why not pure formula fields:** `Risk_Level__c` and `Risk_Reason__c` need the *highest
  stage previously reached*, which no formula can read (`OpportunityFieldHistory` is not
  a queryable sObject — verified: `SELECT ... FROM OpportunityFieldHistory` →
  `sObject type 'OpportunityFieldHistory' is not supported`). C4 is therefore stateful
  Apex by necessity. `Inactive_Days__c` stays a formula because it is a pure function of
  `Last_User_Change__c` and `TODAY()` — it must stay correct between evaluations, and a
  formula is the only shape that does.
- **Why event + nightly, not nightly only:** AC6 demands the level/reason reflect a
  representative's change *without any manual action*; a nightly-only job leaves the record
  stale for hours. AC11 (bulk import) and AC10 (org-wide consistency) are covered by the
  same service on both paths. The nightly job exists because C1 and C3 are time-based:
  they change with the calendar, not with a record edit.
- **Why a second `..._Write` PS (SCRUM-388/436 house pattern):** the trigger path writes
  inside the *user's* transaction. Measured 2026-10-02 (SCRUM-436, probe run
  `707WU00001LcArj`): a user with read-only FLS triggered a system write of a read-only
  field with **no** FLS exception — so the trigger path needs no Write-PS. The scheduled
  batch path runs as one single scheduled user and the org holds no proof for it; the
  house therefore ships `SCRUM449OpportunityRiskWrite` for the scheduler user only.
  **AC9 stays satisfied**: no *human* profile gets editable=true on any of the six fields.

---

## 7. Permission Set design (never Profile edits)

`SCRUM449OpportunityRisk` — read-only, all six fields explicit:

```xml
<PermissionSet>
  <fieldPermissions>
    <editable>false</editable>
    <field>Opportunity.Risk_Level__c</field>
    <readable>true</readable>
  </fieldPermissions>
  ... (Risk_Reason__c, Inactive_Days__c, Last_Risk_Evaluation__c,
       Last_User_Change__c, Highest_Stage_Reached__c — same shape)
  <hasActivationRequired>false</hasActivationRequired>
  <label>SCRUM449OpportunityRisk</label>
</PermissionSet>
```

`SCRUM449OpportunityRiskWrite` — same six fields with `editable=true`, assigned **only**
to the CLI target-org user that runs the scheduler (the user the nightly job executes as).
Never to Sales Reps / Sales Managers.

**Assignment is half the work** (measured six times on this project): deploying a PS grants
nothing. The Developer-Handoff comment must carry the read-back:
`SELECT PermissionSetAssignment FROM <user>` showing both PS assigned, plus one field
read back through a real session. Without it the first symptom is a `No such column`
SOQL error that reads like a missing field, not like a permission.

**FLS default of a new field is not predictable** — do not extrapolate from a Profile block.
The negative proof belongs in `SCRUM449OpportunityRiskFlsTest` (house shape
`SCRUM382...FlsTest`): `runAs` a user *without* the PS, assert the field is not readable /
not writable; `runAs` a user *with* the PS, assert readable and **not writable** (AC9).

---

## 8. Sharing / OWD consequence

`Opportunity` standard sharing applies. No new sharing rule, no owner-based restriction,
no OWD change requested or made. Consequence stated: the six fields are FLS-gated, not
sharing-gated — a user who can open the record sees them (PS read), a user who cannot
open the record sees nothing at all. That satisfies the data-classification requirement
(competitive pipeline information never leaks to users who cannot open the Opportunity).
No record-owned-by-other-rep restriction is in play for Opportunity here; AC10 is about
consistency of derivation, not about access.

---

## 9. Governor-limit risks and mitigation

| Risk | Mitigation |
|---|---|
| SOQL in a record loop | Service does **one** SOQL for the batch's support fields (`WHERE Id IN :ids`), never inside the loop. Bulkified throughout. |
| Trigger recursion (own writes re-firing the trigger) | House pattern: static `hasFired` guard in the handler (as in `OpportunityOverdueResetHandler`) — one evaluation per transaction. |
| Bulk import of many records (AC11) | `after insert`/`after update` receive the whole chunk; evaluation is pure Apex over the batch, DML happens on the records in-hand (no extra save). Chunked DML in the scheduler path (2000-record chunks, house pattern from SCRUM-417). |
| Nightly full scan | `recomputeAll()` = 1 selective SOQL over open Opportunities (`WHERE IsClosed = false`), chunked DML. Test-Org holds **73 open / 127 total** Opportunities today — one query, no pagination risk today; the code must still chunk for Prod growth. |
| Mixed DML (support-field inserts vs. business inserts) | No new sObject is created — all six fields live on `Opportunity`. No PSA insert in any test transaction that also inserts Account/Case records (SCRUM-442 lesson): keep the FLS-negative proof in its own transaction. |
| ValidationRule on a standard object reddening CI | **None added.** This story ships no ValidationRule — the Prod-Org Drift Gate therefore gains no new blocked-state test classes. |

---

## 10. Technical acceptance criteria (for the Tester, on top of the PO's AC1–AC12)

| PO AC | Artefact that must exist | Measured expectation on Test-Org today |
|---|---|---|
| AC1 Inactivity | Apex: open opp, anchor 15 days old → `Low`, reason names inactivity, `Inactive_Days__c` = 15 | **40 of 73** open opps have `LastModifiedDate` older than 14 days |
| AC2 Early stage + close in 7 days | Apex + reason text | **0 of 73** open opps currently have a CloseDate within the next 7 days → the Tester **must create** a record; a criterion measured on 0 records is *untested*, not PASS |
| AC3 Past close date = High | Apex | **13 of 73** open opps have a past CloseDate |
| AC4 Setback >1 = High, =1 = warning | Apex, both branches asserted | 0 records with a setback exist today → Tester creates them |
| AC5 Two warnings → Medium | Apex | derived, Tester constructs |
| AC6 Recalculation on change | Apex before/after update | — |
| AC7 Closed cleared | Apex, `IsClosed = true` → level/reason null | 54 closed opps exist (127 − 73) |
| AC8 Recovery → cleared | Apex | — |
| AC9 Nobody sets by hand | `SCRUM449OpportunityRiskFlsTest` `runAs` without Write-PS → write refused, stored value unchanged | — |
| AC10 Org-wide consistency | Apex over opps of different `AccountId` | 73 open opps across accounts |
| AC11 Bulk import | Apex `@isTest` inserting ≥ 200 opps, assert **every** record assessed (count = inserted count) | — |
| AC12 Filter + report | E2E/Playwright: list/report `Risk_Level__c = High` org-wide; fields are `groupable`/`sortable` (verified via describe) | — |

**No Apex assertion may encode an org-setup precondition** (TZ, profile FLS lock, OWD):
those belong in the Org-Setup table with a read-back, not in a CI-gated test class.

---

## 11. Deployment sequencing (phase manifests, house pattern)

1. `scr449-phase1-fields.xml` — the six fields (fields first; nothing references them yet).
2. `scr449-phase2-referencing.xml` — `SCRUM449OpportunityRisk`, `SCRUM449OpportunityRiskWrite`,
   the trigger, the service, the scheduler.
3. `scr449-phase3-apextests.xml` — `SCRUM449OpportunityRiskTest`, `SCRUM449OpportunityRiskFlsTest`
   (v67.0 house shape).
4. Org step (DevOps, not CI): `System.schedule('SCRUM-449 Risk Evaluation', '0 0 4 * * ?', new OpportunityRiskScheduler());`
   — Scheduled Jobs are **runtime objects, not metadata**: without this org step the code
   is deployed but never runs. Also: assign both PS to the CLI target-org user and to the
   human test account, then read back one field through a real session.

`apiVersion` for the trigger: **62.0** (house: `OpportunityOverdueReset.trigger-meta.xml`).
Manifest `<version>`: **67.0** (house: `scr414-phase2b-ps.xml`).

---

## 12. Naming decision

PO names → API names (Salesforce convention, requested spelling kept as Label):
`Risk Level` → `Risk_Level__c` (Label `Risk Level`), `Risk Reason` → `Risk_Reason__c`
(Label `Risk Reason`), `Inactive Days` → `Inactive_Days__c` (Label `Inactive Days`),
`Last Risk Evaluation` → `Last_Risk_Evaluation__c` (Label `Last Risk Evaluation`).

---

## 13. Open points (non-blocking, owner named)

- [ ] Cron slot 04:00 collides with an existing scheduled job? → **@devops-agent** checks in the Org.
- [ ] Which user runs the nightly job in Prod-Org (needs `SCRUM449OpportunityRiskWrite`)? → **@devops-agent**.
- [ ] Report/list-view placement for AC12 (a dedicated list view is *not* required by this story) → **@tester-agent** verifies filterability + a report; **@devops-agent** for any Org-side report setting (report-level "All users" sharing is not source-persistable).
- [ ] `Stage__c` picklist change in the Org later → the STAGE_ORDER test assertion turns it red; a re-read step belongs to **@devops-agent** at release.

---

## 14. Repo/Org findings that affect other agents

- ⚠️ `Status` does not exist on `Opportunity` (verified `INVALID_FIELD` on Test-Org). Use `IsClosed`.
- ⚠️ `Owner` does not exist on `Opportunity` either (verified `INVALID_FIELD`). The rep is `Owner` on the *Account*-side; the PO's field list is not usable as written.
- ⚠️ `OpportunityFieldHistory` is not queryable (verified `INVALID_TYPE`) → C4 needs the explicit `Highest_Stage_Reached__c` support field; there is no way to derive it at read time.
- ⚠️ The shared checkout sits on `feature/SCRUM-424-first-response` and holds leftovers from SCRUM-424/442/445 (modified Case test classes, `Case.object-meta.xml`, `Case/validationRules/`, several `docs/SCRUM-44*-*.md`). **Not mine — neither commit nor delete them.** My work lives in its own worktree on `feature/SCRUM-449-risk-level`.
- ⚠️ Test-Org counts today: 127 Opportunities, 73 open, 54 closed; C1 40, C2 0, C3 13. The zero for C2 is a gap the Tester must close by creating records — not a PASS.

