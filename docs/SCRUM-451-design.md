# SCRUM-451 — Wartungsvertrag at the Customer: Start-/Enddate, remaining time, expiry, sales overview

Autoritative Build-Spec for the Developer-Agent.

Repo-Ursprung surveyed: `origin/master` @ `d2e14c3a538e1a92482970b125100fb022e9a148` (2026-10-18 11:06, after `git fetch origin`).
Org facts measured 2026-10-18 against **Test-Org** (alias `Test-Org`, api 68.0) — see §9 "Verification log".

## Ziel

The customer (Account) records contract start and end date; the remaining time, the "counts as a maintenance customer" decision and the sales renewal overview are **derived declaratively** (formula fields + one ValidationRule + one Report), and the existing SCRUM-431 Case indicator follows the expiry — no Apex, no Flow, no email/task/reminder.

## ADR-1 — Apex vs. Flow vs. declarative

**Decision: 100 % declarative. No Apex production logic, no Flow.**

| Option | Verdict | Rationale |
|---|---|---|
| **Formula fields + ValidationRule + Report** | **chosen** | Every behaviour demanded is either (a) a per-record derived value or (b) a filter/sort over one object. No cross-record aggregation, no branching across records, no bulk processing. Formula fields are recomputed **at read**, so expiry follows today without a migration and without a nightly job — the SCRUM-431 Case indicator already works exactly this way. |
| Flow | **rejected** | Adds an `apiVersion`/naming surface and a strict XML schema for zero benefit; Flows have repeatedly failed deploy/schema validation in this project. Nothing here needs process steps. |
| Apex (trigger/handler) | **rejected** | A trigger would only be needed if a *stored* value had to change. PO decision 2 forbids overwriting the manually recorded flag; the derived decision must not be written. A trigger would also re-fire on the second save cycle of platform rules (skill `salesforce-describe-first` §5) without any gain. |

Consequence for the review gate: this ticket ships **no production Apex class**. Test artefacts (Apex `@isTest`, Playwright E2E) are still required — see §8.

## Components

| # | Component | Path | New/Changed |
|---|---|---|---|
| 1 | Contract start date | `force-app/main/default/objects/Account/fields/Wartungsvertrag_Start__c.field-meta.xml` | NEW |
| 2 | Contract end date | `force-app/main/default/objects/Account/fields/Wartungsvertrag_End__c.field-meta.xml` | NEW |
| 3 | Remaining days (measurable) | `force-app/main/default/objects/Account/fields/Wartungsvertrag_Ende_Tage__c.field-meta.xml` | NEW |
| 4 | Status at a glance (word value) | `force-app/main/default/objects/Account/fields/Wartungsvertrag_Status__c.field-meta.xml` | NEW |
| 5 | "counts as maintenance customer" (derived) | `force-app/main/default/objects/Account/fields/Wartungsvertrag_Active__c.field-meta.xml` | NEW |
| 6 | "ends within today → today+3 months" (window gate) | `force-app/main/default/objects/Account/fields/Wartungsvertrag_Renewal_Soon__c.field-meta.xml` | NEW |
| 7 | Case indicator | `force-app/main/default/objects/Case/fields/Wartungsvertrag_Anzeige__c.field-meta.xml` | **CHANGED formula only** (SCRUM-431 field, not duplicated) |
| 8 | End-before-start refused | `force-app/main/default/objects/Account/validationRules/Wartungsvertrag_End_Before_Start.validationRule-meta.xml` | NEW |
| 9 | Sales overview | `force-app/main/default/reports/Sales/Wartungsvertrag_Renewals_3M.report-meta.xml` | NEW |
| 10 | Account detail page | `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`, `Account-Account %28Support%29 Layout.layout-meta.xml`, `Account-Account %28Sales%29 Layout.layout-meta.xml` | CHANGED (new section) |
| 11 | FLS — team leads (dates) | `force-app/main/default/permissionsets/SCRUM451_Wartungsvertrag_Dates_Teamleitung.permissionset-meta.xml` | NEW |
| 12 | FLS — service + sales (read) | `force-app/main/default/permissionsets/SCRUM451_Wartungsvertrag_Dates_Read.permissionset-meta.xml` | NEW |
| 13 | Service morning overview (SCRUM-431) | `force-app/main/default/reports/Service/Morgen_UEbersicht_Vertragskunden.report-meta.xml` | CHANGED filter (decision D-7, PO-vetoable) |
| 14 | Manifest | `manifest/scr451-wartungsvertrag.xml` (1–13 above) | NEW |

