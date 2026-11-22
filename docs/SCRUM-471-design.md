# SCRUM-471 — „Key Account"-Mark on the Customer Record — Build Spec (Architect)

Freigiven: Architect-Agent, 2026-11-22. Repo surveyed on `origin/master` @ `f9708a9`
("[DEVOPS][SCRUM-470] Prod release manifest …"). Org measurements: Test-Org, via `sf data query`.

## Ziel

One manual yes/no mark on the standard `Account` record, visible next to the name,
read by everyone who can open the record, changed only by those who may edit the
record today — and nothing else happens.

## ADR — Implementation medium (mandatory)

| Option | Verdict | Reason |
|---|---|---|
| **Declarative config (chosen)** | **approved** | The requirement is state, not logic: one Checkbox field, two Permission Sets, four layout items. No branch, no calculation, no process step. |
| Flow | **rejected** | Adds an `apiVersion` + strict-XML surface and a naming convention for zero benefit. Flows have repeatedly failed deploy/schema validation in this project (SOUL rule: Apex over Flow). Nothing here needs process steps. |
| Apex | **rejected** | Any handler/trigger that reacts to the mark would violate AC8 by construction. A guard is not needed either: the field is editable by hand and refused by FLS (see §5). |

Consequence for the review gate: **this ticket ships no production Apex class at all.**
Test classes only (see §7).

## 1. Data model

Standard object `Account` only. **Exactly one new field**, no new object, no new
record type, no related list, `Opportunity`/`Case` untouched.

`force-app/main/default/objects/Account/fields/Is_Key_Account__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Is_Key_Account__c</fullName>
    <label>Key Account</label>
    <description>SCRUM-471: Manual mark "Key Account" — set by hand when management decides, cleared by hand when that changes. No scoring, no automatic rule.</description>
    <defaultValue>false</defaultValue>
    <type>Checkbox</type>
</CustomField>
```

House shape verified against `origin/master:objects/Account/fields/Is_Locked__c.field-meta.xml`
(same Checkbox + `defaultValue` + type, no `<length>`, no `required`).
Naming follows the house for booleans on Account: `Is_Locked__c`, `Is_Inactive__c`.

**Name collision check (measured, not assumed):**
`SELECT QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Account'`
filtered on `Is_%`/`%Key%` → 3 rows only: `IsDeleted`, `Is_Locked__c`, `Is_Inactive__c`.
`Is_Key_Account__c` is free in Test-Org.

**Semantics of the Checkbox:** `false` renders as unchecked = "No", `true` = checked = "Yes".
`defaultValue=false` covers AC1 (new record) **and** AC9 (the 251 records that exist today
read "No" on day one — measured `SELECT Id, Name FROM Account` → totalSize 251, see §9).

## 2. Layout — the mark next to the name

The mark goes into the **first section** (label `Account Information`) of **every Account
layout on `origin/master`**, as the item **directly after the `Name` item**:

| File (path on master) | Sections | First-section fields (measured) |
|---|---|---|
| `layouts/Account-Account Layout.layout-meta.xml` (429 lines) | 7 | OwnerId, **Name**, ParentId, AccountNumber, Site, Type, Industry, AnnualRevenue, … |
| `layouts/Account-Account %28Sales%29 Layout.layout-meta.xml` (341 lines) | 7 | OwnerId, **Name**, ParentId, AccountNumber, Site, Industry, Sic, AnnualRevenue, … |
| `layouts/Account-Account %28Support%29 Layout.layout-meta.xml` (325 lines) | 7 | OwnerId, **Name**, ParentId, AccountNumber, Site, Phone, Fax, … |
| `layouts/Account-Account %28Marketing%29 Layout.layout-meta.xml` (286 lines) | 6 | OwnerId, **Name**, ParentId, AccountNumber, Site, Rating, … |

All four first sections are labelled `Account Information` and carry `Name` at position 2 —
so one anchor works for all four and AC4 ("next to the name, no scrolling") holds on every
tab the Sales and Service people use.

Exact delta item (house shape, copied from the `Is_Locked__c` item in the default layout):

```xml
            <layoutItems>
                <behavior>Edit</behavior>
                <field>Is_Key_Account__c</field>
            </layoutItems>
```

`behavior` is `Edit` (not `Readonly`): the field is writable by hand. The house contrast
is visible in the same file — `Is_Inactive__c` sits there with `behavior=Readonly`
(system-maintained), `Is_Locked__c` with `behavior=Edit`. This field is like `Is_Locked__c`.

⚠️ **Layout delta rule (house SCRUM-468/469):** the branch file is **master + this item only**.
Never retrieve the layout from the org and commit it — a Test-Org-retrieved layout carries
Test-Org-only section fields that redden the Prod-Org Drift Gate.

