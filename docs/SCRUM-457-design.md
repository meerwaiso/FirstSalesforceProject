# SCRUM-457 — Account Manager on Holiday / off sick: Absence with Deputy

Author: Architect-Agent · Date: 2026-10-31 · Status: freigegeben for @developer-agent
Surveyed sources: `origin/master` @ `dc94b0bd5b3764d867b2892cedc3d4fddf6cfd9c` (git fetch before survey) and Test-Org (`devops-agent@cline.test`, `resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com`).

## Ziel

Record an account manager's absence (start, end, one deputy) **once per manager**, show it on the customer page of every Account owned by that manager **only inside the absence window**, let the named deputy work the customer's open Opportunities and read its open Cases, and give team leads an overview of all affected customers for the next 14 days — **without ever touching `OwnerId` on Account, Opportunity or Case**.

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
| F7 | The role hierarchy exists (`Role` object, 15+ roles via the Tooling API) but **every user in Test-Org has `UserRoleId = null`** — no user carries a role. PO assumption 5 ("team lead vs. account manager is an existing role") is **not satisfied in Test-Org**. | `sf data query --query "SELECT Id, Name, UserRoleId FROM User" --target-org Test-Org` · `sf data query --use-tooling-api -q "SELECT Id, Name FROM Role" --target-org Test-Org` |
| F8 | 197 Accounts in Test-Org, owned by several users (`Meerwais Osmani`, `devops-agent`, `Automated Process`). | `sf data query --query "SELECT Id, OwnerId, Owner.Name FROM Account" --target-org Test-Org` |
| F9 | **The OWD (sharing model) of Account / Opportunity / Case is not exposed by any API we have.** Verified by calling all three: `sobject describe`, `ui-api/object-info/<Object>` and the Data API `sobjects/<Object>/describe` — none returns a sharing/access-model field. It is a Setup setting and must be read in Setup, not inferred. | see commands above |
| F10 | Dry-run-validated against Test-Org (9/9 components `Created`): `Absence__c` object + `Absent_User__c`/`Deputy__c` Lookup→User + `Start__c`/`End__c` Date + `Account.Absence_Start__c`/`Absence_End__c` Date + `Account.Absence_Deputy__c` Text(80) + `Account.Absence_In_Window__c` Text-formula with `&&` and date arithmetic. | `sf project deploy start --source-dir <probe> --target-org Test-Org --dry-run` |
| F11 | Report filter shape is `<filter><criteriaItems><column/><operator/><value/></criteriaItems></filter>` — `ReportFilter` has exactly `criteriaItems` (schema in the CLI's own `@salesforce/types/lib/metadata.d.ts`); `<criteria>`, `<field>` and `<reportFilters>` are all rejected. Dry-run accepted the shape; the only remaining complaint was the not-yet-deployed custom field. | `sf project deploy start --dry-run` + schema grep |
| F12 | A Permission Set cannot be validated before its fields exist: `In field: field - no CustomField named Account.Absence_Start__c found`. **Deploy order: fields → Permission Set → report.** | same dry-run |

---

## 2. Data model (decided before any implementation)

### 2.1 New custom object `Absence__c` — one record per account manager and absence

House shape F4 (`CustomerTransfer__c`). `sharingModel=Private`, `AutoNumber` name field.

```xml
<!-- force-app/main/default/objects/Absence__c/Absence__c.object-meta.xml -->
<CustomObject>
  <deploymentStatus>Deployed</deploymentStatus>
  <label>Fehlzeit</label>
  <pluralLabel>Fehlzeiten</pluralLabel>
  <sharingModel>Private</sharingModel>
  <nameField><displayFormat>ABSENCE-{0000}</displayFormat><label>Lauf-Nr.</label><type>AutoNumber</type></nameField>
</CustomObject>
```

| Field | Type | Purpose |
|---|---|---|
| `Absent_User__c` | Lookup → `User` (`relationshipName=Absences_AbsentUser`) | the account manager who is away |
| `Deputy__c` | Lookup → `User` (`relationshipName=Absences_Deputy`) | the covering colleague — exactly one (PO assumption 2) |
| `Start__c` | `Date` | absence from (PO assumption 1: absent **through `End__c` inclusive**) |
| `End__c` | `Date` | absence until |

`Date`, not `DateTime`: the requirement is day-granular ("from when, until when"), and the window test is `Start__c ≤ today ≤ End__c`.

**Cancel = delete the `Absence__c` record** (PO's CRUD row "Delete (= cancel an absence)"). Changing dates or deputy = edit the same record (AC6).

### 2.2 Mirror fields on `Account` — written by Apex, never by hand

The absence belongs to the manager; the customer page and the overview need it on the customer. A formula field cannot traverse `Account.Owner`, so the mirror is Apex-written. This is what makes AC2, AC3, AC6 and AC8 expressible at all.

| Field on `Account` | Type | Content |
|---|---|---|
| `Absence_Start__c` | `Date` | copy of `Absence__c.Start__c` |
| `Absence_End__c` | `Date` | copy of `Absence__c.End__c` |
| `Absence_Deputy__c` | `Text(80)` | display name of the deputy (display-only; the User Id lives on `Absence__c.Deputy__c`) |
| `Absence_In_Window__c` | `Text` formula | `"YES"` while the absence is now or within 14 days, else blank — drives the AC8 report filter without a relative-date filter |

Formula (dry-run-validated F10, no `<length>` on a Text-formula field):

```
IF(NOT(ISBLANK(Absence_End__c)) && NOT(ISBLANK(Absence_Start__c))
   && Absence_End__c >= TODAY() && Absence_Start__c - TODAY() <= 14, "YES", "")
```

`Absence_Manager__c` is **not** needed: the report column `USERS.NAME` already names the Account's owner (F5).

### 2.3 `OwnerId` is never written

AC7. The handler reads `OwnerId` to find the Accounts; it never assigns it. Contrast with SCRUM-410 `CustomerTransferJob`, which exists precisely to change ownership — **do not reuse that class**, reuse only its bulk-DML shape.

---

## 3. Components

| # | Component | Path | Responsibility |
|---|---|---|---|
| 1 | `Absence__c` object + 4 fields | `force-app/main/default/objects/Absence__c/` | the single record per manager and absence |
| 2 | 4 mirror fields on `Account` | `force-app/main/default/objects/Account/fields/` | visibility on the customer page + report columns |
| 3 | `AbsenceSyncTrigger` | `force-app/main/default/triggers/AbsenceSyncTrigger.trigger` (+meta) | `afterSaveTrigger` + `afterDeleteTrigger` on `Absence__c`; delegates to the handler |
| 4 | `AbsenceSyncHandler` | `force-app/main/default/classes/AbsenceSyncHandler.cls` | bulkified mirror write: one `Account` query per distinct absent user, then `update accounts;` (house idiom from `CustomerTransferJob`) |
| 5 | `SCRUM457_AbsenceRead` PS | `force-app/main/default/permissionsets/` | FLS read on the 4 mirror fields + object CRUD on `Absence__c` + tab |
| 6 | `SCRUM457_AbsenceWrite` PS | `force-app/main/default/permissionsets/` | Create/Edit/Delete on `Absence__c` for account managers and team leads |
| 7 | `SCRUM457_DeputyAccess` PS | `force-app/main/default/permissionsets/` | the deputy's record access — see ADR-3, this is the open decision |
| 8 | `Fehlzeiten_nach_Kunde` report | `force-app/main/default/reports/Sales/` | AC8 overview, `AccountList`, `scope=organization`, filter on `Absence_In_Window__c = YES` |
| 9 | Layout section "Fehlzeit" | `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml` | the 4 mirror fields on the customer page (house pattern: one custom section per feature — `Wartungsvertrag`, `Sperre`, `Kundansatisfaction` already exist) |
| 10 | Apex test pair + E2E spec | `force-app/main/default/classes/SCRUM457*Test.cls`, `tests/e2e/SCRUM-457*.spec.ts` | see §6 |

### Handler contract (pseudocode)

```
AbsenceSyncHandler(afterSave | afterDelete):
  usersWithActiveAbsence = { Absent_User__c -> (Start__c, End__c, DeputyName) }   // latest record wins
  usersWithoutAbsence     = Absent_User__c of deleted/cancelled records
  if both empty: return
  accounts = [SELECT Id, Owner, Absence_Start__c, Absence_End__c, Absence_Deputy__c
              FROM Account WHERE Owner IN :allUsers]          // ONE query, not one per record
  for a in accounts:
     if a.Owner in usersWithActiveAbsence:  a.Absence_Start__c = …; a.Absence_End__c = …; a.Absence_Deputy__c = …
     else if a.Owner in usersWithoutAbsence: a.Absence_Start__c = null; a.Absence_End__c = null; a.Absence_Deputy__c = null
  if (!accounts.isEmpty()) update accounts;                    // house idiom, CustomerTransferJob
  // OwnerId is never touched (AC7)
```

`Absence_In_Window__c` is a formula field — it re-evaluates at read time, so a shortened or cancelled absence follows immediately (AC6) without a second write.

---

## 4. ADR — decisions and why

**ADR-1 · Apex over Flow.** No Flow. The logic is a cross-object mirror write driven by a lookup on `Owner`, plus a revocable access grant. Flow elements cannot express "find all Accounts of this user and write three fields", and Flows have repeatedly failed at deploy/schema validation here. Declarative-only was rejected for the same reason. → Apex, per the house default.

**ADR-2 · Absence object, not User custom fields.** F3: `User` rejects Lookup fields, so the deputy cannot live on the User. A custom object with Lookup→User is the proven house shape (F4). One record per manager also satisfies "record it once, not per customer" — the user's story says a colleague could not even tell *which* customers an absence covered.

**ADR-3 · Deputy access — the hard requirement.** This is the one thing the org cannot express the way the story asks, and it must be decided before code:

- Per-record cross-owner sharing for **standard** Sales Cloud objects is not available: `Account.AccountAccess` does not exist in this org (F1, two routes), and sharing rules (`sharingRule` metadata) exist only for custom objects.
- Ownership may not change (AC7) — explicitly ruled out by the PO.
- The remaining org-expressible mechanism is **object-level access via a Permission Set**: `allowRead`/`allowEdit` + `viewAllRecords=true` on `Account`, `Opportunity`, `Case`. The house already proved this is the mechanism that makes cross-owner access work here (`SCRUM451_TestObjectAccess` carries `viewAllRecords=true` on `Account` for exactly that reason).
- **Consequence:** the grant is per *user*, not per *record*. Assigning `SCRUM457_DeputyAccess` to the deputy gives them access to **all** Accounts/Opportunities/Cases, not only the absent manager's. AC4 and AC5 are satisfied literally (assign on absence start, unassign on absence end/cancel), but the scope is broader than the absence.

Decision table for the Developer — **measure the OWD first (F9: Setup read-back, both orgs)**:

| OWD of Account / Opportunity / Case | What the deputy needs | PS scope |
|---|---|---|
| Private | `SCRUM457_DeputyAccess` assigned for the absence window, revoked after | ⚠️ org-wide, must be accepted by the PO or the requirement reworded |
| Read-Only (Account) / Full Access (Opp, Case) | record access already exists; the PS only carries FLS on the mirror fields + object CRUD | permanently assignable to colleagues, no revocation churn |

The PO must pick one. My recommendation, if the OWD turns out Private: accept the org-wide deputy PS **only for users who are entitled deputies** (i.e. assign `SCRUM457_DeputyAccess` to the deputy at absence start), and state in the ticket that the deputy can see other customers during their absence — the alternative (OWD change) is global and permanent and would change what every user sees.

**Revocation mechanism** (AC5): `PermissionSetAssignment` is a system object. The house shape exists (`insert new PermissionSetAssignment(AssigneeId = …, PermissionSetId = …)` in the `*FlsTest` classes). **Open point:** whether a non-admin user may DML `PermissionSetAssignment` — the Developer must probe this with a real Standard User before choosing between (a) the handler assigns/revokes the PS automatically, and (b) the team lead assigns/revokes it in Setup. Do not ship (a) unprobed.

**ADR-4 · Team lead vs. account manager = Permission Sets, not roles.** F7: no user in Test-Org carries a `UserRoleId`, so a role-hierarchy-based distinction cannot be tested there. House convention keeps Profiles untouched and expresses capability in Permission Sets: `SCRUM457_AbsenceWrite` (record/change/cancel an absence) is assigned to account managers and team leads. If the role hierarchy is wanted as well, it is an Org-Setup step (§5), not code.

**ADR-5 · Mirror on Account + formula window field, not a live lookup.** AC2 demands the information *on the customer page*; AC8 counts *customers*. Both need the data on the Account. `Absence_In_Window__c` as a formula keeps the 14-day window correct at read time without a nightly job (nothing automatic beyond the mirror write).

---

## 5. Org-Setup preconditions — read-back required, never asserted in a CI-gated test

Per the house rule, an AC that is an org configuration is a precondition, not an `@isTest` assertion. Each row needs the read-back in the Developer handoff (Test-Org) and the DevOps release comment (Prod-Org).

| # | Precondition | Read-back |
|---|---|---|
| S1 | OWD of `Account`, `Opportunity`, `Case` | Setup → Object Manager, read and write the three values into the handoff (F9: no API returns them) |
| S2 | `SCRUM457_*` PSs are **assigned** — to the CLI's target-org user and to the human test account | `sf data query -q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM457_AbsenceRead'"` + one mirror field read back through a real session |
| S3 | Report sharing ("All users") so team leads can open `Fehlzeiten_nach_Kunde` | Report → Settings (report-level sharing is not in the source) |
| S4 | Prod-Org: same OWD values as Test-Org | Prod-Org Drift Gate covers metadata drift; the OWD values themselves need the S1 read-back in Prod |

---

## 6. Technical acceptance criteria — every AC against a named artefact

| AC | Artefact | What the test must prove |
|---|---|---|
| AC1 | `SCRUM457AbsenceTest` (Apex, `@isTest`) | insert `Absence__c` with the three values, read them back; second test under `System.runAs(teamLead)` for the "record it for someone else" case |
| AC2 | Apex: after the insert, `SELECT Absence_Start__c, Absence_End__c, Absence_Deputy__c FROM Account WHERE Owner = :absentUser` returns non-null for **every** owned Account · E2E: the Account detail page shows the "Fehlzeit" section |
| AC3 | Apex: an Account whose owner has no absence, and one whose `End__c < TODAY()`, both read back **all three mirror fields null** · E2E: page identical to today |
| AC4 | Apex under `System.runAs(deputy)`: the Account, its open Opportunities and its open Cases are queryable, and an Opportunity update succeeds |
| AC5 | Apex negative: after the PS is unassigned (absence ended/cancelled), `System.runAs(deputy)` cannot query the Account — **unless** the deputy has the access independently, which the test must set up as a second, passing case |
| AC6 | Apex: change `End__c`/`Deputy__c` → mirror follows; delete the record → mirror null; `Absence_In_Window__c` recomputed |
| AC7 | Apex: capture `OwnerId` of Account, its Opportunities and its Cases before, assert identical after record/change/cancel |
| AC8 | Report run + row count. **A row count of 0 is not a pass** — the PO measures the expected number of customers in the window first and the Tester compares |
| AC9 | Apex: after the whole flow, assert no `EmailMessage`, no `Task`, no `Post`/chatter record and no Flow was created; and the design ships none of these artefacts |

Mixed-DML warning (house finding SCRUM-438/442): a `PermissionSetAssignment` insert may not join `Account`/`Case`/`Opportunity` DML in one transaction — the FLS-negative proof (AC5) and the business proof (AC4) must run in **separate transactions**.

---

## 7. Governor limits

- One `Account` query per trigger event (`WHERE Owner IN :users`), not one per record — the SCRUM-410 bulkification pattern. Worst case measured: 197 Accounts in Test-Org; Prod-Org count must be read back (S1 row).
- One `update accounts;` per event. A single absence covering N customers is one query + one update, not N.
- No SOQL inside a loop; no per-record DML.
- The handler must guard against recursion: it writes `Account` fields, and no `Account` trigger may depend on them (checked: `AccountLockGuard` is the only Account trigger in the repo — it reads `Is_Locked__c`/`Lock_Reason__c`, no overlap).

---

## 8. Open points (not blocking the implementation, owner named)

- [ ] **OWD values** (S1) decide the ADR-3 branch. Owner: @developer-agent, first action of the ticket.
- [ ] **Scope of the deputy grant** if the OWD is Private — the org cannot scope it per record (F1). Owner: @po-agent / @user, decision needed before AC4/AC5 can be worded finally.
- [ ] **Whether a Standard User may DML `PermissionSetAssignment`** (automatic assign/revoke vs. manual in Setup). Owner: @developer-agent, probe with `scripts/apex-probe.sh` plus a real-user runAs test before choosing.
- [ ] Prod-Org OWD and FlexiPage state (F6 was measured in Test-Org only). Owner: @devops-agent at release.
- [ ] `Account.Owner` FLS: the repo's `SCRUM451` PS comment records the deploy rejecting `Account.Owner` as a required field, while the `salesforce-platform-quirks` note says non-required lookup fields take an FLS entry. **Ask the platform** (`sf sobject describe --sobject Account` → `fieldRequired`) before writing any FLS entry on `Account.Owner` — do not copy either note.
