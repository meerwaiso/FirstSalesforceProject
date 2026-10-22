# SCRUM-453 — Contact „has left the company“ — Architecture-Design (Architect-Agent)

Surveyed: `origin/master` @ `3d65b136508315912c5fa0212c396782bee5cc9b` (git fetch 2026-10-22).
Org facts read from **Test-Org** with `sf` on 2026-10-22 (probes listed in §11).
This file is the authoritative build spec. Jira comments mangle API names — copy names from here, never from the ticket.

## 1. Ziel

Mark a Contact as „has left the customer's company“ plus the date, keep the record and its whole history, make the mark visible on the Contact, on the Case and in one Account overview, let only team leads undo it, and never touch the newsletter consent.

## 2. ADR — Apex vs. Flow vs. declarative

**No Flow.** No Salesforce Flow exists in the repo (the only `flows/` hits on `origin/master` are `.github/workflows/`). Flows have repeatedly failed to deploy here; nothing in this story is declarative-only anyway (a transition-dependent restriction cannot be a Flow).

| # | Decision | Rationale |
|---|---|---|
| ADR-1 | Mark = **editable Checkbox + editable Date**, not a formula | AC-2 requires correcting the date later; a formula field is read-only. House shape: SCRUM-451 Date fields (`Account.Satisfaction_Fenster_Start__c`). |
| ADR-2 | **Undo restriction = Apex guard**, not FLS | FLS is per field, not per transition. Setting and clearing edit the *same* field, so FLS cannot refuse only the clearing direction. SCRUM-445 gated a whole field by FLS (`SCRUM445_Discount_Manager`) — that shape does not fit here. |
| ADR-3 | **Team lead = holder of a dedicated Permission Set**, not a role name | Test-Org has 18 roles (standard sample hierarchy, read 2026-10-22). The house already restricts by Permission Set, never by role: `SCRUM428_Teamleitung`, `SCRUM431_Wartungsvertrag_Teamleitung`, `SCRUM451_Wartungsvertrag_Dates_Teamleitung`. SCRUM-445 measured the role hierarchy as unusable for actor resolution. |
| ADR-4 | **Account aggregates = Apex full-recompute** (SCRUM-416 handler pattern), not declarative Rollup | Zero `Rollup`-type fields in the repo. SCRUM-416 chose a handler + bulk recompute (`OpenOpportunityRollupHandler`) for exactly this shape: idempotent, drift-free, heals re-parenting, testable in CI. ⚠️ see F-1. |
| ADR-5 | **Case visibility = Text formula on Case** referencing the Contact lookup | House precedent `Case.Wartungsvertrag_Anzeige__c` (SCRUM-431/451) references the Account lookup and is deployed. ⚠️ No deployed Case formula references a *Contact* lookup in this org — unverified, first deploy gate. Fallback: system-write a read-only Text field from the guard trigger (SCRUM-436-proven route). |
| ADR-6 | **No deactivation, no record-state flags** | PO: the contact must stay in the system; the mark is data, not state. |
| ADR-7 | **Nothing automatic beyond the mark itself**: no `Mail`/`EmailMessage`/`Task`/`SetStatus`/FeedItem call anywhere in the new code | AC-9. Contrast SCRUM-445, which deliberately posts a FeedItem — here that is forbidden. |

## 3. Data model (before implementation)

| Field (API name) | Type | Shape | Formula | Editable by |
|---|---|---|---|---|
| `Contact.Has_Left_Company__c` | Checkbox | `required=false unique=false externalId=false trackTrending=false defaultValue=false` | — | Set-PS (Sales/Service), Undo-PS (team leads) |
| `Contact.Left_Company_Date__c` | Date | `required=false unique=false externalId=false trackTrending=false` | — | Set-PS, Undo-PS |
| `Contact.Contact_Status_Anzeige__c` | Text (formula) | `required=false unique=false formulaTreatBlanksAs=BlankAsZero` — **NO `<length>`** | `IF(Has_Left_Company__c, "Austritt – not there any more", "Active")` | nobody (formula) |
| `Account.Contacts_Without_Mark__c` | Number | `precision=6 scale=0 required=false unique=false defaultValue=0 trackTrending=false` | — | nobody (system-maintained) |
| `Account.Contacts_Left_Count__c` | Number | same as above, `defaultValue=0` | — | nobody (system-maintained) |
| `Account.Last_Contact_Left_Date__c` | Date | `required=false unique=false externalId=false trackTrending=false` | — | nobody (system-maintained) |
| `Case.Contact_Left_Anzeige__c` | Text (formula) | as above, **NO `<length>`** | `IF(Contact.Has_Left_Company__c, "Austritt – not there any more (" & TEXT(Contact.Left_Company_Date__c) & ")", "")` | nobody (formula) |

