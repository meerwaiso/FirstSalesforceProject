# SCRUM-477 — Developer notizen (2026-11-25)

Hard-won findings, each with the command that produced it. Read this first after
any compaction; the artefacts are in the commit, the reasoning is here.

## Org / CLI facts measured this ticket

- Org alias `Test-Org` resolves to `devops-agent@cline.test`; org users (query
  `SELECT Id, Username, Name FROM User` → 8 rows): the human test account is
  `meerwais.osmani@resourceful-bear-6f1u4j.com` (Id `005WU000017tBhRYAU`).
- `Opportunity` has **no** `Status` and no `Owner` field: open/closed comes from
  `StageName`, the owner is `OwnerId` (`SELECT ... Owner FROM Opportunity` →
  "No such column 'Owner' on entity 'Opportunity'").
- After the deploy: **76** open Opportunities have
  `Stage_Days_In_Current_Stage__c > 30` (`sf data query -o Test-Org -q
  "SELECT COUNT() FROM Opportunity WHERE Stage_Days_In_Current_Stage__c > 30 AND
  StageName != 'Closed Won' AND StageName != 'Closed Lost'"` → Total records
  retrieved: 76). Top row `Dickenson Mobile Generators | Qualification | 15000 |
  144`, sorted descending. This is the Observed M the Tester needs; 0 is a build
  problem, not a fact about the org.
- CLI-session read of the field works (same query, `ORDER BY ... DESC`, rows back
  with values) → FLS granted + assigned for the CLI user.
- `scripts/fls-check.sh Opportunity Stage_Days_In_Current_Stage__c Test-Org` →
  1. Existenz ja (Formula (Number)); 2. granted by `SCRUM477_CurrentStageDays_Read`
  read=true edit=false; 3. assigned to 2 users (devops-agent@cline.test,
  meerwais.osmani@...).

## Two org rejections that had to be repaired in the files

1. `description` > 255 chars on BOTH `PermissionSet` and `Report` →
   "data value too large" / "Value too long for field: Description maximum
   length is:255". Shortened, redeployed.
2. Report: the day counter may not sit in `<columns>` **and** `<groupingsDown>` →
   "columns-field: You can't include groupings in the selected columns list".
   AC8 (longest first) needs the grouping, so the day count is the **group label**,
   exactly like the house report `Ueberfaellige_Faelle` (SCRUM-390), where the
   grouping `PRIORITY` is not a column either. AC7's five values are therefore
   four detail columns + the day count as group label — open point for the
   reviewer, see PR.

## Apex API traps hit this ticket (compiler said it, don't re-guess)

- `DateTime.getDate()` does not exist → `o.CreatedDate.date()` (house:
  `AccountReactivationBatch.cls:87  ref = a.CreatedDate.date();`).
- `Date.dayDistance(...)` and `Date.diff(...)` do not exist → `from.daysBetween(to)`
  (house: `AccountReactivationBatch.cls:112 return fromDate.daysBetween(toDate);`).
- `User_Identifier__c` is not a type in an anonymous `sf apex run` script, and
  `System.runAs` there fails with "System.runAs can only be used within a test
  method" → an FLS read-back of a real org user needs an `@isTest` class deployed
  with `--test-level RunSpecifiedTests -t <TestClass>`, never a probe.
- A test class without `SeeAllData=true` sees NO pre-existing org record: all three
  methods failed with "no stuck record found" while the CLI query returned 76 rows.
  The read-back class is therefore annotated `@isTest(SeeAllData=true)` on class
  AND per method (a method-level plain `@isTest` alone re-enters the sandbox).

## Deploy state (all live in Test-Org)

- `sf project deploy validate` has **no** `NoTestRun` in CLI 2.150.6
  (`--help` lists only RunAllTestsInOrg|RunLocalTests|RunSpecifiedTests|RunRelevantTests);
  `--test-level RunRelevantTests` ran 0 tests, so the shape checks cost no test budget.
- Phase 1 `manifest/scr477-phase1-field.xml` → field Created (Deploy ID 0AfWU00000dQ4hR0AS).
- Phase 2 `manifest/scr477-phase2-referencing.xml` → PS Created, Layout Changed,
  Report Created (0AfWU00000dQ4sj0AC), after the two rejections above.
- Phase 3 `manifest/scr477-phase3-test.xml` → `SCRUM477StageDaysReadTest`
  deployed + run with RunSpecifiedTests: **3/3 passing** (0AfWU00000dQ6L30AK).
- PS assigned with `sf org assign permset -n SCRUM477_CurrentStageDays_Read -o
  Test-Org -b devops-agent@cline.test -b meerwais.osmani@resourceful-bear-6f1u4j.com`.

## Untouched by this ticket

The shared checkout (`feature/SCRUM-424-first-response`) carries files of other,
unfinished tickets; work happened in the worktree
`/home/fino/Desktop/SoftwareProjects/Salesforce/wt-SCRUM-477` and nothing else was
touched.
