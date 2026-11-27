# SCRUM-483 — Notizen (Architect, 2026-11-27)

Verdacht nach jeder Verdichtung: diese Datei zuerst. Alle Org-Befehl are listed below.

## Org facts (Test-Org, commands below)

| Fact | Value |
|---|---|
| Users | 8, **all `IsActive=true`**, **`ManagerId` NULL on all 8** |
| Accounts | 268 owned (Meerwais 12, Automated Process 1, devops-agent 255) |
| Opportunities | 157 owned (Meerwais 33, devops-agent 124); **89 open, 68 closed**; Meerwais: 18 closed / 15 open |
| Locked Accounts | 4, **0 with `Open_Opportunity_Count__c > 0`** |
| `DiscountApprovalManager__c` | 2 rows, Meerwais↔devops-agent circular |
| `SalesUser` object | **does not exist** (no Sales Books in this org) |
| User ids | Meerwais `005WU000017tBhRYAU`, devops-agent `005WU000017tEKLYA2`, Automated Process `005WU000017tBpWYAU` |

## Commands that produced them (rerun only if a fact must be current again)

```
sf sobject describe -s User --target-org Test-Org --json          # IsActive, ManagerId (both updateable=true)
sf sobject describe -s Opportunity --target-org Test-Org --json   # StageName (10 values), IsClosed/IsWon readonly, NO IsLost
sf sobject describe -s Account --target-org Test-Org --json
sf data query --target-org Test-Org -q "SELECT Id,Name,IsActive,ManagerId FROM User"
sf data query --target-org Test-Org -q "SELECT COUNT(Id),OwnerId FROM Account GROUP BY OwnerId"
sf data query --target-org Test-Org -q "SELECT COUNT(Id),OwnerId FROM Opportunity WHERE IsClosed = false GROUP BY OwnerId"
sf data query --target-org Test-Org -q "SELECT Id,Name,Rep__c,Manager__c FROM DiscountApprovalManager__c"
sf data query --target-org Test-Org -q "SELECT COUNT() FROM Account WHERE Is_Locked__c = true"
sf data query --target-org Test-Org -q "SELECT Id,Name FROM SalesUser"        # -> error/0: object absent
```

## Unexpected results / pitfalls hit

- `sf sobject describe ... --json` writes the JSON **to stderr**; `2>/dev/null` gives an empty file.
  Use `> file 2>&1` and `json.JSONDecoder().raw_decode(t[t.find('{'):])` — the CLI-version warning
  rides in front and `json.loads` on the whole blob fails.
- `sf data query --use-tooling-api -q "… FROM CronTrigger"` → `sObject type 'CronTrigger' is not supported`.
  The schedule read-back is **not** this query; do not write it into a handoff (rule: verifying is not delegatable).
- The User SOQL column is **`IsActive`**, not `Active` (memory: `WHERE Not Active` rejected).
- No custom field named `Handed_*`, `Handover*`, `Previous*` on Account/Opportunity
  (read out of the two describes) → new names are free.
- Repo survey basis: `git ls-tree -r origin/master` @ **8718cb4** (shared checkout was on
  `feature/SCRUM-424-first-response` with modified files — never touched; worktree `wt-SCRUM-483`).
- `OpportunityLockedAccountGuard.cls` exists on master with **no caller in any `.cls`**.

## House shapes to copy (paths on origin/master)

- Lookup→User field: `objects/CustomerTransfer__c/fields/From_User__c.field-meta.xml`
- Custom object (AutoNumber + Picklist status): `objects/CustomerTransfer__c/CustomerTransfer__c.object-meta.xml`
- Object-CRUD PS + tab: `permissionsets/SCRUM445_DirectManager_Map.permissionset-meta.xml`,
  `permissionsets/SCRUM410_CustomerTransfer...` (`objectPermissions`, `tabSettings`, `classAccesses`)
- Read/System PS pair: `SCRUM436_CaseReminder` / `SCRUM436_CaseReminderSystem`
- Scheduler + why the CRON entry is an org step: `classes/AccountSatisfactionScheduler.cls` (SCRUM-442)
- Queueable atomic transfer + audit: ADR-2 in `docs/SCRUM-410-design.md`, `classes/CustomerTransferJob.cls`
- System-write suppression flag: `OpportunityRiskService.systemWriteInProgress` (SCRUM-449)

## Dependencies a deploy revealed

- Scheduled jobs are runtime objects → DevOps must `System.schedule` (Test-Org on deploy, Prod on release).
- FLS wall: without `SCRUM483_Handover_System` assigned to the scheduled user, DML reads
  `No such column` — looks like a missing field, is a missing assignment.

## State reached

- [x] design doc written, [ ] commit+push (next), [ ] Jira comment + handoff
