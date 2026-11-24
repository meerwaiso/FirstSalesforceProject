# SCRUM-476 — Developer notizen (measured 2026-11-24)

Nur gemessen Fakten, je jeeline with the command. Read this first after every compaction.

## Org / Session

- `sf org list`: Test-Org alias -> `devops-agent@cline.test` (orgId 00DWU00000oibVJ2AY),
  Prod-Org alias -> `devops-agent@cline.de`. Developer works on Test-Org only.
- `scripts/fls-check.sh Account Company_Size__c Test-Org` -> "Existenz NEIN — nicht in dieser
  Org deployt." (Architect M1 confirmed, 2026-11-24)

## House shapes (each read from origin/master in the SCRUM-476 worktree)

- Lead field authority `objects/Lead/fields/Company_Size__c.field-meta.xml`: four API values
  `up_to_10` / `11_to_50` / `51_to_250` / `more_than_250`, labels "up to 10 employees" /
  "11 to 50 employees" / "51 to 250 employees" / "more than 250 employees". `<required>false`,
  no `<defaultValue>`, `<trackTrending>false`, no blank marker.
- PS pair house `SCRUM471_KeyAccount_Read` / `SCRUM471_KeyAccount_Set`: fieldPermissions only,
  no objectPermissions, no user entries in source. Read: editable=false readable=true. Set: both true.
- Layout item house (`Lead-Lead Layout.layout-meta.xml` line 24-27): `<layoutItems>`
  `<behavior>Edit</behavior><field>Company_Size__c</field>` directly after the `Company` item
  in the first section.
- Trigger house shape: `apiVersion 62.0`, `<status>Active</status>`, thin trigger file + handler class.
- Only Account trigger today: `AccountLockGuard on Account (before update)` -> handler
  `AccountLockClearHandler` (static `hasFired` per-transaction guard).
- Four Account layouts in source; default `Account-Account Layout.layout-meta.xml` = 433 lines.
- Deploy job house (SCRUM-472): phase1 field alone, phase2 PS+layout (they reference the field),
  phase3 Apex test classes with `--test-level RunSpecifiedTests --tests <class>`.