## Data model (before implementation)

| Field (API name) | Type | Shape | Formula | Editable by |
|---|---|---|---|---|
| `Account.Wartungsvertrag_Start__c` | Date | `required=false unique=false externalId=false trackTrending=false` | — | Teamleitung |
| `Account.Wartungsvertrag_End__c` | Date | same | — | Teamleitung |
| `Account.Wartungsvertrag_Ende_Tage__c` | Number | `precision=10 scale=0 unique=false formulaTreatBlanksAs=BlankAsZero` | `IF(ISBLANK(Wartungsvertrag_End__c), null, IF(Wartungsvertrag_End__c >= TODAY(), Wartungsvertrag_End__c - TODAY(), null))` | nobody (formula) |
| `Account.Wartungsvertrag_Status__c` | Text | `required=false unique=false formulaTreatBlanksAs=BlankAsZero` — **NO `<length>`** | `IF(ISBLANK(Wartungsvertrag_End__c), null, IF(Wartungsvertrag_End__c < TODAY(), "expired", IF(Wartungsvertrag_End__c = TODAY(), "ends today", "in " & TEXT(Wartungsvertrag_End__c - TODAY()) & " days")))` | nobody (formula) |
| `Account.Wartungsvertrag_Active__c` | Checkbox | `formula` only | `AND(Wartungsvertrag__c, OR(ISBLANK(Wartungsvertrag_End__c), Wartungsvertrag_End__c >= TODAY()))` | nobody (formula) |
| `Account.Wartungsvertrag_Renewal_Soon__c` | Checkbox | `formula` only | `AND(NOT(ISBLANK(Wartungsvertrag_End__c)), Wartungsvertrag_End__c >= TODAY(), Wartungsvertrag_End__c <= ADDMONTHS(TODAY(), 3))` | nobody (formula) |
| `Case.Wartungsvertrag_Anzeige__c` | Text (existing) | keep deployed shape | `IF(AND(Account.Wartungsvertrag__c, OR(ISBLANK(Account.Wartungsvertrag_End__c), Account.Wartungsvertrag_End__c >= TODAY())), "Ja", "Nein")` | nobody (formula) |

**Single source of truth for "counts as a maintenance customer"** — one boolean expression, written identically in two artefacts:

    Wartungsvertrag__c AND ( Wartungsvertrag_End__c IS BLANK  OR  Wartungsvertrag_End__c >= TODAY() )

It appears in `Account.Wartungsvertrag_Active__c` (§5) and inline in the Case formula (§7). They must not drift: the Tester asserts both against the same three fixtures (end = today+45, end = today, end = today-1, end blank). End date is **inclusive** (PO decision 1): `>= TODAY()`.

Empty end date ⇒ `Wartungsvertrag_Ende_Tage__c` and `Wartungsvertrag_Status__c` blank, `Wartungsvertrag_Active__c` = the flag unchanged, Case indicator "Ja" — i.e. exactly today's behaviour (PO decision 3/4). No negative day count is ever produced (the `null` branch), matching the house pattern `Opportunity.Days_Close_Date_Overdue__c` (`MAX(0, …)`).

## Artefacts (exact XML — the repo files are authoritative, not this comment)

### 1+2 Date fields

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Wartungsvertrag_Start__c</fullName>
    <label>Wartungsvertrag start</label>
    <description>SCRUM-451: Manually recorded start of the maintenance contract (team leads only). Commercially sensitive business data, not PII. Empty = never recorded, behaviour unchanged.</description>
    <type>Date</type>
    <required>false</required>
    <unique>false</unique>
    <externalId>false</externalId>
    <trackTrending>false</trackTrending>
