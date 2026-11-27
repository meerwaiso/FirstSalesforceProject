# SCRUM-483 — Architecture-Design: Sales-Austritt-Übergab

Autoritative Build-Spec. Der Developer baut **hier**, nicht vom Jira-Kommentar
(Konverter korruptiert Names — House-Pitfall SCRUM-375). Repo-Dateien are the
Source of truth.

Survey basis: `origin/master` @ **8718cb4** (fetched 2026-11-27), org reads
against **Test-Org** (2026-11-27). No deploy, no org write by the Architect.

## Ziel

At the moment a sales user is deactivated, their open Opportunities and their
Customers move to their manager (else to a fallback person sales management
chose), and the receiving person can see in one place what they got, from whom
and when — without a single other field, email or record type being touched.

---

## ⚠️ ORG MEASUREMENTS (Test-Org, 2026-11-27) — the design follows these, not the ticket wording

| Query (command in notizen) | Result |
|---|---|
| `SELECT Id,Name,IsActive,ManagerId FROM User` | **8 Users, `IsActive=true` for all 8, `ManagerId` NULL on all 8** |
| Account owner distribution (`GROUP BY OwnerId`) | 268 owned: Meerwais Osmani 12, Automated Process 1, **devops-agent 255** |
| Opportunity owner distribution | 157 owned: Meerwais 33, devops-agent 124 |
| `Opportunity WHERE IsClosed=false` | 89 open (68 closed) |
| `Account WHERE Is_Locked__c=true` | 4 — **0 of them with `Open_Opportunity_Count__c > 0`** |
| `SELECT Id,Name,Rep__c,Manager__c FROM DiscountApprovalManager__c` | **2 rows**, both directions between Meerwais ↔ devops-agent |
| `SELECT Id,Name FROM SalesUser` | **0 rows — no Sales Books / `SalesUser` object in this org** |
| Ownership object | standard `OwnerId` on `Account` and `Opportunity` (both `updateable=true`) |
| Stage / close-state fields | `Opportunity.StageName` picklist (10 values, `Closed Won` / `Closed Lost`), readonly `IsClosed` **and `IsWon`**; **`IsLost` does not exist** |
| Deactivation marker | `User.IsActive` (boolean, `updateable=true`) — exists and is writable |
| Manager field | `User.ManagerId` (reference → User, `updateable=true`) — exists, carries no data |

**Two corrections to the PO's decisions (PO asked for exactly this):**

1. *„their manager“ = the manager of that user in the user hierarchy* — the field
   exists (`User.ManagerId`) but is **NULL on all 8 users**; SCRUM-445 already
   measured why: „the role hierarchy is not usable here (UserRole: 18 standard
   roles, every ForecastUserId null)“ and built the **mapping object**
   `DiscountApprovalManager__c` (`Rep__c` → `Manager__c`, 2 rows, maintained by
   sales management via PS `SCRUM445_DirectManager_Map`). The hierarchy PO means
   is *this mapping*, not the Setup user hierarchy. → Resolution R-1 below.
2. *Sales people are recognised by their place in the hierarchy* — usable as: a
   user is „of sales“ iff he appears as `Rep__c` in that mapping. A purely
   ownership-based rule would hand over the Account of **Automated Process**
   (owns 1 Account, not a sales person) — AC10's negative case would be broken.

---

## ADR-1 · Apex, not Flow

Branching (target resolution over 3 sources), bulkified DML over 268 Accounts +
89 Opportunities, error handling with a compensating write, and an audit insert
in the same transaction. Flow has none of that cleanly (no atomic async, no
governor control, no try/catch) and has repeatedly failed deployment/schema
validation here. House decision, same as SCRUM-410 ADR-1 and SCRUM-449.
**→ Apex.**

## ADR-2 · Detection: scheduler, NOT a trigger on `User`

There is no hook on a user deactivation: no Apex trigger, no Validation Rule, no
Flow can observe „a User stopped being active“. (Unverified as a platform rule —
but the repo holds 28 triggers and **not one on `User`**, and every org-wide
state-scan in this repo is a Scheduler: `AccountReactivationScheduler` 388,
`CaseReminderScheduler` 436, `AccountSatisfactionScheduler` 442,
`OpenOpportunityHistoryScheduler` 417. `AccountSatisfactionScheduler` even
documents *why*: „Scheduled Jobs are LAUFTIME-Objects, KEINE Metadata — the
CRON-Entry is NOT created by a deploy and must be set in the Org“ →
**@devops-agent org step**, without it the code runs NIE.)