- e2e specs ship inside the feature PR (house: SCRUM-472 spec in PR #194, SCRUM-471 spec in PR #193).
- `scripts/fls-check.sh` exists in the repo root and answers the 3-query FLS chain.

## Worktree

- Own worktree: `/home/fino/Desktop/SoftwareProjects/Salesforce/scr476-wt` on
  `feature/SCRUM-476-company-size` (Architect branch head ce2efb2). Shared checkout stays untouched.

## Deploy order (measured constraint, memory house rule)

field -> PS pair + layout -> assign both PS (`sf org assign permset`) -> handler class ALONE
-> two triggers -> Apex test classes (RunSpecifiedTests, one `--tests` flag per class).

## Deploy commands that work on this CLI (2.150.6, measured 2026-11-24)

- `sf project deploy validate --manifest <file> --test-level ...` REJECTS `--source-dir`
  together with `--manifest` ("--manifest cannot also be provided when using --source-dir").
- `validate` has NO `NoTestRun` option (options: RunAllTestsInOrg|RunLocalTests|RunSpecifiedTests|RunRelevantTests,
  default RunLocalTests). The pure dry run is therefore:
  `sf project deploy start --dry-run -l NoTestRun -x manifest/<file> -o Test-Org --concise`
- Deploy: `sf project deploy start -x manifest/<file> -o Test-Org --concise` (also accepts `-l NoTestRun`).
- Assign: `sf org assign permset -n <PS> -n <PS> -o Test-Org -b <user> -b <user>`.

## Measured in Test-Org 2026-11-24 (after field + PS deploy)

- Deploy IDs: phase1 field `0AfWU00000dNFr70AG`, phase2 PS pair + layout `0AfWU00000dNFvx0AG`,
  both Status: Succeeded (dry runs before them: `0AfWU00000dNFpV0AW`, `0AfWU00000dNBMz0AO`).
- SOQL BEFORE assigning the PS: `No such column 'Company_Size__c' on entity 'Account'` -> FLS wall.
- `sf org assign permset` assigned BOTH PS to `devops-agent@cline.test` AND to
  `meerwais.osmani@resourceful-bear-6f1u4j.com`.
- `PermissionSetAssignment` read-back: totalSize 4 (2 PS x 2 users).
- `FieldPermissions` for Account.Company_Size__c: 3 rows, ALL `IsOwnedByProfile=false`:
  `SCRUM476_CompanySize_Read` (read, no edit), `SCRUM476_CompanySize_Set` (read+edit),
  plus a pre-existing org PS `Agentic Near Core CRM` (read only).
  => NO Profile grants the field: the negative FLS test (a fresh Standard User without any
  PS cannot read/write it) is satisfiable, not unsatisfiable-by-construction.
- SOQL read-back through the CLI session after assignment: 3 rows, all `Company_Size__c = null`.
- Counts (F-4 baseline BEFORE go-live): `SELECT COUNT() FROM Account` -> 268;
  `Account WHERE Company_Size__c != null` -> 0; `Lead WHERE Company_Size__c != null` -> 0.
  The carry-over has NO source record to be exercised on in Test-Org (PO gap also measured by
  the Tester: 66 Leads / 0 sized) -> fixtures must be seeded, AC1/AC4/AC5 are untested on org data.

## Contradiction found in the house (report to the Architect, do not re-assert)

- Design ADR-7 claims a restricted `valueSet` rejects an out-of-range value. The SCRUM-472 test
  class in the SAME repo measured the opposite on the identical shape (2026-11-23): Apex AND the
  REST API both ACCEPT and STORE `several hundred` / `nonsense_band`; only the Lightning UI offers
  the four labels. So the "invalid range rejected" criterion (AC 9 here) is a UI criterion ->
  no Apex assert for it, E2E job of the Tester. Writing such an assert would be a fake PASS.

  ## Measured at implementation (Test-Org, 2026-11-24)

  - `fls-check.sh Account Company_Size__c Test-Org` -> Existence: yes (Picklist). Granted by
  `SCRUM476_CompanySize_Read` (read, no edit), `SCRUM476_CompanySize_Set` (read+edit), plus the
  pre-existing org PS `AncCrmIntegrationUser` (read, assigned to NOBODY). No `IsOwnedByProfile=true`
  row -> the FLS negative (no PS -> invisible) is satisfiable.
  - Org read-back of the live `Account Layout`: `<behavior>Edit</behavior><field>Company_Size__c</field>`
  directly after the Required `Name` item (retrieve, not the repo file).
  - Org read-back of the field enum: `up_to_10 / 11_to_50 / 51_to_250 / more_than_250` with the four labels,
  defaultValue null -> verbatim identical to `Lead.Company_Size__c`, the carry is one assignment.
  - `Lead.Company` has NO permission for `devops-agent@cline.test` -> the attach handler reads the customer
  NAME from `Lead.Company` (its mode allows it), but a test cannot query `Lead.Company`.
  A fixture Lead must NOT start on a Company that is already a customer: the org refuses
  `Lead.Company = null` with REQUIRED_FIELD_MISSING (looks like a platform fault, is not).
  - after-insert records are READ-ONLY ("entity is read-only, only Id is writable") -> the band is written
  by ONE bulkified `update` of FRESH sObjects (Id + band), never in place.
  - ValRule `Letzter_Versuch_KeineZukunft` refuses a Lead save after 10 conversions -> test fixtures
  convert a Lead at most 8x.
  - The convertor storm creates Account + Contact + Opportunity (+Case) in the same save even without a Case.
  - PS assignment read-back: 2 assignees per PS = `devops-agent@cline.test` +
  `meerwais.osmani@resourceful-bear-6f1u4j.com`.
  - Apex: 15/15 green (test run 707WU00001WFKGU). Class coverage: CompanySizeCarryHandler 90 %,
  AccountCompanySizeCarry 100 %, LeadCompanySizeCarry 100 %; org-wide 87 %.
  - Deploy IDs seen: triggers 0AfWU00000dNMpYQ, tests 0AfWU00000dNJQ50AO (Test-Org).
  - Counts after go-live: 66 Leads, 0 carrying a size; 0 Accounts carrying `Company_Size__c`.

## Open measurements still to record

- `Account.NumberOfEmployees` stays untouched (Architect F-1).


## Review round 1 (PR #196 rejected) — measured findings

- `Exception` has NO `getType()` in this org's Apex (deploy report 0AfWU00000dNP7J0AW:
  "Method does not exist or incorrect signature: void getType() from the type Exception").
  A bare `throw;` is not Apex either ("Unexpected token ';'") — re-throw is `throw e;`.
  Access refusals are therefore discriminated on the fault TEXT in `getMessage()`
  (upper-cased, `indexOf` is case-sensitive).
