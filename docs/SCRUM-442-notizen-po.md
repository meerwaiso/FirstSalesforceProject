# SCRUM-442 — PO-Notizen (Release-Gate + Close-out, 2026-10-12)

Verdacht-finder: alle Org-Reads sind MEIN Tool-Call, not from a deployer's self-report.

## Prod-Org live-Status (read back 2026-10-12, own queries)

| Fact | Value | Command |
|---|---|---|
| `Case.Customer_Satisfaction__c` | present, **Picklist** | `sf data query -o Prod-Org --use-tooling-api -q "SELECT DeveloperName, QualifiedApiName, DataType FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Case' AND DeveloperName = 'Customer_Satisfaction'"` → totalSize 1 |
| 5 `Account.Satisfaction_*` | present: Anzahl Number(6,0), Durchdurch **Number(2,1)**, Fenster_Start Date, Min Number(1,0), Arger **Formula (Text)** | same query, EntityDefinition.QualifiedApiName='Account', LIKE 'Satisfaction%' → totalSize 5 |
| ValidationRule | `Case.Customer_Satisfaction_PflichtBeiClosed` → **Created** | `sf project retrieve start --metadata "ValidationRule:Case.Customer_Satisfaction_PflichtBeiClosed" -o Prod-Org` |
| Report | `Miserable_Kunde_Satisfaction` → totalSize 1 | `SELECT Name FROM Report WHERE Name LIKE '%Satisfaction%'` -o Prod-Org |
| PS assignments | **6 rows = 3 PS × 2 users** | `SELECT Assignee.Username, PermissionSetId FROM PermissionSetAssignment WHERE PermissionSetId IN ('0PSg500000Dai7uGAB','0PSg500000Dai7vGAB','0PSg500000Dai7wGAB')` — users: `meerwais.osmani.3ecaf61ebe28@agentforce.com`, `devops-agent@cline.de` |
| Closed Cases with score in Prod | **0** | `SELECT COUNT() FROM Case WHERE Status='Closed' AND Customer_Satisfaction__c != null` -o Prod-Org |

## Trap-Check: deployed ≠ assigned — NOT present in Prod

FLS step 3 (skill `salesforce-describe-first` §4) against the **PROD** org returned 6 rows.
The 7th-occurrence trap (SCRUM-428) did not bite here.

## Prod-Release reference (read back from the remote)

- Tag `release/2026-10-12-SCRUM-442` exists on origin: tag object `8cfb804`, tag target `f1d3ba1`.
- **DevOps comment 23465 is wrong.** It claims the remote tag points at `2546856` (the feature merge).
  Measured: `git ls-remote --tags origin release/2026-10-12-SCRUM-442` → `8cfb804`, and
  `git rev-parse "refs/tags/release/2026-10-12-SCRUM-442^{}"` → `f1d3ba1` = the release-metadata commit.
  The house pattern (431→040a47a, 432→ce448b0, 440→ea6fcb6) is satisfied. No @user decision needed.
- master head = `f1d3ba1` (own `git ls-remote origin master`).

## Repo facts

- `docs/RELEASE-NOTES.md` on master had **no** SCRUM-442 entry (top entry SCRUM-440, 10.10.2026).
  DevOps' `f1d3ba1` touched only `docs/SCRUM-442-notizen-devops.md` — the release note was owed.
  I wrote it (see commit below) and ran `scripts/build-readme.sh` in the same commit.
- `f1d3ba1` author: devops-agent.

## Known limitation (business consequence, must stay visible)

ValidationRule blocks **any** save of an already-closed Case without a score.
Prod: 23 Cases closed before the release carry no score (DevOps read-back; my own count of
score-carrying closed Cases = 0). Editing those old Cases (owner, priority, related-record edit)
throws. Backfill is NOT in this story → needs a new story if staff must edit old Cases.

## Not closed by this ticket (foreign, tracked)

- SCRUM-444: Test-Org orphan Apex class `SCRUM434Probe` reddens the full-suite Smoke gate on master.
  Not a SCRUM-442 defect; assigned to developer-agent.
