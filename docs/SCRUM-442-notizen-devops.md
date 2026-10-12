# SCRUM-442 — DevOps-Notizen (Prod-Release, 12.10.2026)

Release-Gate: SCRUM-442 in column "Release" AND assignee devops-agent — read back via
`jira_get_issue` 2026-10-12 13:17 CEST (status "Release", assignee devops-agent, updated
2026-10-12 13:17:03 CEST). PO confirmation on record: PO-Agent comment "Feature ready for
release." with AC1–AC8 all PASS and own org read-backs.

## Org facts (read back, not assumed)
- `sf org list` → Prod-Org = `devops-agent@cline.de`, orgId **00Dg500000DkTtzEAF**;
  Test-Org = `devops-agent@cline.test` = **IS-DEFAULT** (🍁). Every org write carries
  `-o Prod-Org` explicitly.
- Prod-Org baseline: `SELECT COUNT() FROM Case` → **26**; `WHERE Status='Closed'` → **23**;
  `SELECT COUNT() FROM Account` → **13**.

## Clean-start proof (Prod-Org, before deploy)
`sf project retrieve start -m ... -o Prod-Org` → **Nothing retrieved**, 6 warnings, all
`cannot be found`:
`CustomField:Case.Customer_Satisfaction__c`, `CustomField:Account.Satisfaction_Anzahl__c`,
`ValidationRule:Case.Customer_Satisfaction_PflichtBeiClosed`,
`ApexTrigger:CaseSatisfactionTrigger`, `ApexClass:SatisfactionTaskHandler`,
`PermissionSet:SCRUM442_Satisfaction_Read`.
=> none of SCRUM-442 was live in Prod before this release.

**Trap that produced a false proof:** the same retrieve WITHOUT `-o Prod-Org` returned
`Created` for all six — that was Test-Org (the default), not Prod. An org-mismatch signal,
not a deploy problem.

## Manifest vs disk (verified before touching the org)
All 8 `manifest/scr442-*.xml` parsed, **38 manifest members, 0 missing on disk** in the
master worktree at `2546856`. apiVersion of all 8 manifests: **67.0** (the SCRUM-440 trap —
68.0 is rejected by the Prod validator — is already correct here).

## Release scope = diff to previous release tag (measured, not from memory)
`git diff --name-only release/2026-10-10-SCRUM-440 origin/master -- force-app/` → **46 files**,
identical to PR #164's force-app file list (46). Mapping:
- phase1 fields: 6 CustomFields (Case.Customer_Satisfaction__c + 5 Account.Satisfaction_*)
- phase2 referencing: ValRule + 3 PS + 2 Layouts + 3 Apex classes + Trigger
- phase2b report: 5 Account fields + `Sales/Miserable_Kunde_Satisfaction`
- phase3 house tests: 17 ApexClasses (16 house fixture tests the merge had to adapt to the
  new mandatory field + SCRUM442TestFixtures) — **older fixture tests belong to the release
  scope** because the merge commit changed them; otherwise they run red in Prod against the
  new ValRule
- testps: `SCRUM442_TestObjectAccess` (test-local, assigned ONLY to fixture users created by
  SCRUM442TestFixtures — never to real users)
- apextests: SCRUM442SatisfactionTest, SCRUM442SatisfactionFlsTest, SCRUM442AccountRollupTest

## ValRule dependency check (Prod)
`errorConditionFormula` = `AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Customer_Satisfaction__c)), NOT(Dedupliziert__c))`
→ `Case.Dedupliziert__c` verified **Created in Prod-Org** (retrieve proof), so the rule's
dependency is live. Validation rules do not re-validate existing records; the 23 already-closed
Prod Cases are not retroactively blocked.

## Pre-deploy validate (Prod-Org) — measured, not assumed
`sf project deploy validate --manifest manifest/scr442-phase1-fields.xml -o Prod-Org --concise`
→ Deploy ID **0Afg500000Fm0jRCAR**, `Deploying Metadata 6/6 (100%)`, `Running Tests 330/331`,
**Status: Failed** — one test failure, byte-exact:
`SCRUM424FirstResponseTest.ac7_weekend_calendar_minutes_under_247` —
`Expected: 2520, Actual: 1980` (line 212).
That is the **known foreign BusinessHours trap** (SCRUM-437 notizen name the same class; SCRUM-424
notizen record Prod BusinessHours being set to Mo–Fr 09–17 on 2026-09-23). Read back
`GET /sobjects/BusinessHours/01mg5000004gR7xAAE -o Prod-Org`: `Name=Default IsDefault=True
TimeZoneSidKey=Europe/Berlin`, Mon–Fri `09:00:00.000Z`–`17:00:00.000Z`, Sat/Sun `00:00` →
Prod is a working-week org, so a test that hard-codes 24/7 (2520 min) is **stale for Prod**, not
a SCRUM-442 defect. `validate` has no `NoTestRun` (help: RunAllTestsInOrg|RunLocalTests|
RunSpecifiedTests|RunRelevantTests) — a validate always runs tests. Hence the house 3-phase
pattern: deploy with `--test-level NoTestRun` (the deploy subcommand accepts it), Apex tests in a
separate `sf apex run test -o Prod-Org`.