Handover candidates are therefore derived from the record, not from an event:

```
candidate  ⇔  the owning User record is missing  OR  IsActive = false
```

The „missing“ branch covers IT deleting the user instead of deactivating it —
then the manager cannot be resolved any more and the fallback rule applies
(R-1/R-2), and the reason is recorded (`Deactivation_Evidence__c`).

Cadence: **hourly** (`0 5 * * * ?` — minute 5, no collision with the nightly
slots 01/02/03/04/06:00 that SCRUM-388/417/436/442/319 document as taken).
AC1/AC7 are then satisfied *within one hour of the deactivation* — state the
delay in the release note, the PO acceptance must measure it.

## ADR-3 · Queueable job (one transaction), not Batchable

Reused verbatim from SCRUM-410 ADR-2: audit insert + ownership change must be
**all-or-nothing**; measured work volume is 255 Accounts + 74 open Opportunities
for the largest owner — comfortably inside the real-time limits of one
`Queueable` job, one bulk SOQL and one bulk DML per object type.
**Fallback documented** (SCRUM-410): above ~5,000 affected child records for a
single person switch to `Database.Batchable` (then no atomicity → the Error row
is the compensation).

## ADR-4 · Failure handling = three tiers, and the User record is never touched

The deactivation itself cannot fail because of this feature: **the handover
never writes `User`**. AC11 is therefore structurally satisfied, and the
remaining work is making the failure *visible*:

1. **Blocked** (pre-flight, no DML at all): no target resolvable (AC4), target
   == the deactivated user, or a `SalesDepartureHandover__c` row for that user
   and that `Deactivation_Evidence__c` already exists (idempotency).
2. **Failed** (caught DML exception): explicit compensating write — re-save the
   affected rows with the previous `OwnerId` and the provenance fields cleared —
   then `Status__c=Failed`, `Error_Detail__c` = the German message. Reason this
   is explicit: **a caught Apex exception does not roll back** the transaction,
   so „all-or-nothing“ needs a real revert. No `SavePointId` precedent exists in
   this repo (checked `origin/master` 8718cb4: only the definition above is
   relevant); do not invent one.
3. **Uncaught** (compensation itself broken): log the rows as `Failed`, let the
   job abort, and report to @tester-agent — this is an escalation, not a silent
   state.

## ADR-5 · FLS = Permission Sets only, never a Profile edit

House rule (SCRUM-321/327/329, `salesforce-describe-first` §4). Every new field
gets its own `fieldPermissions` entry — FLS is never inherited from object CRUD.
Table below. Negative FLS test must be *falsifiable* (skill `salesforce-describe-first`
§4 and SCRUM-430/470): assert
`getDescribe(SalesDepartureHandover__c.getValues(...)).isAccessible() == false`
under `System.runAs()` of a user without the Read-PS — **not** a
try/catch that can never fail; and `System.runAs` is refused outside `@isTest`.

---

## Data model (before implementation)

### 1. `SalesDepartureHandover__c` — the handover trail (1 row per person × run)

Path `force-app/main/default/objects/SalesDepartureHandover__c/`
House shape: `CustomerTransfer__c` (SCRUM-410) + `CaseRebuildRun__c` (SCRUM-367).

| Field | Type | Note |
|---|---|---|
| `Name` | AutoNumber `HANDOVER-{0000}` | house `<nameField>` |
| `From_User__c` | Lookup → `User` | the deactivated person; house field shape SCRUM-410 `From_User__c` |
| `To_User__c` | Lookup → `User` | the receiver; **empty when nothing moved** |
| `Target_Rule__c` | Picklist `Manager` / `Fallback` / `None` | which rule gave the target |
| `Deactivation_Evidence__c` | Picklist `IsActive_false` / `Owner_record_deleted` | how the system found it (ADR-2) |
| `Status__c` | Picklist `Done` / `Blocked` / `Failed` | house Picklist-Status |
| `Accounts_Handed_Over__c` | Number, scale 0 | AC1/AC7 |
| `Open_Opportunities_Handed_Over__c` | Number, scale 0 | AC1 |
| `Closed_Opportunities_Kept__c` | Number, scale 0 | **AC5 evidence**: >0 with unchanged owner |
| `Handed_Over_At__c` | DateTime | AC8 „when“ |
| `Error_Detail__c` | Text(255) | AC11, German sentence |
| `Info__c` | Text(255) | AC4, e.g. „Keine Manager, kein Fallback-person configured“ |

