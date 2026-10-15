# SCRUM-448 — Tester notes (2026-10-15)

Ticket: Bug "SCRUM-445 Prod-Org: 6 Apex test methods fail on hardcoded Test-Org
usernames (drift gate stays red)". Board at start: status Testen, assignee
tester-agent — already mine, no board correction needed.

## Branch
Own branch `feature/SCRUM-448-org-fixture-users` cut from origin/master
(`b4ca485` after PR #169). Worktree `../wt-SCRUM-448`. Shared checkout (SCRUM-424,
foreign dirty files) untouched.

## Org measurements (all read back by me, not quoted from the ticket)
- Users, Prod-Org (`SELECT Id, Username FROM User`): 9 rows. The two that matter:
  `005g5000009C4M4AAK devops-agent@cline.de`, `005g5000009C38DAAS
  meerwais.osmani.3ecaf61ebe28@agentforce.com`.
- Users, Test-Org: 8 rows; `005WU000017tEKLYA2 devops-agent@cline.test`,
  `005WU000017tBhRYAU meerwais.osmani@resourceful-bear-6f1u4j.com`.
- The hardcoded literals `devops-agent@cline.test` and
  `meerwais.osmani@resourceful-bear-6f1u4j.com` exist ONLY in Test-Org. Confirmed
  by reading both user lists.
- PS -> user assignment via `scripts/fls-check.sh <Object> <Field> <Org>`
  (plain SOQL cannot reach PermissionSetAssignment: 0 rows for every filter,
  also with --use-tooling-api):
  - Prod-Org: SCRUM445_Discount_Owner 2 users, SCRUM445_Discount_Manager 2,
    SCRUM445_Discount_System 2 — all the SAME pair (devops-agent@cline.de,
    meerwais.osmani.3ecaf61ebe28@agentforce.com).
  - Test-Org: same three PSs, same 2 users each (the two Test-Org names above).
  - => intersection is EXACTLY 2 in both orgs, so the new resolver's
    assertEquals(2, ...) holds in both.
- Ordering by Username: 'devops...' < 'meerwais...' in both orgs, so pair[0] is
  the rep and pair[1] the manager in both — the substitution is role-preserving,
  not just present.

## The fix (test artifact only)
force-app/main/default/classes/SCRUM445DiscountApprovalTest.cls:
- `orgUser(username)` (scalar SELECT on User, threw "List has no rows for
  assignment to SObject" in Prod-Org) replaced by `orgFixturePair()`:
  PermissionSetAssignment read of the three SCRUM445 PSs, intersection,
  ORDER BY Username, assertEquals(2, size) — fails loudly when the pair is
  missing or ambiguous, never passes vacuously.
- All 6 call sites replaced (ac3, ac10, ac6, ac13, notification_executeBothPaths,
  bulk_200_updates). grep -c "orgUser(" after the patch: 1, and that one is the
  comment naming the old bug — no live call site left.
- SCRUM445DiscountFlsTest.cls untouched: it builds its own users with mkUser +
  PSA insert, never names an org user.
- SCRUM442TestFixtures.cls line 66 mentions a Test-Org username only in a
  comment — not a fixture, left alone.

## Why no assertion had to change
Read the 6 method bodies: every assertion is on record data (StageName,
Discount_Approval__c, Approval_Requested_On__c) or on the handler counters
(mappingSoqlCount, enqueueCount). None names a user Id or username, so a PSA-
resolved pair is a legal substitution.

## Runs
- Apex in Test-Org, RunSpecifiedTests on the patched class only:
  `sf project deploy start --source-dir .../SCRUM445DiscountApprovalTest.cls(+meta)
  --test-level RunSpecifiedTests --tests SCRUM445DiscountApprovalTest -o Test-Org`
  -> status Succeeded, numberTestsTotal 11, numberTestsCompleted 11,
  numberTestErrors 0, operation id 0AfWU00000cFpQv0AK.
  (RunSpecifiedTests reports an OPERATION id, not a job id.)
- Resolver probe (scratch/probe448guard.apex, `sf apex run -o Test-Org`, read-only):
    SCRUM445_Discount_Owner holders=2
    SCRUM445_Discount_Manager holders=2
    SCRUM445_Discount_System holders=2
    intersection size=2
      005WU000017tEKLYA2  devops-agent@cline.test
      005WU000017tBhRYAU  meerwais.osmani@resourceful-bear-6f1u4j.com
    resolved count=2
    NEGATIVE PROOF: missing PS threw List has no rows for assignment to SObject
    threw=true
  => positive: the pair the resolver picks in Test-Org is BYTE-IDENTICAL to the
     pair the literals named, in the same order — the substitution is role-
     preserving, not merely present.
  => negative: a PS name that does not exist throws before any assertion runs,
     so the resolver cannot hand back an empty pair and pass vacuously.
- Prod-Org: NOT run by me (test artifacts deploy to Test-Org only; the gate is
  CI's action). Prod proof is the read-only org measurement above: fls-check.sh
  names the same 2 holders for each of the three PSs in Prod-Org, so
  assertEquals(2, ...) holds there and the scalar SELECT that threw can no
  longer be empty.

## Apex budget
RunSpecifiedTests, one class, 11 tests. Budget checked before the run.


## Prod-Org: NOT run by me
Rule: test artifacts deploy to Test-Org only. The Prod-Org Drift Gate runs the
validate itself (CI's action). My Prod-Org proof is the org-level measurement
above: the fixture pair resolves to exactly 2 users there, so the scalar query
that threw can no longer be empty.
