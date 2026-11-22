# SCRUM-470 — DevOps-Notizen (merge-Station)

Messung per DevOps-Agent, 22.11.2026. Each value read back, not assumed.

## Gate measurement (before merge)

- Ticket: SCRUM-470 status `Deployment`, assignee `devops-agent` (jira_get_issue, updated 2026-11-22 20:06:26).
- PR #191 `feature/SCRUM-470-preferred-contact` -> `master`; remote head `baa77c6c8c94c7ba12199e719422ee752da3ed9a` (git ls-remote origin).
- CI run `45057073901` head_sha = `baa77c6…` = PR head at merge time. Jobs (gh api runs/…/jobs):
  - `Lint & Format (advisory)` success (job 137314553110)
  - `Metadata, Apex & Session Smoke` success (job 137314553454) — steps `Determine Apex test scope`, `FLS gate …`, `Run Apex tests`, `Validate metadata (check-only, advisory)`, `Playwright session smoke` all **completed success**, not skipped
  - `Prod-Org Drift Gate` success (job 137314553340) — step `Validate against Prod-Org (check-only)` completed success; `Cancel a Prod-Org validation …` skipped (no leftover run = clean)
  - `README aus Release Notes` success (job 137314553309)
- Approval: Jira comment 23757 = Architect-Agent **approved** on head `2e53e45`; GitHub review id 6013572535 is `COMMENTED` (shared account -> no machine-readable APPROVED).
- Approval still carries the merged code: `git diff --name-status 2e53e45 baa77c6` = `A docs/SCRUM-470-notizen-tester.md`, `A tests/e2e/SCRUM-470-preferred-contact-way.spec.ts` only; `git merge-base --is-ancestor 2e53e45 baa77c6` = YES. No force-app file in the delta.
- Test verdict on record: Jira comment 23758 (Tester-Agent, E2E 6/6, Apex 11/11, 3 of 680 Contacts carry a value).

## Branch facts

- PR diff vs `origin/master` (`48ee748`): 14 files = PR `changedFiles` 14.
- 1 new field (`Contact.Preferred_Contact_Method__c` picklist), 1 Permission Set (`SCRUM470_ContactContactWay`), 1 layout edit (`Contact-Contact Layout.layout-meta.xml`), 2 test classes, 3 phase manifests, 4 docs/spec files.

## Prod-Release facts (for the release deploy after PO)

- The field + PS + layout are live in Test-Org only. Prod-Org does not know `Preferred_Contact_Method__c` yet -> pre-release Drift Gate self-trip expectation until the release deploy (skill pattern SCRUM-436/442/445).
- Prod deploy order mirrors the branch manifests: phase1 field -> phase2 PS + layout (PS must be **assigned**, read-back via PermissionSetAssignment) -> phase3 Apex test classes.
