# SCRUM-471 — Notizen (Developer, 2026-11-22)

Hard-won findings only, each with the command that produced it. Read this first after
any compaction. Build spec: `docs/SCRUM-471-design.md` (Architect).

## Board state (read back, not assumed)
- SCRUM-471 at start of this turn: status `In Bearbeitung` (= column Implementierung),
  assignee `developer-agent` — correct, nothing to fix.

## Worktree
- `git worktree add scratch/wt-SCRUM-471 feature/SCRUM-471-key-account` (the shared
  checkout sits on `feature/SCRUM-424-first-response` with foreign uncommitted files —
  untouched by me).

## Deploy sequence (each phase: validate first, then start)
1. `sf project deploy validate -x manifest/scr471-phase1-fields.xml -o Test-Org --test-level RunRelevantTests --concise --json`
   -> Succeeded 1/1, 0 components errors, numTestsRun 0.
   `sf project deploy start -x manifest/scr471-phase1-fields.xml -o Test-Org -l NoTestRun` -> Deploy ID 0AfWU00000dKRGw0AO, Succeeded.
   `sf project deploy report -o Test-Org -i 0AfWU00000dKRGw0AO` -> status Succeeded, 1 component, 0 errors.
2. `... -x manifest/scr471-phase2-permsets-layouts.xml ...` -> Succeeded 6/6 (2 PSs + 4 Layouts);
   `deploy start` -> Deploy ID 0AfWU00000dKSGD0A4, Components 6/6.
3. `... -x manifest/scr471-phase3-apextests.xml --test-level RunSpecifiedTests --tests SCRUM471KeyAccountTest --tests SCRUM471KeyAccountFlsTest` (see outcome below).

## Measurements in Test-Org (all commands on the page, not inherited)
- Field exists: `sf data query -o Test-Org -t -q "SELECT DeveloperName, QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='Account' AND DeveloperName LIKE 'Is_%'"`
  -> 4 rows: IsDeleted, Is_Locked__c, Is_Inactive__c, **Is_Key_Account__c (Checkbox)**.
  Note: `FieldDefinition.DeveloperName` = `Is_Key_Account` (no `__c`); only `QualifiedApiName` carries it.
- PSs exist: `SELECT Id, Name, Label FROM PermissionSet WHERE Name IN ('SCRUM471_KeyAccount_Read','SCRUM471_KeyAccount_Set')` -> 2 rows.
- PS assignment (after `sf org assign permset --name SCRUM471_KeyAccount_Read --name SCRUM471_KeyAccount_Set --target-org Test-Org --on-behalf-of devops-agent@cline.test --on-behalf-of meerwais.osmani@resourceful-bear-6f1u4j.com`):
  `SELECT Id, Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN (...)`
  -> **4 rows**: Read -> devops-agent@cline.test, Read -> meerwais.osmani@..., Set -> both.
- Field read through a real session: `sf data query -o Test-Org -q "SELECT Id, Name, Is_Key_Account__c FROM Account"`
  -> **totalSize 251**, 251 rows with `Is_Key_Account__c = false`, **0** with true.
  Aggregate check: `SELECT COUNT() FROM Account` -> 251; `SELECT COUNT() FROM Account WHERE Is_Key_Account__c = true` -> 0.
- FLS default of the NEW field (decides whether the negative tests mean anything):
  `SELECT Parent.Label, Parent.IsOwnedByProfile, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE SobjectType='Account' AND Field='Account.Is_Key_Account__c'`
  -> **3 rows, all IsOwnedByProfile=false**:
  `SCRUM471_KeyAccount_Read` read=true edit=false; `SCRUM471_KeyAccount_Set` read=true edit=true;
  `Agentic Near Core CRM` read=true edit=false (an org PS that is assigned to NO user — it appears in
  the PermissionSetAssignment table for no username at all).
  **No Profile row** -> the Standard User profile grants nothing on this field, so the PS-less
  negative is a real FLS wall, not a lucky default. This settles the SCRUM-421/430
  contradiction for THIS field by measurement.
- `Work__Report` is NOT an sObject in Test-Org:
  `sf data query -o Test-Org -q "SELECT Id FROM Work__Report LIMIT 1"` -> INVALID_TYPE
  "sObject type 'Work__Report' is not supported". `EmailMessage` and `Task` exist (totalSize 0).
  So the "no work record" half of AC8 is not countable in Test-Org.

## Two platform facts that cost a cycle each (fixes, not workarounds)
- Apex SOQL has **no `NOT LIKE`**: `WHERE Name NOT LIKE 'x%'` -> "Expecting 'IN' but was: 'LIKE'"
  (compile error in the deploy validate report). Negate in Apex code (prefix check), not in the query.
- Inside an Apex test, org-wide SOQL sees **only the test's own records**:
  `[SELECT Id FROM Account].size()` returned 0 in a test method that creates none
  (guard `total > own` reddened with 0 > 0). Consequence: AC9 (the 251 existing
  customers still read "No") is NOT assertable in Apex — it is an org-level fact,
  proven by the CLI read-back above. Kept this as a comment in `SCRUM471KeyAccountTest`
  so the Tester's coverage table cites the count 251 / 0 marked, not an Apex row.

## Not done deliberately (so the reviewer does not chase it)
- No production Apex in this ticket (ADR: declarative). Only the two test classes.
- E2E spec `tests/e2e/SCRUM-471-key-account.spec.ts` belongs to the Tester (AC4 render proof);
  the AC5/AC6/AC7 negatives cannot be proven in the browser (2/2 System-Administrator licences).
