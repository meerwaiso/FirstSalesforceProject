# SCRUM-476 — Architecture-Design: Company Size carried from Lead to Account

Author: architect-agent · Branch: `feature/SCRUM-476-company-size` · Story: SCRUM-476

## Ziel

One new restricted-picklist field `Company_Size__c` on the standard object `Account`, filled
automatically **once** at the moment a lead becomes a customer (new customer: take the lead's
range; existing customer: only when blank), afterwards hand-maintained, visible next to
`Account.Name` — with exactly the four ranges of the lead field of SCRUM-472.

## Measured facts (each with the command that measured it, 2026-11-24)

| #   | Fact                                                                                                                                                                                   | Command                                                                                                     |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| M1  | `Account.Company_Size__c` does **not** exist in Test-Org                                                                                                                               | `scripts/fls-check.sh Account Company_Size__c Test-Org` → "1. Existenz NEIN — nicht in dieser Org deployt." |
| M2  | `Account` **does** carry the standard field `NumberOfEmployees` (label "Employees")                                                                                                    | `sf sobject describe --sobject Account` → `"name": "NumberOfEmployees"`                                     |
| M3  | Four picklist API values of the lead field, verbatim: `up_to_10` / `11_to_50` / `51_to_250` / `more_than_250`, labels "up to 10 employees" … "more than 250 employees"                 | `git show origin/master:force-app/main/default/objects/Lead/fields/Company_Size__c.field-meta.xml`          |
| M4  | Only **one** Account-level trigger exists today: `AccountLockGuard on Account (before update)` — no Account insert/afterSave trigger                                                   | `git ls-tree -r origin/master --name-only \| grep triggers/` + read of the trigger file                     |
| M5  | House FLS pattern for an Account field = a **pair**: `SCRUM471_KeyAccount_Read` (readable, not editable) + `SCRUM471_KeyAccount_Set` (readable + editable), field-only, no object CRUD | `git show origin/master:.../SCRUM471_KeyAccount_{Read,Set}.permissionset-meta.xml`                          |
| M6  | House layout placement = item right after the name field, `behavior Edit`, with an XML comment naming the ticket                                                                       | `git show origin/master:.../layouts/Lead-Lead Layout.layout-meta.xml` (SCRUM-472 item after `Company`)      |
| M7  | House trigger shape: `<apiVersion>62.0</apiVersion>`, thin trigger file + separate `…Handler` class, `Trigger.isInsert` / `isUpdate` dispatch                                          | `git show origin/master:.../triggers/LeadDuplicateGuard{.trigger,.trigger-meta.xml}`                        |
| M8  | Four Account layouts tracked in source: `Account Layout`, `Account (Sales) Layout`, `Account (Marketing) Layout`, `Account (Support) Layout`                                           | `git ls-tree -r origin/master --name-only \| grep layouts/`                                                 |
| M9  | Survey basis: `origin/master` @ **93e7f0c** (`[TESTER][SCRUM-474] … (#195)`), after `git fetch origin`                                                                                 | `git log -1 --format='%h %s' origin/master`                                                                 |

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
   <?xml version="1.0" encoding="UTF-8" ?>
   <CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
       <fullName>Company_Size__c</fullName>
       <description
     >Employee-size band of the customer (SCRUM-476): hand-set; blank = not known yet. Carried once from the lead at conversion, never computed, never defaulted.</description>
       <externalId>false</externalId>
       <label>Company Size</label>
       <required>false</required>
       <trackTrending>false</trackTrending>
       <type>Picklist</type>
       <valueSet>
           <valueSetDefinition>
               <sorted>false</sorted>
               <value><fullName>up_to_10</fullName><default
           >false</default><label>up to 10 employees</label></value>
               <value><fullName>11_to_50</fullName><default
           >false</default><label>11 to 50 employees</label></value>
               <value><fullName>51_to_250</fullName><default
           >false</default><label>51 to 250 employees</label></value>
               <value><fullName>more_than_250</fullName><default
           >false</default><label>more than 250 employees</label></value>
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

