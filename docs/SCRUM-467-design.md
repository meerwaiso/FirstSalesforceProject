# SCRUM-467 — Opportunity: Offer sent on / valid until, expiry at a glance, expired offer cannot be won, team-lead overview of the next 14 days

Autoritative Build-Spec for the Developer-Agent — **status: READY (2026-11-21)**.
The PO answered the blocking point (§0 is marked RESOLVED): the permission boundary is
the new Permission Set, not record ownership. Everything in **§11 "Verified shapes"**
was check-only validated against Test-Org today; the exact files are committed under
`docs/SCRUM-467-shapes/` (inert — the Developer copies them into `force-app/`).

Repo-Ursprung surveyed: `origin/master` @ `31da29f70f808377b3ca1d2e2022660dc37f4d07`
(2026-11-21 07:46, after `git fetch origin`).
Org facts measured 2026-11-21 by the Architect against **Test-Org** (alias `Test-Org`,
latest API `68.0`) — commands in §10 "Verification log".

## Ziel

Record on an open Opportunity when an offer was sent and until when it is valid; derive
the expiry state at read time so that an expired offer can no longer be closed as Won,
renew it by hand, and give the team leads two organisation-wide overviews (expiring
within 14 days / already expired).

## ADR-1 — Apex vs. Flow vs. declarative

**Decision: 100 % declarative — formula fields + ValidationRules + Reports/Layout; no
Flow, no production Apex class at all** (the PO ruled the user-based guard out, §0 RESOLVED).

| Option | Verdict | Rationale |
|---|---|---|
| **Formula fields + ValidationRules + Reports/ListViews** | **chosen** | Every demanded behaviour is either (a) a per-record derived value or (b) a filter/sort over one object. No cross-record aggregation, no bulk processing, no state machine. Formula fields are recomputed **at read**, so expiry follows today without a migration and without a nightly scheduler. This is the released house pattern of SCRUM-451 (contract start/end + remaining days + status + renewal overview) and SCRUM-449/461 (Opportunity VRs + `Opportunity.*` listViews). |
| Flow | **rejected** | Adds an `apiVersion`/naming surface and a strict XML schema for zero benefit; Flows have repeatedly failed deploy/schema validation in this project. Nothing here needs process steps. |
| Apex trigger/handler | **rejected** | A trigger would be needed only if a *stored* value had to change or if a save had to be refused based on who the user is. Formula fields must not be written; AC1/AC6 write the two dates by hand. The PO ruled a user-based guard out — the boundary is FLS, so no handler is introduced. |

Consequence for the review gate: this ticket ships **no production Apex class at all**.
Test artefacts are required (§8).

## 0. Blocking point — AC12 vs. AC13 could not both hold — **RESOLVED by the PO (2026-11-21)**

