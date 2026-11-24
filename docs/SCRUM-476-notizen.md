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
