# SCRUM-445 — Architektur-Design: Discount in %, Manager-Approval >15 %, Hard Cap 25 %

Basis: origin/master @ 537caaf (git fetch 2026-10-12). Alle Shapes unten dry-run-validatef against Test-Org (check-only, nothing deployed) — see docs/SCRUM-445-notizen.md.

## Ziel
Every Opportunity carries the offered discount in %; above 15 % closing as Won is blocked until the rep's direct manager approved, above 25 % never allowed; sales management sees a waiting list with duration; FLS keeps the approval state un-editable for reps.

## ADR — Apex over Flow
Apex Trigger + Handler + Queueable Notification, house pattern SCRUM-319 (OpportunityOverdueReset/Notification) and SCRUM-418. Branching (thresholds, approval-invalidation on raise), bulkification and the notification need code; Flows have repeatedly failed deploy/schema-validation here. Declarative parts (fields, ValRules, ListView, PS) stay XML. Flow not chosen: no Flow in this repo works today for logic.

## Data Model (Opportunity, standard object — no new fields exist yet in Test-Org/Prod-Org, verified via FieldDefinition)

| API name | Type | Semantics |
|---|---|---|
| `Discount_in_Pct__c` | Percent (precision 3, scale 2) | Discount offered, stored as percent value (20 = 20 %) |
| `Discount_Approval__c` | Picklist: `Pending` / `Approved` / `Rejected` | State of the approval; system sets Pending, only manager PS edits it |
| `Approval_Requested_On__c` | DateTime | Set by system when Pending is (re-)created — waiting duration starts here |
| `Approved_Discount_Value__c` | Percent (3/2) | The discount value the approval covers — raise above it invalidates, lowering does not |
| `Approval_Decided_By__c` | Lookup → User | Who decided (manager/sales mgmt); system-set |
| `Approval_Decided_On__c` | DateTime | When decided; system-set |
| `Rejection_Reason__c` | Text(120) | Manager's short reason; manager-editable |
| `Approval_Waiting_Days__c` | Number formula | `IF(ISPICKVAL(Discount_Approval__c, "Pending"), MAX(0, (NOW() - Approval_Requested_On__c)), NULL)` — dry-run green |

All dry-run-validated 2026-10-12 (Test-Org). Pitfalls already paid: enum is `DateTime` not `Datetime`; Lookup needs `<required>false</required>` (house shape: CustomerTransfer__c/From_User__c); picklist needs `valueSet/valueSetDefinition` (house: Loss_Reason__c), `valueMap` invalid; `unique` not allowed on Lookup.

## Mapping object — direct manager (Open Decision resolved by measurement)
UserRole in Test-Org: 18 standard roles, every `ForecastUserId` null → role hierarchy cannot derive the direct manager. Decision: CMOM mapping object, house shape CustomerTransfer__c:

- `DiscountApprovalManager__c` — AutoNumber name (`DM-{0000}`), sharing ReadWrite, Deployed
  - `Rep__c` — Lookup → User (the sales rep)
  - `Manager__c` — Lookup → User (their direct manager)

Sales management maintains the mapping (one record per rep). Trigger resolves owner → mapping → manager. Dry-run green. A custom Lookup on `User` itself is rejected by the platform ("Invalid data type", verified) — do not try.

## Validation Rules (Opportunity) — dry-run green

1. `Discount_Hard_Cap_25` — `Discount_in_Pct__c > 25` → every save refused (AC hard cap).
2. `No_Won_Without_Approval` —
   `AND(ISPICKVAL(StageName, "Closed Won"), Discount_in_Pct__c > 15, OR(ISBLANK(TEXT(Discount_Approval__c)), ISPICKVAL(Discount_Approval__c, "Pending"), ISPICKVAL(Discount_Approval__c, "Rejected"), Discount_in_Pct__c > Approved_Discount_Value__c))`
   Blank approved value counts as 0 → blocked. Raise above approved value → blocked (AC raise-invalidates); lower → passes (AC lowering-keeps).

## Components (paths)

1. `force-app/main/default/objects/Opportunity/fields/…` — the 8 fields above.
2. `force-app/main/default/objects/Opportunity/validationRules/Discount_Hard_Cap_25` + `No_Won_Without_Approval`.
3. `force-app/main/default/objects/DiscountApprovalManager__c/…` — mapping object + 2 fields.
4. `force-app/main/default/triggers/DiscountApprovalTrigger.trigger` + `classes/DiscountApprovalHandler.cls` — house pattern OpportunityOverdueResetHandler:
   - before-update: discount changed AND > 15 AND (no approval OR discount > `Approved_Discount_Value__c`) → set `Discount_Approval__c = Pending`, `Approval_Requested_On__c = NOW()`, collect manager target.
   - approval transition (old ≠ new, editable only via manager PS): `Approved` → `Approved_Discount_Value__c = Discount_in_Pct__c`, decision fields; `Rejected` → decision fields, reason stays.
   - one batchified SOQL for the mapping records (`IN :ownerIds`), no SOQL in loop, one `System.enqueueJob` per batch.