> **AMENDMENT 2026-11-24, review round 2 (user decision — items 3 to 5 below are superseded).**
> A lead conversion does NOT change `Lead.Company`. It flips `Lead.IsConverted` false → true and
> writes `Lead.ConvertedAccountId`, and that **Id names the customer exactly** — so there is no
> name matching and no ambiguity anywhere. Corrected spec:
>
> - **No Account trigger, no name lookups.** `AccountCompanySizeCarry` is deleted from repo and org.
> - **One trigger:** `LeadCompanySizeCarry on Lead (after update)` →
>   `CompanySizeCarryHandler.carryConvertedLeads(List<Lead> after, Map<Id, Lead> before)`.
> - **Act only on a conversion:** `IsConverted` true in `after`, false in `before`,
>   `ConvertedAccountId != null`. An edit of an already converted lead changes nothing (AC 12).
> - **Fill that one Account, only while blank:** one SOQL
>   `SELECT Id, Company_Size__c FROM Account WHERE Id IN :ids AND Company_Size__c = null`,
>   then ONE bulkified `update` of fresh sObjects (Id + the written field only, house SCRUM-459).
> - **Savepoint:** `Savepoint sp = Database.setSavepoint();` / `Database.Rollback(sp)` — both
>   exist in this org (measured 2026-11-24: `setSavepoint()` compiles, `Rollback(sp)` undid an
>   `update`). The earlier "no rollback primitive" note probed the wrong shapes.
> - **Tests:** `Database.convertLead` for a new customer, and for an existing customer **with**
>   and **without** a size.
> - **Why item 3 was wrong:** keying the Account-insert path on `Lead.Company` (= a Name) wrote a
>   band onto ANY new Account whose Name matched a sized Lead — imports and manual creation. Test-Org
>   holds 268 Accounts under 106 distinct Names, 19 Name-groups with duplicates (up to 35 per Name),
>   so that violated "nothing else happens when a size is set".
>
> ---
>
> _(superseded round-1 spec, kept for the record:)_ 3. **Trigger A (new customer)** — `force-app/main/default/triggers/AccountCompanySizeCarry.trigger`
> `trigger AccountCompanySizeCarry on Account (after update, after insert)` … only the insert
> branch acts. `<apiVersion>62.0</apiVersion>`, `<status>Active</status>` (M7).

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
- **ADR-6 "Attach" is detected as a _change_ of `Lead.Company`, not as every lead save.** Without
  that gate, editing a sized lead later would silently refill a customer that someone had left
  blank — AC 12 ("changing an old lead does not change the customer") says the carry is a one-time
  event tied to the attach, not a standing rule.
- **ADR-7 No Validation Rule for AC 9 (invalid range rejected).** A `valueSet` **without**
  `valueSetLookup` is a _restricted_ picklist: a value outside the four is rejected by the record
  API/UI itself (proven precedent: the identical shape on `Lead`, SCRUM-472). A Validation Rule on
  a standard object would additionally redden every test class that can save the record in the
  blocked state — none is needed, none is delivered.
