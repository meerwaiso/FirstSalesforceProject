# SCRUM-453 — DevOps merge-station notizen (2026-10-22)

Ticket: SCRUM-453 (Story), column `Deployment`, assignee `devops-agent` — read back before the merge.
PR: #178, branch `feature/scr453-kontakt-austritt`, head `4b8bc0745acee13e1a049f5794d63f27800fa0fc`.

## Gate read-back (all four, measured before the merge)

1. **CI green on the head I merged**: run `39851247519`, `headSha` = `4b8bc07` (current PR head), event `pull_request`. All four jobs `completed success`, none skipped: Lint & Format (advisory), Metadata/Apex/Session Smoke, Prod-Org Drift Gate, README aus Release Notes.
2. **Apex really ran**: `apex-test-results` artifact `12458098322` → junit **18 tests, 0 failures, 0 errors**, classes `SCRUM453ContactLeftTest` + `SCRUM453ContactLeftFlsTest`, run id `707WU00001PE8ok` (Test-Org).
3. **Approval on record**: Jira 23561 `APPROVED (design)`, review id 5619946674, on head `2abcf6e`. Delta `2abcf6e..4b8bc07` = **only test artefacts** (`tests/e2e/SCRUM-453-kontakt-austritt.spec.ts`, `docs/SCRUM-453-notizen-tester.md`); approval head is an ancestor of the merged head → no production code changed after approval.
4. **Test verdict on record**: Jira 23562 Tester PASS — Playwright E2E 9/9, Apex 18/18, spec on head `4b8bc07`.

## Drift Gate: green job, red validate — self-trip, no foreign drift

`prod-validate` artifact `12458772206` (validate job `0Afg500000G6UlNCAV`) reports `FailedValidationError`, but the **cause is this ticket's own new field**:

- single root cause: `No such column 'Contacts_Without_Mark__c' on entity 'Account'` → `Class.SCRUM453ContactLeftHandler.recompute` line 133, `Trigger.ContactLeftGuardTrigger` line 32.
- the failing test classes are foreign (`SCRUM386LeadDuplicateTest`, `SCRUM405FirmenTelefonnummerValueTest`, `SCRUM410CustomerTransferTest`) — they insert Contacts, which fire SCRUM-453's new `ContactLeftGuardTrigger`; the trigger queries the new Account field, which exists in Test-Org and not yet in Prod-Org.
- foreign drift markers (`RypplePost`, `SCRUM319`, `Rueckruf`, `VIP_Customer`): **none**.

Expected pre-release self-trip; re-greens at the Release deploy (same shape as SCRUM-436/442/445).

## Merge

- `gh pr merge 178 --repo … --squash --match-head-commit 4b8bc07…` → `origin/master` `3d65b136508315912c5fa0212c396782bee5cc9b` → `19ff1b6771d143bafb1225cd3b1ffdd8f8ed1581`.
- **Strongest verification: `git diff --name-only 4b8bc07 19ff1b6` is EMPTY** — the merged tree is byte-identical to the CI-verified head. 34 files carried = PR `changedFiles` 34.
- Local master synced with `git fetch origin master:master`; shared working tree stayed on `feature/SCRUM-424-first-response` with foreign uncommitted files untouched.
- Feature branch NOT deleted (branch deletion is policy-gated here) — `git ls-remote` still shows `4b8bc07`.
- No master CI run by design: `ci.yml` triggers on `pull_request` + `workflow_dispatch` only; the green PR-head run IS the master verdict.

## Not yet in Prod

Prod-Org NOT touched: needs ticket in `Release` AND assigned to `devops-agent`. New Account fields (`Contacts_Without_Mark__c`, `Contacts_Left_Count__c`, `Last_Contact_Left_Date__c`), `Case.Contact_Left_Anzeige__c`, the Contact mark fields, the trigger/handler and the overview report exist in Test-Org only.

## Open items carried forward (not mine)

- AC-5 recipient-exclusion half is **SCRUM-454**, PO holds it blocked on the user's question — not covered by this story.
- Tester finding: Related tab of a marked Contact renders "No related lists to display" (AC-3 covered by the Case/Opportunity pages instead).
- Tester: UI-negative undo unsatisfiable in this org — both licences hold `SCRUM453_ContactLeft_Undo`; negative proven in Apex only.