Consistency rule (SCRUM-437 pitfall): the mark is **row-level** (one Checkbox per Contact). The Account fields are **counts over the row set**. They must not be read as one shared string; the Tester asserts both against the same fixtures.

## 4. Components

1. **Contact fields** — `force-app/main/default/objects/Contact/fields/{Has_Left_Company__c,Left_Company_Date__c,Contact_Status_Anzeige__c}.field-meta.xml` — NEW
2. **Account aggregate fields** — `force-app/main/default/objects/Account/fields/{Contacts_Without_Mark__c,Contacts_Left_Count__c,Last_Contact_Left_Date__c}.field-meta.xml` — NEW
3. **Case indicator** — `force-app/main/default/objects/Case/fields/Contact_Left_Anzeige__c.field-meta.xml` — NEW
4. **Guard + rollup handler** — `force-app/main/default/classes/SCRUM453ContactLeftHandler.cls` — NEW (`public without sharing`, apiVersion like the other handlers)
5. **Trigger** — `force-app/main/default/triggers/ContactLeftGuardTrigger.trigger` (+ meta) — NEW; before-save, insert/update only, calls the handler for (a) undo check, (b) date default, (c) Account recompute
6. **Contact record page** — `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml` — CHANGED (new section: mark, date, status display)
7. **Case record page** — `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` — CHANGED (the indicator in the top section, visible without opening the Contact)
8. **Existing Contact list views** — `objects/Contact/listViews/{Kritische_Kontakte,Letzter_Real_Kontakt,Letztes_Anliegen}.listView-meta.xml` — CHANGED (add `Contact.Contact_Status_Anzeige__c` as a column, so a marked contact stands out in every list)
9. **Overview „customer without a contact person“** — `force-app/main/default/reports/Sales/Kunde_ohne_Kontaktperson.report-meta.xml` — NEW (`reportType=AccountList`, `scope=organization`)
10. **Permission Sets (3)** — `force-app/main/default/permissionsets/SCRUM453_ContactLeft_{Read,Set,Undo}.permissionset-meta.xml` — NEW
11. **Manifest** — `manifest/scr453-phase1-fields.xml`, `manifest/scr453-phase2-referencing.xml` — NEW (house phase split: fields first, then everything referencing them)

## 5. Artefacts (exact XML — the repo files are authoritative)

Checkbox (house shape `Lead.Is_Due__c`):

```xml
<fullName>Has_Left_Company__c</fullName>
<label>Austritt – has left the company</label>
<type>Checkbox</type><defaultValue>false</defaultValue>
<required>false</required><unique>false</unique><externalId>false</externalId><trackTrending>false</trackTrending>
```

Date (house shape SCRUM-451 `Wartungsvertrag_Start__c`):

```xml
<fullName>Left_Company_Date__c</fullName>
<label>Austritt am</label>
<type>Date</type><required>false</required><unique>false</unique><externalId>false</externalId><trackTrending>false</trackTrending>
```

Text formula (house shape `Case.Wartungsvertrag_Anzeige__c`; `&` and `<`/`>` must stay XML-escaped):

```xml
<fullName>Contact_Status_Anzeige__c</fullName>
<formula>IF(Has_Left_Company__c, &quot;Austritt – not there any more&quot;, &quot;Active&quot;)</formula>
<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs><required>false</required><type>Text</type><unique>false</unique>
```

Report (house shape `Morgen_UEbersicht_Vertragskunden` for the filter block, `Betreuungslast_nach_Firma` for grouping/scope). Column tokens verified against the Analytics API for `AccountList` on 2026-10-22: `ACCOUNT.NAME`, `USERS.NAME` and the three `Account.*__c` fields are all valid columns for that report type.

```xml
<columns><field>ACCOUNT.NAME</field></columns>
<columns><field>USERS.NAME</field></columns>
<columns><field>Account.Last_Contact_Left_Date__c</field></columns>
<columns><field>Account.Contacts_Left_Count__c</field></columns>
<columns><field>Account.Contacts_Without_Mark__c</field></columns>
<filter>
  <criteriaItems><column>Account.Contacts_Without_Mark__c</column><columnToColumn>false</columnToColumn><isUnlocked>false</isUnlocked><operator>equals</operator><value>0</value></criteriaItems>
  <criteriaItems><column>Account.Contacts_Left_Count__c</column><columnToColumn>false</columnToColumn><isUnlocked>false</isUnlocked><operator>greaterThan</operator><value>0</value></criteriaItems>
</filter>
<format>Tabular</format>
<name>Kunde_ohne_Kontaktperson</name>
<reportType>AccountList</reportType>
<scope>organization</scope>
<sortColumn>Account.Last_Contact_Left_Date__c</sortColumn>
<sortOrder>Asc</sortOrder>
```

