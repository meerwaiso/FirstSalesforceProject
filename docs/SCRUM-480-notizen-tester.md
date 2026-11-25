# SCRUM-480 — Notizen Tester-Agent (2026-11-25)

Repro (measured): `sf project deploy validate --source-dir force-app -o Prod-Org -l RunRelevantTests`
(job 0Afg500000H9W0UCAV, DevOps-Agent, 20:07) → 48 local Apex tests, 45 passing, 3 failing:
`SCRUM445DiscountApprovalTest.ac2/ac5/ac8` → `System.DmlException` →
`OpportunityFollowupMonitorTrigger` AfterUpdate → `System.QueryException: No such column 'Followup_Required__c'`.

## Root cause

- The org trigger `OpportunityFollowupMonitorTrigger` fires on **every** Opportunity update.
  `FollowupMonitoringHandler.recalculate` (line 108 ff) reads **seven** SCRUM459 fields
  (`Followup_Required__c`, `Next_Followup_Date__c`, `Overdue_Followup_Count__c`, …) **and writes**
  them (`upd.Followup_Required__c = …`, lines 197–202). Because the trigger runs in the
  **runAs user's** context, a synthetic test user needs both halves:
  `SCRUM459_FollowupMonitoring_Read` **and** `SCRUM459_FollowupMonitoring_Write`.
- Verified present in both orgs: `sf data query -o <org> -q "SELECT Id, Name FROM PermissionSet WHERE Name LIKE 'SCRUM459%'"`
  → `SCRUM459_FollowupMonitoring_Read`, `SCRUM459_FollowupObligation_Rep`, `SCRUM459_FollowupMonitoring_Write`
  in **Test-Org and Prod-Org** alike.
- House rule already in memory: a synthetic runAs user needs **every** PS a real profile holds,
  because org AfterUpdate triggers run in user mode. Missing one fails on a *foreign* field,
  which reads like a platform fault.

## Fix (test artifact only)

`force-app/main/default/classes/SCRUM445DiscountApprovalTest.cls`: all five `grantPS(...)` lists
(ac2, ac5, ac7, ac8, ac9) got the two PS names appended; header comment records why.
No production component touched, no PS widened, no Profile edit.

## Measurements

| What | Command | Result |
|---|---|---|
| Test-Org, class scoped | `sf project deploy start --metadata ApexClass:SCRUM445DiscountApprovalTest -o Test-Org --test-level RunSpecifiedTests --tests SCRUM445DiscountApprovalTest` | success, **11 tests, 0 failures** |
| Test-Org, CI's own call (2nd route) | `sf apex run test --test-level RunSpecifiedTests --class-names SCRUM445DiscountApprovalTest --code-coverage --result-format human --wait 30 --output-dir apex-test-results -o Test-Org` | Passed, **11 tests, Pass Rate 100%**, Test Run Id `707WU00001WXL1o`, Test-Org `00DWU00000oibVJ2AY`, wide coverage 61% |
| CI Smoke on head `1e7437b` (run 45686111487) | step `Run Apex tests` **failed after 1m52s** | CI runs `sf apex run test`, which uses the class **as compiled in the org** — CI never deploys. At that moment Test-Org still held the *pre-fix* class → the gate was red for the very defect SCRUM-480 names. |

**Consequence for CI:** a test-class fix only turns the Smoke gate green once the fixed class
is compiled **in the org**. Order: deploy the class to Test-Org first, then re-trigger CI
(push the next commit). A CI run that starts before the deploy re-tests the old class.

## CI scope (read out of `.github/workflows/ci.yml:139-190`, not assumed)

`Determine Apex test scope` = union of tickets in the **branch name** and in the **changed paths**
(`grep -oE 'SCRUM-?[0-9]+'`), then `ls force-app/main/default/classes/ | grep -E '^(445|480)…Test\.cls'`.
For this branch the changed path names `SCRUM445`, so the scope was `RunSpecifiedTests — SCRUM445DiscountApprovalTest`
(a full-suite fallback would have spent ~26 classes of the 24 h test budget).

## Open question I did not paper over

- Budget rows: `ApexTestQueueItem WHERE CreatedDate > LAST_N_HOURS:24` → **MALFORMED_QUERY**
  ("unexpected token: 'LAST_N_HOURS'"). The 24 h window has to be spelled as a literal
  timestamp; not needed for this verdict, so it was left unmeasured rather than guessed.
- Prod-Org: `RunRelevantTests` validates the **branch source** in the org, so the fixed class
  is compiled there by the Drift Gate itself; no Prod deploy of a test class by me (Tester deploys
  test artifacts to Test-Org only).
