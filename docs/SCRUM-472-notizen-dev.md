# SCRUM-472 — Developer notizen (measured 2026-11-23)

- Worktree: `Salesforce/wt-scr472` on branch `feature/SCRUM-472-company-size` (shared checkout sat on `feature/SCRUM-424-first-response` with leftovers of other tickets — untouched).
- Survey base: `git fetch origin` first; branch head at that point = 79ab64e (architect docs).
- Org = Test-Org only (alias `Test-Org`, user `devops-agent@cline.test`, `sf org display`). Human test account in Test-Org: `meerwais.osmani@resourceful-bear-6f1u4j.com` ("Meerwais Osmani").

## Measured org facts (commands in this file)

| Fact | Value | Command |
|---|---|---|
| Leads in Test-Org before go-live | 66 | `sf data query -o Test-Org -q "SELECT COUNT() FROM Lead"` |
| `Lead.Company_Size__c` before go-live | does NOT exist (no such field in the describe) | `sf sobject describe -o Test-Org -s Lead` (grep `company`/`size`: only `Company`, `CompanyDunsNumber`, `DandbCompanyId`) |
| `Lead.NumberOfEmployees` | standard field, exists — NOT touched | same describe |
| ApexTestQueueItem rows, rolling 24 h | 50 (ceiling max(500, 10 x classes) = 500) | `sf data query -o Test-Org -t -q "SELECT COUNT() FROM ApexTestQueueItem WHERE CreatedDate = LAST_N_DAYS:1"` |
| Users holding a Lead-granting PS | exactly 2: `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com`, 8 rows over SCRUM318/378/386/394/464_Fabrikant_List_Read | `sf data query --use-tooling-api -q "SELECT Id, Assignee.Name, Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN (...)"` |
| PSA columns | `PermissionSetName` / `Assignee` do NOT exist -> use `PermissionSet.Name` / `Assignee.Name` and `--use-tooling-api` (plain query returns 0 rows, house SCRUM-449 finding) | rejected call + working call above |

## Deploys (Test-Org)

- Order: field alone first (PS + layout REFERENCE the field) — house SCRUM-430/382/470/471.
- `sf project deploy validate` always runs tests: use `--test-level RunRelevantTests`, never `RunLocalTests` (24 h org budget). `deploy start` uses `-l NoTestRun`.