`Contacts_Left_Count__c > 0` is what implements the PO decision „customers that never had a contact person are excluded“ — no extra field needed.

## 6. FLS — Permission Sets (never Profile edits)

House read/write split: SCRUM-388 (`SCRUM388_AccountReactivation` read + `SCRUM388_AccountReactivationWrite`).

| PS | Grants | Who |
|---|---|---|
| `SCRUM453_ContactLeft_Read` | `readable=true, editable=false` on all 3 Contact fields **and** the 3 Account fields | Sales, Service, Marketing (all internal readers) |
| `SCRUM453_ContactLeft_Set` | `editable=true, readable=true` on mark + date | Sales, Service |
| `SCRUM453_ContactLeft_Undo` | `editable=true, readable=true` on mark + date | team leads only |

Every new/changed field gets an explicit `fieldPermissions` entry — FLS is never inherited from object-level CRUD.

**Assignment is half the work.** Deploying a PS grants nothing. The Developer-Handoff comment must carry the read-back: the `PermissionSetAssignment` holder list for all three PSs, plus one field read through a real session. Verified route (probe 2026-10-22, Test-Org): `UserInfo.getUserId()` compiles and runs; `[SELECT Id, Name FROM PermissionSet WHERE Name = 'SCRUM428_Teamleitung']` and `[SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :me AND PermissionSetId = :psId]` both run (PS found, 2 holders).

## 7. Sharing model

No `sharingRules` artefact exists on `origin/master` → sharing is OWD-only, i.e. org config, not source. The overview reads **only Account fields**, so an account manager needs Account read access; no OWD change is required for the overview itself. Contact detail stays behind Contact access. No sharing change is designed; the OWD values of Account/Contact are read back as Org-Setup evidence (§9).

## 8. Governor limits

- Trigger: **no SOQL in a loop.** Per batch: 1 `SELECT` over the Contacts of the touched Accounts (for the recompute) + 1 `update` of the Accounts. Bound measured in Test-Org: max 4 Contacts per Account, 139 Contacts over 74 Accounts.
- Undo check: 1 `PermissionSet` query + 1 `PermissionSetAssignment` query per batch, only when at least one clearing is present.
- Recompute only for Accounts whose set actually changed (SCRUM-416 „write only on actual change“); re-parenting recomputes old **and** new Account.
- Account update fires no Contact trigger → no recursion.

## 9. Org-Setup steps (not CI-gated; read-back is the evidence)

| # | Step | Owner | Mandatory read-back |
|---|---|---|---|
| S1 | Assign the 3 Permission Sets (CLI target-org user + human test account; Undo also to the team-lead users) | DevOps | `PermissionSetAssignment` holder count per PS |
| S2 | Report placement in the Sales folder + sharing of the report | DevOps | report opens as an account manager |
| S3 | Lightning record-page visibility of the new section (repo tracks Classic layouts only) | DevOps | section visible in Lightning |
| S4 | OWD of Account/Contact unchanged (no sharing change designed) | DevOps | read current OWD, state it |

## 10. Technical acceptance criteria (AC → artefact → test)

| AC | Artefact | Test artefact |
|---|---|---|
| AC-1 marking + record intact | Checkbox + Date, Set-PS | `SCRUM453ContactLeftTest` (TA-1) |
| AC-2 date defaults to the day of marking, correctable later | handler default `date() ` when mark set and date blank; Date editable | TA-2 + TA-3 |
| AC-3 history reachable | no deactivation, no lookup change | TA-4 (Cases/Opportunities/Activities of a marked Contact still open) |
| AC-4 stands out in list + record page | `Contact_Status_Anzeige__c` + layout section + list-view columns | E2E spec |
| AC-5 newsletter recipient excluded, consent untouched | Read-PS for Marketing; handler never writes consent | TA-5 asserts `NewsletterConsent__c`/`ConsentDate__c` unchanged after marking |
| AC-6 undo refused for non-leads, works for leads | guard trigger + `SCRUM453_ContactLeft_Undo` | `SCRUM453ContactLeftFlsTest` (negative: `runAs` user without Undo-PS → save refused; positive: with Undo-PS → mark cleared) |
| AC-7 visible on the Case | `Case.Contact_Left_Anzeige__c` + Case layout | E2E spec (case page, without opening the Contact) |
| AC-8 overview exact + oldest first | report filter + `sortOrder=Asc` | report assertion + **fixtures, count > 0** |
| AC-9 nothing automatic | ADR-7 | TA-6 asserts no `Mail`/`Task`/`FeedItem`/`SetStatus` side effect and no other record's business field changed |