`<sharingModel>ReadWrite</sharingModel>` — house SCRUM-445 `DiscountApprovalManager__c`
(measured working with a Read-PS), so the tab is openable by sales management.
German `<label>`s, English DevNames (house naming rule).

### 2. `SalesHandoverFallback__c` — the fallback person, chosen by sales management

One row (AutoNumber `FALLBACK-{0000}`), `<sharingModel>ReadWrite</sharingModel>`,
Deployed. Path `force-app/main/default/objects/SalesHandoverFallback__c/`.

| Field | Type | Note |
|---|---|---|
| `Fallback_User__c` | Lookup → `User` | the whole team's receiver |
| `Deputy_Name__c` | Text(40), optional | free note |

A Lookup on `User` itself is **rejected** by the platform (measured in SCRUM-445,
house note); a Lookup *to* User on a custom object is the proven shape.

### 3. Provenance on both record types (PO's CRUD/FLS section demands it on both)

`Account` **and** `Opportunity` — 3 fields each, identical DeveloperNames:

| Field | Type | Note |
|---|---|---|
| `Handed_Over_From__c` | Lookup → `User` | previous owner, even if that user was deleted (AC9) |
| `Handed_Over_On__c` | DateTime | AC9 „when“ |
| `Handover_Run__c` | Lookup → `SalesDepartureHandover__c` | points at the run row (AC8/AC9 falsifiable per record) |

Required: `<required>false</required>` on every Lookup (house pitfall SCRUM-445),
`<relationshipName>`s unique per object. Name collision measured: Account and
Opportunity carry **no** `Handed_*`/`Handover*`/`Previous*` field (describes in
notizen) — no clash. SCRUM-410's `CustomerTransfer__c` is *not* extended: its
semantics are the manual team-lead transfer (SCRUM-410), this is a system-only
transfer; one row type each.

### 4. Apex components (`force-app/main/default/classes/`)

```
SalesDepartureHandoverService.cls      — target resolution + bulk DML, without sharing
  resolveTargets(Set<Id> ownerIds) → Map<Id owner, Id target | null>
        R-1: target = DiscountApprovalManager__c.Manager__c where Rep__c = owner
        R-2: else User.ManagerId, if that user IsActive
        R-3: else SalesHandoverFallback__c[0].Fallback_User__c, if IsActive
        null → Blocked row (AC4). target == owner → Blocked row.
  isSalesUser(ownerId) → Boolean     ⇔ owner appears as Rep__c in the mapping (AC10)
  handoverAccount(List<Account>) / handoverOpportunity(List<Opportunity>)
        one save per record: Owner + the 3 provenance fields
        sets OpportunityRiskService.systemWriteInProgress = true (suppression, ADR-6)
SalesDepartureHandoverBatch.cls        — Database.Batchable, QueryLocator, 200-chunks (ADR-3 fallback)
SalesDepartureHandoverJob.cls          — Queueable wrapper (ADR-3 primary), one try/catch + compensation (ADR-4)
SalesDepartureHandoverScheduler.cls    — Schedulable, starts the Job; CRON doc-comment like SCRUM-442
SalesDepartureHandoverTest.cls         — behaviour pair (see §Tests)
SalesDepartureHandoverFlsTest.cls      — FLS pair, runAs negative (skill §4)
```

Apex **class access** to `SalesDepartureHandoverService`/`...Job` inside the
system PS: house shape `SCRUM410_CustomerTransfer` (`<classAccesses>`).

---

## Permission Sets (`force-app/main/default/permissionsets/`)