**Why the layout is the right place (measured):** Test-Org holds 9 FlexiPages
(`SELECT MasterLabel, DeveloperName, EntityDefinitionId, Type, ManageableState FROM FlexiPage`):
8 UtilityBars and 1 RecordPage for `User`. **No Account RecordPage exists** → the Account
detail page renders from the Classic layout sections above. A new FlexiPage RecordPage is
not an option: measured house finding SCRUM-460 — a deployed RecordPage FlexiPage never
activates and renders nowhere.

## 3. Permission Sets (FLS — never Profile edits)

Two PSs, house pair Read + Set (verified on master: `SCRUM442_Satisfaction_Read`/`_Write`,
`SCRUM453_ContactLeft_Read`/`_Set`, `SCRUM431_Wartungsvertrag_ServiceTeam`). Both carry
**no `objectPermissions` block** — a field PS never grants object CRUD (house note in
`SCRUM424_FirstResponse_Read`: "House-Form SCRUM421_Zuordnung (ohne objectPermissions-Block)").

`permissionsets/SCRUM471_KeyAccount_Read.permissionset-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Account.Is_Key_Account__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM471_KeyAccount_Read</label>
    <description>SCRUM-471 Read-FLS: the Key Account mark is readable by everyone who may open the customer record (Sales and Service staff). No edit, no object CRUD. Profiles unchanged.</description>
</PermissionSet>
```

`permissionsets/SCRUM471_KeyAccount_Set.permissionset-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Account.Is_Key_Account__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM471_KeyAccount_Set</label>
    <description>SCRUM-471 Set-FLS: only colleagues who may edit customer records today may set/clear the mark. Assigned to a subset of the Read-PS holders. No object CRUD.</description>
</PermissionSet>
```

Assignment rule (PO-pinned, and what the Developer must read back):

| Right | Granted by | Assigned to |
|---|---|---|
| Read the mark | `SCRUM471_KeyAccount_Read` | every Sales **and** Service user (in Test-Org today: the CLI user `devops-agent@cline.test` **and** the human `meerwais.osmani@resourceful-bear-6f1u4j.com`) |
| Set/clear the mark | `SCRUM471_KeyAccount_Set` | **only** those who may edit customer records today |
| Delete | n/a — the mark is cleared, never deleted | — |

House rule for PS assignment (AGENTS.md, "Permissions"): the PS is assigned to **both** users
of the org — the CLI user and the human account. `scripts/fls-gate.py` reddens the org CI job
when a changed field names no Permission Set, or when the granting PS is assigned to nobody.
A deployed-but-unassigned PS looks like a missing field (`No such column`), not like a
permission — six tickets shipped exactly that. **The Developer handoff comment must carry
the `PermissionSetAssignment` read-back plus one field read through a real session.**

## 4. Sharing / OWD impact

**No impact — nothing changes.** No `sharingRules` element is introduced, no OWD is touched,
no owner-only rule is added. Record access stays exactly as it is today; the mark inherits
the visibility of the record it sits on. A colleague who can read a customer they do not own
still sees the mark on it (AC4/AC5), a colleague without record access sees neither record
nor mark (AC6).

## 5. AC5 / AC7 — how "read but cannot change" is enforced, and how it is proven

A Permission Set can **grant, never revoke**. The mechanism is therefore:

1. the new field's own FLS is OFF for anyone who holds neither PS (house measurement SCRUM-440
   note "Standard-FLS for new fields stays OFF"),
2. `SCRUM471_KeyAccount_Set` is assigned to the narrower group only,
3. the refusal comes from field-level security at runtime — not from a validation rule
   (a ValidationRule cannot test PS membership and would fire on every save, breaking AC8).

⚠️ **Do not assume (1) or (2).** The FLS default of a newly deployed field is **not**
predictable — measured contradiction on file: SCRUM-421 read+edit in the standard profile,
SCRUM-430 not. The negative must be **measured by the Developer in Test-Org**, and the
Architect sign-off is only granted when the probe shows it. The house oracle is
`force-app/main/default/classes/SCRUM470PreferredContactMethodFlsTest.cls` (SCRUM-470,
released to Prod) — copied shape, verified on `origin/master`:

