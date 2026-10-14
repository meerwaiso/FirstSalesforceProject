# SCRUM-449 — Developer-Notizen

Verfahrt: own worktree `scr449-wt`, Branch `feature/SCRUM-449-risk-level`.
Shared checkout sits on feature/SCRUM-424-first-response with SCRUM-424/442/445
leftovers — not mine, neither commit noch delete.

## Org-Facts (gemessen, nicht assumed)

- `sf sobject describe -s Opportunity --target-org Test-Org` → StageName picklist
  in configured order: 1 Prospecting, 2 Qualification, 3 Needs Analysis,
  4 Value Proposition, 5 Id. Decision Makers, 6 Perception Analysis,
  7 Proposal/Price Quote, 8 Negotiation/Review, 9 Closed Won, 10 Closed Lost.
  `restrictedPicklist: False`, groupable/sortable true. Early = 1–5.
- Opportunity: NO `Status`, NO `Owner` (OwnerId exists). `IsClosed` = house SoT.
- 127 Opportunities, 73 open (`SELECT COUNT() FROM Opportunity WHERE IsClosed=false`).
- `ScheduledJob` (Tooling API): 0 jobs in Test-Org today → CRON 04:00 collides with nothing.
- FieldDefinition (Tooling API): none of the six risk fields exists yet.
- CLI target-org user = `devops-agent@cline.test` (alias Test-Org).

## Decisions / deviations from the design doc

- Picklist XML: house pattern `<valueSet><valueSetDefinition>` (verified in
  `Loss_Reason__c`, `Servicebereich__c`) — the design's `<picklist><picklistValues>`
  sketch is NOT the repo's shape. Same semantics (fixed value set, no default).
- Formula `Inactive_Days__c` falls back to `LastModifiedDate` while
  `Last_User_Change__c` is still blank → AC1 measurable on legacy records
  immediately, not only after the first nightly seed.
- Apex `inactiveDays` = `Math.round((now - anchor)/86400)` — same rounding the
  formula does at scale 0, so Apex C1 and the visible number never disagree.

## Verified during implementation (2026-10-14, each line names its command)

- Stage positions: `Id. Decision Makers` is position **5**, not 4 — an AC4
  "setback of 1" fixture must seed `Highest_Stage_Reached__c = 'Value Proposition'`
  against a `Needs Analysis` record (position 4 vs 3). A wrong picklist position
  in a test fixture reads as a service bug; it was one.
- Apex APIs that do NOT exist (each rejected by `scripts/apex-probe.sh` against
  Test-Org): `Map.Entry` as an iteration type, `Date.before()/after()`,
  `List.subList`, `Date.format()`, `instanceof Scannable`,
  `System.cancelJob/deactivateJob/unschedule/cancelScheduledJob/removeJob`.
  `System.abortJob(Id)` DOES exist. Date comparison = operators; date display
  = `String.valueOf(Date)`; chunking = buffer+flush.
- `DateTime.time()` returns ms-since-midnight but arithmetic with Integer/Long
  is rejected. Working elapsed-days: parse `format('HH')`/`format('mm')` to
  Integers, delta in minutes, floor + half-up.
- `FieldPermission` is NOT a queryable sObject (`sf data query -t` rejects it).
  Use `scripts/fls-check.sh <Object> <Field>` — it answers existence, grant,
  assignment in one call.
- `PermissionSetAssignment` columns are `AssigneeId`/`PermissionSetId` — there
  is no `Assignee` and no `PermissionSetName` to join on.
- TestSetup statics are NOT visible from helper methods (fresh static context
  per test method): a `@testVisible` Id set in `@TestSetup` reads null inside a
  helper. Look the record up by a stable field (Alias) and cache it — the
  bulk test (200 records) blew the SOQL limit with an uncached lookup per row.
- `bulk` is a reserved word in Apex (compile error on `List<Opportunity> bulk`).
- `User.Alias` is max 8 chars; `LanguageLocaleKey`/`LocaleSidKey` = `en_US` and
  `TimeZoneSidKey` = `America/Los_Angeles` in this org (`de_DE`/`UTC` rejected).
- A test user without the read-PS cannot SELECT the risk fields at all — an
  FLS test's positive read-back must run in System context, not inside `runAs`.
- A record with no applying condition has `Risk_Level__c = null`; an FLS test
  asserting "the trigger assessed it" needs a record where a condition applies.
- PS deploy ≠ assignment: both PSs were assigned via `sf data create record -s
  PermissionSetAssignment --values "AssigneeId=... PermissionSetId=..."` (space-
  separated pairs) to `devops-agent@cline.test`, then read back.
- Branch was cut from an OLD master commit: 334 files present in master were
  missing from the branch tree. Fixed with `git rebase --onto origin/master
  36f77ef HEAD`; verified 0 deletions vs master before pushing.
- Live proof record: `006WU00000TWM7zYAH` (SCRUM449_live_proof) — created via
  `sf data create record`, read back with `sf data get record`: Risk_Level__c
  Low, reason names the close-date condition, Inactive_Days__c 0.
- Test results: 14/14 green, deploy `0AfWU00000cDp3f0AC`, RunSpecifiedTests.
- PR #168 (https://github.com/meerwaiso/FirstSalesforceProject/pull/168).