</CustomField>
```

(`Wartungsvertrag_End__c` identical, label `Wartungsvertrag end`.) House shape: `Account.Satisfaction_Fenster_Start__c`.

### 3–6 Formula fields

House shapes: Number = `Account.Customer_Since_Days__c` (SCRUM-382); Text = `Case.Wartungsvertrag_Anzeige__c` / `Lead.Data_Quality__c` (no `<length>`); Checkbox = `Lead.Is_Due__c` (SCRUM-378). `&gt;`/`&lt;`/`&amp;` are the XML escapes the deployed files use.

```xml
<fullName>Wartungsvertrag_Ende_Tage__c</fullName>
<formula>IF(ISBLANK(Wartungsvertrag_End__c), null, IF(Wartungsvertrag_End__c &gt;= TODAY(), Wartungsvertrag_End__c - TODAY(), null))</formula>
<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
<precision>10</precision><scale>0</scale><type>Number</type><unique>false</unique>
```

```xml
<fullName>Wartungsvertrag_Renewal_Soon__c</fullName>
<formula>AND(NOT(ISBLANK(Wartungsvertrag_End__c)), Wartungsvertrag_End__c &gt;= TODAY(), Wartungsvertrag_End__c &lt;= ADDMONTHS(TODAY(), 3))</formula>
<type>Checkbox</type>
```

**`ADDMONTHS`, not `ADD_MONTHS`** — measured: `ADD_MONTHS` and `ADD_MONTH` are rejected ("Unknown function"), `ADDMONTH` is rejected ("may not be used in this type of formula"), `ADDMONTHS(TODAY(), 3)` validates. Do not "fix" the spelling.

### 8 ValidationRule

```xml
<fullName>Wartungsvertrag_End_Before_Start</fullName>
<active>true</active>
<errorConditionFormula>AND(NOT(ISBLANK(Wartungsvertrag_Start__c)), NOT(ISBLANK(Wartungsvertrag_End__c)), Wartungsvertrag_End__c &lt; Wartungsvertrag_Start__c)</errorConditionFormula>
<errorMessage>Enddate before Startdate is refused - please correct the contract dates.</errorMessage>
```

House shape: `Account.LockReason_PflichtBeiGesperrt` (SCRUM-384). Equal dates are allowed (PO decision 1).

### 9 Sales overview (AccountList)

```xml
<columns><field>ACCOUNT.NAME</field></columns>
<columns><field>USERS.NAME</field></columns>
<columns><field>Account.Wartungsvertrag_End__c</field></columns>
<columns><field>Account.Wartungsvertrag_Status__c</field></columns>
<filter> … column Account.Wartungsvertrag_Renewal_Soon__c, operator equals, value 1 … </filter>
<format>Tabular</format>
<reportType>AccountList</reportType>
<scope>organization</scope>
<showDetails>true</showDetails>
<sortColumn>Account.Wartungsvertrag_End__c</sortColumn>
<sortOrder>Asc</sortOrder>
```

Column tokens are **not** derivable from API names; they were read back from the platform (§9): `ACCOUNT.NAME` → Account.Name, `USERS.NAME` → Account.Owner.Name (label "Account Owner"). Custom Account fields resolve as `Account.<Field>__c` (house: `Offene_Werte_nach_Kunde`, `Miserable_Kunde_Satisfaction`). `<scope>organization</scope>` is the value the deployed AccountList reports use (`scopeInfo` is null for AccountList — do not carry `org` over from LeadList).

No `timeFrameFilter`: there is **no 3-month interval token** (CLI metadataRegistry: LAST7/30/60/90/120, LASTMONTH, LASTWEEK, CURRENT, CUSTOM) and `timeFrameFilter` carries exactly one date column — the SCRUM-443 defect. The window lives in `Wartungsvertrag_Renewal_Soon__c` and is stated in the description.

### 11+12 Permission Sets

```xml
<!-- SCRUM451_Wartungsvertrag_Dates_Teamleitung -->
<fieldPermissions><editable>true</editable><field>Account.Wartungsvertrag_Start__c</field><readable>true</readable></fieldPermissions>
<fieldPermissions><editable>true</editable><field>Account.Wartungsvertrag_End__c</field><readable>true</readable></fieldPermissions>
<!-- SCRUM451_Wartungsvertrag_Dates_Read (service + sales) -->
<fieldPermissions><editable>false</editable><field>Account.Wartungsvertrag_… every one of the 6 new Account fields …</field><readable>true</readable></fieldPermissions>
```

`SCRUM451_Wartungsvertrag_Dates_Read` must list **all six** new Account fields (2 dates + 4 derived) with `readable=true, editable=false`. FLS is never inherited from object CRUD, and a formula field the user cannot read renders invisible — the Case indicator reads `Account.Wartungsvertrag_End__c`, so service/sales need that read grant to see "Ja"/"Nein" at all.

**Assignment is half the work.** Both PS must be assigned, and the Developer hand-off must carry the read-back:

```
sf data query -o Test-Org -q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM451_Wartungsvertrag_Dates_Read'"
```

Target users (measured, house rule "both users of the org"): `devops-agent@cline.test` and `meerwais.osmani@resourceful-bear-6f1u4j.com` — the same two users the SCRUM-431 PS are assigned to today. Plus one field read back through a real session.

## Architecture decisions

1. **Derived, never stored.** The expiry decision is a formula, so an expired contract stops counting on the next read without touching a single record — and the manually recorded flag is never overwritten (PO decision 2).
2. **Extend, do not duplicate.** `Case.Wartungsvertrag_Anzeige__c` keeps its API name, type and layout placement; only its `<formula>` changes. Same for the SCRUM-431 Service report (D-7).
3. **Window gate as a field, not as a report filter.** A report cannot express "today → today+3 months" (no interval token, one date column per `timeFrameFilter`). A Checkbox formula field is precise, visible, and testable; the report filters on it.
4. **Two display artefacts, not one.** `Wartungsvertrag_Ende_Tage__c` (Number) is the measurable "45"; `Wartungsvertrag_Status__c` (Text) is the human glance ("in 45 days" / "ends today" / "expired"). The AC "never shows a negative day count" is satisfied by the `null` branch, not by `MAX(0,…)`, so an expired contract shows no number at all.
5. **`Account.Owner` stays standard.** The overview reads it via the report column `USERS.NAME`; no new field, no Profile change.
6. **Sharing model: no impact.** No sharing rule, no OWD change, no new object. The overview is org-wide via `<scope>organization</scope>`; a user without Account read does not see the record anyway (Read All semantics unchanged).
7. **D-7 (PO-vetoable):** the SCRUM-431 Service morning overview filters `Account.Wartungsvertrag__c equals 1` — the raw flag. After this story an expired customer is no longer a maintenance customer, so that report would still list it: the same mistake the user reported, one artefact further. Proposed: switch its filter to `Account.Wartungsvertrag_Active__c equals 1`. Not in the AC list; the PO may veto.

## ⚠️ Findings (measured, with the command)

1. **Counts are near-zero in Test-Org today.** `SELECT COUNT() FROM Account` → **187**; `Account WHERE Wartungsvertrag__c = true` → **1**; `SELECT COUNT() FROM Case` → **665**. No contract dates exist anywhere (the fields are new). So the sales overview renders **0 rows** and the expired-indicator criterion has **0 records** until test data is seeded. Per the guardrail, a criterion measured against zero records is *untested*, not PASS. The Tester must seed customers with end dates (today+45, today, today-1, blank) in Test-Org and report the four counts.
2. **Lightning vs. Classic.** The repo tracks Classic `*.layout-meta.xml` only. The detail page the user opens may be a Lightning page → layout placement in the Org is an **Org step** (@devops-agent); the repo-side guarantee is FLS read. State both in the coverage table.
3. **Report-level sharing/folder placement is not in source** (verified against deployed report XML in SCRUM-442): making the overview openable by sales users is an Org step.
4. **ValidationRule on a standard object (Account).** It runs on API and UI save (not on Apex DML without `DMLOptions`) and it aborts a bulk import as a unit. Measured: **0** classes on `origin/master` reference `Wartungsvertrag_Start__c`/`Wartungsvertrag_End__c`, so no existing test class can save an Account in the blocked state. The Tester's own Account-inserting tests must not set end < start except in the deliberate negative test.
5. **Mixed DML.** `PermissionSetAssignment` inserts must not join Account/Case inserts in one `SaveResult` block, in either order — split the FLS-negative proof from the business-DML proof into separate transactions (house lesson SCRUM-438/442).
6. **FLS defaults of new fields are not predictable.** The negative test ("a non-team-lead cannot change the flag or the dates") is only satisfiable if the profile blocks; measure it with an own `@isTest` probe in the target profile, never extrapolated from a Profile block.
7. **Formula fields cannot be written in tests.** Set up the dates as a team-lead user, then read the derived fields; assert the derived values, never assign them.

## Verification log (commands I ran, 2026-10-18, Test-Org)

| Question | Command | Result |
|---|---|---|
| Do the SCRUM-431 artefacts exist? | `git ls-tree -r origin/master` | flag, Case indicator, 2 PS, Service report, `docs/SCRUM-431-design.md` |
| Name collision for the new fields? | `git grep -E 'Wartungsvertrag_(Start\|End)' origin/master` | **0 hits** |
| Report column tokens for AccountList | `sf api request rest /services/data/v68.0/analytics/reportTypes/AccountList` | 7 columns: `ACCOUNT.NAME`, `USERS.NAME`(=Account.Owner.Name), `DUE_DATE`, … ; `scopeInfo: null` |
| Month function in formulas | `sf project deploy start --source-dir scratch/probe452 --dry-run` | `ADDMONTHS` ✅, `ADD_MONTHS`/`ADD_MONTH` ❌, `ADDMONTH` ❌(wrong formula type) |
| Field/report/valrule shapes | same dry run (checkOnly) | all 6 fields, the ValidationRule and the Tabular+`sortColumn` report validate |
| Case cross-object formula | same dry run | validates against the new Account date |
| FLS grant of the existing flag | `sf data query -o Test-Org -q "SELECT Parent.Label, Parent.IsOwnedByProfile, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE SobjectType='Account' AND Field='Account.Wartungsvertrag__c'"` | ServiceTeam read-only, Teamleitung read+edit, both `IsOwnedByProfile=false` |
| FLS assignment of the 431 PS | `sf data query -o Test-Org -q "SELECT Assignee.Username FROM PermissionSetAssignment WHERE PermissionSet.Name='…'"` | 2 users each: `devops-agent@cline.test`, `meerwais.osmani@resourceful-bear-6f1u4j.com` |
| Nothing was deployed by the probes | `sf data query --use-tooling-api … FieldDefinition … LIKE 'Wartuvertag%'` → see below | exactly **1** Account field: `Wartungsvertrag__c` (Checkbox) — the dry runs were `checkOnly: true` |

## Technical acceptance criteria (Tester's coverage table)

| PO AC | Artefact | Test artefact (house shape) |
|---|---|---|
| dates stored + visible to service/sales | fields 1+2, PS 12 | `SCRUM451WartungsvertragFlsTest` (shape `SCRUM431FlsTest`) + read-back |
| non-team-lead change refused, value unchanged | PS 11/12 `editable=false` | `SCRUM451WartungsvertragFlsTest` negative, `System.runAs` restricted user |
| "45 days" at a glance | 3+4 | `SCRUM451WartungsvertragTest` (shape `SCRUM382CustomerSinceDaysTest`): end = today+45 → `Ede_Tage__c = 45`, `Status__c = "in 45 days"` |
| ends today still counts | `>= TODAY()` | same class: end = today → 0 days, `Active__c = true`, Case "Ja" |
| expired states + no negative count | 3+4 | end = today-1 → `Ede_Tage__c` blank, `Status__c = "expired"`, `Active__c = false` |
| case of expired customer shows no indicator, count 0 | 7 | same class + SOQL count of Cases of expired customers with `Wartungsvertrag_Anzeige__c = 'Ja'` must be **0** |
| empty end date keeps today's behaviour | 3–7 | end blank → flag unchanged, Case "Ja", not in overview |
| start without end behaves the same | 5+7 | fixture with start only |
| overview rows = measured count | 9 | E2E `tests/e2e/SCRUM-451-wartevertrag-renewals.spec.ts` (shape `SCRUM-431-wartevertrag.spec.ts`): frontdoor.jsp auth, assert the header's "Select N items" count, never the rendered row count (Lightning renders only the first page) |
| expired + no-end-date not listed | 6+9 | same spec |
| nothing automatic | no email/task/reminder artefact | absence-of-artefact check in the review |
| end before start refused | 8 | negative save test must throw |

## Offene Punkte (do not block the implementation)

- [ ] D-7 (Service morning report filter switch) — @po-agent may veto; default = switch.
- [ ] Lightning placement of the new section + report availability for sales users — Org step, @devops-agent.
- [ ] Which Test-Org user stands in for "Sales" when the negative/positive FLS proof runs — measured: only the two users above hold the 431 PS; the Tester needs a user **without** `SCRUM451_Wartungsvertrag_Dates_*` for the negative test.

## Handoff

Branch `feature/SCRUM-451` (fresh from `origin/master` @ `d2e14c3a`). This file plus `docs/SCRUM-451-notizen.md` are committed and pushed here; reachability is proven with `git cat-file -e origin/feature/SCRUM-451:docs/SCRUM-451-design.md`.
