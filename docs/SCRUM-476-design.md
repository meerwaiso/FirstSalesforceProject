# SCRUM-476 — Architecture-Design: Company Size carried from Lead to Account

Author: architect-agent · Branch: `feature/SCRUM-476-company-size` · Story: SCRUM-476

## Ziel

One new restricted-picklist field `Company_Size__c` on the standard object `Account`, filled
automatically **once** at the moment a lead becomes a customer (new customer: take the lead's
range; existing customer: only when blank), afterwards hand-maintained, visible next to
`Account.Name` — with exactly the four ranges of the lead field of SCRUM-472.

## Measured facts (each with the command that measured it, 2026-11-24)

| # | Fact | Command |
|---|---|---|
| M1 | `Account.Company_Size__c` does **not** exist in Test-Org | `scripts/fls-check.sh Account Company_Size__c Test-Org` → "1. Existenz NEIN — nicht in dieser Org deployt." |
| M2 | `Account` **does** carry the standard field `NumberOfEmployees` (label "Employees") | `sf sobject describe --sobject Account` → `"name": "NumberOfEmployees"` |
| M3 | Four picklist API values of the lead field, verbatim: `up_to_10` / `11_to_50` / `51_to_250` / `more_than_250`, labels "up to 10 employees" … "more than 250 employees" | `git show origin/master:force-app/main/default/objects/Lead/fields/Company_Size__c.field-meta.xml` |
| M4 | Only **one** Account-level trigger exists today: `AccountLockGuard on Account (before update)` — no Account insert/afterSave trigger | `git ls-tree -r origin/master --name-only \| grep triggers/` + read of the trigger file |
| M5 | House FLS pattern for an Account field = a **pair**: `SCRUM471_KeyAccount_Read` (readable, not editable) + `SCRUM471_KeyAccount_Set` (readable + editable), field-only, no object CRUD | `git show origin/master:.../SCRUM471_KeyAccount_{Read,Set}.permissionset-meta.xml` |
| M6 | House layout placement = item right after the name field, `behavior Edit`, with an XML comment naming the ticket | `git show origin/master:.../layouts/Lead-Lead Layout.layout-meta.xml` (SCRUM-472 item after `Company`) |
| M7 | House trigger shape: `<apiVersion>62.0</apiVersion>`, thin trigger file + separate `…Handler` class, `Trigger.isInsert` / `isUpdate` dispatch | `git show origin/master:.../triggers/LeadDuplicateGuard{.trigger,.trigger-meta.xml}` |
| M8 | Four Account layouts tracked in source: `Account Layout`, `Account (Sales) Layout`, `Account (Marketing) Layout`, `Account (Support) Layout` | `git ls-tree -r origin/master --name-only \| grep layouts/` |
| M9 | Survey basis: `origin/master` @ **93e7f0c** (`[TESTER][SCRUM-474] … (#195)`), after `git fetch origin` | `git log -1 --format='%h %s' origin/master` |

⚠️ M2 corrects the PO's statement "no size or employee field exists on Account": that was checked
against the **repo** (custom fields), not against the org's standard field list. `NumberOfEmployees`
is an exact-count `Integer`, not the four ranges, and is not hand-maintained as a band. The new
restricted picklist stays the right artefact (§ADR-3), but the Developer must **not** reuse or
populate `NumberOfEmployees`, and the Tester must not read "no employee field" as an AC.

## Components

