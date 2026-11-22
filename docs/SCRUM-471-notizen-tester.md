# SCRUM-471 — Tester notizen (Test-Org, 2026-11-22)

Verifierte Befund per Line; je Line steht der Command/Probe, der's geholt hat.

## Render path / DOM facts (Account record page, Details tab)

- Aria line of the mark (page-level `page.ariaSnapshot()`, closed shadow roots —
  `document.body.innerText` sees none of the Details fields):
  `- text: Key Account True Key Account` — a Checkbox renders **True/False**, NOT Yes/No.
  Probe: `scratch/probe471b.mjs` on Account 001WU00002LqtMhYAJ, marked via CLI.
- First Details section, measured order: **Account Name, Phone, Key Account,
  Parent Account, Website**. Next section heading is `heading "Wartungsvertrag" [level=3]`
  (snapshot line 180) — the mark sits at line 128, i.e. in the section with the name.
- `page.getByRole('button', { name: 'Edit Key Account' })` → count 1 on the Details tab.
- In inline edit mode the mark is exactly **one** `input[name="Is_Key_Account__c"]`
  type=checkbox; `.click()` toggles `checked` (true → false measured);
  bounding box top **536 px of a 720 px viewport** → above the fold. Probe: `scratch/probe471c.mjs`.
- `page.getByLabel('Key Account', {exact:true})` → count **0** on the read-only Details tab
  (labels there are text nodes, no form controls). Use `getByText(label, {exact:true})`:
  'Account Name' → 1, 'Key Account' → 2 (label + checkbox accessible name).
- `/lightning/o/Account/new`: the mark is offered as `- checkbox "Key Account"` →
  `getByRole('checkbox', {name:'Key Account'})` count 1; the control needs ~2.5 s
  after `.slds-global-header` before it exists. Probe: `scratch/probe471.mjs`.

## Org counts (measured 2026-11-22, `sf data query --target-org Test-Org --json`)

| query | totalSize |
|---|---|
| SELECT COUNT() FROM Account | 251 |
| ... WHERE Is_Key_Account__c = true | 0 |
| ... WHERE Is_Key_Account__c = false | 251 |
| SELECT COUNT() FROM Case | 681 |
| SELECT COUNT() FROM Opportunity | 157 |
| SELECT COUNT() FROM EmailMessage | 0 (VACUOUS: no records in the org) |
| SELECT COUNT() FROM Task | 0 (VACUOUS) |

## Permissions (scripts/fls-check.sh Account Is_Key_Account__c)

- Field exists (Checkbox). Read granted by SCRUM471_KeyAccount_Read (edit=false),
  SCRUM471_KeyAccount_Set (edit=true), AncCrmIntegrationUser (edit=false, **assigned to nobody**).
- Both PSs assigned to exactly 2 users: `devops-agent@cline.test` and
  `meerwais.osmani@resourceful-bear-6f1u4j.com` — **both hold Read AND Set**.
  Consequence measured, not assumed: there is no real Read-only colleague in Test-Org,
  so the AC5 read-but-cannot-edit negative exists only as a test-local user
  (`System.runAs` on the Standard User profile). The browser session user IS
  `devops-agent@cline.test` → it can edit the mark, a UI negative is impossible
  (2/2 licences, both System Administrators).

## Apex run (my own re-run of the branch classes)

`sf project deploy start --source-dir <both SCRUM471*Test.cls> -l RunSpecifiedTests
--tests SCRUM471KeyAccountTest SCRUM471KeyAccountFlsTest --target-org Test-Org --json`
→ status Succeeded, numberTestsTotal 8, numberTestsCompleted 8, numberTestErrors 0,
runTestsEnabled true. Report JSON: `scratch/apex471.json` (session scratch dir).

## Playwright-in-a-worktree gotcha

`npm run test:e2e:smoke` in a fresh worktree fails `error: unknown command 'test'` —
the worktree has no node_modules. Fix: `ln -s ../FirstSalesforceProject/node_modules node_modules`
(.gitignore already covers `node_modules/`). Probe scripts read `auth/storage-state.json`
relative to the CWD (worktree root), not relative to `scratch/`.