5. `classes/DiscountApprovalNotification.cls` (Queueable) — house pattern OpportunityOverdueNotification: FeedItem on the manager's feed ("informed without email"), `if (!Test.isRunningTest())` guard like the house class.
6. ListView `force-app/main/default/objects/Opportunity/listViews/Discount_Approval_Waiting.listView-meta.xml` — dry-run green: columns `OPPORTUNITY.NAME, ACCOUNT.NAME, CORE.USERS.ALIAS, Discount_in_Pct__c, Discount_Approval__c, Approval_Requested_On__c, Approval_Waiting_Days__c`, filter `Discount_Approval__c = Pending`. (Cross-object tokens like `OPPORTUNITY.NAME` are the house shape — Ueberfaellige_Chancen proves it; plain API names do not resolve.)
7. Permission Sets (see below) + test pair + E2E spec (Developer ships, PR gate).

## Permission Set design (FLS — never Profile; every field explicit)

| PS | Fields | editable | Assign to |
|---|---|---|---|
| `SCRUM445_Discount_Read` | all 8 fields | read-only (editable=false) | every sales-dept rep incl. non-owners + sales management |
| `SCRUM445_Discount_Owner` | `Discount_in_Pct__c` | true | opportunity owners + sales management |
| `SCRUM445_Discount_Manager` | `Discount_Approval__c`, `Rejection_Reason__c` | true | direct managers + sales management ONLY — a rep with this PS defeats the story; negative test mandatory |
| `SCRUM445_DirectManager_Map` | `DiscountApprovalManager__c` CRUD | — | sales management (mapping maintenance) |

System-set fields (`Approval_Requested_On__c`, decision fields, `Approved_Discount_Value__c`) are written by Apex in system context; FLS-wise they are read-only everywhere. Remember: a PS grants, never revokes — the negative-access AC is only enforceable because the Profile blocks (Salesforce default for new fields is profile-open; the FLS-negative test must therefore assert against the *owner/manager* PSs being absent, house rule from SCRUM-421/430).

## Sharing model
Opportunity OWD is NOT readable via any API (verified: object-info carries no sharing keys, no REST endpoint). AC "every other rep may view the record" requires OWD ≥ ReadOnly — Org-Setup precondition with mandatory read-back (Tester: non-owner rep opens record; DevOps release comment names it). Not an Apex assert (house rule SCRUM-424: org-config AC = setup precondition, else the Prod drift gate runs red forever).

## Org-Setup steps (read-back belongs in Developer handoff + DevOps release comment)
1. Opportunity OWD ≥ ReadOnly (read-back: non-owner rep sees record).
2. Mapping records for the test reps (Tester creates them).
3. ListView visible to sales management (App Builder placement if needed).

## Governor limits
Trigger batchified (1 mapping SOQL per batch, map lookups, 1 enqueueJob per batch). No SOQL in loop. Notification runs in Queueable context like SCRUM-319.

## Test obligations (PR gate, house shapes)
- Apex pair: `SCRUM445DiscountApprovalTest` (thresholds, raise/lower, hard cap, waiting duration) + `SCRUM445DiscountFlsTest` (negative: rep without Manager-PS cannot set Approved; user outside dept cannot read). Mixed-DML rule (SCRUM-442): PSA insert and business DML in SEPARATE transactions.
- E2E Playwright spec for the waiting view + blocked Closed Won (frontdoor.jsp auth, no networkidle).
- Counts: PO states none; Tester counts created records per criterion, observed 0 = untested.

## CI facts (verified 2026-10-12)
- Prod-Org drift gate gates COMPONENT findings only; new fields + test classes referencing them in ONE package → 0 component findings, test-phase "No such column in Prod-Org" = warning only. Probe run id 0Afg500000FmN4vCAF.
- cls-meta must be `<status>Active</status>` — `<active>true</active>` yields "Invalid api version:0.0" = component error = gate red.
- apiVersion for this release train: 67.0 (Prod-Org validator, SCRUM-440/442).
- Test-Org runs ONE broad Apex test run at a time; Developer uses `--test-level RunSpecifiedTests --tests SCRUM445*`.

## Open points (non-blocking)
- [ ] Mapping seed data for test reps → @tester-agent creates in Test-Org.
- [ ] Notification = FeedItem on manager feed (house pattern); if the PO wants Chatter-post instead of in-app notification, say so before Testen.
