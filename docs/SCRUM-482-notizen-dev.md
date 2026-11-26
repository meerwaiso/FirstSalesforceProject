# SCRUM-482 notizen (Developer, 2026-11-26) — hard-won findings, one line each

- Worktree: `git worktree add <path> feature/SCRUM-482-stage-days-test-fixtures` (the branch
  already carried the Architect's design commit `0a791c6`; the shared checkout sits on
  `feature/SCRUM-424-first-response` and holds other tickets' files — never touched).
- `python3 scripts/test-hygiene-gate.py --files <the two rebuilt .cls>` → **green, 0 findings**
  (was 5 `SeeAllData` findings on the old sources). Re-run on the branch after the rebuild.
- `git diff origin/master -- <field> <PS> <report>` → **empty** (AC6: field, Permission Set and
  report untouched).
- Fixture shapes checked against the live validation rules on master (all eight Opportunity
  rules read): Closed Won with blank `Discount_in_Pct__c` clears `No_Won_Without_Approval`
  (`Discount_in_Pct__c > 0.15` is false) and `Discount_Hard_Cap_25`; Closed Lost needs
  `Loss_Reason__c` — picklist value `KeinBudget` is live (`grep <value> .../Loss_Reason__c.field-meta.xml`),
  `Wettbewerber` would additionally need `Competitor_Lost_To__c` (avoided).
- Stage transition for the restart criterion: `Prospecting → Value Proposition`, both open
  (`sf sobject describe` picklist values in the Architect notes), so the record stays on the
  stuck list and the closed-stage rules stay out of the way.
- `readBack()` is a query, never the in-memory SObject: a formula field is not populated by DML
  (house note SCRUM-403). Every read-back asserts `rows.size() == 1`, so a fixture that was never
  created cannot pass.
- ADR-6 deviation, teardown: class 1 deletes its own Opportunities at the end of each method
  (System context, same object type — compiles and runs green). Class 2 does not delete its
  Users/PSAs: `delete` on a User (a setup object) after Opportunity DML in the same transaction
  is the SCRUM-442 MIXED_DML shape, so it would need its own transaction; with `SeeAllData=false`
  nothing a test creates is ever committed to the org, and the leftover check below proves it.
  UNVERIFIED half: that the delete itself would have been rejected — never attempted.

## Measurement pending (deploy + test run, Test-Org)

- Command: `sf project deploy validate --manifest manifest/scr482-test.xml -o Test-Org
  -l RunSpecifiedTests -t SCRUM477StageDaysReadTest -t SCRUM477CurrentStageDaysFlsTest`
  (validate's own default is `RunLocalTests` = the whole local suite, never that).
- Attempt 1 FAILED, compile error (3x): `DML requires SObject or SObject list type: List<Id>` —
  `delete` needs a list of SObjects, not a list of Ids. Fixed by keeping `List<Opportunity>` for
  the delete and a separate `List<Id>` for the `WHERE Id IN :ids` bind.
- Attempt 2 (validate) SUCCEEDED, job 0AfWU00000dRjSP0A0: Components 2/2, Tests Successful 5/5.
- `sf project deploy start --manifest manifest/scr482-test.xml -o Test-Org -l RunSpecifiedTests
  -t SCRUM477StageDaysReadTest -t SCRUM477CurrentStageDaysFlsTest` → Status: Succeeded, job
  0AfWU00000dRjVd0AK, Deployed Source = both .cls + both -meta.xml (State: Changed),
  Test Results Summary Passing: 5, Failing: 0, Total: 5, Time 6499 ms.
  Five methods ran = the 3 of class 1 plus the 2 of class 2, so no method was silently skipped.
- Leftovers read back in Test-Org after the run: `SELECT Id, LastName FROM User WHERE LastName
  LIKE 'Scr482Fls%'` → 0 records; `SELECT Id, Name FROM Opportunity WHERE Name LIKE
  'TEST-SCRUM-482%'` → 0 records (note: that query needs the plain data-query route — via
  `--use-tooling-api` the Tooling API answers "sObject type 'Opportunity' is not supported").
- Not measured by me: the same run in Prod-Org. That is the Prod-Org Drift Gate's job on the PR
  head (the classes are not deployed to Prod by me — Developer deploys to Test-Org only).

## Round 3 (Architect's rejection of round 2: right code, wrong place — head 8dbda39, 2026-11-26)

- The rejection was about placement, not code: PR #202 merged at 14:33 CET at head e106432 (3 methods in the
  counter class). My round-2 push went to the ALREADY-MERGED branch, so head 4c6c5c3 got no PR and no CI
  (Architect measured: merge-base not an ancestor, 0 runs). Lesson: check the merge state of the PR before
  pushing another round to its branch — a merged PR means a new branch cut from master, one branch per ticket
  round only while the PR is open.
- New branch feature/SCRUM-482-t2-aged-deal-proof cut from master (c3808d9), head 8dbda39, PR #204 (base master).
  Diff vs master: the counter class (4 methods incl. agedOpenDeal_showsTheAgedDays_andAStageChangeRestartsThem),
  the design doc with the corrected ADR-3, both notes. master's README/release-note files from PR #203 are kept
  — copying the whole old branch tree would have deleted them, so I copied four paths, not a tree.
- Read-back org vs branch (round 3): validate/dry run showed SCRUM477StageDaysReadTest State: Changed, deploy
  start Succeeded, Test Results Summary Passing 6 / Failing 0 / Total 6, 7008 ms, 0 records TEST-SCRUM-482%.
  `sf project retrieve start --metadata ApexClass:SCRUM477StageDaysReadTest -o Test-Org` (inside the project,
  -r ./retrieve-482) returns the SAME 4-method source: the diff against the branch file differs only in the
  final newline. Org == branch, verified.
- CLI flag traps on retrieve (measured): `--target-dir` does not exist (Nonexistent flag) — the flag is
  `-r, --output-dir`, and it refuses a path outside the project root
  (OutputDirOutsideProjectError). And retrieving into /tmp is a trap: @devops-agent had retrieved the SAME
  class name from Prod-Org there, so a diff against the leftover /tmp file reads as "the org lacks the method"
  when it is really the other org's stale copy. Retrieve inside the project and delete the dir.
- Not mine: the Prod-Org run of 6 methods (Prod still has the 3-method class — the release read-back with 6
  needs DevOps re-authorization in Release). CI on head 8dbda39: PR #204 run started, verdict read from gh.
- Cleanup: worktree wt-482b removed after the handoff; retrieve-482 dir deleted before the last commit.

## Round 2 (Architect's design correction, head cc998f9, 2026-11-26)

- The Architect's correction holds and I measured it myself: `Test.setCreatedDate(<Id>,
  Datetime.now().addDays(-40))` after the insert ages a test fixture, and the counter read back
  through `WHERE Id = :fixtureId` answered **exactly 40** (assertion `assertEquals((Double) 40,
  counter)` green). `LastStageChangeDate` stays null on a fresh fixture, so the formula takes the
  `CreatedDate` branch — the precondition the user named. My ADR-3 summary line above ("a record a
  test creates can never be 31+ days old") is superseded by this measurement; the magnitude IS
  automated now (T2 method `agedOpenDeal_showsTheAgedDays_andAStageChangeRestartsThem`).
- Still unreachable, and asserted nowhere: an aged STAGE CHANGE — `LastStageChangeDate` is refused
  at compile time (`Field is not writeable`), so the anchor switch is proven at 0 days only
  (fixture aged by creation, then stage moved → counter back to 0).
- Apex compile trap that bit me twice in this ticket: `delete` needs a list of SObjects, a
  `List<Id>` does not compile; and an unescaped apostrophe inside a single-quoted Apex string
  literal (`'... THIS record's anchor ...'`) closes the literal and turns the whole rest of the
  class into garbage (313 component errors from ONE bad quote). The deploy report names the line
  and column — read it, do not re-theorise. Rephrase or escape, never nest a bare apostrophe.
