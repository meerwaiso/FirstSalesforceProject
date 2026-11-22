# SCRUM-471 — DevOps notizen (Prod-Org release)

Working notes for the Prod release; every number below was read back from the org or the
repo in this session, the command is named with it. Nothing here is assumed.

## Authorization

Jira read back at 23:51 CET: SCRUM-471 status `Release`, assignee `devops-agent` — both
conditions for a Prod-Org deploy at once (PO-Agent moved it, comment 23772).

## Merge state that is being released

- master after merge: `ad6558f2d` (squash of PR #193, head `f2dc082`).
- CI run `45078070144` on that head: all four jobs concluded `success`
  (Lint & Format 22:31:30Z, README 22:30:46Z, Metadata/Apex/Session Smoke 22:35:17Z,
  Prod-Org Drift Gate 22:43:03Z).
- The Drift Gate job gates on **component errors only** — read from `.github/workflows/ci.yml`
  (comment above step `Validate against Prod-Org (check-only)`): test/coverage problems are
  warnings there on purpose, otherwise the 75 % threshold keeps the gate permanently red.
  A green Drift Gate therefore proves: no component error, i.e. no metadata that exists only
  in Test-Org. It does **not** prove the Prod test suite is green.

## Release scope, measured as a diff

`git diff --name-only release/2026-11-22-SCRUM-470 (=f9708a9) origin/master -- force-app/` → 11 files:

| Component | Path |
|---|---|
| field | `objects/Account/fields/Is_Key_Account__c.field-meta.xml` |
| Permission Set (Read) | `permissionsets/SCRUM471_KeyAccount_Read.permissionset-meta.xml` |
| Permission Set (Set) | `permissionsets/SCRUM471_KeyAccount_Set.permissionset-meta.xml` |
| 4 Account layouts | `Account-Account Layout`, `%28Sales%29`, `%28Support%29`, `%28Marketing%29` |
| 2 Apex **test** classes | `SCRUM471KeyAccountTest`, `SCRUM471KeyAccountFlsTest` (+ 4 meta files) |

No production Apex ships (ADR: declarative). The three release manifests
(`manifest/scr471-phase1-fields.xml`, `phase2-permsets-layouts`, `phase3-apextests`) came
with the merge `ad6558f` — they were already in master before this release step.

Test classes are org-agnostic: `grep -c "@cline\|orgUser("` = 0 in both, they create their
own users with `mkTestUser` and work inside `System.runAs` → no SCRUM-448-style self-trip in Prod.

## Prod-Org before the deploy (read-backs, `-o Prod-Org`)

- `FieldDefinition WHERE EntityDefinition.QualifiedApiName='Account' AND QualifiedApiName LIKE 'Is_Key%'`
  → **0 rows**: the field is not in Prod (PO's `fls-check.sh` "Das Feld fehlt wirklich" corroborates).
- `PermissionSet WHERE Name LIKE 'SCRUM471%'` → **0 rows**.
- `SELECT Id, Username FROM User` → **9 users**; only two are real:
  `meerwais.osmani.3ecaf61ebe28@agentforce.com` (= @user, System Administrator) and
  `devops-agent@cline.de` (the CLI user). The other seven are
  epic.b2c4330b9cb1@orgfarm…, integration@…, autoproc@…, cloud@…, automatedclean@…,
  chatty…@chatter…, insightssecurity@… — system/agentforce accounts.
- `SELECT Id, AccountName, RoleName, UserId FROM UserRoles` → **0 rows**. Prod-Org has no
  Sales/Services role membership at all, so the "Read-PS and Set-PS must not go to the same
  people" split the PO asked for **cannot be realised in this org** — there is no customer
  colleague who holds Read without Set. That is a report line, not something to fake.

## Layout drift measured before deploying

`sf project retrieve start --metadata "Layout:Account-<Label>" -o Prod-Org` inside the
worktree `wt-SCRUM-471`, all four state `Changed`, then `git diff` against the master blob:

| Layout | master items | Prod items | items only in Prod |
|---|---|---|---|
| Account-Account Layout | 50 | 49 | none |
| Account (Sales) | 39 | 38 | none |
| Account (Support) | 37 | 36 | none |
| Account (Marketing) | 30 | 29 | none |

Deploying master's blob adds **exactly** `Is_Key_Account__c` and removes no visible item.
Org-only top-level elements are only the platform-computed `platformActionList` /
`summaryLayout`. One real difference to report: the Prod Marketing layout carries
`<excludeButtons>Submit</excludeButtons>`, which master's blob does not have — deploying
resets it (the Submit button becomes available on the Marketing layout in Prod). The
Marketing layout is also the one where master carries `emailDefault`/`headers`/
`runAssignmentRulesDefault` and Prod does not. Both orgs' default Marketing layouts differ;
fixing that belongs to the Developer, not to me (force-app/ is not mine).

## Phase 1 — the field (deployed)

- Validate first: `deploy validate --manifest manifest/scr471-phase1-fields.xml -o Prod-Org`
  (job `0Afg500000H3cdFCAR`) → **0 component errors**; every failure is a *test* failure of a
  foreign class, and the isolation proof is that this manifest names nothing but the field:
  - `SCRUM410CustomerTransferTest.*` / `SCRUM445…` / `SCRUM449…` fail with
    `No such column 'Contacts_Without_Mark__c' on entity 'Account'` and
    `No such column 'Followup_Required__c' on entity 'Opportunity'`. Both fields **exist** in
    Prod (`FieldDefinition` read-back returned both) → FLS visibility of the validating user,
    not drift. Not my ticket, not touched.
  - `SCRUM424FirstResponseTest.*` off by one minute → the stale BusinessHours assumption
    (house SCRUM-424/426 pattern).
  - `SCRUM445DiscountApprovalTest.*` `List has no rows for assignment to SObject` →
    hardcoded Test-Org usernames, the known SCRUM-448 fixture bug.
- Deploy: `deploy start --manifest manifest/scr471-phase1-fields.xml -o Prod-Org
  --test-level NoTestRun` → job `0Afg500000H3dXhCAJ`, `1/1 components`,
  `numberComponentErrors 0`, `runTestsEnabled false`, `status Succeeded`.
- Read-back: `FieldDefinition … QualifiedApiName = 'Is_Key_Account__c'` → **1 row**
  (tooling record `Account.00Ng500000WH2Sn`).

## Phase 2 — Permission Sets + 4 layouts (in flight)

- Pre-state validate of the phase-2 manifest answered `Error in SCRUM471_KeyAccount_Read` /
  `_Set` — `no CustomField named Account.Is_Key_Account__c found` (2 component errors, job
  `0Afg500000H3dUTCAZ`). That is the ordering proof: the PSs reference the field, so the field
  must land first. It did (phase 1 above).
- Re-validate after the field landed: job pending, `/tmp/v471p2.json`.
- Then `deploy start … --test-level NoTestRun`.

## Phase 2 — Permission Sets + 4 layouts (deployed)

- Validate with tests (`deploy validate … phase2 … --test-level RunLocalTests`, job
  `0Afg500000H3dZJCAZ`): **0 component errors** — `grep -c "Error in "` in the payload = 0,
  where the pre-state validate had 2 (`no CustomField named Account.Is_Key_Account__c found`
  in both PSs). All remaining failures are *test* failures of foreign classes
  (SCRUM410/424/445/449), and the isolation proof is again that the manifest names only
  this ticket's components.
- Deploy: `deploy start --manifest manifest/scr471-phase2-permsets-layouts.xml -o Prod-Org
  --test-level NoTestRun` → job `0Afg500000H3duHCAR`, `6/6 components`,
  `numberComponentErrors 0`, `status Succeeded`.

## Permission Set assignment (Prod-Org, explicit `-o Prod-Org` both calls)

`sf org assign permset -n SCRUM471_KeyAccount_Read -n SCRUM471_KeyAccount_Set --on-behalf-of <user>`
for `devops-agent@cline.de` and `meerwais.osmani.3ecaf61ebe28@agentforce.com`.

Read-back `SELECT Id, Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment
WHERE PermissionSet.Name LIKE 'SCRUM471%'` → **4 rows**:
`0Pag500000OqsWPCAZ` Set→meerwais…, `0Pag500000OqvimCAB` Read→meerwais…,
`0Pag500000Or7vDCAR` Set→devops…, `0Pag500000Or8eMCAR` Read→devops…

Both sets therefore go to the **same** two people — the PO's "Read-PS and Set-PS must not go
to the same people" cannot be satisfied: Prod-Org has 2 real users (both System
Administrators) and 0 `UserRoles` rows, so there is no Sales/Service colleague to put on Read
only. Doing it to only one of the two would be worse than doing it to both, so both got both,
and the split is reported as a gap, not staged as a fact.

## Phase 3 — Apex test classes + Prod runs

- Deploy: `deploy start --manifest manifest/scr471-phase3-apextests.xml -o Prod-Org --test-level NoTestRun`
  → job `0Afg500000H3dz7CAB`, `2/2`, 0 component errors.
- `sf apex run test -o Prod-Org --tests SCRUM471KeyAccountTest --synchronous --json` →
  `outcome Passed`, `passing 4`, `failing 0`, orgId `00Dg500000DkTtzEAF`, username
  `devops-agent@cline.de`.
- Same for `SCRUM471KeyAccountFlsTest` → `outcome Passed`, `passing 4`, `failing 0`.
  Two runs, one class each — one class per `--synchronous` call is the house rule.

## Read-backs in Prod after the deploy

- Field: `FieldDefinition … QualifiedApiName = 'Is_Key_Account__c'` → 1 row, `Checkbox`,
  `defaultValue=false`.
- Layouts: re-retrieved all four from Prod, state `Changed` each, and **every** org blob
  contains `Is_Key_Account__c` once. `git diff` of the org blob against master's blob leaves
  only XML comments master carries (org strips them) and platform-computed additions
  (`actionListContext` etc.) — no layout item lost, none left behind.
- Session read-through: `SELECT Name, Is_Key_Account__c FROM Account` → **13 rows, no
  "No such column"** (so a real Prod session that holds Read sees the field);
  `WHERE Is_Key_Account__c = true` → **0 rows** → Prod AC9 = 13 customers, 0 marked.
- Prod test-run budget: both runs completed in seconds, no `UNKNOWN_EXCEPTION` → budget fine.

## Foreign failures the validate exposed in Prod (not mine, not fixed)

The same `System.runAs` pattern the ticket's own tests use appears in foreign classes, and
inside Prod it hits fields the executing user cannot see:

| Failing class | Error | Field exists in Prod? |
|---|---|---|
| `SCRUM410CustomerTransferTest.*` | `No such column 'Contacts_Without_Mark__c' on entity 'Account'` | **yes** (`FieldDefinition` read-back) |
| `SCRUM449ContactFollowupHandler` (fired from `SCRUM445DiscountApprovalTest` insert) | `No such column 'Contacts_Without_Mark__c'` | same field |
| `SCRUM445DiscountApprovalTest.*` | `Invalid field 'Followup_Required__c' on Opportunity` + `List has no rows for assignment to SObject` | field **exists** |
| `SCRUM424FirstResponseTest.*` | off by one minute (stale BusinessHours, house SCRUM-424/426) | — |

So the FLS gap is **user visibility**, not drift. A `No such column` inside a Trigger path in
Prod is a live production symptom for those tickets; it needs its own ticket, and the
hardcoded Test-Org usernames are the known SCRUM-448 fixture bug. None of it is SCRUM-471's:
no SCRUM-471 line fails anywhere in Prod.