Test pair house shapes: `SCRUM359NewsletterConsentFlsTest` (FLS negative) and `SCRUM416OpenOpportunityRollupTest` (bulk recompute, 200 records, one recompute call). E2E house shape: `tests/e2e/SCRUM-359_newsletter-consent.spec.ts` (frontdoor.jsp auth only).

## 11. ⚠️ Findings

- **F-1 (AC-8 vs. AC-9 tension).** AC-8 needs a per-customer aggregate; the only way to filter „exactly those customers“ is a value on the Account. Those Account fields therefore *do* change by themselves when a Contact is marked. AC-9 literally says „no field on other records changes by itself“. Reading: AC-9 forbids emails, tasks, reminders and business writes; read-only derived aggregates are accepted. **Needs PO confirmation.** A report-only alternative cannot express „exactly those“ (no filter on an aggregate), so it fails AC-8.
- **F-2 (newsletter).** No send and no recipient list exists in the repo or the org. `Campaign`, `CampaignMember`, `EmailMessage` are standard objects present in every org — their existence proves nothing about a send. AC-5 is enforceable here only at the recipient selection; the rest belongs to the marketing side.
- **F-3 (Lightning).** Repo tracks Classic `.layout-meta.xml` only. Layout changes cover Classic; Lightning visibility is FLS (repo) + App Builder placement (org step S3). Tester must check both UIs.
- **F-4 (team lead).** „Team lead“ = holder of `SCRUM453_ContactLeft_Undo`. Today the analogous `SCRUM428_Teamleitung` has exactly 2 holders (`devops-agent@cline.test`, `meerwais.osmani@resourceful-bear-6f1u4j.com`) — read 2026-10-22. Role names in Test-Org (18, read 2026-10-22): CEO; CFO, COO, SVP Sales & Marketing, SVP Customer Service & Support, SVP Human Resources; VP North American Sales, VP International Sales, VP Marketing; Director Channel Sales, Director Direct Sales; Eastern Sales Team, Western Sales Team, Channel Sales Team, Marketing Team; SVP Customer Service & Support → Customer Support International / North America, Installation & Repair Services. The house does not use these for restrictions.
- **F-5 (`$User`).** `$User` and `$Profile` do **not** compile in `sf apex run` (probes 2026-10-22). Use `UserInfo.getUserId()` — verified compiling and returning the running user's Id.
- **F-6 (unverified shape).** No deployed Case formula in Test-Org references a Contact lookup (Case describe 2026-10-22: 5 formula fields, none referencing Contact). `Case.Contact_Left_Anzeige__c` is the one artefact whose cross-object reference is unverified; the first deploy validates it. Fallback per ADR-5 if rejected: system-write a read-only Text field from the guard trigger.
- **F-7 (coverage of the overview).** 649 Contacts, 195 Accounts; only **139 Contacts carry an AccountId** (74 Accounts have ≥1 Contact, distribution 11×1, 62×2, 1×4). Contacts without a customer can never appear in an Account-level overview — state it, do not silently lose them.
- **F-8 (fixtures).** 0 Contacts are marked today, so AC-8 matches 0 records until fixtures exist. A criterion matching zero records is not met.

## 12. Open points (non-blocking, owner named)

- [ ] F-1 wording — @po-agent: confirm that read-only derived Account aggregates satisfy AC-9.
- [ ] F-2 newsletter send — @po-agent / @user: where is the newsletter sent from?
- [ ] A future-dated „left“ value: refuse or accept? Not designed as a rule (would be inventing a threshold).
- [ ] Which users get `SCRUM453_ContactLeft_Undo` — proposed: the same 2 users that hold `SCRUM428_Teamleitung`.
- [ ] S1–S4 org steps — @devops-agent; E2E scope for both UIs — @tester-agent.

## 13. Handoff duties for the Developer

Branch `feature/scr453-kontakt-austritt` off `origin/master`. Deploy order per manifest phase split (fields → referencing). Handoff comment must carry: PR link, branch, Test-Org deploy confirmation, the `PermissionSetAssignment` read-back for all three PSs, one field read through a real session, and the fixture counts for AC-8 (non-zero).
