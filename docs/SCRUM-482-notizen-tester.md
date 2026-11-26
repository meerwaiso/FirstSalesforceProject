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
- Run 1 (`npm run test:e2e -- tests/e2e/SCRUM-477-tage-jetzige-stage.spec.ts`): 8 passed, 1 failed, 2.9 min.
  Observed: report SOQL 61 = UI Total 61; groups 145 (12 rows) and 72 (12 rows); record pages 41 and 145 days;
  AC8 edit affordance counter 0 vs Stage 1; AC7 closed aged over 30 = 52, closed with a number = 0.
- The red test was AC10 (`AsyncApexJobs grew by 1`). Attributed by reading the org: the job in the save window
  was `JobType = TestRequest`, ApexClassId `01pWU00000TnyGrYAJ` = SCRUM477CurrentStageDaysFlsTest — a concurrent
  Apex test run (CI job "Apex tests independent of the org", started 14:01:51Z), not a side effect of the save.
- Run 2 of the same spec (same head, minutes later): file-level preflight red, 1 of 7 preconditions unmet —
  AC3 asks for an aged open record in Qualification, found 0. Cause measured: run 1 moved exactly that record
  (Dickenson Mobile Generators) Qualification → Prospecting. The SCRUM-477 spec consumes its org fixtures
  and is not replayable the same day. Never re-run a fixture-consuming E2E spec to "confirm green".
- HTML reports copied out of the worktree before teardown:
  cache/e2e-reports/SCRUM-482-20261126-run1 and -run2 (index.html + playwright-results.json).

## Open items nach dem Test run

- AC2 Prod verdict: CI Prod-Org Drift Gate success at this head; the Tester never runs Apex in Prod-Org.
  The FLS class precondition (`Permission Set ... is deployed`) holds in both orgs (PS read back above).
- T2 ">30 days" magnitude — CORRECTED in round 3 by @user's challenge: `createable:false` only means the
  constructor cannot carry the anchor. `Test.setCreatedDate(recordId, Datetime.now().addDays(-40))` after
  the insert does age a test fixture (house precedent SCRUM398EskalationsstufeTest L42,
  SCRUM424FirstResponseTest L62), and on a fresh insert `LastStageChangeDate` reads back null, so the
  formula takes the CreatedDate branch. The magnitude IS automated now (Observed 40 in round 3).
  Still impossible: an aged STAGE CHANGE — `LastStageChangeDate` is refused at compile time
  ("Field is not writeable"), so the anchor switch is provable at 0 days only.
- `SCRUM477CurrentStageDaysFlsTest` orphan in Prod: DevOps obligation at Release.

## Round 3 — head e3a88e6, branch feature/SCRUM-482-t2-aged-deal-proof (PR #204)

- Head verified before testing: `git diff --name-only origin/master...origin/feature/SCRUM-482-t2-aged-deal-proof`
  = 4 files (3 docs + `force-app/main/default/classes/SCRUM477StageDaysReadTest.cls`); no metadata XML, no
  `.github/workflows/` file. Worktree `../wt-SCRUM-482-r3`.
- Deployed the two classes FROM THIS HEAD into Test-Org (`--test-level RunSpecifiedTests`, both classes,
  zipFileCount 5, 2 components) and ran them twice on the same source:
  job `0AfWU00000dRvyD0AS` Succeeded 6 run / 0 failures (ms: holder 3459, blind 2224, agedOpenDeal 837, closed 312, new 291, stageChange 365)
  job `0AfWU00000dRw1R0AS` Succeeded 6 run / 0 failures (ms: holder 1879, blind 1408, agedOpenDeal 459, closed 196, new 172, stageChange 218)
- T2 method `agedOpenDeal_showsTheAgedDays_andAStageChangeRestartsThem` is the magnitude proof:
  anchor null + counter 0.0 before the backdate, `Test.setCreatedDate(aged.Id, Datetime.now().addDays(-40))`,
  CreatedDate read back at the moved anchor, `expectedAged = anchor.date().daysBetween(Date.today())` asserted == 40
  (derived from the date the test itself set — no calendar constant), then the live formula field asserted == 40.0,
  then stage update → `LastStageChangeDate` not null, daysBetween 0, counter 0.0 again. Green in both runs.
- Teardown read back: `SELECT COUNT() FROM Opportunity WHERE Name LIKE 'TEST-SCRUM-482%'` → 0.
- TRAP (measured, it produced a false "leftover 1"): `SELECT COUNT(Id) ...` returns `totalSize` 1 — the number is in
  `records[0].expr0`. `SELECT COUNT() ...` puts the number in `totalSize`. Never mix the two readings.
- Org observability read-backs (T2m half, not a test): Test-Org counter > 30 open = 58, Prod-Org = 13
  (`COUNT()` variant, CLI target-org user); PS `SCRUM477_CurrentStageDays_Read` holders 4 in Test-Org, 5 in Prod-Org
  (Tooling query `PermissionSetAssignment WHERE PermissionSetId = ...`; the field is AssigneeId/AssigneeName, not `Assignee.Name`).
- E2E SCRUM-477 spec not re-runnable on this day: round-1 saves consumed its fixtures (preflight red 1 of 7).