```apex
// 1. temp User on the 'Standard User' profile, no PS assigned yet (house mkTestUser)
Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
User u = new User(ProfileId = p.Id, LastName = 'Fls471', Alias = 'f471neg', …); insert u;

// 2. PRECONDITION FIRST, otherwise every assert below is green for the WRONG reason
Boolean accountReadable = false;
System.runAs(u) { accountReadable = Account.SObjectType.getDescribe().isAccessible(); }
System.assert(accountReadable, 'precondition: object-level Account access, else the wall below '
    + 'comes from missing CRUD, not from missing FLS (house needs a *_TestObjectAccess PS).');

// 3. NEGATIVE read — read INSIDE runAs, ASSERTED outside any try
Boolean readable = false;
System.runAs(u) { readable = Account.Is_Key_Account__c.getDescribe().isAccessible(); }
System.assertEquals(false, readable, 'AC5/AC6: without the PS the mark is not readable.');

// 4. NEGATIVE write
Boolean editable = false;
System.runAs(u) { editable = Account.Is_Key_Account__c.getDescribe().isUpdateable(); }
System.assertEquals(false, editable, 'AC7: without the Set PS the mark is not updateable.');

// 5. SOQL probe — NOTHING but the SELECT inside the try (house falsifiability)
Boolean threw = false;
System.runAs(u) {
    try { List<Account> rows = [SELECT Is_Key_Account__c FROM Account WITH USER_MODE LIMIT 1]; }
    catch (Exception e) { threw = true; }   // 'No such column' / SecurityException — both are the wall
}
System.assert(threw, 'AC6: reading the mark without access must hit the FLS wall.');
```

For **AC5/AC7 specifically** (read-but-cannot-edit) the same class assigns
`SCRUM471_KeyAccount_Read` to the temp user and **not** `SCRUM471_KeyAccount_Set`, then asserts
`isAccessible() == true` **and** `isUpdateable() == false`. Both directions need the temp user.

⚠️ **Falsifiability rule (house, memory SCRUM-430/470):** a `System.assert(false)` inside the
`try` of a SELECT probe can never fail. The `try` contains **only** the SELECT; the asserts
on `getDescribe().isAccessible()/isUpdateable()` sit outside it. A probe that cannot fail
confirms nothing — name the result that would redden it.

The profile-grant check that makes the negative mean anything (house SCRUM-470 header):
`SELECT Parent.Label, Parent.IsOwnedByProfile, PermissionsRead, PermissionsEdit FROM FieldPermissions`
`WHERE SobjectType='Account' AND Field='Account.Is_Key_Account__c'` must show **only** rows with
`IsOwnedByProfile=false` (Permission Set rows). A `Profile` row would mean the negative passes
by luck and the test class is the wrong oracle. Plain query — `--use-tooling-api` on this object
is a wrong call (house SCRUM-449: `sObject type 'FieldPermissions' is not supported`).

⚠️ **The empty-group trap (measured, house SCRUM-467).** In Test-Org there is **no** org-visible
"Sales"/"Service" membership and **no** per-role profile: 41 standard profiles
(`SELECT Id,Name FROM Profile`, Tooling API) contain no "Sales Team"/"Service" profile; the
only Groups are Queues (`Billing`, `First Level Support`, `Technischer Support`,
`Vertragsservice`) and auto-generated Role groups. The only org discriminator left is
**Permission Set membership** — that is the house pattern (SCRUM-467 §11; SCRUM-428/431/442/453
all name their PS after the group). Therefore:

* Positive AC2/AC3/AC4: users holding Read + Set.
* Negative AC5/AC7: a user holding **Read but not Set** (or neither). If the assignment lists
  in Test-Org make both sets identical, the negative test is **vacuous** — it proves nothing
  and the Tester must produce a PS-less/Read-only user (house: `System.runAs` on a temp user)
  or say on record that AC5/AC7 are untested, not PASS.

## 6. AC8 — nothing else fires (measured, not assumed)

* No trigger, no ValidationRule, no formula field, no report, no Flow is added by this ticket.
* `SELECT Name, Active, SobjectType FROM AssignmentRule` → 2 rows, **Case and Lead only**
  (`Standard`/`Standard`). Nothing auto-assigns on an Account save.
* The one Account trigger on `origin/master` is `AccountLockGuard` (before update) →
  `AccountLockClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap)`, whose guard is
  `if (oldAcct != null && oldAcct.Is_Locked__c && !acct.Is_Locked__c)`. A mark-only save
  leaves `Is_Locked__c` untouched → the handler is a no-op, 0 SOQL.
* `Account.ValidationRules` on master: `LockReason_PflichtBeiGesperrt`,
  `Wartungsvertrag_End_Before_Start` — both keyed on other fields, not on this mark.

Nothing of that is changed by this ticket. The Tester still has to prove it (AC8 row): after
set/clear, assert no `EmailMessage`, no `Task`/`Work__Report` record and no other field
changed — count-based, not "looks fine".

## 7. Technical acceptance criteria → test artefacts (PR gate, not a bonus)