**PO decision (written into the ticket):** the boundary is **who holds the ONE new
Permission Set**, never who owns the record. AC12 ("the team leads can do it for
everyone") is read as a *capability*, not as a restriction. Therefore: **no non-owner
guard, no second marker Permission Set, no Apex class for that purpose.** AC13 stays the
mandatory negative-access test — a user without the Permission Set cannot fill the two
dates and the attempt is refused (house pattern: the SCRUM-451 negative test class).

The proof below is kept as the reason the original wording was unimplementable — it is
what forced the PO back to the board, and it is why no owner-based condition may be
re-introduced later.

Proof sketch (all three facts measured/stated, not assumed):

1. Profiles in Test-Org are exactly the standard Salesforce set — there is **no**
   "Account Manager" and **no** "Sales Team Lead" profile (Profile recordtype query,
   §10). Profile identity therefore cannot separate the two groups.
2. SCRUM-457 (released, confirmed by @user): "A team lead is **not a role** in the org:
   nobody has a role assigned and the only existing roles are Salesforce standard
   sample roles." Role hierarchy therefore cannot separate them either.
3. SCRUM-457 (released, confirmed by @user): OWD of Opportunity is **Public Read/Write**
   in both orgs — record access cannot refuse a foreign-owned record, and SCRUM-467 asks
   for no OWD/sharing change.

The only org-visible discriminator left is **Permission Set membership** (house pattern
of SCRUM-428/431/445/451/459/461/464: a `*_Teamleitung` / `*_Team` PS marks the team
leads). But the PO demands **exactly ONE** new PS carrying Read+Edit of the two new
fields, **assigned to both groups**. A single PS grants identical rights to every
assigned user, so:

- an ownership-only guard (allow iff `user == Opportunity.OwnerId`) refuses the team
  lead as well → **AC12 fails**;
- no ownership guard at all lets the account manager edit foreign records → **AC13 fails**.

An AC13 test built under the second design is a probe that cannot fail under its
hypothesis — it proves nothing.

| Resolution | What it means concretely | Cost |
|---|---|---|
| **A (recommended)** | AC13 is dropped to FLS truth: every holder of `SCRUM467_Offer_Dates` may record and renew on any open Opportunity (team lead and account manager alike). AC13 is deleted from the ticket; the negative test becomes "a user **without** the PS cannot fill the two dates". | no extra artefact, 100 % declarative, matches SCRUM-457's released "the deputy needs no extra access — Public Read/Write already covers it" |
| **B** | Keep the one `SCRUM467_Offer_Dates` PS for the fields (PO constraint intact) and define "team lead" = holder of a **second, marker PS** (e.g. `SCRUM467_Offer_Teamlead`) that carries **no** field rights. The guard is one Apex `AfterUpdate/AfterSave` handler: refuse when the two dates actually changed, `user != record.OwnerId`, and the user does not hold the marker PS. | contradicts "exactly ONE new Permission Set"; one Apex class + trigger; must be bulkified and guarded inside the changed-branch (§7, SCRUM-456 pitfall) |

The PO has to choose. Nothing is implemented before that answer.

## Components (final names — collision-checked against Test-Org, §10)

| # | Component | Path | New/Changed |
|---|---|---|---|
| 1 | Offer sent on | `force-app/main/default/objects/Opportunity/fields/Offer_Sent_On__c.field-meta.xml` | NEW |
| 2 | Offer valid until | `force-app/main/default/objects/Opportunity/fields/Offer_Valid_Until__c.field-meta.xml` | NEW |
| 3 | Effective last valid day (derived) | `force-app/main/default/objects/Opportunity/fields/Offer_Expires_On__c.field-meta.xml` | NEW |
| 4 | Days left (derived, measurable) | `force-app/main/default/objects/Opportunity/fields/Offer_Days_Left__c.field-meta.xml` | NEW |
| 5 | Status at a glance (derived wording) | `force-app/main/default/objects/Opportunity/fields/Offer_Status__c.field-meta.xml` | NEW |
| 6 | Expired gate (derived) | `force-app/main/default/objects/Opportunity/fields/Offer_Expired__c.field-meta.xml` | NEW |
| 7 | Expires within 14 days (derived) | `force-app/main/default/objects/Opportunity/fields/Offer_Expiring_14D__c.field-meta.xml` | NEW |
| 8 | Expired offer cannot be won | `force-app/main/default/objects/Opportunity/validationRules/Offer_Won_With_Expired_Offer.validationRule-meta.xml` | NEW |
| 9 | End date not before start date (house-consistent, PO-vetoable) | `force-app/main/default/objects/Opportunity/validationRules/Offer_End_Before_Start.validationRule-meta.xml` | NEW |
| 10 | Dates frozen once won/lost (CRUD "not editable once closed") | `force-app/main/default/objects/Opportunity/validationRules/Offer_Dates_Kein_Closed_Change.validationRule-meta.xml` | NEW, shape flagged in §5b |
| 11 | Record page — at a glance | `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml` | CHANGED (new section) |
| 12 | Team-lead overview 1 (next 14 days, sorted) | `force-app/main/default/reports/Sales/Offers_Expire_14D.report-meta.xml` | NEW |
| 13 | Team-lead overview 2 (already expired) | `force-app/main/default/reports/Sales/Offers_Already_Expired.report-meta.xml` | NEW |
| 14 | Record-page list views | `force-app/main/default/objects/Opportunity/listViews/Offers_Expire_14D.listView-meta.xml`, `.../Offers_Already_Expired.listView-meta.xml` | NEW |
| 15 | FLS | `force-app/main/default/permissionsets/SCRUM467_Offer_Dates.permissionset-meta.xml` | NEW |
| 16 | (only under Resolution B) marker PS + guard | `force-app/main/default/permissionsets/SCRUM467_Offer_Teamlead.permissionset-meta.xml`, `.../classes/OfferGuardHandler.cls`, `.../triggers/OfferGuardTrigger.trigger` | NEW, conditional |
| 17 | Manifest | `manifest/scr467-offer-validity.xml` | NEW |

No naming collision: Test-Org's Opportunity carries no `Offer*` field (§10) and master
has no VR/report/listView of these names.

## Data model (before implementation)

| Field (API name) | Type | Shape | Formula | Editable by |
|---|---|---|---|---|
| `Opportunity.Offer_Sent_On__c` | Date | `required=false unique=false externalId=false trackTrending=false` | — | PS (§6) |
| `Opportunity.Offer_Valid_Until__c` | Date | same | — | PS (§6) |
| `Opportunity.Offer_Expires_On__c` | Date + formula | see §3a — **unproven shape in the house, must deploy-validate** | `IF(ISBLANK(Offer_Sent_On__c), null, IF(ISBLANK(Offer_Valid_Until__c), Offer_Sent_On__c + 30, Offer_Valid_Until__c))` | nobody |
| `Opportunity.Offer_Days_Left__c` | Number | `precision=10 scale=0 formulaTreatBlanksAs=BlankAsZero` | `IF(ISBLANK(Offer_Expires_On__c), null, IF(Offer_Expires_On__c >= TODAY(), Offer_Expires_On__c - TODAY(), null))` | nobody |
| `Opportunity.Offer_Status__c` | Text | **no `<length>`** (deploy rejects it on Text-formula, house bc0b57f) | `IF(ISBLANK(Offer_Expires_On__c), null, IF(Offer_Expires_On__c < TODAY(), "offer expired", IF(Offer_Expires_On__c = TODAY(), "offer valid today", "offer valid for " & TEXT(Offer_Expires_On__c - TODAY()) & " more days")))` | nobody |
| `Opportunity.Offer_Expired__c` | Checkbox | formula only | `AND(NOT(ISBLANK(Offer_Expires_On__c)), Offer_Expires_On__c < TODAY())` | nobody |
| `Opportunity.Offer_Expiring_14D__c` | Checkbox | formula only | `AND(NOT(ISBLANK(Offer_Expires_On__c)), Offer_Expires_On__c >= TODAY(), Offer_Expires_On__c - TODAY() <= 14)` | nobody |

**Single source of truth for "expired"** — the one boolean expression
`Offer_Expires_On__c < TODAY()` (with the not-blank guard) is written identically in
`Offer_Expired__c` (§6 component) and in the ValidationRule of §5a. They must not drift;
the Tester asserts both against the same fixtures (end = today+45, end = today,
end = today+14, end = today, end = today-1, end blank, sent-only-no-end).

End date is **inclusive** ("the end date itself is the last valid day", AC2/AC3):
`>= TODAY()` live, `< TODAY()` expired. Day after the end date ⇒ expired. ✓

AC2 default rule lives in exactly one place (`Offer_Expires_On__c`); the recorded
`Offer_Valid_Until__c` stays **empty** when the user leaves it empty — nothing is ever
written automatically (AC11, AC1 "exactly as entered").

## Artefacts (exact XML — the repo files are authoritative, not this comment)

**The verified files are in `docs/SCRUM-467-shapes/` (§11) — every one of them passed a
check-only deploy validation against Test-Org today. The draft XML in the sections below
is superseded where it differs.** Copy from `docs/SCRUM-467-shapes/` into `force-app/`.

### Two Date fields (house shape: `Account.Wartungsvertrag_Start__c`, SCRUM-451)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Offer_Sent_On__c</fullName>
    <label>Offer sent on</label>
    <description>SCRUM-467: Date the offer was sent to the customer. Business data, not PII. Empty = no offer recorded, record behaves as today.</description>
    <type>Date</type>
    <required>false</required>
    <unique>false</unique>
    <externalId>false</externalId>
    <trackTrending>false</trackTrending>
</CustomField>
```

(`Offer_Valid_Until__c` identical, label `Offer valid until`, description adds
"empty = default rule, valid until Offer sent on + 30 days".)

### Formula fields

House shapes: Number = `Opportunity.Inactive_Days__c` / `Account.Wartungsvertrag_Ende_Tage__c`;
Text = `Lead.Data_Quality__c` / `Account.Wartungsvertrag_Status__c` (no `<length>`);
Checkbox = `Account.Wartungsvertrag_Renewal_Soon__c`. XML escapes: `&gt;` `&lt;` `&amp;`.

```xml
<fullName>Offer_Expires_On__c</fullName>
<formula>IF(ISBLANK(Offer_Sent_On__c), null, IF(ISBLANK(Offer_Valid_Until__c), Offer_Sent_On__c + 30, Offer_Valid_Until__c))</formula>
<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
<type>Date</type>
```

**⚠️ Two shapes are NOT yet proven in the house — the Developer must deploy-validate
them first (`sf project deploy validate --source-dir force-app --test-level RunSpecifiedTests --tests <SCRUM467 classes>`), before anything else of this ticket deploys:**

1. a **Date-typed formula field** (the house has only Number/Text/Checkbox formula
   fields — measured over all `*.field-meta.xml` on `origin/master`);
2. **Date + Number** inside that formula (`Offer_Sent_On__c + 30`).

Fallback if (1) or (2) is refused: keep `Offer_Sent_On__c + 30` as `ADDDAYS(Offer_Sent_On__c, 30)`
if the platform knows that function (deploy-validate answers; SCRUM-451 measured that
`ADDMONTHS` is the valid spelling and `ADD_MONTHS`/`ADDMONTH` are not), else derive the
effective end day **only as a Number** (`Offer_Days_Left__c` + `Offer_Expiring_14D__c`
+ `Offer_Expired__c`) and use `Offer_Valid_Until__c` for the displayed expiry date,
documenting that default-rule rows show the date as computed. Do not hand over a
half-validated formula.

### Validation rules

**(a) AC5 — expired offer cannot be won** (house shape: `No_Won_Without_Approval`,
SCRUM-445; `Competitor_PflichtBeiWettbewerber`, SCRUM-461 — a VR fires only on the
records being saved, so historical deals stay untouched, which is exactly AC8/AC6):

```xml
<fullName>Offer_Won_With_Expired_Offer</fullName>
<active>true</active>
<errorConditionFormula>AND(ISPICKVAL(StageName, &quot;Closed Won&quot;), Offer_Expired__c = true)</errorConditionFormula>
<errorDisplayField>Offer_Valid_Until__c</errorDisplayField>
<errorMessage>The offer has expired. Renew it with a new sent date and a new validity end date before the deal can be closed as Won.</errorMessage>
```

AC7 (losing stays possible) is satisfied because the rule looks only at `Closed Won`.
AC4 (no offer at all) because `Offer_Expired__c` is false while both dates are blank.

**(b) house-consistent** (AC1/AC6 sanity, PO-vetoable, mirrors SCRUM-451
`Wartungsvertrag_End_Before_Start`):

```xml
<fullName>Offer_End_Before_Start</fullName>
<errorConditionFormula>AND(NOT(ISBLANK(Offer_Sent_On__c)), NOT(ISBLANK(Offer_Valid_Until__c)), Offer_Valid_Until__c &lt; Offer_Sent_On__c)</errorConditionFormula>
```

**(c) CRUD "not editable once the deal is won or lost" (AC8).** This needs the
*previous* stage, not the saved one:

```xml
<fullName>Offer_Dates_Kein_Closed_Change</fullName>
<errorConditionFormula>AND(ISPICKVAL(PREVIOUS(StageName), &quot;Closed Won&quot;) ... )</errorConditionFormula>
```

**Open verification:** `PREVIOUS()` is not used anywhere on `origin/master` (measured:
zero hits), so its availability inside a ValidationRule error formula is unproven here.
The Developer validates it with a deploy-validate of this one file. If it is refused,
the accepted fallback is the weaker house-shaped rule
`AND(ISPICKVAL(StageName,"Closed Won"), ISPICKVAL(StageName,"Closed Lost") excluded, changed dates)`…
— concretely: refuse when the saved record is already `Closed Won`/`Closed Lost` **and**
a date changed; the residual gap (closing and editing the dates in one single save) is
then stated in the PR description and verified by the Tester as an E2E step, not silently
accepted.

## FLS / Permission Set design

Exactly ONE new PS as the PO demands, house shape (`SCRUM451_Wartungsvertrag_Dates_*`,
`SCRUM459_FollowupMonitoring_*`): Read+Edit on the two recorded dates, Read-only
(`editable=false`, `readable=true`) on the five derived fields — a formula field must
be readable to be shown on the record page and to resolve in a Report.

```xml
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>SCRUM467_Offer_Dates</fullName>
    <description>SCRUM-467: Read+Edit of the two recorded offer dates for account managers and team leads; read-only on the five derived fields. No Permission Profile edited.</description>
    <fieldPermissions><editable>true</editable><field>Opportunity.Offer_Sent_On__c</field><readable>true</readable></fieldPermissions>
    <fieldPermissions><editable>true</editable><field>Opportunity.Offer_Valid_Until__c</field><readable>true</readable></fieldPermissions>
    <fieldPermissions><editable>false</editable><field>Opportunity.Offer_Expires_On__c</field><readable>true</readable></fieldPermissions>
    <fieldPermissions><editable>false</editable><field>Opportunity.Offer_Days_Left__c</field><readable>true</readable></fieldPermissions>
    <fieldPermissions><editable>false</editable><field>Opportunity.Offer_Status__c</field><readable>true</readable></fieldPermissions>
    <fieldPermissions><editable>false</editable><field>Opportunity.Offer_Expired__c</field><readable>true</readable></fieldPermissions>
    <fieldPermissions><editable>false</editable><field>Opportunity.Offer_Expiring_14D__c</field><readable>true</readable></fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM467_Offer_Dates</label>
</PermissionSet>
```

**Deploying the PS is half the work** (house rule, six recurrences on this board): it
must be **assigned** — to the CLI target-org user **and** to the human test account —
and one of the two dates must be **read back through a real session** before hand-off.
The first symptom otherwise is a `No such column` / `fields being inaccessible on Sobject`
error that reads like a missing field, not like a permission. `scripts/fls-check.sh
Opportunity Offer_Sent_On__c` ends the question in twenty seconds; CI's `scripts/fls-gate.py`
reddens a changed field that names no PS or names one assigned to nobody.

Resolution B adds `SCRUM467_Offer_Teamlead` with **no** field permissions (a pure marker),
assigned to the team-lead users only — the Apex guard tests membership, not rights.

## Sharing model impact

**No impact, and that is a measured decision, not an assumption:** SCRUM-457 (released,
@user-confirmed) states OWD of Account, Opportunity and Case is **Public Read/Write in
both orgs** — renewal rights and the overviews therefore already reach records owned by
other account managers, and no sharing rule, OWD change or owner-only rule is needed
(PO text of SCRUM-467 asks exactly that). The `OwnerId` field exists on Opportunity in
Test-Org (`OwnerId`, "Owner ID", reference) and is the column token `FULL_NAME`
("Opportunity Owner") in the `Opportunity` report type (§10) — so "the account manager"
of AC9 is expressible without any sharing change.

## Overview artefacts (AC9/AC10)

Two Reports are the authoritative AC9/AC10 artefacts because a Report carries
**sort and scope in source**, a ListView does not (the ListView schema has no sort
element — measured in SCRUM-432; sorting is then a UI/Org step).

House file for the whole shape: `force-app/main/default/reports/Sales/Hoeh_Risk_Chancen.report-meta.xml`
(SCRUN-449) and `Kunde_ohne_Kontaktperson.report-meta.xml` (SCRUM-453).

* `Offers_Expire_14D`: `reportType Opportunity`, `scope organization`,
  `format Summary`, filter `Opportunity.Offer_Expiring_14D__c equals 1` **and**
  `STAGE_NAME notEqual Closed Won,Closed Lost` (house criterion from `Hoeh_Risk_Chancen`),
  columns `ACCOUNT_NAME`, `FULL_NAME`, `AMOUNT`, `Opportunity.Offer_Expires_On__c`,
  `OPPORTUNITY_NAME`, `STAGE_NAME`;
  `<sortColumn>Opportunity.Offer_Expires_On__c</sortColumn><sortOrder>Asc</sortOrder>`
  → "soonest expiry first" is in source, no Org step.
* `Offers_Already_Expired`: identical except filter `Opportunity.Offer_Expired__c equals 1`
  and sort `Desc` (oldest expiry first, renewal decision).

Column tokens were **read from the platform**, not guessed (§10): `ACCOUNT_NAME`
("Account Name"), `FULL_NAME` ("Opportunity Owner"), `AMOUNT`, `OPPORTUNITY_NAME`,
`STAGE_NAME`, `CLOSE_DATE` are the `Opportunity` report type's `detailColumnInfo`.
Custom Opportunity fields resolve as `Opportunity.<Field>__c` (live house proof:
`Hoeh_Risk_Chancen` columns `Opportunity.Inactive_Days__c`, `Opportunity.Risk_Reason__c`).

**`timeFrameFilter` house caution (SCRUM-449 comment in the file):** deploying *without*
the element does not clear an existing one. Set it explicitly with a custom span that
covers every record (`INTERVAL_CUSTOM`, e.g. 2000-01-01 … 2099-12-31) on a date column
that exists in the type (`CLOSE_DATE`), and say so in the PR.

The two ListViews (`Offers_Expire_14D`, `Offers_Already_Expired`) use the house tokens of
`Follow_up_Monitoring` (`OPPORTUNITY.NAME`, `OPPORTUNITY.AMOUNT`, `OPPORTUNITY.STAGE_NAME`,
custom fields bare) — a possible owner column must be deploy-validated (cross-object
tokens are only answerable by deploy-validate, SCRUM-432); if refused, drop that column
from the ListView, the Report already carries `FULL_NAME`.

Org steps for these ACs (not CI-gated, must be read back): Report **sharing** ("All
users may open") is not in the source (verified in SCRUM-449/§4 of the FLS skill) —
it is an App-Builder/Report-Settings step for @devops-agent, with a read-back.

## Governor-limit and blast-radius notes

* No SOQL, no loop, no scheduler: everything derived is recomputed at read; AC11
  ("nothing automatic") is structurally guaranteed — no email, no task, no object, no
  auto-renewal, no nightly job.
* New ValidationRule on a **standard** object reddens every Apex test class that can
  SAVE an Opportunity in the blocked state (measured house finding, SCRUM-442). Count
  **by result state**, not by token: `Offer_Won_With_Expired_Offer` needs an *expired
  offer*, which needs the new fields, which no existing test class fills → expected
  blast radius of the new rules on the existing suite is **zero**. The Tester must
  still prove it once by a broad run, not assume it.
* Under Resolution B the guard must be a single bulkified handler over the records being
  saved, and the ownership test must sit **inside** the "the two dates actually changed"
  branch — an unconditional guard is what broke unrelated saves in SCRUM-456
  (`ContactLeftGuardTrigger` failing inserts for users without the read right).
* Test-Org allows only **one broad Apex run at a time** (house rule, SCRUM-394):
  deploy with `--test-level RunSpecifiedTests --tests <SCRUM467 classes>`; the full
  suite belongs to CI.

## Test artefacts required at the PR gate

House pair (shapes `SCRUM382CustomerSinceDaysTest` / `...FlsTest`,
`SCRUM451WartungsvertragTest` / `...FlsTest` / `SCRUM451TesterFlsNegativeTest`),
plus an E2E spec for the two overviews:

* `force-app/main/default/classes/SCRUM467OfferValidityTest.cls` — AC1–AC8
  (fixtures: end = today+45, today+14, today, today-1, blank end with sent date, no
  offer at all; assert `Offer_Status__c` wording, `Offer_Days_Left__c`, the VR throw on
  `Closed Won` with expired offer, no throw on `Closed Lost`, nothing changed on a
  historical closed record).
* `force-app/main/default/classes/SCRUM467OfferFlsTest.cls` — AC12/AC13 **inside
  `System.runAs()`** on a PS-holding and a non-holding user; the negative side is the
  mandatory negative-access test (house rule: no Done without it). Mixed-DML caution
  (SCRUM-438/442): the FLS-negative proof and the business-DML proof need **separate
  transactions**.
* `tests/e2e/SCRUM-467_offer-verfalluebersicht.spec.ts` — AC9/AC10 in the Lightning UI:
  frontdoor.jsp session only, no `networkidle`, and assert the header's
  `Select N items` count, never the rendered row count (Lightning renders only the first
  page, house finding SCRUM-449 PR #172).
* Playwright is not an Apex substitute: "verified live against the org, read-back
  confirmed" is evidence, not a test (approval rule, SCRUM-359).

## Counts that must be measured, not guessed

Measured by the Architect in **Test-Org** on 2026-11-21 (§10):
76 open Opportunities, 63 closed. **0 records carry offer data** — the fields do not
exist yet. Therefore, before any acceptance:

* (a) open Opportunities without offer data: **76** today → drops to 76 minus the fixtures
  the Tester seeds;
* (b) expiring within the next 14 days: **0** today;
* (c) already expired: **0** today.

(b) and (c) are **zero-record criteria in the untouched org** → they are *untested*, not
green. The Tester must seed a non-zero fixture count per state and report the counts; the
PO gate re-counts in the org that is being validated. A coverage row whose Observed
column reads 0 is not a PASS (house rule, SCRUM-398).

## Org-Setup steps (non-source, must be read back)

1. Assign `SCRUM467_Offer_Dates` (and under Resolution B `SCRUM467_Offer_Teamlead`) —
   read-back: `SELECT Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment
   WHERE PermissionSet.Name = 'SCRUM467_Offer_Dates'`.
2. Report sharing "All users may open" for both new Reports; read-back: open the Report
   as the second user.
3. Layout/App-Builder placement of the new record-page section in the Lightning page
   (repo tracks the Classic `Opportunity-Opportunity Layout` only — house finding, the
   Lightning page lives in the Org). Read-back: screenshot of the record page showing
   `Offer_Status__c`.

## 11. Verified shapes — check-only deploy validation against Test-Org (2026-11-21)

The whole artefact set was submitted as `sf project deploy validate -o Test-Org
--source-dir force-app --test-level RunRelevantTests --async --json` and polled with
`sf project deploy report`. **Final op `0AfWU00000dIgjt0AC`: status Succeeded, 13/13
components, 0 errors, `checkOnly: true`.** Read-back `sf sobject describe --sobject
Opportunity --json --target-org Test-Org | grep -c 'Offer_'` → **0** — the org is
unchanged, the Architect deployed nothing (check-only creates no components).

Earlier ops in the same session and what each one taught (the fixes, not guesses):

| op | verdict | finding |
|---|---|---|
| `0AfWU00000dIf330AC` | cancelled after the component phase (7 fields + PS: 8 OK / 0 failed) | Date formula field with `Offer_Sent_On__c + 30` is accepted; the op had to be cancelled because `--test-level RunLocalTests` queued 506 org tests and had already run 480 — the 24 h test budget of Test-Org |
| `0AfWU00000dIfkb0AC` | Failed 9 OK / 3 failed | a leading XML comment on a `.validationRule-meta.xml` file breaks the CLI conversion ("Invalid XML tags or unable to find matching parent xml file") — house VR files carry no comment; reports do carry comments and are fine |
| same op | "Incorrect number of parameters for function 'ISCHANGED()'. Expected 1, received 0" | `ISCHANGED()` takes a field in a validation rule — use `ISCHANGED(StageName)` |
| same op | "You can't include groupings in the selected columns list: 00NWU00002GNBa6" | the grouping field must NOT be repeated in `<columns>` (house caution in `Kunde_ohne_Kontaktperson`) |
| `0AfWU00000dIfsf0AC` | Failed 10 OK / 2 failed | VR `description` and Report `description` are limited to 255 characters |
| `0AfWU00000dIfvt0AC` | Failed 11 OK / 1 failed | `PREVIOUS(StageName)` rejected: "Field StageName is a picklist field. Picklist fields are only supported in certain functions" → the already-closed change-guard cannot read the previous stage; it uses `NOT(ISCHANGED(StageName))` + `ISCHANGED(<date>)` instead |
| `0AfWU00000dIfxV0AS` | **Succeeded 12/12** | final field/PS/VR/report set |
| `0AfWU00000dIfJC0A0` | **Succeeded 12/12** | 4-branch expiry formula (only one date filled still yields an expiry) |
| `0AfWU00000dIgNJ0A0` | Failed 12/13 | Layout: "Element layoutSections is duplicated at this location" — the new section had to be inserted *between* existing sections, not after the last one |
| `0AfWU00000dIgjt0AC` | **Succeeded 13/13, 0 errors** | fields + PS + 2 VRs + 2 Reports + Layout all accepted together |

Component names the deploy accepted (verbatim from the report):
`Opportunity.Offer_Days_Left__c`, `Opportunity.Offer_Expired__c`,
`Opportunity.Offer_Expires_On__c`, `Opportunity.Offer_Expiring_14D__c`,
`Opportunity.Offer_Sent_On__c`, `Opportunity.Offer_Status__c`,
`Opportunity.Offer_Valid_Until__c`, `Opportunity.Offer_Dates_Kept_When_Closed`,
`Opportunity.Offer_Won_With_Expired_Offer`, `Sales/SCRUM467_Offer_Expired_Renewals`,
`Sales/SCRUM467_Offer_Renewals_Due_14D`, `Opportunity-Opportunity Layout`,
`SCRUM467_Offer_Dates`.

`docs/SCRUM-467-shapes/` holds exactly these files (same relative layout as `force-app/`).
The Developer copies them to `force-app/main/default/…` and deploy-validates again; the
Layout file there is the master layout **plus** the new "Offer validity" section — it must
be diffed against the org's current layout before deploy (house rule: org-owned metadata is
retrieved, not rewritten).

## Verification log (Architect, Test-Org, 2026-11-21)

* `sf api request rest "/services/data/"` → latest API `68.0`.
* `sf sobject describe --sobject Opportunity --json` → 81 fields; `OwnerId` ("Owner ID",
  reference) present; 39 custom fields, **none** starting with `Offer`.
* `sf api request rest "/services/data/v68.0/analytics/reportTypes/Opportunity"` →
  `reportExtendedMetadata.detailColumnInfo`: `ACCOUNT_NAME`, `FULL_NAME` (label
  "Opportunity Owner"), `AMOUNT`, `OPPORTUNITY_NAME`, `STAGE_NAME`, `CLOSE_DATE`, …
  `aggregateColumnInfo.RowCount` ("Record Count").
* `sf data query --query "SELECT Id, Name FROM Profile" --use-tooling-api` → 41 records,
  all standard profile names; **no** "Account Manager", **no** "Sales Team Lead".
* `sf data query --query "SELECT Id, Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment …" --use-tooling-api` →
  12 assignments for the six SCRUM-445/451/459 PSs: only two users
  ("Meerwais Osmani", "devops-agent"), each holding **every** PS of the pairs → the org
  has no second user population that a role hierarchy could separate.
* `sf data query --query "SELECT COUNT(Name) FROM Opportunity WHERE IsClosed=false"` → 76;
  `IsClosed=true` → 63.
* Repo survey `origin/master @ 31da29f`: `git grep PREVIOUS` → 0 hits; no Date-typed
  formula field in any `*.field-meta.xml`; house VRs/reports/listViews as cited.

**Not verifiable by the Architect** (no org write access, and the Architect deploys
nowhere): the two formula shapes of §3a and `PREVIOUS()` in §5c are stated as *to be
deploy-validated by the Developer*, measured as unproven in the house, not asserted as
working.

## Open points (non-blocking once §1 is answered)

* [ ] PO: Resolution A or B (§1) — blocking, owner @po-agent.
* [ ] Developer: deploy-validate the Date-formula shape and `PREVIOUS()` (§3a, §5c);
  report the result in the PR description.
* [ ] @tester-agent: seed non-zero fixtures for (b) and (c) and count them; the org
  currently has 0 offer records.
* [ ] @devops-agent: the three Org steps above with read-backs; never merge on Report
  sharing alone.