- `new Exception('...')` and `System.abort(String)` do not compile in anonymous scripts
  ("Type cannot be constructed: Exception" / "Method does not exist: void abort(String)").
  A throw with a message needs a declared `class X extends Exception {}`.
- An anonymous `sf apex run` script cannot `insert` a User:
  `LICENSE_LIMIT_EXCEEDED` (Test-Org is at the active-user licence limit). Inside an Apex
  TEST the same insert works — the read-only fixture users only exist in test context.
- Fixture shapes the org accepts (house, read off `SCRUM416OpenOpportunityRollupTest` /
  `SCRUM365OpenCasesCountTest`): `Opportunity(AccountId, Name, StageName, CloseDate)` —
  `AccountName` is NOT a field here; `Case(ContactId, Status='New', Subject)` — Case has no
  AccountId, and `Case.ContactId` must be an Id OF TYPE Contact.
- Test-Org test budget: the phase-5 deploy with RunSpecifiedTests took 6m03s for 18 tests;
  one more full run of both classes is ~6 min, so the class deploy is done with
  `-l NoTestRun` and the run is issued separately (`sf apex run test`).
- F-6 discriminator is MEASURED green: `probe_accessRefusalIsRecognised` runs a real
  read-only fixture user, the update IS refused, and `isAccessRefusal` recognised the fault
  (test green). The read-only user really refused (`refused == true` assert green).

## Measured at review round 1 (2026-11-24, Test-Org)

- Accounts SHARING a Name exist: `sf data query --json -q 'SELECT Name FROM Account'` ->
  268 rows; e.g. "TESTFIRMASCRUM396ONE" x16, "TESTFIRMASCRUM396THREE" x16,
  "[Scrum-412-E2E] akte 0" x35. The PO's ambiguity criterion is therefore TESTABLE
  (not a zero-record criterion); the Tester does not have to report it as UNTESTED.
- SOQL GROUP BY aggregate: `SELECT COUNT() FROM Account GROUP BY Name HAVING COUNT() > 1`
  -> MALFORMED_QUERY "unexpected token 'COUNT()'" in this org's parser. Counting duplicates
  was done client-side over the 268 rows instead.
- Apex test run (standalone): 18/18 green, Test Run Id 707WU00001WFdTZ
  (`sf apex run test --tests SCRUM476CompanySizeTest --tests SCRUM476CompanySizeFlsTest`),
  incl. both ambiguity fixtures and the F-6 access-refusal probe. Org-wide coverage 83 %.
- CI collision (measured in the finished job log 138386164057 of run 45377097991):
  FLS-Gate printed "FLS-Gate grün" for `Account.Company_Size__c ok
  (SCRUM476_CompanySize_Set, SCRUM476_CompanySize_Read)`; the step then died with
  `Error (ALREADY_IN_PROCESS): Test already enqueued 01pWU00000TkuDu` — the org had MY
  deploy's RunSpecifiedTests job enqueued at the same time. One Apex test run per org at a
  time; the CI step needs a re-run with the org test queue free.

## Review round 2 (2026-11-24, user decision: conversion = IsConverted flip + ConvertedAccountId)

Measured in Test-Org, this round, each line with the command that produced it:

- `Lead` carries `IsConverted` and `ConvertedAccountId`:
  `sf sobject describe -s Lead -o Test-Org --json` (fields list read with jq).
- `Database.setSavepoint()` EXISTS (the user was right, my earlier note was wrong):
  scratch `probe476_savepoint.cls` — `Savepoint sp = Database.setSavepoint();` compiles.
  `Database.rollback(sp, 1)` does NOT ("Method does not exist or incorrect signature: void rollback(Savepoint, Integer)");
  `Database.Rollback(sp)` compiles AND rolls the update back (probe script ran to completion,
  the read-back Name stayed the pre-update value). Shapes that failed before and were never this API:
  `Savepoint.set()/pop()`, a `SAVEPOINT` statement.
