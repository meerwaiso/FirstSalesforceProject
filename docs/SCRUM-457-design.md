# SCRUM-457 — Account Manager on Holiday / off sick: Absence with Deputy

Author: Architect-Agent · Date: 2026-10-31 · **Revision 2 — supersedes the approval of PR #180 at 11:34.**
Rewritten after the user's confirmed answers (ticket description rewritten 12:45) and the measured sharing model. The build on `feature/scr457-absence` is already partly right; §9 names the delta.
Surveyed sources: `origin/master` @ `dc94b0bd5b3764d867b2892cedc3d4fddf6cfd9c`, branch head `c3b3206` (git fetch before survey) and Test-Org (`devops-agent@cline.test`).

## Ziel

Record an account manager's absence (start, end, one deputy) **once per manager**, show it on the customer page of every Account owned by that manager **only inside the absence window**, and give team leads an overview of all affected customers for the next 14 days — **without ever touching `OwnerId` on Account, Opportunity or Case**, and **without granting any user new access**. A customer whose named deputy is themselves away stands out in the overview exactly like a customer without a deputy (AC10).

---

## 1. Measured facts (each with the command that produced it)

| # | Finding | Command |
|---|---|---|
| F1 | `Account.AccountAccess` (the Sales Cloud per-record share field) **does not exist** in Test-Org. Two independent routes: the full `sobject describe` field list contains no `*Access*`/`*Share*` field, and SOQL answers `No such column 'AccountAccess' on entity 'Account'`. | `sf sobject describe --sobject Account --target-org Test-Org` · `sf data query --query "SELECT Id, AccountAccess FROM Account" --target-org Test-Org` |
| F2 | The org has **no absence object**. Custom objects in Test-Org: `CaseRebuildRun__c`, `CustomerTransfer__c`, `DiscountApprovalManager__c`, `OpenOpportunityHistory__c`. | `sf sobject list --target-org Test-Org` |
| F3 | `User` carries exactly one custom field today: `SCRUM428_Verfuigung__c` (boolean). User custom fields exist — but Lookup/Reference on `User` is rejected by the platform ("Invalid data type", dry-run-verified, skill `salesforce-describe-first` §7b). ⇒ **the deputy cannot be a Lookup on a User custom field**; the absence must be its own object. | `sf sobject describe --sobject User --target-org Test-Org` |
| F4 | House shape for a per-user record with Lookup→User: `CustomerTransfer__c` (SCRUM-410) — `From_User__c`/`To_User__c` are `Lookup` with `referenceTo=User`, `relationshipLabel`, `relationshipName`, `<required>false</required>`; object is `sharingModel=Private`, `AutoNumber` name field. | `git show origin/master:force-app/main/default/objects/CustomerTransfer__c/...` |
| F5 | Report column tokens for custom fields are `Object.Field__c` (house: `Account.Open_Opportunity_Value__c`, `Contact.Betreuungsstufe__c`). `AccountList` report type: `ACCOUNT.NAME` = Account Name, `USERS.NAME` = **Account Owner** (`Account.Owner.Name`). `AccountList` scope values: `user` (default), `team`, **`organization`** (= "All accounts"), `scopingRule`. | `sf api request rest "/services/data/v64.0/analytics/reportTypes/AccountList" --target-org Test-Org` |
| F6 | The **Account record page has no FlexiPage override** in Test-Org. The only record-page FlexiPage is `BetreuungsuebergabePage` on `User`. ⇒ the Lightning Account detail page follows the **Account layout**, which the repo tracks. No App Builder step needed for the customer page. | `sf data query --use-tooling-api -q "SELECT DeveloperName, EntityDefinitionId FROM FlexiPage" --target-org Test-Org` |
| F7 | The role hierarchy exists (`Role` object, 15+ roles via the Tooling API) but **every user in Test-Org has `UserRoleId = null`** — no user carries a role. The user confirmed: a team lead is **not** a role in either org; the only existing roles are Salesforce's standard sample roles. | `sf data query --query "SELECT Id, Name, UserRoleId FROM User" --target-org Test-Org` · `sf data query --use-tooling-api -q "SELECT Id, Name FROM Role" --target-org Test-Org` |
| F8 | 197 Accounts in Test-Org, owned by several users (`Meerwais Osmani`, `devops-agent`, `Automated Process`). | `sf data query --query "SELECT Id, OwnerId, Owner.Name FROM Account" --target-org Test-Org` |
| F9 | **The OWD (sharing model) of Account / Opportunity / Case is not exposed by any API we have.** Verified by calling all three: `sobject describe`, `ui-api/object-info/<Object>` and the Data API `sobjects/<Object>/describe` — none returns a sharing/access-model field. It is a Setup setting and must be read in Setup, not inferred. | see commands above |
| F10 | Dry-run-validated against Test-Org (9/9 components `Created`): `Absence__c` object + `Absent_User__c`/`Deputy__c` Lookup→User + `Start__c`/`End__c` Date + `Account.Absence_Start__c`/`Absence_End__c` Date + `Account.Absence_Deputy__c` Text(80) + `Account.Absence_In_Window__c` Text-formula with `&&` and date arithmetic. | `sf project deploy start --source-dir <probe> --target-org Test-Org --dry-run` |
| F11 | Report filter shape is `<filter><criteriaItems><column/><operator/><value/></criteriaItems></filter>` — `ReportFilter` has exactly `criteriaItems` (schema in the CLI's own `@salesforce/types/lib/metadata.d.ts`); `<criteria>`, `<field>` and `<reportFilters>` are all rejected. | `sf project deploy start --dry-run` + schema grep |
| F12 | A Permission Set cannot be validated before its fields exist: `In field: field - no CustomField named Account.Absence_Start__c found`. **Deploy order: fields → Permission Set → report.** | same dry-run |
| **F13** | **Sharing is settled and needs no mechanism.** The user states the OWD of Account, Opportunity and Case is **Public Read/Write in both orgs**; the Tester read it back in Setup on 2026-10-31 (Account Public Read/Write, Opportunity Public Read/Write, Case Public Read/Write/Transfer, external access Private on all three, no sharing rules). Corroborated from my side: as `devops-agent` — not the owner of the mirrored Accounts — I read the mirrored fields and the owner's records. ⇒ **no Permission Set for deputy access, nothing to revoke.** `SCRUM457_DeputyAccess` was deleted from org and branch — correct. | Jira comment 23572 (Setup read-back) · `sf data query ... PermissionSet WHERE Name='SCRUM457_DeputyAccess'` → 0 rows |
| **F14** | **The house has no ValidationRule anywhere** (`git grep -l validationRules origin/master -- force-app/main/default/objects/` → no file) **and no `$Permission` merge field in any Apex file** (`git grep -n '\$Permission' origin/master -- classes triggers` → no hit). Neither mechanism has a precedent in this repo; the guard in §3 must be compile-proven by the Developer, not assumed. | `git grep` on `origin/master` |
| **F15** | **No Permission Set in the repo carries `userPermissions`** (`git grep -l userPermissions origin/master -- force-app/main/default/permissionsets/` → no file). The house never grants `RunReports`; a team lead opens the overview through the report's own sharing setting (Setup), which is precondition S3, not code. | `git grep` on `origin/master` |
| **F16** | The report `Fehlzeiten_nach_Kunde` at head `c3b3206` already carries the marker column `Account.Absence_Ohne_Deputy__c` and filters on `Account.Absence_In_Window__c = YES`. AC10 can reuse that column — no new report needed. | `git show c3b3206:force-app/main/default/reports/Sales/Fehlzeiten_nach_Kunde.report-meta.xml` |

---

## 2. Data model

### 2.1 New custom object `Absence__c` — one record per account manager and absence

House shape F4 (`CustomerTransfer__c`). `sharingModel=Private`, `AutoNumber` name field. Unchanged from revision 1.

| Field | Type | Purpose |
|---|---|---|
| `Absent_User__c` | Lookup → `User` (`relationshipName=Absences_AbsentUser`) | the account manager who is away |
| `Deputy__c` | Lookup → `User` (`relationshipName=Absences_Deputy`) | the covering colleague — exactly one; **never `Absent_User__c` itself** (user decision 3 + AC1 new clause, guard in §3) |
| `Start__c` | `Date` | absence from |
| `End__c` | `Date` | absence until — **inclusive** (user decision 1: away until Friday, back Monday; same rule as the SCRUM-451 contract end date) |

`Date`, not `DateTime`: day-granular requirement, window test `Start__c ≤ today ≤ End__c`.
**Cancel = delete the `Absence__c` record.** Change = edit the same record (AC6).

### 2.2 Mirror fields on `Account` — written by Apex, never by hand

A formula field cannot traverse `Account.Owner`, so the absence is copied down onto the customer. This is what makes AC2, AC3, AC6, AC8 and AC10 expressible at all.

| Field on `Account` | Type | Written by | Content |
|---|---|---|---|
| `Absence_Start__c` | `Date` | Apex | copy of the winning `Absence__c.Start__c` |
| `Absence_End__c` | `Date` | Apex | copy of the winning `Absence__c.End__c` |
| `Absence_Deputy__c` | `Text(80)` | Apex | display name of the deputy (display only; the User Id lives on `Absence__c.Deputy__c`) |
| **`Absence_Deputy_Start__c`** | `Date` | **Apex — NEW** | start of the **deputy's own** open absence (blank if the deputy has none) |
| **`Absence_Deputy_End__c`** | `Date` | **Apex — NEW** | end of the deputy's own open absence |
| `Absence_In_Window__c` | `Text` formula | formula | `"YES"` while the manager's absence is running today or starts within 14 days — drives the AC8 report filter without a relative-date filter |
| `Absence_Ohne_Deputy__c` | `Text` formula | formula | `"OHNE DEPUTY"` while in window **and** (no deputy named **or** the deputy's own window covers today) — the AC8 + AC10 marker |
| `Absence_Anzeige__c` | `Text` formula | formula | the one line the customer page shows; blank outside an absence (AC3) |

**Winning record** = the manager's open absence with the latest `End__c` (ties: later Id as String). The deputy's own window is taken the same way over `Absence__c WHERE Absent_User__c = :deputyId AND End__c >= TODAY()`.

`Absence_Ohne_Deputy__c` formula — extends the deployed one by the deputy term; keep the existing window guard verbatim and add the OR:

```
IF(NOT(ISBLANK(Absence_Start__c)) && NOT(ISBLANK(Absence_End__c))
   && Absence_End__c >= TODAY() && Absence_Start__c - TODAY() <= 14
   && ( ISBLANK(Absence_Deputy__c)
        || ( NOT(ISBLANK(Absence_Deputy_End__c))
             && Absence_Deputy_Start__c <= TODAY()
             && Absence_Deputy_End__c >= TODAY() ) ),
   "OHNE DEPUTY", "")
```

The marker value is **identical** for "no deputy" and "deputy is away" — AC10 says "stands out exactly like a customer without a deputy", so the report must not distinguish them. If the user later wants them distinguished, that is a new marker value, not a new field.

`Absence_Manager__c` is still not needed: `USERS.NAME` names the owner (F5).

### 2.3 `OwnerId` is never written

AC7. The handler reads `OwnerId` to find the Accounts; it never assigns it. Do **not** reuse SCRUM-410 `CustomerTransferJob` — that class exists precisely to change ownership; reuse only its bulk-DML shape.

---

## 3. Components

| # | Component | Path | Responsibility |
|---|---|---|---|
| 1 | `Absence__c` + 4 fields | `objects/Absence__c/` | the single record per manager and absence |
| 2 | 5 Apex-written + 3 formula fields on `Account` | `objects/Account/fields/` | visibility on the page + report columns (2.2) |
| 3 | `AbsenceSyncTrigger` | `triggers/AbsenceSyncTrigger.trigger` | `(before save, after insert, after update, after delete)` on `Absence__c` — **before save added for the AC1 guard**; one trigger per object (house rule) |
| 4 | `AbsenceSyncHandler` | `classes/AbsenceSyncHandler.cls` | bulkified mirror write + the two new deputy-window fields; **bidirectional recompute** (§3b) |
| 5 | `SCRUM457_AbsenceRead` PS | `permissionsets/` | FLS read on all 8 Account absence fields + read on `Absence__c` |
| 6 | `SCRUM457_AbsenceWrite` PS | `permissionsets/` | Create/Edit/Delete on `Absence__c` + FLS on its 4 fields — **granted to account managers** |
| 7 | **`SCRUM457_Absence_Teamleitung` PS — NEW** | `permissionsets/` | same grants as #6 — **granted to team leads**; this set is what marks a team lead (house naming: `SCRUM428_Teamleitung`, `SCRUM431_Wartungsvertrag_Teamleitung`, `SCRUM451_Wartungsvertrag_Dates_Teamleitung`) |
| 8 | `Fehlzeiten_nach_Kunde` report | `reports/Sales/` | AC8 overview, `AccountList`, `scope=organization`, filter `Absence_In_Window__c = YES`, marker column `Absence_Ohne_Deputy__c` (F16) |
| 9 | Layout section "Fehlzeit" | `layouts/Account-Account Layout.layout-meta.xml` | the absence fields on the customer page |
| 10 | Apex test class + E2E spec | `classes/SCRUM457*Test.cls`, `tests/e2e/SCRUM-457-absence.spec.ts` | §6 |

**Deleted, do not re-add:** `SCRUM457_DeputyAccess` (F13 — under Public Read/Write it grants nothing and can revoke nothing).

### 3b Handler contract (pseudocode — the recompute is bidirectional)

AC10 creates a second dependency direction: when **the deputy's** absence changes, every customer whose manager names that deputy must be re-mirrored. A one-directional handler leaves a stale marker until the manager's own absence is touched.

```
AbsenceSyncHandler:

beforeSave  (AC1 guard, runs before the record is saved):
  for rec in Trigger.new where rec.Deputy__c == rec.Absent_User__c:
      throw new SavePointError('... a manager can never be their own deputy')   // AC1
  // mechanism for the guard: see §8 G1 — must be compile-proven

handleAfter (after insert | after update | after delete):
  touched   = Absent_User__c of Trigger.new ∪ Absent_User__c of Trigger.oldMap.values()
              // both are null on the wrong event (measured: oldMap null on insert,
              // new null on delete) — guard both or the whole insert rolls back
  // direction 2: managers whose deputy is one of the touched users
  managersViaDeputy = [SELECT Absent_User__c FROM Absence__c
                        WHERE Deputy__c IN :touched AND Absent_User__c != null]      // Q1
  managers = touched ∪ managersViaDeputy
  if managers empty: return

  openRec  = [SELECT Id, Absent_User__c, Start__c, End__c, Deputy__c
              FROM Absence__c WHERE Absent_User__c IN :managers]                     // Q2
  winner(m) = open record with the latest End__c (ties: later Id as String); End__c >= TODAY()
  deputyIds = Deputy__c of every winner

  deputyOpen = [SELECT Id, Absent_User__c, Start__c, End__c
                FROM Absence__c WHERE Absent_User__c IN :deputyIds AND End__c >= TODAY()]  // Q3
  deputyWindow(d) = winner over deputyOpen for d   (null if the deputy has none)

  names = [SELECT Id, Name FROM User WHERE Id IN :deputyIds]                          // Q4

  accounts = [SELECT Id, OwnerId, Absence_Start__c, Absence_End__c, Absence_Deputy__c,
              Absence_Deputy_Start__c, Absence_Deputy_End__c
              FROM Account WHERE OwnerId IN :managers]                                 // Q5
  for a in accounts:
      m = a.OwnerId
      if winner(m) exists:  copy start/end/deputy-name + deputyWindow(m) dates
      else:                 clear all five
      // OwnerId never assigned (AC7)
  if changed not empty: update changed;    // ONE bulk update
```

Five SOQL queries per trigger event, constant in the number of records — no SOQL inside a loop, no per-record DML.

---

## 4. ADR — decisions and why

**ADR-1 · Apex over Flow.** No Flow. The logic is a cross-object mirror write driven by a lookup on `OwnerId`, plus a save-time guard. Flow elements cannot express "find all Accounts of these users and write five fields", and Flows have repeatedly failed at deploy/schema validation here. → Apex, per the house default.

**ADR-2 · Absence object, not User custom fields.** F3: `User` rejects Lookup fields, so the deputy cannot live on the User. A custom object with Lookup→User is the proven house shape (F4). One record per manager also answers the user's story: a colleague could not tell *which* customers an absence covered.

**ADR-3 · No deputy access grant — the sharing premise is dead (F13).** Revision 1 branched on the OWD because it was unread. It is now measured and confirmed by the user: **Public Read/Write in both orgs**, so every internal user can already open and edit any customer, its Opportunities and its Cases. Consequences:
- AC4 is a **regression** criterion, not a grant: the feature must not break what the sharing model already gives.
- AC5 ("the feature grants and takes nothing") replaces the old revocation criterion. A `viewAllRecords` Permission Set would grant nothing the OWD does not already grant and could never revoke it — a test for it could never fail. `SCRUM457_DeputyAccess` is deleted from org and branch.
- Narrowing access to "only the deputy may work this customer during the absence" is **not** what this org does; making it so is an org-wide, permanent change that would affect the reports and commissions the user already had trouble with. Out of scope; needs its own ticket if the user wants it.

**ADR-4 · Team lead = a Permission Set, not a role (user decision 5 + F7).** Nobody in either org carries a `UserRoleId`; the only existing roles are Salesforce's standard sample roles. A team lead is whoever holds `SCRUM457_Absence_Teamleitung`, named after the house pattern (`SCRUM428_Teamleitung`, `SCRUM431_..._Teamleitung`, `SCRUM451_..._Teamleitung`). FLS cannot scope a Permission Set to "only records you own", so `SCRUM457_AbsenceWrite` (account managers) and `SCRUM457_Absence_Teamleitung` (team leads) carry the same CRUD/FLS on `Absence__c` — the difference is **who is assigned it**, and that is what the overview and the actor model read. If "only a team lead may record for a colleague" must be enforced, that is an Apex guard (§8 G1), not a Permission Set.

**ADR-5 · Mirror on Account + formula window fields, not a live lookup.** AC2 demands the information on the customer page, AC8 counts customers, AC10 flags them — all three need the data on the Account. The window tests are formula fields so they stay correct at read time as `TODAY()` moves, without a nightly job (nothing automatic beyond the mirror write).

**ADR-6 · The deputy's own window is mirrored as dates, not as a boolean.** A boolean "deputy is away" written at save time is wrong the day the deputy's absence ends — it would need a nightly refresh or a second trigger. Mirroring `Absence_Deputy_Start__c`/`Absence_Deputy_End__c` and comparing with `TODAY()` in the marker formula is correct at read time and costs two Date fields.

---

## 5. Org-Setup preconditions — read-back required, never asserted in a CI-gated test

| # | Precondition | Read-back |
|---|---|---|
| S1 | OWD of `Account`, `Opportunity`, `Case` = Public Read/Write (Case: Public Read/Write/Transfer) | user-stated for both orgs + Tester's Setup read-back (comment 23572). Prod-Org still needs its own read-back at release; the Setup page is `/p/own/OrgSharingDetail?setupid=SecuritySharing` (plain HTML — the Lightning Setup pages never fill their content pane in an automated browser, skill `salesforce-platform-quirks`) |
| S2 | `SCRUM457_AbsenceRead`, `SCRUM457_AbsenceWrite` and **`SCRUM457_Absence_Teamleitung`** are assigned — to the CLI's target-org user and to the human test account | `sf data query -q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='<PS>'"` + one absence field read back through a real session |
| S3 | Report sharing so team leads can open `Fehlzeiten_nach_Kunde` | report-level sharing is not in the source (F15: no PS grants `RunReports` in this repo) |
| S4 | Prod-Org: same OWD values and no FlexiPage override on the Account page | Prod-Org Drift Gate covers metadata drift only |

---

## 6. Technical acceptance criteria — every AC against a named artefact

| AC | Artefact | What the test must prove |
|---|---|---|
| AC1 | `SCRUM457AbsenceSyncTest` | insert `Absence__c` with the three values, read them back · under `System.runAs(teamLead)` holding only `SCRUM457_Absence_Teamleitung`, record the absence **for another user** · **new clause:** a record with `Deputy__c == Absent_User__c` is refused and the create rolls back (positive + negative) |
| AC2 | Apex: after the insert, `SELECT Absence_Start__c, Absence_End__c, Absence_Deputy__c, Absence_Anzeige__c FROM Account WHERE OwnerId = :absentUser` non-null for **every** owned Account · E2E: the Account detail page shows the "Fehlzeit" section |
| AC3 | Apex: an Account whose owner has no absence and one whose `End__c < TODAY()` read back **all five Apex mirror fields null** and both formula fields blank · E2E: page identical to today |
| AC4 | Apex under `System.runAs(deputy)`: the Account, its open Opportunities and its open Cases are queryable and an Opportunity update succeeds (`StageName` Warm→Hot) with `OwnerId` asserted unchanged — this is the **regression** proof under Public Read/Write |
| AC5 | **Grants and takes nothing:** no `PermissionSetAssignment` names a deputy-access set before or after the absence, and the deputy's access read-back is identical during and after it. A test that can only pass is not a test — assert the *absence of a grant*, not the loss of one |
| AC6 | Apex: change `End__c`/`Deputy__c` → mirror follows; delete → mirror cleared; `Absence_In_Window__c` recomputed |
| AC7 | Apex: capture `OwnerId` of Account, its Opportunities and its Cases before, assert identical after record/change/cancel **and after the deputy edits a record** |
| AC8 | Report run + row count. **A row count of 0 is not a pass** — the PO measures the expected number of customers in the window first and the Tester compares (measured today: 13 Accounts in window, 1 carries the marker) |
| AC9 | Apex: after the whole flow, assert no `EmailMessage`, no `Task`, no `Post`/chatter record; the design ships none of these artefacts |
| **AC10** | Apex: two absences — manager A (window covers today) with deputy D, and D's own absence covering today → the mirrored Account of A carries `Absence_Deputy_Start__c/End__c` of D and `Absence_Ohne_Deputy__c = "OHNE DEPUTY"`; **and** the reverse direction: creating/changing **D's** absence re-flags A's customers without touching A's record (this is the bidirectional recompute, §3b) · E2E: the report row for that customer carries the marker |
| AC10 assumption | "away at the same time" = **overlap at the time of viewing** (PO assumption, non-blocking). If it must instead be fixed per row for the whole absence period, the marker formula changes, not the data model |

Mixed-DML warning (house finding SCRUM-438/442): a `PermissionSetAssignment` insert may not join `Account`/`Case`/`Opportunity` DML in one transaction — keep the FLS proof and the business proof in **separate transactions**.

---

## 7. Governor limits

- Five SOQL queries per trigger event (Q1–Q5 in §3b), constant in the number of records; **one** bulk `update`. Worst case measured: 197 Accounts in Test-Org; the Prod-Org count must be read back (S4).
- No SOQL inside a loop, no per-record DML.
- Recursion guard: the handler writes `Account` fields; the only Account trigger in the repo (`AccountLockGuard`) reads `Is_Locked__c`/`Lock_Reason__c` — no overlap. Re-check before adding any Account trigger.
- The `before save` guard adds no query.

---

## 8. Open points (owner named)

- [ ] **G1 — mechanism of the AC1 own-deputy guard.** No ValidationRule and no `$Permission` merge field exists anywhere in this repo (F14), so neither has a precedent here. Two options, both must be **compile-proven by the Developer before shipping**: (a) a declarative ValidationRule on `Absence__c` (`errorConditionFormula: Deputy__c = Absent_User__c`) — cheap, but its behaviour under Apex DML is unverified in this repo, so an Apex negative test could pass vacuously; (b) the `before save` guard in `AbsenceSyncTrigger` throwing `SavePointError` — covers UI, API and Apex and is testable. **Recommend (b); if (a) is added as well, the test must fail when the guard is removed**, otherwise it proves nothing (probe-that-cannot-fail rule).
- [ ] **G2 — should the customer page also show that the named deputy is away?** AC10 only names the overview; the page currently still shows the deputy as deputy. Out of scope unless the user asks. If wanted: add a term to `Absence_Anzeige__c`, no new field.
- [ ] **G3 — may an account manager record a colleague's absence?** FLS cannot distinguish it (ADR-4); both write sets carry the same grants. Enforcing "only team leads" needs the same guard mechanism as G1. Default: not enforced.
- [ ] Prod-Org OWD and Account-page FlexiPage state (F6/F13 measured in Test-Org only). Owner: @devops-agent at release (S4).
- [ ] `Account.Owner` FLS: the repo's `SCRUM451` PS comment records the deploy rejecting `Account.Owner` as a required field, `salesforce-platform-quirks` says non-required lookups take an FLS entry. **Ask the platform** (`sf sobject describe --sobject Account` → `fieldRequired`) before writing any FLS entry on `Account.Owner` — do not copy either note.

---

## 9. What the build must change (delta on head `c3b3206`)

Already correct, do not touch: `AbsenceSyncHandler` mirror logic and its bulk shape, `Absence__c` object + 4 fields, `AbsenceRead`/`AbsenceWrite` PSs and their assignments, the layout section, the report (F16 — the marker column is already there), the deletion of `SCRUM457_DeputyAccess`.

1. **New:** `Account.Absence_Deputy_Start__c` + `Account.Absence_Deputy_End__c` (Date, `required=false`, `editable=false`) — deploy before the PSs that list them (F12).
2. **New:** `SCRUM457_Absence_Teamleitung` PS (house naming), same grants as `SCRUM457_AbsenceWrite`; add it to the manifest **and assign it** (S2) — a PS assigned to nobody is the recurring failure here.
3. **Extend:** `Absence_Ohne_Deputy__c` formula with the deputy term (2.2) — the deployed formula only tests `ISBLANK(Absence_Deputy__c)`.
4. **Extend:** `AbsenceSyncHandler` — the bidirectional recompute (§3b) and the two new mirror fields. The one-directional handler leaves a stale marker when only the deputy's absence changes.
5. **Extend:** `AbsenceSyncTrigger` with `before save` for the AC1 own-deputy guard (G1).
6. **Tests:** the class at head `c3b3206` has 11 methods (`activeAbsenceMirrorsEveryCustomer`, `ownerIdIsNeverWritten`, `changedAbsenceFollowsImmediately`, `cancelledAbsenceClearsMirror`, `latestEndWinsAmongSeveralAbsences`, `endedAbsenceIsNotMirrored`, `bulkStaysWithinGovernorLimits`, `absenceWithoutDeputyStandsOut`, `deputyWorksNonOwnedCustomerRecords`, `absenceCreateRunsUnderTheWritePermissionSet`, `absenceCreateIsBlockedWithoutThePermissionSets`) — **none covers the own-deputy guard, the team-lead set recording for a colleague, or AC10**. Add those three (AC10 in both directions).
7. **Retire:** the Tester's E2E spec on head `c3b3206` was written against the **old** AC list; its verdict is superseded and must be re-run after 1–6 land.