## Prod deploy (measured, job ids read back)
| Phase | Manifest | Deploy ID | Result |
|---|---|---|---|
| 1 fields | scr442-phase1-fields.xml | **0Afg500000FlxKACAZ** | 6/6 Created, 0 errors, 35.5s |
| 2 referencing | scr442-phase2-referencing.xml | **0Afg500000Fm23hCAB** | 10/10 (12 Created, 2 Layouts **Changed**) |
| 2b report | scr442-phase2b-report.xml | **0Afg500000Fltq2CAB** | 6/6 (5 fields Unchanged — already in Phase 1 — + Report Created) |
| 3 house tests | scr442-phase3-house-tests.xml | — | 17 classes: 15 Changed, 2 Created |
| ticket tests | scr442-apextests.xml | **0Afg500000Fm2JpCAJ** | Succeeded, numberComponentErrors 0 |
| test-local PS | scr442-testps.xml | **0Afg500000Fm2LRCAZ** | Succeeded |

## PS assignment read-back (Prod-Org) — 6 rows = 3 PS × 2 users
PS Ids: Read `0PSg500000Dai7uGAB`, System `0PSg500000Dai7vGAB`, Write `0PSg500000Dai7wGAB`.
`SELECT Id, AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE PermissionSetId IN (...)`
→ **6 rows**: `005g5000009C38DAAS` (@user, System Admin) and `005g5000009C4M4AAK` (CLI) each hold
all three PS.
**Trap:** querying `PermissionSetName` on `PermissionSetAssignment` throws `No such column` — the
field is `PermissionSetId` (the record has no name field). A wrong field name, not a missing
assignee.

## Field read-back through a real session (Prod-Org)
- `SELECT Id, Subject, Status, Customer_Satisfaction__c FROM Case WHERE Status='Closed' LIMIT 3`
  → 3 rows, column present, values `null` (the 23 Cases closed **before** the release carry no
  score; validation rules do not re-validate existing records).
- `SELECT ... Satisfaction_Anzahl__c, Durchdurch__c, Min__c, Fenster_Start__c, Arger__c FROM Account`
  → 2 rows, all 5 columns readable, `Arger__c = 'Kein Daten'` (formula, no scores yet).
- `Name` is **not** a field on Case (`No such column 'Name'`) — use `Subject`.

## Prod Apex tests (separate run, scoped to this ticket)
`sf apex run test -o Prod-Org --tests SCRUM442SatisfactionTest --tests SCRUM442SatisfactionFlsTest
--tests SCRUM442AccountRollupTest` → run **707g500000qJpWr**, `sf apex get test -i ... -o Prod-Org`
→ **Outcome Passed, 19 tests, Pass Rate 100 %, Fail Rate 0 %, OrgId 00Dg500000DkTtzEAF**.
Includes the negative FLS tests green in Prod: `withoutPS_scoreInvisible`,
`salesShape_writeRefusedValueUnchanged`, `readPS_readableNotUpdateable`.
`--tests` separates by **repetition/space**, not comma. `sf apex get test` has **no `--wait`** flag.

## Status
- [x] gate check (Release + assignee devops-agent, both read back)
- [x] PO confirmation on record (AC1–AC8 PASS)
- [x] clean-start proof in Prod (6/6 `cannot be found`)
- [x] manifest members vs disk (38/38 present, apiVersion 67.0)
- [x] Prod baseline counts (26 Cases / 23 closed / 13 Accounts)
- [x] pre-deploy validate (metadata 6/6; 1 foreign stale test, documented above)
- [x] Phase 1 fields → Prod (0Afg500000FlxKACAZ, 6/6)
- [x] Phase 2 referencing → Prod (0Afg500000Fm23hCAB, 10/10)
- [x] Phase 2b report → Prod (0Afg500000Fltq2CAB, Report Created)
- [x] Phase 3 house tests + ticket tests + test-local PS → Prod
- [x] PS assigned to BOTH Prod users; read-back 6 rows
- [x] field read-back through real session (Case + Account columns present)
- [x] Apex tests in Prod: 19/19 Pass, run 707g500000qJpWr
- [ ] release tag `release/2026-10-12-SCRUM-442`

## Open foreign blocker (not mine, not blocking this release)
SCRUM-444: Test-Org orphan Apex class `SCRUM434Probe` reddens the Smoke gate on `master`
for every following PR. Filed 2026-10-12, assigned developer-agent. The Prod release does
not depend on it — Prod test runs are scoped to SCRUM-442's own classes.