Declarative-field tickets ship the house test pair plus the E2E spec. "Deployed and ran once
green" is **evidence, not a test** (house SCRUM-359 rule): the PR is rejected without these.

| Artefact | House shape on master | Covers |
|---|---|---|
| `classes/SCRUM471KeyAccountTest.cls` | `SCRUM442…Test`, `SCRUM453…Test` | AC1 new record = false; AC2 set → true; AC3 clear → false; AC8 no side records; AC9 the 251 existing records read false (assert the count) |
| `classes/SCRUM471KeyAccountFlsTest.cls` | `SCRUM442…FlsTest`, `SCRUM453_ContactLeft` FLS test | AC5/AC7 negative FLS probes of §5 (Read-only + PS-less), AC6 no record access → nothing visible |
| `tests/e2e/SCRUM-471-key-account.spec.ts` | `tests/e2e/SCRUM-428-ac12-report.spec.ts` + the `SCRUM-378_lead-nachfassliste` shape | AC4: the mark renders in the first detail section, next to `Name`, without scrolling |

E2E constraints (house rules, binding): auth **only** via the `frontdoor.jsp` exchange in
`globalSetup` shared through `storageState`; `waitForLoadState('networkidle')` forbidden on
Lightning pages; never guess a locator — probe it, exactly one per element. Memory SCRUM-449:
Lightning renders only the first page of a list view → assert the header count, not rendered
rows (only relevant if the spec checks a list).

E2E scope limit (house finding SCRUM-405, quoted in the SCRUM-470 class header — **not**
re-measured this turn): "Test-Org holds 2/2 System-Administrator licences, so a second
low-privilege browser session for the negative proof is impossible → AC6 belongs to the
Apex class; `System.runAs()` does NOT bypass FLS." So **AC5/AC6/AC7 negatives are Apex
assertions, the E2E covers only the positive AC4.** A Tester report that proves the negatives
only in the browser is incomplete.

## 8. Governor-limit risks

Test-run constraint (house): one broad Apex test run per org at a time; deploy own work with
`--test-level RunSpecifiedTests --tests <own classes>`; the full suite belongs to CI, once,
at the end.

* Production: **0 SOQL, 0 Apex, 0 loop** — nothing runs on save. Layout deploy = 4 components,
  field + 2 PS = 7 components total; no bulk concern.
* Tests must stay bulkified: assert counts over the 251 Accounts with one query, no SOQL per record.
* `fls-gate.py` (CI, org job) reddens when the new field names no PS or when the PS is assigned
  to nobody — §3 pre-empts both.

## 9. Counts that travel forward (measured in Test-Org)

| Fact | Value | Query |
|---|---|---|
| Account records today | **251** | `sf data query --target-org Test-Org -q "SELECT Id, Name FROM Account" --json` → totalSize |
| Accounts already marked | **0** (the field does not exist yet) | no `Is_Key_Account__c` row in the FieldDefinition query |
| Human users in Test-Org | **2** (`meerwais.osmani@resourceful-bear-6f1u4j.com`, `devops-agent@cline.test`) of 8 users | `SELECT Id,Username,… FROM User` |
| Expected AC9 observation on day one | 251 read "No", **0** read "Yes" | — |

A criterion that counts key accounts must expect **0** before someone marks one — a row whose
Observed column reads zero is not a PASS (AGENTS.md).

## 10. Not in scope (PO pinned, deliberate)

Filtering, sorting, reporting by key accounts and "show me only my key accounts" are separate
asks. No list view, no report, no related list in this ticket.

## 11. Open points (non-blocking)

- [ ] **Prod assignment lists** — who holds `SCRUM471_KeyAccount_Set` in Prod-Org is a release
      decision (owner @devops-agent at Release; the PO/user must confirm the named colleagues).
      Not a design gap; the read-back requirement of §3 applies in Prod too.
- [ ] **Label wording** — "Key Account" kept as the user's own wording; the org's labels are
      German elsewhere ("Wartungsvertrag", "Gesperrt"). Cosmetic, PO decides; the API name
      `Is_Key_Account__c` is not affected.
- [ ] **Sales/Support/Marketing tabs** — the delta adds the item to all four Account layouts.
      If the user wants it on the default page only, that is a smaller delta, not a bigger one.

## 12. Pre-handoff checklist (own requirement, complete)

- Data model changes: §1 (one Checkbox, name-collision measured)
- Permission Set / FLS design: §3 + §5 (two PSs, explicit `fieldPermissions`, no Profile edit)
- Sharing model impact: §4 ("no impact", stated, not implied)
- Governor-limit risks: §8
- Flow apiVersion / naming convention: n/a — no Flow (ADR: rejected, reason given)
- Technical acceptance criteria: §7 (+ §9 counts)
