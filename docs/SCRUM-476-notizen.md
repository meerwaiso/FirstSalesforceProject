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

## Open measurements still to record

- `Account.NumberOfEmployees` stays untouched (Architect F-1).

