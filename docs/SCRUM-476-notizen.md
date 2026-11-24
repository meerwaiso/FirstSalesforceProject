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

## Open measurements still to record

- FieldPermissions for `Account.Company_Size__c` after deploy: is there a
  `Parent.IsOwnedByProfile=true` row? If yes the negative FLS test is unsatisfiable by
  construction (skill salesforce-describe-first §4) -> must be stated, not asserted.
- `Account.NumberOfEmployees` stays untouched (Architect F-1).
