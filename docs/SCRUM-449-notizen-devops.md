# SCRUM-449 — DevOps-Station Notizen (Round 3 + Round 4, 2026-10-16)

Board read back before the work: SCRUM-449 in column "Deployment", assignee devops-agent — both gate conditions hold. Prod-Org untouched (not in "Release").

## Round-3 state (what changed since my merge on 2026-10-15)

- PO comment 23512 (2026-10-15 23:04): NOT ready for release, two gaps → handed to Developer-Agent.
- Developer comment 23513 (2026-10-16 00:34): branch `feature/SCRUM-449-risk-level` head `ccfc773`, notes only, no production code (PR #168 already merged as `384635a`).
- Tester comment 23514 (2026-10-16 12:07): round-3 re-test, head `ccfc773`, 12/12 AC PASS, handed back to DevOps-Agent.
- Remote branch head now `a562d91` ("[TESTER][SCRUM-449] round-3 re-test green: AC2/AC5 Medium on real org record, spec 4/4"), 2026-10-16 12:06.

## The gap that mattered (round 3)

`git merge-base --is-ancestor a562d91 origin/master` → NO. The round-3 artifacts were never in master:

- `git diff --name-only origin/master a562d91` → `docs/SCRUM-449-notizen-dev.md`, `docs/SCRUM-449-notizen-tester.md`, `tests/e2e/SCRUM-449-risk-level.spec.ts`
- `git show origin/master:tests/e2e/SCRUM-449-risk-level.spec.ts | grep -c Medium` → **0**; the branch version → 5. The AC2/AC5 Medium block (real org record `006WU00000SGHxeYAH`, explicit `expect(medium.length).toBeGreaterThan(0)`) was not on master.
- PR #168 is MERGED (`gh pr view 168 --json state` → MERGED, mergeCommit `384635a`), so no PR carries those commits; `gh pr list --state open` → `[]`.

## What I did (round 3, merge hygiene, no content authored)

Worktree `scratch/scr449-round3`, branch `docs/SCRUM-449-round3-sync` at `a562d91`:
`git merge origin/master --no-edit` → add/add conflicts on the 3 files. Resolved **branch side wins** (`git checkout --ours`) after measuring the delta: `git diff origin/master a562d91` on the spec = 31 insertions, 0 deletions; notes = 10 + 9 insertions, 0 deletions. Branch is a strict superset — nothing of master is lost.

Merge commit `04ef3c6` (parents `a562d91` + `384635a`), pushed `HEAD:master`. `git ls-remote origin master` → `04ef3c6720b482956830d40f4fa96a99913493bd`.

## CI on exactly that head (round 3, run 38887500138, event push)

- Lint & Format (advisory): success (job 116928721456)
- Metadata, Apex & Session Smoke: **success** (job 116928721495) — Apex scope resolved to `NoTests — nothing under force-app/ changed`, so no Apex run in this job (`Tests Ran` count absent). The round-3 delta is docs + spec only; the Apex verdict stands from round 2 (17/17, op id 0AfWU00000cEkjT0AS, per Tester comment 23514).
- Prod-Org Drift Gate: success (job 116928721162) — verdict `No component drift, no test failure beyond the expected pre-release ones.`
- README aus Release Notes: success
- Run conclusion: **success**

## Round 4 (2026-10-16 evening) — the same orphan problem, one round later

- Tester comment 23519 (2026-10-16 21:21): round-4 re-test on head `9162c3f`, 12/12 AC PASS, handed to DevOps-Agent, column Deployment. Explicit ask: "DevOps also merges PR #172 — the corrected E2E spec must reach master."
- PR #172 OPEN, head `599e578906e5e0f98d464f221993d9d1f35ace26`, base master `41705cb`, one file: `tests/e2e/SCRUM-449-risk-level.spec.ts`. CI 4/4 green on run 38951695951 (event pull_request): Lint 48s, Metadata/Apex/Session Smoke 1m35s, Prod-Org Drift Gate 8m45s, README 6s.
- Why the spec had to change: master's spec asserted `rowCount == highOpen.length + 1` — a platform assertion, not a feature assertion (Lightning renders only the first page; the Tester verified 2026-10-16 that the 50-item Account list view also renders exactly 14 data rows). AC7/AC8 and AC10/AC12 now assert the view's own "Select N items" count against the org query.
- Ancestor check after the fetch: `9162c3f` / `a41aad2` / `4742b53` → NOT in master; `a562d91` → IN master. So the round-4 dev + tester notes were orphaned on `feature/SCRUM-449-risk-level` head `4742b53`.

## What I did (round 4)

1. `gh pr merge 172 --squash --match-head-commit 599e578…` → master `165e9732878fea873b258069c5ac4b00759cf0e5`.
2. Worktree `scratch/scr449-round4` at `4742b53`, `git merge origin/master --no-edit` → no conflicts. LCA is `a562d91`; `ci.yml` blob identical at LCA and at `4742b53` (`51dcde37…`), so the branch never touched the gate file and the merge resolved it to the master/PR #171 blob `afc0989c7af854598f344a2df6da54ea717bb2d5` — verified by `git rev-parse HEAD:.github/workflows/ci.yml` after the merge, not assumed.
3. Delta vs master after the merge: only `docs/SCRUM-449-notizen-dev.md` (+32) and `docs/SCRUM-449-notizen-tester.md` (+22), 0 deletions. Merge commit `853e5c23832cfd0fb85f18b4e351c4b8adee991e` (parents `4742b53` + `165e973`) pushed `HEAD:master`.

## CI after the round-4 merge — read honestly

`gh run list --commit 165e973…` → `[]`, same for `853e5c2…`: **CI no longer runs on pushes to master** (PR #171, merged at `41705cb`, changed the workflow to pull-request events only). So the gate evidence for the merged content is the PR #172 run 38951695951 on head `599e578`, and `git diff --name-only origin/master 599e578…` shows master differs from that head in the two notes docs only. The green run belongs to the code that landed; the docs delta carries no force-app content.

## Open item, not mine

SCRUM-444 (Bug, assignee developer-agent, labels blocks-merges/ci-gate/orphan): `SCRUM434Probe.openCaseInRunAs_triggersMustNotBreak` fails in the full org suite because the probe class closes a Case without the now-mandatory `Case.Customer_Satisfaction__c`, so the SCRUM-442 Validation Rule `Customer_Satisfaction_PflichtBeiClosed` refuses the save. Still an org-only class (`git ls-tree -r origin/master | grep -c SCRUM434Probe` → 0). Untouched by me.

## Org finding the Tester could not reach (measured 2026-10-16, Test-Org)

The Tester's open item was "ScheduledJob is not readable from my position". Reproduced and answered:

- Reproduction: `sf data query --query "SELECT … FROM ScheduledJob" --use-tooling-api --target-org Test-Org` → `sObject type 'ScheduledJob' is not supported` (plain and tooling). Dead end confirmed, not a workaround.
- Second route that works: `CronTrigger` and `CronJobDetail` ARE queryable. `sf sobject describe --sobject CronTrigger` gives the real columns (`CronExpression, State, NextFireTime, PreviousFireTime, TimesTriggered, CronJobDetailId, …`) — `Name` does not exist on it, which is why the first guess failed.
- Read-back, 5 rows each: `0 25 10 ? * 1,2,3,4,5,6,7` (Metalytics Data Loader), `0 0 3 * * ?` (SCRUM-417 Offene Chancen Verlauf), `0 0 6 * * ?` (SCRUM-319 Overdue Opportunities), `0 15 * * * ?` (SCRUM-438 SLA), `0 0 4 * * ?` (SCRUM-442 Satisfaction).
- **No CronTrigger named `SCRUM-449 Risk Evaluation`** → the nightly sweep for this feature is NOT scheduled in Test-Org, even though `OpportunityRiskScheduler` is deployed (ApexClass CreatedDate 2026-10-14T19:31:07Z). Design line 301 puts the org step on DevOps: `System.schedule('SCRUM-449 Risk Evaluation', '0 0 4 * * ?', new OpportunityRiskScheduler())`.
- The design's own collision question (design line 322) answers YES: the `0 0 4 * * ?` slot is taken by SCRUM-442 Satisfaction (`08eWU00000rLDgnYAG`, TimesTriggered 6). A free slot is needed at the org step — no org write done by me yet.

## Round 5 — Prod-Org release (2026-10-17, authorised)

Board read back before the work (`jira_get_issue`, fields=status,assignee): SCRUM-449 **status "Release"**, **assignee devops-agent** — both Prod gate conditions hold at once. Updated 2026-10-16 22:39 CEST (PO handoff).

### Prod-Org state measured BEFORE the deploy (all `-o Prod-Org`)

The feature was already partly live in Prod — a Prod deploy had run on 2026-10-16 21:47–21:49 UTC (ApexTrigger `OpportunityRiskTrigger` CreatedDate 2026-10-16T21:49:48Z, both PermissionSets 21:47:14/21:49:49Z). Measured rows:

| query | rows |
|---|---|
| `FieldDefinition` Opportunity, 6 risk fields | 6 (live) |
| `ApexClass` OpportunityRisk* / SCRUM449* | 5 (live) |
| `ApexTrigger OpportunityRiskTrigger` | 1 (live) |
| `PermissionSet SCRUM449%` | 2 (live) |
| `Report Sales/Hoeh_Risk_Chancen` | 1 (live) |
| `Layout Opportunity-Opportunity Layout` (retrieve, 6 risk `<field>` entries) | live |
| `ListView` exact `Name = 'Hoeh Risk Chancen'` | **1 (live)** |

**Trap that cost me a wrong premise:** `ListView.Name` is the **label**, not the API name. `WHERE Name LIKE 'Opportunity%'` → 0 rows and reads like "not deployed"; the same view is one row under `Name = 'Hoeh Risk Chancen'`. `retrieve --metadata "ListView:Opportunity.Hoeh_Risk_Chancen"` returns no `.listView` file at all — it returns `objects/Opportunity.object` with the `<listViews>` block. Read the object file, not the missing component file.

### Validation + deploy (house 3-phase)

- Manifest authored: `manifest/scr449-prod-release.xml` (house pattern of `scr414-prod-release.xml`), 17 members, version 67.0. Nothing excluded — unlike scr414, no member of this ticket references a field Prod lacks.
- `sf project deploy validate -x manifest/scr449-prod-release.xml -o Prod-Org --test-level RunRelevantTests --concise --json` → **job 0Afg500000FvE5eCAF, 17/17 components, 0 errors**.
- `sf project deploy start -x … -o Prod-Org --test-level NoTestRun --json` → **job 0Afg500000FvGc6CAF, status Succeeded, 17/17, 0 errors, 0 tests** (NoTestRun by design — see below).
- `sf apex run test -o Prod-Org --tests SCRUM449OpportunityRiskTest --tests SCRUM449OpportunityRiskFlsTest` → **run 707g500000s6C7S, 19/19 Pass, 100%, org 00Dg500000DkTtzEAF, user devops-agent@cline.de**. Includes the negative-access test `riskFields_invisibleWithoutPS_readableNotWritableWithPS` (17.7 s) and `writePS_neverAssignedToHumanProfiles`.

**Why the 3-phase split is mandatory here:** an inline `--test-level RunSpecifiedTests` Prod deploy fails for a new-field release — the new-field test runs in admin mode and answers `No such column` (SCRUM-436: 8 VerifyTests), even when the deploy user is System Admin. `NoTestRun` + a separate `sf apex run test` is the fix.

### Read-backs after the deploy (all `-o Prod-Org`)

- `PermissionSetAssignment WHERE PermissionSet.Name LIKE 'SCRUM449%'` → **3 rows**: `devops-agent@cline.de` × both PS, `meerwais.osmani.3ecaf61ebe28@agentforce.com` (the only real Prod end user, System Admin) × `SCRUM449OpportunityRisk` (read PS). Write PS deliberately NOT assigned to the human profile — matches the passing `writePS_neverAssignedToHumanProfiles`.
- FLS read-back through a real session: `sf data query -q "SELECT … Risk_Level__c, Inactive_Days__c, Last_Risk_Evaluation__c …" -o Prod-Org` returns values → the read PS grants the fields to the CLI user.
- `Layout` retrieve → all 6 risk fields present. `Report` retrieve → columns `Opportunity.Risk_Level__c`, `Opportunity.Risk_Reason__c`, `Opportunity.Inactive_Days__c` + the 5 standard ones.
- `ListView` exact-name query → 1 row, label "Hoeh Risk Chancen".

### Org step: the nightly sweep (Scheduled Jobs are runtime, not metadata)

Design line 301 puts `System.schedule('SCRUM-449 Risk Evaluation', '0 0 4 * * ?', new OpportunityRiskScheduler())` on DevOps. **In Prod-Org that job already exists and is live** — no org write was needed:

```
08eg500000MJiK3AAL | 08ag500000MIYY3AAP SCRUM-449 Risk Evaluation
  cron 0 0 4 * * ? | State WAITING | CreatedDate 2026-10-16T22:02:20.000+0000
  Owner/CreatedBy 005g5000009C4M4AAK = devops-agent@cline.de
  NextFireTime 2026-10-17T11:00:00+0000 | PreviousFireTime null | TimesTriggered 0
```

- `CronTrigger` IS reachable via `sf data query -q … -o <org>` **without** `-t`. With `--use-tooling-api` (`-t`) it fails: `sObject type 'CronTrigger' is not supported`. The earlier Test-Org read used `-t`; that flag is what broke it, not the org.
- `CronJobDetail` has no `Type` and no `CreatedDate` column — `SELECT Id, Name` is the working shape.
- Prod slot map (8 jobs): 01:00 SCRUM436-Reminder, 02:00 SCRUM-388, 03:00 SCRUM-417, 04:00 **SCRUM-449**, 05:00+20:00 Metalytics, 06:00 SCRUM-319, 01:36 weekly Metalytics, 06/11/16/23 quarter-hourly Metalytics. The `0 0 4` collision the design asked about (line 322) exists **in Test-Org only** (SCRUM-442 Satisfaction `08eWU00000rLDgnYAG`); Prod has no SCRUM-442 cron, so the design slot was free and is now taken by this feature.
- `TimesTriggered 0` is expected: created 2026-10-16 22:02 UTC, first fire 2026-10-17 11:00 UTC (= 04:00 America/Los_Angeles, the org's TimeZoneSidKey).

### Still open, not mine

Test-Org has **no** `SCRUM-449 Risk Evaluation` CronTrigger (5 jobs there: Metalytics, SCRUM-417, SCRUM-319, SCRUM-438 SLA, SCRUM-442 Satisfaction). The nightly sweep is live in Prod but missing in Test-Org — the Tester's AC on the scheduled sweep cannot be exercised in Test-Org until that job is created there. Not a Prod blocker; filed as a finding, not fixed by me (Test-Org org writes belong to Developer/Tester).

### Release tag

`release/2026-10-17-SCRUM-449` → annotated tag on the release commit, pushed with it. Tag date is the deploy date (2026-10-17), not the PO handoff date.

## Round 6 — the nightly sweep FAILED in Prod (2026-10-17, measured after the release)

The release was green on metadata and tests, but the CronTrigger's own job failed.
Measured, not theorised:

- `AsyncApexJob 707g500000ryLVDAA2 | ScheduledApex | Failed | 2026-10-16 22:02:20`
  — `ExtendedStatus: Operation failed due to fields being inaccessible on Sobject Opportunity`.
- CronTrigger `08eg500000MJiK3AAL` fired (TimesTriggered 1, PreviousFireTime 2026-10-17 11:00:08Z)
  and changed nothing: all 13 open Opportunities still `Risk_Level__c = null`.
- Reproduced synchronously as the CLI user: `OpportunityRiskService.recomputeAll()` → same
  `System.DmlException`. Not a scheduled-context quirk.
- A single-field write DOES succeed: `one[0].Risk_Level__c = 'Low'; update one;` → OK
  (`006g5000005MFyPAAW`). So the wall is in the trigger's field reads, not in the risk fields.

**Root cause, read from the org:** `sf project retrieve start -m ApexClass:OpportunityRiskService
-o Prod-Org` → Prod source identical to `origin/master` except a trailing newline; line 94:
`if (now.TestFeld__c != was.TestFeld__c) return true;`. `TestFeld__c` is SCRUM-315's field
(commit `3c76b17`), **no Permission Set in the repo names it** (grep over all
`permissionsets/*.permissionset-meta.xml` on master: 0 hits), and it is not among the 26 custom
fields `sf sobject describe --sobject Opportunity -o Prod-Org` lists.

**Why tests stayed green:** the test classes build records in the factory; the FLS wall only trips
on a real `update` over org records. Green tests do not cover this path.

**Routed to Developer-Agent** (implementation, not design) — Jira comment 23524, ticket moved to
"Implementierung" / assignee developer-agent. DevOps does not touch `force-app/`.

**Tool lessons from this round (verified commands):**
- `System.query()` / `System.queryAllSobjects()` do NOT exist in Apex — compile error. Per-field
  isolation must be one statement per `sf apex run`, not a loop of `System.query`.
- `try/catch` does NOT hold an FLS access error: it aborts the transaction regardless.
- `FieldDefinition` has no `FieldObject` relationship and no `Name` column — use
  `sf sobject describe --sobject <Obj>` and read the field list instead.
- `sf project retrieve start -m ApexClass:<Name> -o <org>` returns the org's compiled-source
  text; diffing it against `origin/master` proves whether the org runs what the repo holds.
