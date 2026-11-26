# SCRUM-482 — Tester notizen (measured 2026-11-26, Tester-agent)

Jeder Wert unten wurde gelesen back; keine Number ist ein Gedächtpreparade.
Zitat der verbatimen Class- und PS-Names: `SCRUM477StageDaysReadTest`,
`SCRUM477CurrentStageDaysFlsTest`, `SCRUM477_CurrentStageDays_Read`.

## Apex run in Test-Org (own runs, nicht der Developer report)

- Run 1: job `0AfWU00000dRkgD0AS` — Succeeded, 2 components, 5 tests total / 5 completed / 0 errors.
- Run 2 (same head, re-run): job `0AfWU00000dRcdq0AC` — Succeeded, numTestsRun 5, numFailures 0.
  Method names both runs: `newOpenDeal_showsZeroDays`, `stageChange_restartsTheCount`,
  `closedDeal_carriesNoNumber`, `holderReadsTheCounter_nobodyWritesIt`,
  `withoutPermissionSet_theNumberIsNotReadable`.
- Teardown read back after the runs: 0 records `TEST-SCRUM-482%`, 0 users `Scr482Fls%`.
- Test budget before the runs: 23 ApexTestQueueItem rows in 24 h (ceiling max(500, 10 x classes)).

## Org facts read back on 2026-11-26

- `scripts/fls-check.sh Opportunity Stage_Days_In_Current_Stage__c` Test-Org: field exists,
  Formula (Number); granted by `SCRUM477_CurrentStageDays_Read` (read=true, edit=false);
  4 holders (devops-agent@cline.test, meerwais.osmani@..., integration@..., insightssecurity@...).
- Same command, Prod-Org: field exists, same PS; 5 holders (integration@..., devops-agent@cline.de,
  meerwais.osmani.3ecaf61ebe28@agentforce.com, insightssecurity@..., epic.b2c4330b9cb1@orgfarm...).
- PS assignment count re-read in Test-Org: 4 (unchanged, no new grant).
- `SELECT Name FROM ApexClass WHERE Name LIKE 'SCRUM477%'` (Tooling, -t):
  Test-Org 2 rows, Prod-Org 1 row — `SCRUM477CurrentStageDaysFlsTest` absent in Prod.
  Open release obligation (manifest/scr482-test.xml), not a Tester fix.

## CI on the PR head

- `gh run view 45832115073` status completed, conclusion success, headSha 036eca82dd08121feaba51d5c36615e794197f2c.
- All five jobs success: Lint & Format (advisory), README aus Release Notes,
  Metadata Apex & Session Smoke, Apex tests independent of the org, Prod-Org Drift Gate.

## Hygiene isolation measured on the sources (branch head 036eca8)

- `python3 scripts/test-hygiene-gate.py --files <both classes>`: 0 findings ("no org-dependent test").
  Same gate on master was 5 findings on the old classes (Architect measurement).
- SeeAllData appears only in header comment lines (L3, L16 / L3, L7).
- Every SOQL: `WHERE Id = :id` / `WHERE Id IN :ids` / `WHERE Id = :fresh.Id` / `WHERE Id = :fixtureId`;
  no `FROM User`; the only system queries are `Profile` and `PermissionSet`.
- Date literals in the two classes: 3 lines, all comments (`measured 2026-11-26`, two `@date 2026-11-26`).
  No date constant in any assertion; every expectation derives from the fixture anchor
  via `daysBetween(Date.today())`.
- Assertion counts: 13 in the counter class, 9 in the FLS class.

## E2E regression of the SCRUM-477 behaviour (Test-Org)

- `npm run test:e2e:smoke`: 2 passed (17.4 s) — session layer fine before the spec.
- `npm run test:e2e -- tests/e2e/SCRUM-477-tage-jetzige-stage.spec.ts`: see e2e-477 log / coverage table.

## Open items nach dem Test run

- AC2 Prod verdict: CI Prod-Org Drift Gate success at this head; the Tester never runs Apex in Prod-Org.
  The FLS class precondition (`Permission Set ... is deployed`) holds in both orgs (PS read back above).
- T2 ">30 days" magnitude: not producible on a self-created fixture (CreatedDate / LastStageChangeDate
  createable:false in both orgs); observed at the UI layer by the SCRUM-477 spec instead.
- `SCRUM477CurrentStageDaysFlsTest` orphan in Prod: DevOps obligation at Release.