| PS | objectPermissions | fieldPermissions | tabSettings | classAccesses | assign to |
|---|---|---|---|---|---|
| `SCRUM483_Handover_Keep` | — | read-only (`editable=false, readable=true`) all 6 provenance fields on `Account` and `Opportunity` | — | — | sales team (currently: `devops-agent@cline.test`, `meerwais.osmani@resourceful…`) |
| `SCRUM483_Handover_Log` | `SalesDepartureHandover__c` read+edit+create, **`viewAllRecords=true`, no delete** | read-only all 11 fields | `<tab> SalesDepartureHandover__c` Visible | — | sales team + sales management |
| `SCRUM483_Fallback_Config` | `SalesHandoverFallback__c` CRUD | `Fallback_User__c`, `Deputy_Name__c` read+edit | tab Visible | — | **sales management ONLY** (AC3 — no IT role; no System/Manageable permission in the PS) |
| `SCRUM483_Handover_System` | `SalesDepartureHandover__c` create | **editable=true** all 6 provenance fields | — | Service + Job | the scheduled user (= whoever creates the `System.schedule`) **and** the CLI target-org user |

Shapes: `SCRUM445_DirectManager_Map` (object CRUD + field) and
`SCRUM436_CaseReminder` / `SCRUM436_CaseReminderSystem` (Read vs System pair) —
copied 1:1.

**The org facts make the handover invisible if the assignment step is skipped**
(AGENTS.md: six tickets did this): the `SCRUM483_Handover_System` PS must be
assigned to the *running user of the scheduled job*, otherwise the DML fails as
`No such column`, which reads like a missing field and is not one.
`scripts/fls-check.sh` + `scripts/fls-gate.py` cover this from the other side.

## Sharing model impact

No OWD change, no sharing rule, no role-hierarchy change. Verified in SCRUM-410
ADR-3 (Test-Org read-back: `SharingRules` for Account/Contact/Case/Opportunity
are empty `<SharingRules/>`): ownership change alone gives the receiving person
access to his own records (implicit sharing), independent of OWD. The new
internal objects are `ReadWrite` + FLS via PS (ADR-5). → nothing for @devops-agent
in Setup.

## Governor limits

- **No SOQL in a loop.** Per person: 1 bulk SOQL for `Account`, 1 for open
  `Opportunity`, 1 for the `User` rows and 1 for the mapping rows **per run,
  cached statically** — chunk-independent.
- `IsClosed` is the close-state filter (never `Stage`/`StageName` string compare;
  `IsClosed`/`IsWon` are readonly booleans — measured).
- DML: bulkified `Update.record`, one save per record carrying Owner **and** the
  provenance fields — never a second save, never field-by-field.
- Idempotency (house SCRUM-388/365/417): a row already pointing at a run with
  the same `From_User__c` + `Deactivation_Evidence__c` is skipped → a second
  run touches 0 rows.
- Current org volume (measured) is 268/89 — one Queueable job; the Batchable
  fallback (ADR-3) applies only above ~5,000 records per person.

---

## ⚠️ Side-effect risk on the Owner-change save (decides whether AC6 is implementable)

Our save is a normal `Account`/`Opportunity` update, so **all existing handlers
run**. Measured on `origin/master` 8718cb4:

| Handler | Reacts to | Effect on an Owner-only save |
|---|---|---|
| `AccountLockGuard` → `AccountLockClearHandler` | `Is_Locked__c` true→false | inert |
| `OpportunityOverdueReset` → `OpportunityOverdueResetHandler` + `OpportunityLossReasonClearHandler` | `Is_Overdue__c` transition | inert |
| `OpportunityFollowupMonitorTrigger` → `FollowupMonitoringHandler.onOpportunityUpdate` | „returns unless `IsClosed` or `Amount` changed“ | inert |
| `DiscountApprovalTrigger` → `DiscountApprovalHandler` | `Discount_Approval__c` transitions (`Pending`→Approved/Rejected) | inert |
| **`OpportunityFollowupGuardTrigger` → `FollowupMonitoringHandler.assertNoUserTypedValues`** | **refuses any before-update save that PROPOSES a monitoring value ≠ stored** | **can throw** |
| `OpportunityRiskTrigger` → `OpportunityRiskHandler` | guarded by `OpportunityRiskService.systemWriteInProgress` | suppressed by our own flag (ADR-6) |
| Account Validation Rules `LockReason_PflichtBeiGesperrt`, `Wartungsvertrag_End_Before_Start` | evaluated on the end state | can throw → tier „Failed“ (ADR-4) |
| `OpportunityLockedAccountGuard.cls` (throws when `Account.Is_Locked__c`) | **no caller found in any `.cls` on origin/master** | dead code today; still a throw path if a future ticket attaches it |

