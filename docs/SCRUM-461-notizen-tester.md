# SCRUM-461 — Tester notizen

Verified facts only; each line names the command that produced it.

## Org state (measured 2026-11-17, Test-Org)

| Fact | Command |
|---|---|
| `Competitor__c` deployed (Label "Competitor") | `sf data query --query "SELECT QualifiedApiName, Label FROM EntityDefinition WHERE QualifiedApiName LIKE 'Competitor%'"` |
| Opportunity fields deployed: `Competitor_Lost_To__c` = Lookup(Competitor), `Competitor_Price__c` = Currency(16,2), `Competitor_Gap__c` = Formula(Number) | `sf data query --use-tooling-api --query "SELECT QualifiedApiName, DataType, MasterLabel FROM FieldDefinition WHERE EntityDefinitionId='Opportunity' AND QualifiedApiName LIKE 'Competitor%'"` |
| `Lost_Last_12M__c` = Formula(Checkbox) deployed | same query, exact name |
| Reports deployed: `Verloren_Chancen_je_Wettbewerber` = 00OWU00000RbBRZ2A3, `Verloren_Chancen_je_Wettbewerber_Meine` = 00OWU00000RbBRa2AN | `sf data query --query "SELECT Id, Name FROM Report WHERE Name LIKE 'Verloren_Chancen%'"` |
| All 3 PSs exist: `SCRUM461_Competitor_List_Read` 0PSWU00000Xz4ex4AB, `..._Teamleitung` 0PSWU00000Xz4ey4AB, `SCRUM461_Competitor_Lost` 0PSWU00000Xz4ez4AB | `sf data query --query "SELECT Id, Name, Label FROM PermissionSet WHERE Name LIKE 'SCRUM461%'"` |
| 6 PS assignments: devops-agent@cline.test (005WU000017tEKLYA2) holds ALL THREE; Meerwais Osmani (005WU000017tBhRYAU) holds all three | `sf data query --use-tooling-api --query "SELECT PermissionSetId, AssigneeId, IsActive FROM PermissionSetAssignment WHERE PermissionSetId IN (...)"` |
| CLI target-org user = `devops-agent@cline.test`; only aliases are Test-Org and Prod-Org | `sf org display`, `sf org list` |
| Competitor records in org before my seeding: 0 | `sf data query --query "SELECT Name FROM Competitor__c"` |
| Closed Lost Opportunities: 16, ALL owned by devops-agent@cline.test; 0 with `Loss_Reason__c=Wettbewerber` | `sf data query --query "SELECT Id, OwnerId, ... FROM Opportunity WHERE StageName='Closed Lost'"` |
| 130 Opportunities: 97 owned by devops-agent, 33 owned by Meerwais Osmani (sample data, none Closed Lost) | `SELECT OwnerId FROM Opportunity` + Counter |

## Consequences for the test plan

- The Playwright session authenticates as devops-agent@cline.test, who holds all three PSs
  → the UI can prove the POSITIVE half of AC4 (team-lead rights) only. The negative half
  (a user without `_Teamleitung` cannot create) has no second licensed session: only two
  sf aliases exist (Test-Org, Prod-Org) and re-authenticating is the user's action.
  Negative half = Apex `System.runAs` (house default).
- AC8's "own deals vs all deals" needs a competitor-lost deal owned by a DIFFERENT user.
  OwnerId cannot be set on create. Route taken: flip one sample Opportunity owned by
  Meerwais Osmani (Closed Won → Closed Lost + `Wettbewerber` + competitor). Chosen after
  grepping every spec: no suite asserts an org-wide Closed Lost Opportunity count
  (SCRUM-449 filters `IsClosed = false`, SCRUM-381/416 use their own TAG fixtures).

## CLI / platform quirks hit this ticket

- `SELECT COUNT FROM ...` is not SOQL in CLI 2.150.6 — use `--json` + count records.
- `FieldDefinition` has `DataType`, not `Type`; `PermissionSetAssignment` has
  `PermissionSetId`/`AssigneeId`, not `AssignedUser`; `Report` has no `Scope` column.
- `sf apex run test` flags: `--class-names`, `--tests`, `--test-level` (no `--async`).