1. **Field** — `force-app/main/default/objects/Account/fields/Company_Size__c.field-meta.xml`
   Copy of the SCRUM-472 file, object changed; the four **API values identical** (M3) so the carry
   is a plain assignment, not a mapping. `required=false`, no `defaultValue`, no `blank` marker
   (proven shape from SCRUM-472 — do not invent one).

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
       <fullName>Company_Size__c</fullName>
       <description>Employee-size band of the customer (SCRUM-476): hand-set; blank = not known yet. Carried once from the lead at conversion, never computed, never defaulted.</description>
       <externalId>false</externalId>
       <label>Company Size</label>
       <required>false</required>
       <trackTrending>false</trackTrending>
       <type>Picklist</type>
       <valueSet>
           <valueSetDefinition>
               <sorted>false</sorted>
               <value><fullName>up_to_10</fullName><default>false</default><label>up to 10 employees</label></value>
               <value><fullName>11_to_50</fullName><default>false</default><label>11 to 50 employees</label></value>
               <value><fullName>51_to_250</fullName><default>false</default><label>51 to 250 employees</label></value>
               <value><fullName>more_than_250</fullName><default>false</default><label>more than 250 employees</label></value>
           </valueSetDefinition>
       </valueSet>
   </CustomField>
   ```
   **The SCRUM-472 file is the authority for the third label** (`51_to_250` → "51 to 250 employees").
   Copy M3 verbatim; this comment is a spec, the repo file is the source of truth.

2. **Layout item** — `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`
   Insert into the **first** `layoutColumns` of the "Account Information" section, **directly after
   the `Name` item** ("close to the customer name"). `behavior = Edit` (set/change/clear by hand,
   AC 7/8), house comment naming the ticket. Edit the file already on `origin/master` in place —
   never commit a layout retrieved from the org (it would carry Test-Org-only fields into the Prod
   Drift Gate). Leave the Sales/Marketing/Support variants untouched (§ADR-5).

3. **Trigger A (new customer)** — `force-app/main/default/triggers/AccountCompanySizeCarry.trigger`
   `trigger AccountCompanySizeCarry on Account (after update, after insert)` … only the insert
   branch acts. `<apiVersion>62.0</apiVersion>`, `<status>Active</status>` (M7).

4. **Trigger B (existing customer)** — `force-app/main/default/triggers/LeadCompanySizeCarry.trigger`
   `trigger LeadCompanySizeCarry on Lead (before update, after update)` … only the after-update
   branch acts, and only when `Company` actually changed. Coexists with the existing
   `LeadDuplicateGuard on Lead (before …)` — different phases, no ordering dependency.

5. **Handler (one class, two entries, one shared guard)** — `force-app/main/default/classes/CompanySizeCarryHandler.cls` (+ `-meta.xml`)
   A single class holds the state so Trigger A and Trigger B cannot both write the same customer.

   ```apex
   public class CompanySizeCarryHandler {
       private static Set<Id> carried = new Set<Id>();        // per transaction: no double write, no re-entry

       // A) Account afterSave / insert — new customer takes its lead's band
       public static void carryToNewAccounts(List<SObject> records) {
           Set<String> names = collectName(rec -> rec.Company_Size__c == null);
           if (names.isEmpty()) return;                        // already set ⇒ never touched (AC 3, 4, 12)
           // ONE SOQL, bulkified: Lead.Company is the Account NAME (name-based reference)
           for (SObject l : [SELECT Company, Company_Size__c FROM Lead
                             WHERE Company_Size__c != null AND Company IN :names])
               band.putIfAbsurdNone(l.Company, l.Company_Size__c);   // last wins ⇒ newest lead (max Id) wins
           for (Account rec : records)
               if (rec.Company_Size__c == null && band.containsKey(rec.Name))
                   rec.Company_Size__c = band.get(rec.Name);         // in-place: no extra DML, no recursion
       }

       // B) Lead afterSave / update — attach to an existing customer, fill only when blank
       public static void fillBlankAccounts(List<SObject> newLeads, Map<Id,SObject> oldLeads) {
           Set<String> names = collect(newLeads, l ->
                 l.Company_Size__c != null
                 && oldLeads.get(l.Id) != null
                 && String.valueOf(oldLeads.get(l.Id).Company) != String.valueOf(l.Company));
           if (names.isEmpty()) return;                        // later lead edits never touch the customer (AC 12)
           List<Account> open = [SELECT Id, Name, Company_Size__c FROM Account
                                 WHERE Company_Size__c = null AND Name IN :names];   // blank filter server-side
           List<Account> write = new List<Account>();
           for (Account a : open)
               if (!carried.contains(a.Id) && bandFor(a.Name) != null) { a.Company_Size__c = bandFor(a.Name); write.add(a); }
           if (write.isEmpty()) return;
           SavePoint sp;
           try { carried.mergeAll(…ids…); update write; }      // ONE bulkified DML statement
           catch (AccessException e) { Rollback sp; /* ownership/CRUD refused — never break the save */ }
       }
   }
   ```
   (Sketch for the Developer, not compilable Apex; `putIfAbsent`-style semantics and the band
   lookup are named above in words.)

6. **FLS — Permission Set pair (house pattern M5, no Profile edits)**
   - `force-app/main/default/permissionsets/SCRUM476_CompanySize_Read.permissionset-meta.xml` —
     `Account.Company_Size__c`, `readable=true`, `editable=false` → AC 10 (every reader of the
     customer sees the band).
   - `force-app/main/default/permissionsets/SCRUM476_CompanySize_Set.permissionset-meta.xml` —
     `readable=true`, `editable=true` → AC 7, 8 and "Create" of the CRUD table (colleagues who
     edit customers today).
   Copy the SCRUM-471 files verbatim apart from `<field>`/`<label>`/`<description>`; **no
   `objectPermissions`, no user entries in source** (M5). Clearing = Edit ⇒ no Delete granted.
   `Lead.Company_Size__c` stays owned by `SCRUM472_CompanySize` — do **not** restate it here.

7. **Test artefacts expected at Review** (the PR is not approvable without them — SCRUM-359 rule):
   `classes/SCRUM476CompanySizeTest.cls` (behaviour) + `classes/SCRUM476CompanySizeFlsTest.cls`
   (negative FLS) + `tests/e2e/SCRUM-476-company-size.spec.ts` (UI flow), house shapes
   SCRUM472 / SCRUM-472.spec.ts, plus the deploy job `scr476-phase3-apextests.xml` shape.

## ADR — Apex over Flow / declarative

- **ADR-1 Apex, not Flow.** No Flow artefact for this story. Flow was rejected for the whole
  carry-over: strict XML schema + `apiVersion` drift caused deploy/schema-validation failures
  repeatedly on this project, and the logic needs a cross-object lookup plus a fill-only-if-blank
  branch and a recursion guard — branching complexity Flow expresses badly and that will evolve.
  Apex per the standing rule; no `flows/` file in the PR.
- **ADR-2 Triggers, not an LWC/button/Apex REST.** The requirement is "when a lead is turned into
  a customer" — it must hold for every entry point (Lightning convert button, `Account` created by
  Data-Import, `/apex` code). A trigger covers all of them; a UI-only helper covers one.
- **ADR-3 A restricted picklist on `Account`, not `NumberOfEmployees`, not a formula, not a
  formula/Text field.** `NumberOfEmployees` (M2) is an exact integer with different semantics
  (exact count vs. band); populating it would invent data and break the user's "same four ranges".
  A formula field cannot be hand-set/cleared (AC 7/8) and re-derives on every read — a
  back-reference to old leads, which AC 12 forbids.
- **ADR-4 Two trigger files, one handler.** The two ACs live in different save events: the new
  customer is an **Account insert**; attaching to an existing customer saves **only the Lead** —
  the Account record is never written, so no Account-side code can see that event. One mechanism
  cannot cover both. They are made independent by (a) `Company_Size__c = null` filters on both sides,
  (b) a shared per-transaction `Set<Id> carried`. Whichever fires first wins, the other skips ⇒
  no ordering dependency, no double write. Ordering with `AccountLockGuard` (M4) is likewise
  irrelevant: it acts `before update`, ours `after …`, and both are fill-only-if-blank.
- **ADR-5 Layout: default `Account Layout` only.** SCRUM-472 touched one layout for the Lead. The
  Lightning customer page renders the default layout's detail section; the three classic variants
  stay untouched. If the user views customers under a variant layout, that is an org step for
  @devops-agent, not a source change (see ⚠️ F-3).
- **ADR-6 "Attach" is detected as a *change* of `Lead.Company`, not as every lead save.** Without
  that gate, editing a sized lead later would silently refill a customer that someone had left
  blank — AC 12 ("changing an old lead does not change the customer") says the carry is a one-time
  event tied to the attach, not a standing rule.
- **ADR-7 No Validation Rule for AC 9 (invalid range rejected).** A `valueSet` **without**
  `valueSetLookup` is a *restricted* picklist: a value outside the four is rejected by the record
  API/UI itself (proven precedent: the identical shape on `Lead`, SCRUM-472). A Validation Rule on
  a standard object would additionally redden every test class that can save the record in the
  blocked state — none is needed, none is delivered.
- **ADR-8 Trigger-side writes are not FLS-gated; the user-side Edit is.** The Lead→Account carry
  happens inside a trigger context (system mode); the house precedent SCRUM-436 measured exactly
  this (a user with read-only FLS, a trigger wrote the read-only field, no `FieldSecurityException`,
  probe run `707WU00001LcArj` green). So no third `…_Write` PS is designed for the carry path.
  The **hand-maintained** path (AC 7/8) *is* user-mode DML and needs the `…_Set` PS. Not re-probed
  here (no org write access); the Tester's `System.runAs` class measures the hand path, and the
  FLS test class must be falsifiable per the house rule (assert `isAccessible/isUpdateable = false`,
  never an `assert(false)` inside the try).

## Governor limits & risks (documented per AGENTS.md)

- **Bulkification:** exactly **one SOQL per trigger event** on each side, keyed by `Set<String>
  Account.Name`, plus **one** bulk `update` in the Lead path. No SOQL in a loop, no per-record
  queries. Batch conversion of 200 leads ⇒ ≤2 queries, ≤1 DML statement.
- **Skip-before-query:** both sides return before any SOQL when the band is already set or no
  `Company` changed — `Account` is a hot object (imports, Data Cloud clean-ups); the trigger costs
  nothing on ordinary customer saves.
- **Recursion:** the Lead path writes an `Account` record, which re-fires the Account trigger; the
  shared `Set<Id> carried` plus the `= null` filter stops it (and stops a second `update`).
- **Cross-object write:** `Account`, `Lead`, `Contact`, `Opportunity` are all **core** objects ⇒
  core→core writes are allowed; the `MIXED_DML_OPERATION` seen in SCRUM-438/442 was
  Permission-Set-Assignment (a non-core record) inside the same statement — not our case. The Lead
  `update` is still wrapped in `SavePoint`/`Rollback` so a **refusal** (ownership/CRUD, see F-2)
  cannot abort the lead save and thus cannot break the conversion.
- **No new `Account` validation rule, no new Account insert path** ⇒ no cascade over existing
  Account/Lead test classes (the SCRUM-442 hazard does not apply; the fill only *adds* a
  non-blank value on records that were blank).

## Sharing model impact

- **No sharing-rule change**, `Account` keeps its OWD and role hierarchy (PO).
- **Visibility ≠ ownership:** AC 10 is satisfied by `SCRUM476_CompanySize_Read`, not by owner
  rights — a reader of a foreign customer sees the band.
- **The write can target a record the converter does not own** (Lead path). Refusal by OWD/CRUD is
  caught, not fatal (see F-2). The `carried` set must not be populated when the write rolled back,
  so a later attach attempt can still fill it.

## ⚠️ Findings (repo vs org)

- **F-1 (= M2)** `Account.NumberOfEmployees` exists in the org (standard, Integer). The PO's
  "no employee field exists" was a repo check. Nothing in this design touches it; the picklist is
  still the correct artefact. Tell the Tester so a criterion is not mis-read.
- **F-2 Ownership read-back is not available from this session.** Test-Org's `Account` OWD cannot
  be read by `sf` (no OWD surface) and I write nothing to the org. Consequence: AC 5 ("an existing,
  blank customer is filled") is **only** measurable against the org, and it needs a converter who
  does not own that customer. The design degrades gracefully instead of assuming.
  @tester-agent: measure AC 4/5 **E2E through the real convert/attach flow with a colleague who is
  not the record owner**, and name the observed OWD consequence in the coverage table — do not
  substitute an Apex `update` of `Lead.Company` for the UI flow (that proves the handler, not the
  button).
- **F-3 Four Account layouts in source (M8).** If the org shows customers under `Account (Sales)`
  /`(Support)` layouts, the item must be added there too, or the AC "visible when the customer is
  opened" fails for those users. Decision taken: default layout only; @devops-agent to confirm the
  active layout for the sales/service population in the org before Release, or the layout delta
  grows to those files.
- **F-4 The PO's count criterion "Accounts already carrying a size after go-live: expected 0" is in
  tension with AC 5**: the moment a sized lead is attached to a blank existing customer, that
  Account carries a size — by design. Count **before** go-live (expected 0), then attribute each
  new non-blank Account to a named conversion/attach; a bare "expected 0, got 2" is not a failure,
  and "0 Leads carry a size" (66/0 in Test-Org, 22/0 in Prod) is the untested gap the PO already
  named — the fixture shape (one sized lead → new customer; one sized lead → existing customer that
  already holds a **different** band) stays mandatory.
- **F-5 No `Lead` field is written by this design.** Contact/Opportunity untouched by construction:
  the handlers reference only `Account` and `Lead` (AC 12/no side effects).

## Technical acceptance criteria → artefact at Review

| AC | Artefact |
|---|---|
| 1 new customer takes the lead's band | `SCRUM476CompanySizeTest` (insert path) **and** E2E via the convert button |
| 2 lead without size ⇒ clean empty save | Apex test: `Company_Size__c = null`, assert save + empty |
| 3 lead keeps its own size | Apex/E2E read-back of the lead after conversion |
| 4 existing sized customer never overwritten (conflicting band) | Apex + E2E, PO's conflicting pair `51_to_250` vs `up_to_10` |
| 5 blank existing customer filled | **E2E** (attach flow, non-owner) — Apex alone insufficient (F-2) |
| 6 batch conversion, own band each | Apex batch of ≥20 records, one query asserted (SOQL count) |
| 7/8 set / change / clear by hand | `System.runAs(converter)` Edit + empty-write, assert no throw, record survives |
| 9 invalid range rejected | restricted-picklist try/catch, assert a throw **outside** the try (falsifiable) |
| 10 visible to readers next to the name | `…FlsTest` (readable true, editable false under `Read` PS) + E2E locator on the customer page, probed not guessed |
| 11 no backfill / existing customers stay empty | SOQL count before/after on untouched Accounts |
| 12 no email/task/feed/other record | EmailMessage/Task/SocialPost + `getAccountRecords` row-count asserts **plus** an Account-workflow row count — do not assert a bare equality on a table the org holds empty (house finding SCRUM-471: a 0==0 assert is vacuous) |
| 13 later lead edit ≠ customer change | Apex: second lead save with `Company` unchanged ⇒ assert no Account write |

## Offene Punkte (nicht blocken die Implementierung)

- [ ] Ambiguous band for a **new** customer whose name matches several sized leads: rule taken =
  **newest lead (max `Id`) wins**, no error, nothing else touched. Flag to @po-agent if the user
  wants oldest-wins or "only when exactly one".
- [ ] Two Accounts sharing one `Name` (name-based `Lead.Company`): the fill targets **all** blank
  matches; a new customer matches by its own name only. Flag to @po-agent as a data-quality
  question — out of scope, must not silently guess.
- [ ] F-3 layout variants: org step, owner @devops-agent before Release.
- [ ] F-2 OWD/ownership: owner @tester-agent (E2E, non-owner), outcome may move the story back to
  @po-agent if the fill is refused.

## Build order for the Developer

1. Field meta → 2. Permission Set pair → 3. assign both PS in Test-Org + read back
   (`PermissionSetAssignment` + one field read through a real session — mandatory hand-off
   evidence, SCRUM-382/386/388/390/394/398 house failure) → 4. handler class → 5. two trigger
   files → 6. layout item (edit master's file in place) → 7. test classes + E2E spec → 8. PR +
   deploy jobs green.
   Work on **`feature/SCRUM-476-company-size`** (this branch already carries this doc; do not cut a
   second branch for the ticket).