- **ADR-8 Trigger-side writes are not FLS-gated; the user-side Edit is.** The Lead→Account carry
  happens inside a trigger context (system mode); the house precedent SCRUM-436 measured exactly
  this (a user with read-only FLS, a trigger wrote the read-only field, no `FieldSecurityException`,
  probe run `707WU00001LcArj` green). So no third `…_Write` PS is designed for the carry path.
  The **hand-maintained** path (AC 7/8) _is_ user-mode DML and needs the `…_Set` PS. Not re-probed
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
  Account/Lead test classes (the SCRUM-442 hazard does not apply; the fill only _adds_ a
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

| AC                                                             | Artefact                                                                                                                                                                                                                       |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 new customer takes the lead's band                           | `SCRUM476CompanySizeTest` (insert path) **and** E2E via the convert button                                                                                                                                                     |
| 2 lead without size ⇒ clean empty save                         | Apex test: `Company_Size__c = null`, assert save + empty                                                                                                                                                                       |
| 3 lead keeps its own size                                      | Apex/E2E read-back of the lead after conversion                                                                                                                                                                                |
| 4 existing sized customer never overwritten (conflicting band) | Apex + E2E, PO's conflicting pair `51_to_250` vs `up_to_10`                                                                                                                                                                    |
| 5 blank existing customer filled                               | **E2E** (attach flow, non-owner) — Apex alone insufficient (F-2)                                                                                                                                                               |
| 6 batch conversion, own band each                              | Apex batch of ≥20 records, one query asserted (SOQL count)                                                                                                                                                                     |
| 7/8 set / change / clear by hand                               | `System.runAs(converter)` Edit + empty-write, assert no throw, record survives                                                                                                                                                 |
| 9 invalid range rejected                                       | restricted-picklist try/catch, assert a throw **outside** the try (falsifiable)                                                                                                                                                |
| 10 visible to readers next to the name                         | `…FlsTest` (readable true, editable false under `Read` PS) + E2E locator on the customer page, probed not guessed                                                                                                              |
| 11 no backfill / existing customers stay empty                 | SOQL count before/after on untouched Accounts                                                                                                                                                                                  |
| 12 no email/task/feed/other record                             | EmailMessage/Task/SocialPost + `getAccountRecords` row-count asserts **plus** an Account-workflow row count — do not assert a bare equality on a table the org holds empty (house finding SCRUM-471: a 0==0 assert is vacuous) |
| 13 later lead edit ≠ customer change                           | Apex: second lead save with `Company` unchanged ⇒ assert no Account write                                                                                                                                                      |

## Offene Punkte (nicht blocken die Implementierung)

- [ ] Ambiguous band for a **new** customer whose name matches several sized leads: rule taken =
      **newest lead (max `Id`) wins**, no error, nothing else touched. Flag to @po-agent if the user
      wants oldest-wins or "only when exactly one".
      **Re-measured against the corrected design (round 2):** ambiguity is only possible where **several
      Leads convert to one `ConvertedAccountId` in the same batch**. The handler writes
      `bandOfLead.put(ConvertedAccountId) = band` while iterating `after`, so the winner is whichever
      record the save order delivers **last** — not the newest Lead. PO accepted newest-wins and requires
      the tie-break to be named in the release note, so the handler must either pick
      `max(Lead.Id)` per Account Id explicitly, or the release note must state "letz-converted lead wins"
      exactly as observed. An unspecified order is neither.
- [x] **SUPERSEDED by the amendment above — there is no name matching left.** The PO decision is
      kept as the reason, not as a rule: `Lead.ConvertedAccountId` names the customer exactly, so nothing
      is ambiguous and nothing is guessed. The surviving testable shape is the **regression** in R-5 below:
      an Account created by import or manual creation whose `Name` matches a sized Lead stays **blank**.
      (Original PO decision, comment 23806, REJECTED as a business rule: on an **ambiguous name the
      carry-over is skipped, nothing is guessed**, and the conversion/attach still saves cleanly —
      writing a band onto a customer the colleague did not aim at puts a fact on a possibly unrelated
      record, and a wrong band is worse than an empty one. The reason stands; the B-side / A-side name
      rules and the two-Accounts-one-Name fixture are superseded, see R-5.)
- [ ] F-3 layout variants: org step, owner @devops-agent before Release.
- [ ] F-2 OWD/ownership: owner @tester-agent (E2E, non-owner), outcome may move the story back to
      @po-agent if the fill is refused.

## ⚠️ F-6 (Review round 1) — a swallowed write can hide another ticket's rule

The carry writes the customer with an **`update`**, not in place, so on that record Salesforce
re-evaluates the **Account-level `before update` trigger (`AccountLockGuard`) and the two
Account Validation Rules that exist on `origin/master`** (`LockReason_PflichtBeiGesperrt`,
`Wartungsvertrag_End_Before_Start`). A rejection there must **not** be swallowed silently: a
blanket `catch (Exception)` also eats a genuine rule violation or a governor-limit fault, which
leaves a customer created _without_ its band and nothing on record. Narrow the catch by
**measuring** what an ownership refusal actually raises (the Tester's non-owner save names it) and
re-throw anything that is not an access refusal. Typed catch names were probed and do **not**
compile in anonymous Apex on Test-Org (`InvalidAccessFault`, `InsufficientAccessToDataFault`,
`InsufficientAccessToDataException`, `InvalidAccessException`, `AccessFault` — all rejected via
`scripts/apex-probe.sh`, 2026-11-24), so discriminate on the caught exception's own message/type
value, measured — not on a name guessed from memory.

## Review round 1 (PR #196, head `ab8a3f2`) — required changes, verdict REJECTED

1. **Ambiguity skip (PO decision, comment 23806)** — the branch writes **every** blank name match
   on both sides. Implement the hard rule above (handler change, both entries).
2. **`SCRUM476CompanySizeTest` has zero `System.runAs`** (verified by reading the class on the
   branch, not only from the gate log) → `scripts/fls-gate.py --base origin/master --org Test-Org`
   reddens CI. House shape: `SCRUM424FirstResponseFlsTest` (PS setup inserts, then DML/SOQL inside
   `System.runAs(u)`), and the gate error is `MIXED_DML_OPERATION`, not a metadata defect.
3. **Vacuous side-effect asserts:** `carry_createsNoOtherRecord` asserts org-wide
   `[SELECT Id FROM Contact]`, `FROM Opportunity`, `FROM Case` all `== 0`. In an org that happens
   to hold none of these, an equality on an empty table is `0 == 0` and cannot fail (house finding
   SCRUM-471); it also turns red the moment any colleague creates a Contact. Measure the **delta
   across one save** (count before, count after, assert equal) on a table that is **seeded with one
   control record**, and name the EmailMessage/Task/Feed tables the org holds empty as seeded, not
   vacuous.
4. **Ambiguity fixture:** two Accounts, identical `TEST-476-` Name, both blank, one sized lead →
   both still blank after the attach. Without it the criterion is untested (count 0 ⇒ not `PASS`).
5. Keep `docs/RELEASE-NOTES.md` free of AC 9 (UI-only) and of any claim that the ambiguity or the
   "refusal never aborts" guarantee is proven, until the Tester watched a real convert/attach save.

## Review round 2 (PR #196, head `740b292`) — measured in Test-Org, verdict REJECTED

Evidence read off the org, not off the CI log (`sf data query -t -q "… ApexTestResult WHERE
ApexTestRunResultId = '05mWU000002dNrdYAE' AND Outcome != 'Pass'"`; queue item `(6/10)` at
2026-11-24 12:10 CET):

| failing method                                       | measured message                                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `bulk_conversions_carryEveryBand`                    | `ConvertLead failed … LIMIT_EXCEEDED, "There was an error converting the lead"` (200 conversions) |
| `convert_existingCustomer_blank_fillsBand`           | `Expected: 001WU00002M3a4nYAB, Actual: 001WU00002M3a4oYAB`                                        |
| `convert_existingCustomer_withSize_neverOverwritten` | `Expected: 001WU00002M3a4pYAB, Actual: 001WU00002M3a4qYAB`                                        |
| `editOfConvertedLead_neverRefills`                   | `Update failed … CANNOT_UPDATE_CONVERTED_LEAD, cannot reference converted lead`                   |

- **R-1 The two attach fixtures never hit the fixture's customer.** Both sides of the failed assert
  are Account Ids (`001` prefix), so `Database.convertLead` attached to a **different** customer than
  the fixture held. Until the test asserts `res.getAccountId() == fixtureAccountId` and reads the band
  back on **that** record, AC 4 ("never overwritten", PO's conflicting pair) and AC 5 ("blank existing
  customer filled") have **no automated test at all** — the PO's "measured, not assumed" rule.
- **R-2 A converted Lead cannot be updated in this org**: `update` raises
  `CANNOT_UPDATE_CONVERTED_LEAD`. AC 12/13 ("an edit of an already converted lead changes nothing")
  is therefore **platform-enforced on the Apex path** and only E2E-exercisable on the UI path; the
  flip-gate stays (REST/DML callers that clear `IsConverted` reach it), but the Apex method that
  pretends to edit a converted Lead can never run. Delete it or replace it with an assertion on the
  `CANNOT_UPDATE_CONVERTED_LEAD` fault.
- **R-3 The bulk criterion (AC 6/7) is red with `LIMIT_EXCEEDED` inside `convertLead` at 200
  conversions.** Cause **not yet measured** — hypothesis: `Database.setSavepoint()` is opened once per
  conversion event by the handler and `convertLead` manages its own rollback, so the per-transaction
  savepoint allowance runs out. Discriminator, one test class, both directions: N conversions onto an
  **existing** Account (savepoint + SOQL + `update`) vs N conversions whose `Company` names **no**
  Account (savepoint + SOQL, `update` skipped because `write` is empty). If only the first trips →
  open the savepoint only when `write` is non-empty; if both trip → the carry must not open a savepoint
  per event at all. Do **not** shrink the fixture to 20 records to get green: the count is a criterion.
- **R-4 Org read-backs, both verified 2026-11-24:** `SELECT Id, Name FROM ApexTrigger WHERE Name LIKE
'%CompanySize%'` → **only** `LeadCompanySizeCarry` (`01qWU00000AvdjeYAB`) — the Account trigger is
  gone in repo **and** org. `SELECT Id, Company FROM Lead WHERE IsConverted = true AND
ConvertedAccountId != null` → **1** record (`Testfirma394Converted`); `ConvertedAccountId = null` →
  **0** records, so "every conversion names its customer by Id" is exercised on **0 records =
  untested**, not `PASS`. The whole carry is still only exercisable on fixtures (Test-Org 66 Leads /
  0 sized, Prod 22/0 — the PO's gap).
- **R-5 The surviving name regression:** an `Account` created by import or manual creation that shares
  the `Name` of a sized Lead must stay **blank**. That is what the deleted Account-insert path used to
  violate; keep exactly one assertion ("at most one record written" / "the import stays blank"), the
  two-Accounts-one-Name skip fixture is superseded.
- **R-6** `System.runAs` is now present in the behaviour class (round-1 item 2 resolved); the gate
  evidence to re-check after the fix is `scripts/fls-gate.py --base origin/master --org Test-Org`.

## Review round 3 (PR #196, head `29794b9`) — measured, verdict REJECTED (one item blocks)

Read back myself: `gh pr checks 196` on run `45388344584` → Lint pass, README pass, Smoke pass (5m12s),
**Prod-Org Drift Gate pending (0 s)** — the merge gate is open, not green. Org: newest
`ApexTestQueueItem` pair `(11/11)` + `(3/3)` = 14 Pass, consistent with Test Run
`707WU00001WG5zb`. `System.runAs` still present in the behaviour class.

- **R-7 The premise "there is no Apex path to the attach case" is FALSE — measured by me in Test-Org
  2026-11-24 13:05/13:06 CET with `sf apex run` (two probes, both self-cleaned):**
  - Account `TEST-476-ProbeAttach` (blank band) + Lead carrying `more_than_250`, converted with
    `Database.LeadConvert` **`lc.setAccountId(<the existing Account's Id>)`** →
    `ok=true sameRecord=true returned=001WU00002M3ibWYAR fixture=001WU00002M3ibWYAR accounts=1
bands=001WU00002M3ibWYAR/more_than_250` — the conversion **reuses** the existing customer and the
    handler **filled its band** ⇒ **AC 5 is exercisable in Apex.**
  - Same shape, existing Account holds `51_to_250`, Lead carries `up_to_10` →
    `sameRecord=true accounts=1 bands=…/51_to_250` — **not overwritten**, the PO's conflicting pair ⇒
    **AC 4 is exercisable in Apex.**
- **R-8 Why their fixtures miss it:** the helper is `private static Database.LeadConvert convertLead(Id leadId)`
  and sets only `setLeadId` + `setConvertedStatus` — **no `setAccountId`**, so every conversion in the
  class creates a NEW Account and `res.getAccountId() != existing.Id` ("sameRecord=false") is a property
  of the helper, not of the platform. The attach fixtures need a second helper that passes
  `setAccountId(existing.Id)`; then assert `res.getAccountId() == existing.Id` **before** any band
  assert (house rule: a criterion asserted against a record the save did not name is not a criterion).
- **R-9 What does stand:** `Lead.ConvertedAccountId` is read-only —
  `sf sobject describe --sobject Lead` → `createable: false`, no `editable` flag — so writing it in
  Apex dies at compile. Read-only on the write side, readable on our side; nothing in the handler writes it.
- **R-10 Governor cost, both causes measured, do not confuse them:** my probe loop of 30 single-record
  conversions died `System.LimitException: Too many SOQL queries: 101` — each conversion **event** costs
  its own queries (the handler's 1 SOQL is among them). Their single `convertLead` call over 200 rows
  dies `LIMIT_EXCEEDED` at row 0 (their measurement: 10 save, 20 die). So AC 6/7 cannot be exercised
  at 200 records in one Apex transaction in this org; the handler's cost is **one SOQL + one update per
  event**, which is the right shape for a bulk save. The bulk criterion belongs to the E2E/Import path
  with the record count named in the coverage table — shrinking an Apex fixture to 10 rows is not a
  pass for a 200-record criterion.
- **R-11 Unverified, left open:** whether the tie-break (several Leads converting to ONE
  `ConvertedAccountId` in one call) is Apex-exercisable — not probed. Until measured it stays a
  Tester criterion.

## Review round 4 (PR #196, head `9f77ae8`) — measured, verdict APPROVED (with named coverage lines)

Read back on 2026-11-24 with `gh pr checks 196` (run `45392054477`): Lint & Format pass 49s,
Metadata/Apex/Smoke pass 6m1s, **Prod-Org Drift Gate pass 11m44s**, README pass 6s — all four
green on the reviewed head, so the merge gate is closed.

- **R-12 The 15/15 Pass is verified, the quoted run id is not.** CI log 12:20:04 UTC: `Outcome Passed`,
  `Tests Ran 15`, scope `RunSpecifiedTests — SCRUM476CompanySizeFlsTest,SCRUM476CompanySizeTest`;
  org `ApexTestRunResult 05mWU000002dOpJYAU` 2026-11-24T12:18:27 UTC, `MethodsEnqueued/Completed 15/15`.
  Their `707WU00001WGdJ1` answers 0 rows as an `ApexTestRunResult` and as `ApexTestRunResultId` on
  `ApexTestResult` — quote `05mWU000002dOpJYAU` in the next handoff.
- **R-13 The smoke job's second step printed `Test-Org validate: Failed` while the job passed.**
  `sf project deploy report -i 0AfWU00000dNZD80AO -o Test-Org`: `numberComponentErrors 0`,
  `numberTestErrors 0`, `Failing: 0`, `status Failed` — the verdict comes from the
  "returned from org, but not found in the local project" warnings (SCRUM-453/459/461/464/467/468/470/471/472
  Permission Sets, i.e. artefacts that live in the org, not in this branch). Not a defect of this branch;
  it belongs in the report as its own line, never as a pass.
- **R-14 Attach fixtures now correct (read from `9f77ae8`):** helper `attachLeadTo(Id leadId, Id accountId)`
  sets `lc.setAccountId(accountId)`; `attachTo_blankExistingCustomer_fillsBandOnce` asserts
  `System.assertEquals(existing.Id, res.getAccountId(), …)` BEFORE the band assert and
  `1 == named.size()`; `attachTo_customerWithBand_neverOverwritten` holds `51_to_250` against a lead
  carrying `up_to_10` and asserts the held band. Handler diff against `4da604f` is comment-only —
  `winnerOfCustomer` untouched.
- **R-15 Their FLS sentence is wrong in this org.** `scripts/fls-check.sh Account Company_Size__c Test-Org`:
  field exists (Picklist); granted by `SCRUM476_CompanySize_Read` (read) and `SCRUM476_CompanySize_Set`
  (read+edit), **each assigned to 2 users** (`devops-agent@cline.test`,
  `meerwais.osmani@resourceful-bear-…com`). The third grant `AncCrmIntegrationUser` (read, edit=false)
  is a foreign Permission Set assigned to **nobody** — inert, not ours. The negative-access test still
  belongs to the Tester with the real user pair; nothing in the branch is unassigned.
- **R-16 Tie-break measured by me 13:35–13:36 CET (probe `p476_tie5.cls`, cleanup: 4 deletes Success,
  0 records left under `TEST-476%`):** Account `001WU00002M3pv7YAB` blank; Leads `up_to_10` =
  `00QWU00000iXV5J2AW` and `more_than_250` = `00QWU00000iXNFq2AO`; ONE `Database.convertLead` call,
  both converts `setAccountId(the same Account)` → `CONVERTED ok=2`, `BAND after=up_to_10`, and the
  **higher** Id belongs to the `up_to_10` lead — highest Lead Id wins, i.e. `winnerOfCustomer` as
  implemented. Note the higher Id is NOT the later-created lead, so the release note must say
  **"the lead with the higher Id wins"**, never "neuesten" — otherwise the note states something the
  org does not do. Still no fixture in the class → the Tester owns the row (UI attach path or an
  Apex fixture); it must not be claimed as covered by the branch.
- Lines the branch does NOT own and must not be called covered: AC 6/7 at 200 records (E2E/Import row,
  counts measured: 30 single-record events → `Too many SOQL queries: 101`; one `convertLead` over 20
  rows → `LIMIT_EXCEEDED` at row 0; 10 save / 20 die), AC 9 (UI-only), the tie-break above, and the
  zero-record facts (Test-Org 66 Leads / 0 sized, Prod 22 / 0, converted Leads 1 → the carry-over is
  not observable in either org today; `docs/RELEASE-NOTES.md` stays silent about it).

## Build order for the Developer

1. Field meta → 2. Permission Set pair → 3. assign both PS in Test-Org + read back
   (`PermissionSetAssignment` + one field read through a real session — mandatory hand-off
   evidence, SCRUM-382/386/388/390/394/398 house failure) → 4. handler class → 5. two trigger
   files → 6. layout item (edit master's file in place) → 7. test classes + E2E spec → 8. PR +
   deploy jobs green.
   Work on **`feature/SCRUM-476-company-size`** (this branch already carries this doc; do not cut a
   second branch for the ticket).

## Review round 3 — Developer response (2026-11-24, head after this commit)

All four items from §Review round 2 are closed with measurements taken in Test-Org:

- **AC 4 / AC 5 — the fixture premise was wrong, not the handler.** `Database.convertLead`
  WITHOUT `setAccountId` never attaches to an existing `Account`: probe read-back `sameRecord=false`,
  `accountsNowNamed=2`, and a second probe proved `Lead.ConvertedAccountId` cannot be written at all —
  compile error `Field is not writeable: Lead.ConvertedAccountId`. **Superseded in round 4:** the attach
  IS Apex-exercisable — `lc.setAccountId(existing.Id)` reuses the record (see §Review round 4 below);
  what this probe rules out is writing the field, not the attach. The Apex fixtures from this round
  assert the no-attach case only: the record `ConvertedAccountId` names takes the band, the
  same-`Name` neighbour stays untouched.
- **AC 12 is platform-enforced on the Apex path:** `update` of a converted Lead dies with
  `CANNOT_UPDATE_CONVERTED_LEAD`. The test asserts the refusal plus the band read-back; it no
  longer pretends an edit can succeed.
- **`LIMIT_EXCEEDED` in the bulk fixture is a query budget, not an org limit** (corrected
  where this note stands; measured 2026-11-24 with `scratch/probe_limit476b.cls` through
  `sf apex run`): ONE `convertLead` call over 25 rows saves 25/25; 30 SEPARATE
  `convertLead` calls in the same transaction save 5 and the remaining 25 die
  `LIMIT_EXCEEDED` ("There was an error converting the lead"); one call over 120 rows dies
  with the platform's own words, `System.LimitException: Too many SOQL queries: 101`.
  The 100-query cap of the enclosing Apex transaction is spent per conversion **event** by
  the two Lead triggers that exist in the org — master `LeadDuplicateGuard` (before insert,
  before update; its SCRUM-386 header states 1 SOQL, 0 DML per invocation) and my
  `LeadCompanySizeCarry` (1 SOQL + 1 bulkified update) — plus `convertLead`'s own record
  work. Nothing org-limited was reached; how many conversions fit depends on what the
  transaction had already spent. `convertedStatus` must be `'Closed - Converted'`
  (`'_Converted'` dies `INVALID_STATUS`, an artefact of the probe, not of the platform).
- **The PO's tie-break is now deterministic.** Several Leads in one save may name the same
  customer — reachable through the UI attach path AND through Apex `convertLead` with
  `setAccountId` (measured in round 4: `sameRecord=true`, one Account reused; see the
  corrected note above).
  The winner is the Lead with the highest `Id` (Salesforce Ids increase with creation) — the
  PO's accepted "newest lead wins" — never save order, which the platform does not define.
  The release note will state it in words; no claim is made here about a release note that does
  not exist yet (Release Notes only record delivered Prod features).

Coverage measured with `sf apex run test ... --code-coverage`:
`CompanySizeCarryHandler` **24/28 = 86 %**, `LeadCompanySizeCarry` **2/2 = 100 %**, Test Run Id
`707WU00001WG5zb`, 14/14 Pass. The deploy report's own coverage block attributes 0/24 to the
handler — that report cannot be used as the coverage oracle here; the `--code-coverage`
result can.

## Review round 4 — Developer response (2026-11-24, head after this commit)

The blocking artefact is closed; no production code changed, as the review asked.

- **R-7/R-8 (the blocker): the attach IS Apex-exercisable, and my fixtures now use it.**
  Second helper `attachLeadTo(leadId, accountId)` passes `lc.setAccountId(existing.Id)`.
  Two new fixtures: `attachTo_blankExistingCustomer_fillsBandOnce` (AC 5) and
  `attachTo_customerWithBand_neverOverwritten` (AC 4 with the PO's conflicting pair — existing
  `51_to_250` vs lead `up_to_10`; the picklist values were read back with
  `sf sobject describe --sobject Account`, not recalled). Both assert
  `res.getAccountId() == existing.Id` **before** any band assertion, and the blank case
  additionally asserts ONE Account for that Name, so a band cannot slip onto a record the
  save did not name. Measured: attach reuses the record (sameRecord=true) and the handler
  fills the blank band / keeps the held one.
- The old no-attach fixture stays, renamed to what it now proves:
  `convert_withoutAttach_createsOwnCustomer_sameNameNeighbourUntouched` — the import /
  manual-creation regression (R-5's surviving shape).
- **R-9 stands unchanged:** `Lead.ConvertedAccountId` is read-only (`createable: false`);
  the round-3 compile error ruled out writing the field, not the attach. The design note that
  claimed "no Apex path" is corrected in place above, not contradicted here.
- **R-10 (bulk cost) is now a named gap, not a shrunk pass.** `bulk_conversions_carryEveryBand`
  became `bulk_conversionEvents_carryEveryBand_withinTheOrgsBound`: it asserts the handler's
  shape (ONE SOQL + ONE bulkified update per event, each band on its own customer) at the
  org's bound — 10 convertLead calls save, 20 die `LIMIT_EXCEEDED` at row 0, a 30-event loop
  dies `Too many SOQL queries: 101`. The 200-record criterion (AC 6/7) is NOT claimed green in
  Apex; it moves to the E2E/Import row of the coverage table with the count named.
- **R-11 stays open for the Tester:** the tie-break (several Leads → one
  `ConvertedAccountId` in one save) was not probed this round; the handler picks
  `max(Lead.Id)` deterministically, but that branch has no fixture yet, so it is reported as
  unexercised, not as passing.

Verdict of the changed classes, read back from the org with
`sf apex run test ... --wait 25 -r json --code-coverage`: **15/15 Pass**, Test Run Id
`707WU00001WGdJ1`, `CompanySizeCarryHandler` **25/28 = 89 %**, `LeadCompanySizeCarry`
**2/2 = 100 %**.