**Design rule (ADR-6):** the handover DML writes **only** `Owner` + the 3
provenance fields; it must not re-propose any of the six monitoring fields
(`Status__c`, `Due_Date__c`, …), and sets
`OpportunityRiskService.systemWriteInProgress = true` for the duration — that
flag is already the house mechanism for system writes (SCRUM-449).

**AC6 test shape (falsifiable, per SCRUM-471 and the 0-row trap):**
- **positive control**: a fixture Account/Opportunity in the state where `DiscountApprovalTrigger`
  *would* post (a `DiscountApprovalManager__c` row for the owner, `Discount_Approval__c` Pending)
  and one where FollowupMonitoring flags values — assert the handler classes did
  **not** fire via their `@testVisible` `hasFired` / `systemWriteInProgress` flags.
- assert **all** non-owner fields unchanged (before/after full field map),
  `Contact`/`Case` owners untouched, and `EmailMessage`/`Task` row counts
  **before vs after in the same transaction** — not equality against an empty
  table (0==0 is vacuous).

---

## Tests: the AC → artefact contract (no AC without an artefact)

Wording carried by the Developer (PO, comment 23891): **AC1 and AC7 hold within one hour of the
deactivation**, not at the moment of it — the release note states that delay in plain words, and
the Tester measures the real delay instead of assuming it. (Measure it: the fixture's timestamp of
the switch-off versus the first `Handover_Run__c` read-back of the moved records — assert the delay is
> 0 and ≤ 1 h; "the scheduler must have run" proves nothing.) AC12 (owner missing from the mapping)
is a new criterion and is carried into the build: the test class `SalesDepartureHandoverTest`
asserts it next to AC4 in the same trail tab.

### Release note — ready wording (house file `docs/RELEASE-NOTES.md`, entry due at Deployment)

The PO obligation is not a note to re-derive later; the paragraph is here and the delay is named in
plain words for the person who asked for it ("at the moment a salesperson is deactivated"):

- **Was sich aendert.** When a salesperson leaves the company and IT switches off his user, the
  system hands his open opportunities and the customers he owns over to his manager; without a
  manager to the fallback person sales management has chosen. Deals that are already closed, won or
  lost stay with the person who worked on them. Contacts, cases and everything else stay where they
  are; no amounts, stages, dates or emails to customers are touched.
- **When it happens.** Within one hour after the deactivation — not at the very moment of it. The
  deactivation itself never fails because of the handover: if the move cannot be done, the person
  stays switched off and the reason is listed, not hidden.
- **Wo man es sieht.** The tab "Austritt-Uebergeben": one row per person and run — whom it was
  handed to, how many customers and open opportunities moved, and in `Info__c` / `Error_Detail__c`
  the cases where nothing could be moved (neither manager nor fallback, or the target themselves
  switched off) and a salesperson who is missing from the mapping. On every moved record
  `Handed_Over_From__c`, `Handed_Over_On__c` and `Handover_Run__c` say who had it before and in which
  run.
- **Belege.** SCRUM-483, PR #206; deployed and read back in Test-Org on 2026-11-27.

