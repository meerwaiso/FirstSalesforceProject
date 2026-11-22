# SCRUM-470 — Architect-Design: Favorit Kontakt-Way on `Contact`

Author: architect-agent · Branch: `feature/SCRUM-470-preferred-contact` · surveyed `origin/master` @ `48ee748ca9310642228c1409f54eb9800dbc0d9a` (2026-11-22) · Org re-Read: 2026-11-22 (Test-Org `00DWU00000oibVJ2AY`, Prod-Org `00Dg500000DkTtzEAF`)

This file is the authoritative build spec. The exact API names and XML live here — never copy a name out of the Jira comment (Jira's converter mangles `__c` and XML tags; house finding SCRUM-375).

## Ziel

One purely informational, hand-set picklist on the standard object `Contact` — by phone / by email / by letter, empty = "nobody asked yet" — displayed in the contact-information area of the `Contact` detail page right beside the phone and email fields, readable and changeable by everyone who holds one Read+Edit Permission Set, with **zero automation** (no Flow, no trigger, no validation rule, no formula, no reminder, no email).

## Components (paths in the branch)

| # | Component | Path | Kind |
|---|---|---|---|
| 1 | New field | `force-app/main/default/objects/Contact/fields/Preferred_Contact_Method__c.field-meta.xml` | new |
| 2 | Layout delta | `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml` | change of the file that is on `origin/master` |
| 3 | Permission Set (Read + Edit) | `force-app/main/default/permissionsets/SCRUM470_ContactContactWay.permissionset-meta.xml` | new |
| 4 | Apex test pair (PR gate) | `force-app/main/default/classes/SCRUM470PreferredContactMethodTest.cls` (+ `-meta.xml`), `force-app/main/default/classes/SCRUM470PreferredContactMethodFlsTest.cls` (+ `-meta.xml`) | new |
| 5 | Playwright E2E | `tests/e2e/SCRUM-470-preferred-contact-way.spec.ts` | new |
| 6 | Deploy/test run configs | `manifest/scr470-phase1-fields.xml` (the field) · `manifest/scr470-phase2-referencing.xml` (PS + layout) · `manifest/scr470-phase3-apextests.xml` (the two test classes) — house shapes `manifest/scr382-phase1-fields.xml` / `scr382-phase2-referencing.xml` / `scr467-phase4-apextests.xml`, all `version 67.0` | new |
| 7 | Only if the FLS test needs it | `force-app/main/default/permissionsets/SCRUM470_TestObjectAccess.permissionset-meta.xml` — object-level `Contact` access for the temporary test user | conditional, see ADR-9 |

Nothing else. No `flows/`, no `triggers/`, no `validationRules/`, no `listViews/`, no `reports/`.

## Interface / Data Structure

Field (declarative, house shape measured in `objects/Contact/fields/Rueckruf_Zeitfenster__c.field-meta.xml` at `48ee748`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Preferred_Contact_Method__c</fullName>
    <description>How this customer wants to be reached (SCRUM-470): phone / email / letter. Optional — leer = nobody asked yet. Hand-set only, nothing automatic.</description>
    <externalId>false</externalId>
    <label>Favorit Kontaktmethod</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Phone</fullName>
                <default>false</default>
                <label>telefon</label>
            </value>
            <value>
                <fullName>Email</fullName>
                <default>false</default>
                <label>email</label>
            </value>
            <value>
                <fullName>Letter</fullName>
                <default>false</default>
                <label>Letter</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

Notes on the shape (all house-verified, no invented metadata):
- `<required>false</required>` + no `<defaultValue>` = empty is a valid state and stays empty for every existing contact (AC1, PO "no forced fill").
- No `<restricted>` element: the house picklists on standard objects in this repo carry none (`Open_Cases_Rating__c`, `Rueckruf_Zeitfenster__c` at `48ee748`), and a `valueSet` is enough to express the three choices. Do not add an element the repo has never deployed.
- No `<length>`: `length` belongs to Text, not Picklist (house finding SCRUM-394).
- Dev names `Phone` / `Email` / `Letter`, German labels `telefon` / `email` / `Letter`. Display-only — @user may rename the labels without touching the design (see Offene Punkte).

Layout delta (AC2 "next to the phone number and the email address"):
- File: `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml` — the version **on `origin/master` @ `48ee748`**, plus exactly one `layoutItems` element. Never retrieve the org layout into the branch: Test-Org-only section fields redden the Prod-Org Drift Gate (house finding SCRUM-468/469).
- Insertion point: the **second** `layoutColumns` of the first `layoutSections` (`<label>Contact Information</label>`), **immediately after** the item `<field>Email</field>`. That column block already holds `Phone`, `Firmen_Telefonnummer__c`, `HomePhone`, `MobilePhone`, `OtherPhone`, `Fax`, `Email` — i.e. the field renders inside the contact-information block, directly under the phone/email group, in the first screenful (AC2 "without horizontal scrolling"; the block is `TwoColumnsTopToBottom`, so nothing scrolls sideways at all).

```xml
<layoutItems>
    <behavior>Edit</behavior>
    <field>Preferred_Contact_Method__c</field>
</layoutItems>
```

`behavior=Edit` (not `Readonly`) — required so the Lightning/Classic "Details" tab offers the value for change and clear (AC3/AC4/AC5).

Permission Set (house shape measured in `permissionsets/SCRUM453_ContactLeft_Set.permissionset-meta.xml` at `48ee748`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Contact.Preferred_Contact_Method__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM470_ContactContactWay</label>
    <description>SCRUM-470 Read+Edit FLS for the hand-set preference. Sales/Service users get it; users without it neither see nor set the value (AC6). No Create/Delete right needed: the field is empty at creation time.</description>
</PermissionSet>
```

Exactly **one** Permission Set (`editable=true`, `readable=true`). No `_Read`/`_Write` split, no `_System` PS: nothing writes the value automatically (AC7 hard scope limit), so there is no second context to grant. No Profile edit anywhere (house rule; SCRUM321/327/329 pattern).

## Architektur-Entscheidungen (ADR)

**ADR-1 — declarative config only, no Flow, no Apex logic.** The requirement is a value, a display slot and an access rule. Salesforce expresses all three declaratively (field metadata, layout metadata, Permission Set). Flow was explicitly rejected: it would add a schema-strict XML artefact with `apiVersion` drift and deployment/schema-validation failures this project has hit repeatedly, and it buys nothing here. Apex is used for **tests only** (the CI PR gate). ADR satisfies the AGENTS guardrail "No Flow-based implementation of non-trivial logic without an ADR justifying it" — we ship no Flow at all.

**ADR-2 — one Picklist, not three checkboxes, not Text + ValidationRule.** PO requires three *mutually exclusive* values plus empty, one field. Picklist gives mutual exclusion by construction; three checkboxes would need a validation rule to exclude combinations, and a `Text` field would need one to exclude free text. PO's scope limit forbids validation rules ("no checks that block anything") — so Picklist is the only shape that satisfies mutual exclusion **without** a blocking rule. (This is the reason no `validationRules/` file may appear in the PR: a validation rule on `Contact` would also redden every test class that can save a `Contact` in the blocked state — house finding SCRUM-448.)

**ADR-3 — naming.** Dev name `Preferred_Contact_Method__c` (underscore style of the house: `Open_Cases_Rating__c`, `Last_Real_Contact_Date__c`). Collision check: no such field exists — measured below; the closest existing fields are `Rueckruf_Zeitfenster__c` (callback *window*, SCRUM-430) and `Firmen_Telefonnummer__c` (SCRUM-405); neither is a channel preference, so a new field is required and neither may be reused.

**ADR-4 — FLS = one Read+Edit PS; Create/Delete not granted.** Field-level access is Read/Edit only. AC1/AC3 need "saving a new Contact with the field empty must not fail": a field nobody writes at creation time grants nothing at creation, and the object-level Create right already in the org is untouched. AC5 "clearing back to empty must be allowed": `required=false` on a Picklist + no validation rule = blank is accepted for an Edit user. Nothing must be added that blocks it.

**ADR-5 — one PS serves both the visibility and the negative-access AC.** FLS governs the field itself; a user without the PS neither sees the value in the detail page nor sets it (AC6). The discriminator "in sales/service or not" is PS membership, exactly like `SCRUM428_ServiceTeam` / `SCRUM453_ContactLeft_Set` in this org. **This is not the SCRUM-467 trap**: there the two groups had to be separated *inside* Apex by a guard; here no guard exists at all, so assigning one PS to the sales/service users keeps the positive AC reachable and the negative AC provable. The negative proof must be a real probe (house pattern SCRUM382FlsTest: a temporary `User` on the `Standard User` profile without the PS + `System.runAs`), never an assumption. House evidence that this works in this org: SCRUM-382's comment states "a brand-new custom field is FLS-gated by default: a user WITHOUT the Permission Set cannot read it" and that class ran green here. **The Developer must re-prove it for THIS field with the negative probe class — do not inherit that conclusion.**

**ADR-6 — record/sharing access is untouched and must stay untouched.** No OWD change, no sharing rule, no `sharingRules/` file. Consequence to keep consistent: FLS governs the *field*, the sharing model governs the *record*. A sales/service user can only see the preference on records they can open at all; a non-owner whose record access is read-only sees the value (Read FLS + read access) but cannot save it (object-level write access, not this ticket). PO's question — "can a non-owner with read-only access still see the preference?" — answer: **yes for the field, subject to FLS, provided the record itself is reachable; the change rights come from object-level access plus this PS, and this ticket changes neither.** This is *not* provable in Apex: the design deliberately does not assert sharing in a test class (see ⚠️-3).

**ADR-7 — governor limits: none.** No SOQL, no loop, no formula, no trigger, no Flow element: a save touches one field. Bulkification N/A. The one real limit is the layout: adding one item to an existing section costs one page-render field, no section added — well inside limits.

**ADR-8 — no list view.** PO asked for the detail page only. The three `Contact` listViews on `origin/master` stay untouched; adding the column there would exceed scope and redden the drift gate unnecessarily.

**ADR-9 — the FLS test may need a `SCRUM470_TestObjectAccess` PS, and that is a decision, not a guess.** The negative/positive probes run as a temporary `User` on the `Standard User` profile. If that profile lacks object-level `Contact` access in this org, the class cannot insert/read a `Contact` at all and every FLS assertion would pass for the wrong reason — hence SCRUM-382's shape puts an **object-access precondition first** and fails loudly. House precedent for the fix: `SCRUM442_TestObjectAccess`, `SCRUM451_TestObjectAccess`, `SCRUM464_TestObjectAccess`, `SCRUM467_TestObjectAccess` (all on `origin/master`) each grant object-level access so the test user can touch the record. Not measured whether `Standard User` already has `Contact` access (no source/SOQL route found this design) → the Developer runs the precondition assert and adds the PS only if it reddens. This PS carries **no field rights**; it must not become a second grant of the preference field.

## Measured baseline (my own numbers, org read 2026-11-22)

| What | Number | Command |
|---|---|---|
| `Contact` records, Test-Org | **676** | `sf data query -o Test-Org --query "SELECT Id, LastName FROM Contact" --result-format csv --output-file …` → 677 CSV lines incl. header |
| owner split Test-Org | **656 devops-agent / 20 Meerwais Osmani** | `SELECT Id, Owner.Name, CreatedDate FROM Contact` |
| `Contact` records, Prod-Org | **20** (all owned by `OrgFarm EPIC`) | same query, `-o Prod-Org` |
| contacts already carrying a channel preference | **0 by construction** — the field does not exist yet | collision check below |
| existing custom fields named *contact/prefer* on `Contact` | **none** (no collision for `Preferred_Contact_Method__c`) | `sf api request rest "/services/data/v64.0/sobjects/Contact/describe" -o Test-Org` returned 0 custom-field entries, so the Tooling-API `Field` route was used: `SELECT … FROM Field WHERE Domain='Contact'` → `sObject type 'Field' is not supported` (measured, see ⚠️-1); collision check below |
| `Contact` layouts in Test-Org | **4**: `Contact Layout`, `Contact (Sales) Layout`, `Contact (Marketing) Layout`, `Contact (Support) Layout` | `sf data query -o Test-Org -t --query "SELECT Id, Name FROM Layout"` |
| `Contact` layouts tracked in the repo | **1** (`Contact-Contact Layout.layout-meta.xml`) | `git ls-tree -r origin/master` |
| FlexiPages in Test-Org | **9 components** (types not re-measured this design) | `sf data query -o Test-Org -t --query "SELECT Id FROM FlexiPage"` |
| Profiles in Test-Org | 8 incl. `Standard User`, `Read Only`, `Custom: Sales/Marketing/Support Profile` | `SELECT Id, Name FROM Profile --use-tooling-api` |
| Users in Test-Org | 8: `Meerwais Osmani`, `devops-agent`, `Integration User`, `Automated Process`, `Data.com Clean`, `Security User`, `Chatter Expert`, `Platform Integration User` | `SELECT Id, Name FROM User --use-tooling-api` |
| house PS assignment targets | prior PS carry exactly `devops-agent` **and** `Meerwais Osmani` | `SELECT Id,Assignee.Name,PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN ('SCRUM405_FirmenTelefonnummer','SCRUM453_ContactLeft_Set','SCRUM453_ContactLeft_Read','SCRUM428_ServiceTeam','SCRUM428_Teamleitung')` |

**For the Tester coverage table:** AC1 must be measured against a non-zero population — Test-Org gives 676 contacts, 676 without a preference. AC2/AC4/AC5 need contacts **with** a value, which do not exist yet → the Tester creates the fixtures and counts them; a row whose Observed column reads 0 is not `PASS` (AGENTS rule). Prod-Org: 20 contacts, 0 with a preference — at release the Prod read-back must show the 20 records unchanged and the new value count = whatever the PO's users set.

## Org-Setup read-backs (NOT Apex asserts)

Org configuration is a precondition, not a CI artefact (house rule SCRUM-424). Each needs a read-back in the handoff comment, not a `@isTest` assertion:

| # | Step | Owner | Read-back (must be quoted in the handoff) |
|---|---|---|---|
| S1 | Assign `SCRUM470_ContactContactWay` to the sales/service users — house target set: `devops-agent` **and** `Meerwais Osmani` | Developer (Test-Org) / DevOps (Prod) | `SELECT Id,Assignee.Name,PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM470_ContactContactWay'` — the AGENTS/FLS guardrail: deploying a PS grants nothing until it is assigned. A handoff comment without this read-back is incomplete. |
| S2 | Negative side: a user **without** the PS must not read the field | Developer | the FLS test class' negative probe result (temp `Standard User` profile user, `System.runAs`) — plus CI `scripts/fls-gate.py` |
| S3 | Which `Contact` layout is active for the profiles in use (`Contact Layout` vs `Contact (Sales) Layout`) | Tester / DevOps | read back Setup → the profile-assigned `Contact` layout must be the one carrying the field (see ⚠️-2). If a profile renders a `(Sales)`/`(Marketing)`/`(Support)` variant, AC2 fails there and the layout must also be added there — a source file, not an Org click. |
| S4 | `Contact` sharing model + record access for non-owners | DevOps (Prod) / Tester (Test) | Setup read-back quoted in the comment. Apex asserts must not stand in for it (see ⚠️-3). |

## Test artefacts (PR gate — not optional)

Declarative-field tickets ship the house pair + E2E (AGENTS "Test coverage is a PR gate, not a bonus"; shapes SCRUM382 / SCRUM378 / SCRUM-405):

1. `SCRUM470PreferredContactMethodTest.cls` — semantics: set Email → stored; phone → letter (old value gone, AC4); clear to blank saves (AC5); a save with the field empty on an existing contact saves (AC1); assert nothing else changed (AC7: compare before/after field sets, e.g. record count carrying a value).
2. `SCRUM470PreferredContactMethodFlsTest.cls` — house shape of `SCRUM382CustomerSinceDaysFlsTest.cls`: temp `User` on profile `Standard User` (house notes: `LanguageLocaleKey='en_US'` — `de_DE` rejected in this org; `TimeZoneSidKey='America/Los_Angeles'` — `UTC` rejected), **negative** first (no PS → not readable, not writable), object-level `Contact` access as precondition *before* the FLS asserts (otherwise the FLS asserts pass for the wrong reason), then assign the PS and prove **positive**. `System.runAs` mandatory — `scripts/fls-gate.py` reddens a test class that touches the new field without it.
3. `tests/e2e/SCRUM-470-preferred-contact-way.spec.ts` — frontdoor.jsp `globalSetup` + `storageState` only (no login page, no `sid` cookie), no `networkidle` on Lightning, probed locators only. Cover AC2: on the `Contact` record view (Details tab) the label and the value render inside the contact-information block next to Phone/Email. Fixture contacts must be read back via SOQL in the spec's header comment (house pattern SCRUM-405).
4. `manifest/scr470-phase3-apextests.xml` — the run config listing the two classes for `--test-level RunSpecifiedTests --tests …` (Developer deploys his own work only; the full suite belongs to CI, once).

Negative-AC6 note for the E2E: a second low-privilege browser session is impossible in this org (2/2 licences, both System Administrators — house finding quoted in SCRUM-405). AC6 therefore belongs to the Apex FLS class; the E2E must not fake it.

## ⚠️ Befund (repo + org analysis)

1. **`Field` is not a queryable sObject here.** `sf data query -t --query "SELECT ApiName, Type, Domain FROM Field WHERE Domain='Contact'"` → `sObject type 'Field' is not supported`. The collision check therefore stands on the two other measurements: `sobjects/Contact/describe` (0 custom fields returned) and the repo's 18 `Contact/fields/*.field-meta.xml` on `origin/master` @ `48ee748` — none is `Preferred_Contact_Method__c`. Residual risk: an org-only field invisible to both routes. The Developer's first deploy is the oracle; a rejected name is a name defect, not a broken pipeline.
2. **The org carries 4 `Contact` layouts, the repo tracks 1.** AC2 is expressed in the tracked `Contact Layout` only. House precedent that the tracked layout renders in Lightning: SCRUM-405's E2E read the custom field on the `Contact` Details view (measured 2026-09-10, "the profile-assigned Classic Contact Layout"). The FlexiPage count has moved since (8 → 9), so the Tester must re-measure whether any `Contact` RecordPage exists before claiming Lightning renders the layout — do not inherit SCRUM-405's conclusion.
3. **Sharing cannot be measured from source or SOQL.** `sf project retrieve start --metadata "SalesCloudSharingModel:Contact"` → `Missing metadata type definition in registry for id 'SalesCloudSharingModel'` (measured, and the registry link the CLI names). Consequence: no source artefact exists for the PO's sharing question; it is an org Setup setting. Any `@isTest` class that asserts "a non-owner cannot see the record" is a false oracle here — record access must be proven in the UI (E2E) or reported as an org read-back, never asserted in Apex. If the Setup read-back shows non-owner contacts are hidden, the PO's "everyone in sales and service may see it" is only satisfiable for records they can reach → report back to @po-agent, do not paper over it.
4. **No AutomationController / no trigger on `Contact` may be touched.** Nothing in this design needs one; the PR must add zero `triggers/` and zero `flows/` file (AC7 hard scope limit; the review checks exactly this).

## Offene Punkte (non-blocking — implementation may start)

- [ ] Field label `Favorit Kontaktmethod` and value labels `telefon` / `email` / `Letter` are display-only decisions. Owner: @user — changing them touches nothing else.
- [ ] Should the value also appear in the `Contact (Sales)` layout variant? Default: **no** (repo tracks one layout, SCRUM-405 precedent). Owner: @user / @po-agent. If yes → one more source file, same insertion, no design change (⚠️-2).
- [ ] Which users are "sales and service" for the PS assignment: house target set is `devops-agent` + `Meerwais Osmani`. Owner: @developer-agent (Test-Org) then @devops-agent (Prod). If a third user exists in Prod (`OrgFarm EPIC`), Prod needs it assigned too — S1 read-back per org.
- [ ] "by letter" = paper letter, one channel per contact: PO's two noted assumptions; nothing in the design contradicts them. Owner: @user to confirm.

## Developer handoff expectations

- Branch: `feature/SCRUM-470-preferred-contact` (this branch, cut from `origin/master` @ `48ee748`). Take a worktree on it — never switch the shared checkout.
- Deploy order (Test-Org): field → PS → layout, each validated check-only first (`deploy validate --async` + `deploy report`, never `RunLocalTests`: 24 h org budget). Then `PermissionSetAssignment` read-back (S1) before the handoff comment.
- PR: one PR for the ticket, `[DEV][SCRUM-470] …`, carrying the design doc (this file) plus the components above.
- Commit format `[AGENT][SCRUM-470] …`; stage explicit paths only (the shared tree holds other tickets' files — do not commit, do not delete them).
