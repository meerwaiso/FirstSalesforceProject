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