| AC | Artefact | Count measured today |
|---|---|---|
| AC1 open deals + customers to the manager | `SCRUM483...Test`: deactivate a mapping `Rep__c` → assert 12 Account rows + 15 open Opp rows (Meerwais) move, `Closed_Opportunities_Kept__c = 18` | **0 deactivated users exist** → fixture required |
| AC2 fallback | mapping row removed, `Fallback_User__c` set → same counts move to the fallback | 0 fallback rows exist |
| AC3 fallback editable by sales management, no IT | E2E/`record-ui` + PS check: the PS carries no System permission; negative: a rep PS cannot… (FLS truth per §4) | 0 rows |
| AC4 no manager, no fallback → nothing moves + visible | assert 0 owner changes + one `Status__c=Blocked` row with `Info__c` | 8 users, none eligible |
| AC5 closed/won/lost stay | assert the 68 closed Opps keep `OwnerId`, `Closed_Opportunities_Kept__c > 0` | 68 closed, 18 of them Meerwais |
| AC6 nothing else | see §side-effects, positive control | 4 locked Accounts exist, **0 with open Opps** → the blocking fixture must be built |
| AC7 several at once | deactivate Meerwais **and** devops-agent in one run: 267 Accounts + 89 open Opps, each to its own target (mapping is circular! see R-1 note) | 0 |
| AC8 one place | tab `SalesDepartureHandover__c` visible with the Read-PS + E2E `record-ui`/list view reading `To_User__c`/`From_User__c`/`Handed_Over_At__c` | 0 rows |
| AC9 traceable + chain | per record `Handed_Over_From__c` + `Handover_Run__c`; chain = run rows ordered by `Handed_Over_At__c`; assert chain over **2** successive handovers of one Account | 0 |
| AC10 non-sales / empty user | deactivate `Automated Process` (owns **1 Account**, not a `Rep__c`) → assert **0** moves, **0** log rows | 1 Account |
| AC12 owner owns records but **has no mapping row** (entry mistake) | same fixture, no `Rep__c` row: assert 0 owner changes + one `Status__c=Blocked` row with `Info__c` naming the missing mapping row — the case is listed in the SAME tab as AC4 (PO, comment 23891) | 0 such rows today → fixture builds it |
| AC11 failure shown, deactivation survives | lock that Account (`Is_Locked__c=true` + `Lock_Reason__c`) so a save throws → assert `Status__c=Failed`, `Error_Detail__c` filled, **records still owned by the old user**, `User.IsActive` still false | 0 such rows today → fixture builds it |

**AC7 note (real):** the two mapping rows are circular (Meerwais→devops-agent and
devops-agent→Meerwais). Deactivating both in one run resolves targets against the
*pre-run* mapping; per PO decision „if the manager is himself deactivated in the
same run → fallback“ ⇒ **both persons must receive the fallback person**, and the
run rows say `Target_Rule__c=Fallback`. The rule is evaluated against the set of
all deactivated users in the run, not per record. This is exactly what
@tester-agent must assert.

Org-setup preconditions (read-back, **never** an `@isTest` assert — CI Prod-Org
Drift Gate rule): schedule exists (DevOps), PS assignments (DevOps/Developer),
the mapping rows.

## Org-Setup steps (not deployable artifacts — @devops-agent)

1. `System.schedule('SCRUM-483 Departure Handover','0 5 * * * ?', new SalesDepartureHandoverScheduler())` in Test-Org (on deploy) and Prod-Org (on release); read back the schedule list before choosing the slot (collisions documented by SCRUM-388/417/436/442/319).
2. Assign the 4 PSs to the users in the table above, then read back `PermissionSetAssignment` **and one provenance field through a real session** (AGENTS.md handoff requirement).
3. Set `SalesHandoverFallback__c.Fallback_User__c` and verify the tab is openable by the human test account.

## Open decisions — PO / @user to confirm (none blocks the build)

- **R-1 target precedence.** Built as: mapping `DiscountApprovalManager__c` →
  `User.ManagerId` → fallback. `User.ManagerId` is NULL on all 8 users today, so
  AC1 is only testable via the mapping. Alternative: a second, handover-scoped
  mapping object — then the map is empty today and AC1 stays untestable; the
  mapping semantics would have to stay in sync with SCRUM-445's. If PO wants the
  Setup hierarchy (`User.ManagerId`) to be authoritative, IT must populate it —
  then the negative case (who may edit it) changes, since Setup is IT-only.
- **R-2 AC7/PO manager rule**: manager deactivated in the same run → fallback
  (implemented against the run's whole deactivated set). Confirm.
- **R-3 sales-membership discriminator**: mapping membership (`Rep__c`). PO said
  hierarchy-not-list; this is the org's only populated hierarchy. Confirm, or
  accept the ownership-based rule with its Automated Process break (measured 1
  Account).
- **R-4 AC8/AC4/AC11 visibility** = the tab of `SalesDepartureHandover__c`
  (status + German message). PO reviews at acceptance; alternative is a per-record
  warning field (more FLS, more noise).

## Definition of Done for the Developer (handoff contract)

Data model (§1–3) + the 4 Permission Sets (ADR-5) + sharing impact (none) +
governor notes + **the PS read-back** (`PermissionSetAssignment` rows + one
provenance field read through a session) in the Developer-Handoff comment. Branch
`feature/SCRUM-483-departure-handover`, one PR, Test-Org deploy.