## Release station (Prod-Org, 2026-10-23)

Authorization read back before the first write: `SCRUM-453` status `Release`, assignee `devops-agent`.

### Deploy phases (all `-o Prod-Org`, orgId `00Dg500000DkTtzEAF`)

| Phase | Manifest | Result |
|---|---|---|
| 1 fields | `manifest/scr453-phase1-fields.xml` | validate RunRelevantTests Succeeded → deploy NoTestRun 5/5 |
| 2 referencing | `manifest/scr453-phase2-referencing.xml` | validate RunRelevantTests Succeeded (13 successes, 0 errors) → deploy NoTestRun 12/12 |
| 3+4 Apex | `manifest/scr453-release-apex.xml` (mine: handler + trigger + 2 test classes) | deploy NoTestRun Succeeded |

**Pitfall — the Apex phase cannot be pre-validated green.** `deploy validate` always runs Apex tests (`NoTestRun` is rejected by `validate`, only `start` accepts it), and Prod has 0 % coverage of a brand-new handler/trigger: `Test coverage of selected Apex Class is 0%, at least 75% test coverage is required`. A manifest that names the tests does not help — coverage is measured in the org, and the tests are not in the org yet. House 3-phase pattern (SCRUM-451/442/445) is the only way through: deploy `NoTestRun`, then `sf apex run test -o Prod-Org --tests <class>` separately.

**Pitfall — `sf apex run test --synchronous` takes ONE class.** Two `--tests` with `--synchronous` → `Synchronous test runs can include test methods from only one Apex class`. Run one class per call.

### Prod result

- Apex in Prod-Org: `SCRUM453ContactLeftTest` 11/11 Passed, `SCRUM453ContactLeftFlsTest` 7/7 Passed → **18/18 green**.
- Live in Prod, read back: 3 Account aggregates (FieldDefinition), `Case.Contact_Left_Anzeige__c`, `Contact.Has_Left_Company__c` / `Left_Company_Date__c` / `Contact_Status_Anzeige__c`, `ContactLeftGuardTrigger`, and `sf project retrieve start` pulled the 3 ListViews + `Sales/Kunde_ohne_Kontaktperson` Report out of the org.
- **Not measurable in Prod:** `Account WHERE Contacts_Left_Count__c > 0` → 0 records. No marked Contact in Prod; the PO's counts were Test-Org.
- Tag `release/2026-10-23-SCRUM-453` on `19ff1b6` — read back with `git cat-file -p "$(git rev-parse refs/tags/…)"` → `object 19ff1b6…`.

### The missing half of a foreign PS cost 11 red tests

First Prod test run: 11/11 functional tests died with `Operation failed due to fields being inaccessible on Sobject Contact` at `seedHistory` line 109 (`insert c` with `NewsletterConsent__c`/`ConsentDate__c`). Cause measured, not guessed: `SCRUM359_NewsletterConsent` had **0 `PermissionSetAssignment` rows in Prod** but was assigned to `devops-agent@cline.test` in Test-Org — that is why the same suite was green there. Assigning it to the two real Prod users turned 11 red into 11 green. Same for `SCRUM451_TestObjectAccess` (my own SCRUM-451 release had left it unassigned in Prod).

Rule that follows: before running a foreign-dependent test class in a new org, query `PermissionSetAssignment` for EVERY PS the test grants — a PS that is deployed but assigned to nobody is invisible until the test dies.

### Post-release CI (master, workflow_dispatch run `39913977537`)

- **Prod-Org Drift Gate: success** — the pre-release self-trip re-greened, as predicted.
- **Smoke: failure**, 456 org tests in Test-Org, 5 red — all foreign to SCRUM-453's own classes:
  - 3 × `SCRUM410CustomerTransferTest`: this release's trigger runs `recompute` after every Contact insert; the Account SELECT at handler line 133 is unguarded, so an insert by a user without the PS aborts with `System.QueryException: No such column 'Contacts_Without_Mark__c' on entity Account`. Filed as **SCRUM-455** (developer-agent) — a functional regression in BOTH orgs, not a test artefact.
  - `SCRUM434Probe.openCaseInRunAs_triggersMustNotBreak` + `SCRUM403LastCaseDateTest.existingCase_showsDateAndHumanDuration` — already SCRUM-452.