- `System.Math.fmod` does NOT exist ("Method does not exist or incorrect signature: void fmod(Integer, Integer)
  from the type System.Math", deploy report of phase5). Cycle the band list with an index instead.
- `Opportunity` has NO `AccountName` field (measured earlier, report 0AfWU00000dNGSE0A4): seed with
  `AccountId`, count by `Name`.
- Deleting an org trigger: `sf project delete source -o Test-Org -m "ApexTrigger:AccountCompanySizeCarry" -r -l NoTestRun`
  -> Deploy ID 0AfWU00000dNUAD0A4, Status Succeeded, 1 component. Verified gone with
  `sf data query -t -q "SELECT Name FROM ApexTrigger" -o Test-Org --json` (path `.result.records`;
  only `LeadCompanySizeCarry` matches CompanySize).
- New handler API live: anonymous script calling `CompanySizeCarryHandler.carryConvertedLeads(new List<Lead>(), new Map<Id,Lead>())`
  ran to completion (the old class has no such method -> compile would fail). Deploy IDs:
  handler 0AfWU00000dNURx0AO, trigger 0AfWU00000dNUTZ0A4, tests 0AfWU... (phase5 Succeeded, 3 components).
- `convertLead` LINKS an existing Account by Name: with one existing Account named like the Lead's
  Company, `res.getAccountId()` == that existing Account Id (asserted in the test, not assumed).

## Org behaviour measured while repairing the rewritten tests (2026-11-24)

- convertLead does NOT attach to an existing Account with the same Name. Probe
  `probe476_attach.cls` via `sf apex run`: `success=true accountId=001WU00002M2WCeYAN
  existingId=001WU00002M2WCdYAN`, `sameRecord=false`, `accountsNowNamed=2` — the conversion
  creates its OWN Account and the pre-existing same-Name customer stays untouched. So the
  fill-only-if-blank property is asserted on the record ConvertedAccountId names, and the
  same-Name neighbour is asserted UNTOUCHED; an "attach to an existing customer" path is NOT
  reachable from Apex convertLead in this org and can only be shown through the UI (Tester).
- Editing a converted Lead is refused by the org: `CANNOT_UPDATE_CONVERTED_LEAD`
  ("cannot reference converted lead") on `update l`. AC 12 is therefore proven by that refusal
  plus the band read-back, not by an update that succeeds.
- Bulk conversion limit belongs to the org: 10 convertLead calls in one save save,
  20 die with `LIMIT_EXCEEDED` ("There was an error converting the lead"). Measured by
  running the same test at 10 (green) and 20 (red) — 200 also red (round 1).
- Verdict of the rewritten classes: 13/13 Pass (10 behaviour + 3 FLS), Test Run Id
  707WU00001WFsxWYAT (`sf apex run test --tests SCRUM476CompanySizeTest --tests
  SCRUM476CompanySizeFlsTest --target-org Test-Org --wait 30 --result-format json`).

## Coverage and conversion-field limits measured on the round-3 head (2026-11-24)

- `sf apex run test` has `--code-coverage` (`-c`), and with `-r json` the payload is
  `result.coverage.coverage[]` with `name / totalLines / totalCovered / coveredPercent` —
  NOT `result.codes`. Measured: `CompanySizeCarryHandler` 24/28 = 86 %,
  `LeadCompanySizeCarry` 2/2 = 100 %, run `707WU00001WG5zb`, 14/14 Pass.
- A `sf project deploy start` report's `details.runTestResult.codeCoverage` attributed **0/24**
  to the handler in the same situation — that block is not the coverage oracle, the
  `--code-coverage` run is. Do not quote 0 % to a reviewer.
- `Lead.ConvertedAccountId` cannot be assigned at all: `sf apex run` compile error
  `Field is not writeable: Lead.ConvertedAccountId` (scratch `probe476_attach3.cls`). Combined
  with `sameRecord=false` this closes any Apex "attach to existing customer" fixture.
- Anonymous `sf apex run` scripts must be plain statements: a `public class X { public static
  void run() }` wrapper dies with "static can only be used on methods of a top level type".
- `Lead` name fields in a named-parameter constructor are `Company` and `LastName` —
  `Last_Name` does not exist ("Field does not exist: Last_Name on Lead").
