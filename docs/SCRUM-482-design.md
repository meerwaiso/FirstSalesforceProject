# SCRUM-482 — Design: the two SCRUM-477 stage-days tests judge only their own work

Architect-Agent design for SCRUM-482. Basis: the ticket description plus the artefacts below,
all measured 2026-11-26 (not recalled). The Developer builds exactly this; deviations need a
comment in the PR.

## Goal

Rebuild SCRUM477StageDaysReadTest and SCRUM477CurrentStageDaysFlsTest so that their verdict
comes only from Opportunity records and User rows they create themselves — identical in
Test-Org and Prod-Org, on any day — without touching the counter, its formula, the stuck list
or the Permission Set.

## 1. Measured base (verified 2026-11-26, commands named)

| # | Fact | How it was verified |
|---|------|---------------------|
| M1 | `Stage_Days_In_Current_Stage__c` is a Number formula: `IF(OR(ISPICKVAL(StageName,"Closed Won"),ISPICKVAL(StageName,"Closed Lost")), NULL, TODAY() - DATEVALUE(IF(ISBLANK(LastStageChangeDate), CreatedDate, LastStageChangeDate)))` | `git show origin/master:force-app/main/default/objects/Opportunity/fields/Stage_Days_In_Current_Stage__c.field-meta.xml` |
| M2 | In **both** orgs `CreatedDate` and `LastStageChangeDate` have `createable: false`; no createable, non-autofilled Date field feeds the formula (only `CloseDate`, `Last_Customer_Interaction__c`, `Next_Followup_Date__c`, `Offer_*` do) | `sf sobject describe --target-org Test-Org -s Opportunity --json` and the same for `Prod-Org`, filtered in python |
| M3 | Stage values are the standard ones: Prospecting, Qualification, Needs Analysis, Value Proposition, Id. Decision Makers, Perception Analysis, Proposal/Price Quote, Negotiation/Review, Closed Won, Closed Lost | `sf sobject describe ... picklistValues` |
| M4 | Fixture saves must clear active Opportunity validation rules: Closed Lost needs `Loss_Reason__c` (SCRUM-381); Closed Lost + `Loss_Reason__c='Wettbewerber'` needs `Competitor_Lost_To__c` (SCRUM-461); Closed Won is blocked only if `Discount_in_Pct__c > 0.15` without approval (SCRUM-445); any `Discount_in_Pct__c > 0.25` is refused (SCRUM-445) | `git show .../validationRules/*.validationRule-meta.xml` |
| M5 | The stuck list is the report `Sales/Chancen_Over_30_Tage`: filter `STAGE_NAME notEqual Closed Won,Closed Lost` + `Opportunity.Stage_Days_In_Current_Stage__c greaterThan 30`, `groupingsDown` on the day counter (Day, Desc), columns OPPORTUNITY_NAME/FULL_NAME/STAGE_NAME/AMOUNT, `timeFrameFilter` CREATED_DATE 2000-01-01…2099-12-31 | `git show origin/master:force-app/main/default/reports/Sales/Chancen_Over_30_Tage.report-meta.xml` |
| M6 | PS holders read back today: **4 active, none revoked in Test-Org** (PS id 0PSWU00000YFgTB4A1), **5 in Prod-Org** (0PSg500000EuEcyGAF) — the PO's counts reproduce | `sf data query --target-org <org> --use-tooling-api -q "SELECT AssigneeId, IsActive, IsRevoked FROM PermissionSetAssignment WHERE PermissionSetId = '<ps id>'"` |
| M7 | `scripts/test-hygiene-gate.py` (master d4c310b, the gate the PO means) is red on both current classes — **5 findings, all `SeeAllData = true`** — and green on SCRUM449OpportunityRiskFlsTest and SCRUM467OfferFlsTest | `python3 scripts/test-hygiene-gate.py --files <those four files>` in the SCRUM-482 worktree |
| M8 | The gate only blocks (A) `SeeAllData = true` and (B) a literal `Username/Email` inside a `FROM User` query. A `SELECT ... FROM Opportunity` is **not** caught by the gate — under `SeeAllData = false` the Apex test scope returns only records the test created. Isolation therefore rests on SeeAllData=false, not on the gate | gate source in `scripts/test-hygiene-gate.py` |
| M9 | House shape for User + Permission Set + Opportunity in one test class: `System.runAs` is the savepoint boundary that separates setup DML (User, PSA) from business DML; `Alias` is limited to 8 chars, `LanguageLocaleKey=en_US`, `LocaleSidKey=en_US`, `TimeZoneSidKey=America/Los_Angeles` were rejected otherwise in this org | `SCRUM467OfferFlsTest` (2026-11-21, newest, Opportunity-based) and `SCRUM449OpportunityRiskFlsTest` |
| M10 | An Apex `update` by a user without field FLS is **not** refused (Apex runs "on the inside"); the FLS boundary is enforced for `getDescribe()`, SOQL, UI and API | house measurement in SCRUM467OfferFlsTest AC13 comment |
| M11 | Formula fields are not on the in-memory SObject after DML — the value has to be read back through a query | house note in SCRUM403LastCaseDateTest |

## 2. Components

- **SCRUM477StageDaysReadTest** (rebuilt, `@isTest`, no `SeeAllData`): the *counter behaviour*
  on its own fixtures — new open deal = 0, stage change restarts the count on the new anchor,
  closed deals carry no number, and the value always equals `TODAY()` minus the record's own
  anchor.
- **SCRUM477CurrentStageDaysFlsTest** (rebuilt, `@isTest`, no `SeeAllData`): the *permission
  boundary* on its own two users and its own fixture — holder reads, nobody writes, non-holder
  cannot read.
- **No new class.** `mkUser(tag, psNames)` is a private helper in each class, copied from
  `SCRUM467OfferFlsTest`. A shared `SCRUM482TestFixtures` class was rejected: it adds a
  deployable component that the Prod-Org Drift Gate has to compile in both orgs, and AC5
  ("no orphan Apex test class in either org") turns that extra component into a second
  deployment obligation. Two private helpers cost 15 duplicated lines.

## 3. Interfaces / pseudocode

```
SCRUM477StageDaysReadTest  (@isTest, SeeAllData=false, apiVersion 67.0)
  private Opportunity fixture(Id id, Text stage)   // builds an in-memory record
  private Text readBack(Id id)                     // SELECT Id, StageName, CreatedDate,
                                                   //   LastStageChangeDate,
                                                   //   Stage_Days_In_Current_Stage__c
                                                   //   WHERE Id = :id   -> exactly 1 row asserted
  @isTest  newOpenDeal_showsZeroDays()             // T1: insert StageName='Prospecting',
                                                   //     Name='TEST-SCRUM-482-T1', Amount>0, CloseDate=today+25
                                                   //   assert LastStageChangeDate == null      (fallback branch)
                                                   //   assert counter == 0 == today - CreatedDate
  @isTest  stageChange_restartsTheCount()          // T3: insert open fixture, update StageName
                                                   //     to another open value, assert
                                                   //     LastStageChangeDate != null AND counter == today - LastStageChangeDate
  @isTest  closedDeal_carriesNoNumber()            // T4: insert StageName='Closed Won' (Discount blank ->
                                                   //     M4 rules stay quiet) AND insert StageName='Closed Lost'
                                                   //     with Loss_Reason__c='KeinBudget'
                                                   //   assert counter == null for both

SCRUM477CurrentStageDaysFlsTest  (@isTest, SeeAllData=false, apiVersion 67.0)
  private User mkUser(Text tag, List<Text> psNames)  // verbatim house shape (M9):
                                                   //   Profile 'Standard User'; LastName='Scr482Fls-'+tag;
                                                   //   Alias=('f482'+tag).left(8);
                                                   //   Username='scr482fls-'+tag+'-'+DateTime.now().getTime()+'@example.invalid';
                                                   //   insert u; for each psName:
                                                   //     PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
                                                   //     System.assert(ps != null, 'precondition: PS deployed');
                                                   //     insert new PermissionSetAssignment(AssigneeId=u.Id, PermissionSetId=ps.Id);
  @isTest  holderReadsTheCounter_nobodyWritesIt()   // T5: User with = mkUser('holder',
                                                   //        {'SCRUM477_CurrentStageDays_Read'})
                                                   //     User without = mkUser('blind', {})   // differs ONLY in that grant
                                                   //   runAs(blind): Opportunity.SObjectType.getDescribe().isAccessible()  -> precondition
                                                   //   runAs(holder): SOQL 'SELECT Id, Stage_Days... WHERE Id = :fixtureId'
                                                   //     assert 1 row AND value == 0 (fixture made by holder in runAs)
                                                   //     assert getDescribe().isAccessible() == true
                                                   //     assert getDescribe().isUpdateable() == false   // M10: NOT a refused Apex write
  @isTest  withoutPermissionSet_theNumberIsNotReadable()  // T6, the mandatory negative:
                                                   //   runAs(blind) { try { SELECT Id, Stage_Days... WHERE Id = :fixtureId }
                                                   //                catch (Exception e) { rejected = true; } }
                                                   //   assert rejected == true            // ONLY the SELECT inside the try
                                                   //   assert getDescribe().isAccessible() == false
                                                   //   every assert OUTSIDE the runAs block (house warning SCRUM-449/453)
```

`fixtureId` is created by the test inside the same `runAs` (M9: business DML inside
`runAs`, PSA/User setup outside). Both classes carry a `@TestSetup` only if the Developer's
measurement forces a second savepoint; the default is one method = one transaction.

## 4. ADR

**ADR-1 — Apex, no Flow.** Everything here is Apex test classes plus one report metadata
file. No Flow element is created, changed or referenced; the org's Flow deployments stay as
they are. Flows were not considered for the test layer at all (a Flow cannot assert anything),
and this ticket adds no declarative component, so the "Flow vs Apex" decision is Apex by
default — no schema/apiVersion risk carried.

**ADR-2 — SeeAllData is dropped from both classes; it is the isolation mechanism.** The old
classes run `@isTest(SeeAllData=true)` and read the whole org. With `SeeAllData=false` an
Apex query returns only records created inside the test, so *any* leftover
`SELECT ... FROM Opportunity` in the rebuilt classes can no longer see a stranger's deal:
AC1 ("records the class read but did not create = 0") and AC4 become mechanically true, and
the CI gate `test-hygiene-gate.py` turns the same pattern red on the PR (M7: it is red on
both classes today, green on the model classes). Every fixture query is
`WHERE Id = :fixtureId` with an asserted row count of 1, so a vacuous pass is impossible.

**ADR-3 — T2 ("open deal stuck more than 30 days shows the right number") cannot be produced
by a self-created fixture, and the automated layer tests the rule instead of the magnitude.**
The counter's only inputs are `LastStageChangeDate` (fallback `CreatedDate`) — both
`createable: false` in **Test-Org and Prod-Org** (M2). A record created inside a test
therefore always has both anchors = the run day: the day-difference is always 0, and a fresh
fixture can never be 31+ days old. That is a platform limit, not a test-design shortcut:
`SCRUM477StageDaysReadTest` said so in its own header before this ticket. The ticket's own
hard rules make it worse — an aged fixture (a record created 40 days ago by an earlier run)
would give different verdicts on different days and different verdicts per org, violating
AC2 and AC3.
So the automated layer keeps the **rule**, and the magnitude moves where it actually lives:
- **Automated (both orgs, any day):** counter == `TODAY() − own anchor`; anchor ==
  `LastStageChangeDate` once a stage change happened, `CreatedDate` before that; stage change
  moves the anchor and keeps the count at 0; closed deals return no number. That is T1, T3,
  T4 plus the anchor branch of T2 — non-vacuous because the fixture row count is asserted as 1.
- **Release read-back (PO, per release, not an automated test):** run the report
  `Sales/Chancen_Over_30_Tage` in each org and state the number of rows and the largest group
  label; plus the `PermissionSetAssignment` counts (M6: 4 Test / 5 Prod today). The `> 30`
  threshold itself is metadata on the branch (M5, `greaterThan 30`), and the Prod-Org Drift
  Gate already diffs that file against Prod-Org on every PR.
- **Not allowed:** a test that manufactures an old anchor (impossible), a re-implementation of
  the formula in Apex and a unit test of that copy (tests the copy, not the live field), or a
  long-lived aged fixture left in an org (forbidden by "no leftovers", breaks AC2/AC3).

**ADR-4 — the FLS negative is asserted with `getDescribe()` plus a rejected SOQL read of the
test's own record, never with a refused Apex write.** M10 measured that Apex is "inside" its
own permission check: an Apex `update` by a user without the grant goes through, so asserting
a blocked write proves nothing about the Permission Set; `getDescribe().isAccessible()/
isUpdateable()` and a SOQL read *are* the boundary (and are what the record page and the API
hit). `Stage_Days_In_Current_Stage__c` is additionally `createable: false` (M2), so an Apex
write to it is refused for everyone, with or without the grant — a test built on that would
pass even if the Permission Set granted nothing.

**ADR-5 — Mixed DML: setup DML (User, PermissionSetAssignment) outside, Opportunity DML
inside `System.runAs`.** M9. `PermissionSetAssignment` is not a setup object for Account/Case/
User DML in one transaction (SCRUM-442 measured both orders red). `System.runAs` is the
savepoint boundary the house uses; SCRUM467OfferFlsTest is green with exactly this order
(Opportunity inserts inside `runAs`, User + PSA inserts before it).

**ADR-6 — fixture naming and teardown.** Records: `Name = 'TEST-SCRUM-482-T1'` … one name per
criterion (PO's `TEST-SCRUM-NNN` house prefix, SCRUM-474). Users: `LastName = 'Scr482Fls-<tag>'`,
`Alias = ('f482'+tag).left(8)`, `Username = 'scr482fls-<tag>-<getTime()>@example.invalid'`
(unique per run in whichever org, no real person, no PII). Teardown is explicit: the method
collects the created Ids (Opportunities, Users, PermissionSetAssignments) and deletes them in
one bulk `delete` at the end of the method, including on the failure path; the Apex test
framework's own rollback is not relied on (SCRUM-474 left stale `TEST-SCRUM-378` fixtures in
an org). Any residue is cleaned by a named CLI step at release time, not by an org-wide query
inside a test.

## 5. Data model — no change

`Stage_Days_In_Current_Stage__c` stays exactly as deployed: Number(10, 0), formula per M1,
label "Tage jetzige Stage", same in both orgs. No new field, no renamed field, no touched
formula, no new validation rule, no record type change. The report M5 and the layouts of
SCRUM-477 are untouched.

## 6. Permission Set / FLS design — unchanged by this ticket, restated for the review

- PS `SCRUM477_CurrentStageDays_Read` (read-only): `Opportunity.Stage_Days_In_Current_Stage__c`
  `readable=true`, `editable=false`. Nothing else in the set.
- Holders today (M6, read back 2026-11-26): **Test-Org 4** active, **Prod-Org 5** active, none
  revoked. Three Prod holders are technical accounts no business need names.
- The rebuilt tests may grant **only this one PS, and only to a User they created**. No new
  Permission Set, no assignment to a pre-existing user, no Profile edit, no test-local PS
  (SCRUM-442/467 created `*_TestObjectAccess` sets — forbidden here, and not needed:
  Opportunity object access is OWD for a Standard User, asserted as a precondition).
- Reviewer rule: if a fixture save is refused because an Opportunity trigger writes a field
  the fixture user cannot edit (SCRUM-442 Cause E pattern: "fields being inaccessible on Sobject
  Opportunity"), the fix is **not** a new PS and not a new grant. Four Opportunity triggers
  exist (OpportunityFollowupGuardTrigger, OpportunityFollowupMonitorTrigger,
  OpportunityOverdueReset, OpportunityRiskTrigger). Measure with
  `scripts/fls-check.sh Opportunity <Field__c> <org>` first, then change the fixture's
  transition, not the grant set.

## 7. Sharing model — no impact

Opportunity is not a shared object, no sharing rule, no OWD change, no role hierarchy change.
The report stays `scope = organization`. Stated explicitly because the tests create users: the
fixture users are Standard Users on OWD rights only.

## 8. Governor limits

- Fixtures are bounded: ≤2 Users and 2 PSAs per FLS method, ≤2 Opportunity records per method,
  never a query over the org. The old classes' `ORDER BY ... DESC` over all Opportunities (twice)
  and the loop over every active `User` with a `runAs` each are deleted — that was both the
  org dependency and the expensive part.
- No SOQL inside a loop; each read-back is one `WHERE Id = :id` query.
- Trigger overhead: the four Opportunity triggers run on every fixture save; a stage-change
  update fires them once per fixture. Bounded by the record count above.
- One broad Apex run per org at a time; the Developer deploys/runs with
  `sf project deploy start -x manifest/scr482-test.xml -o Test-Org -l RunSpecifiedTests -t SCRUM477StageDaysReadTest -t SCRUM477CurrentStageDaysFlsTest`
  (flag shapes read from `sf project deploy start --help`: `-l, --test-level` lists
  `NoTestRun|RunSpecifiedTests|RunLocalTests|RunAllTestsInOrg|RunRelevantTests`, and
  `-t, --tests` is "Apex tests to run when --test-level is RunSpecifiedTests"; `-x, --manifest`
  takes the package.xml. Never `RunLocalTests`/`RunAllTestsInOrg` — one broad run per org at a
  time, the full suite belongs to CI).

## 9. Deployment and CI obligations

- Branch: one branch, one ticket — `feature/SCRUM-482-<ticket-slug>` cut fresh from `master`.
- apiVersion **67.0** for the two classes (unchanged `.cls-meta.xml`).
- Deploy manifest: `manifest/scr477-phase3-test.xml` carries only `SCRUM477StageDaysReadTest`.
  Add `manifest/scr482-test.xml` listing **both** classes; the Prod-Org Drift Gate uploads
  branch source and runs it in Prod-Org (check-only), so an FLS/test class missing in Prod is
  the SCRUM-444/475 orphan trap (AC5). Nothing else deploys — no field, no PS, no report.
- Gates on the head: Lint & Format, Metadata/Apex/Session Smoke, **Prod-Org Drift Gate**, and
  the new **test-hygiene** job (M7). All four green, belonging to the head that is merged.
- The two old classes' `SeeAllData=true` lines vanish on this branch, so the gate stops
  complaining about them for good.

## 10. Technical acceptance criteria (mapped to the PO's AC1–AC7)

| PO AC | Automated check the reviewer will run |
|-------|----------------------------------------|
| AC1 | `python3 scripts/test-hygiene-gate.py --files <the two classes>` → green (M7: red today) AND the class sources contain no `SeeAllData`, no `FROM User`, no `SELECT ... FROM Opportunity` without `WHERE Id = :fixtureId` |
| AC2 | the same classes run in Prod-Org (Drift Gate) give the same verdict; both classes present in both orgs (AC5/orphan rule) |
| AC3 | every expectation is derived from the fixture's own `CreatedDate`/`LastStageChangeDate` or is `null`; no date constant, no "N stuck deals today" anywhere |
| AC4 | grep: no `Username =`/`Email =` literal in a query, no 15/18-char Id of a pre-existing record, fixture names carry `TEST-SCRUM-482` |
| AC5 | three CI jobs green on the head + the test-hygiene job; `grep -r SCRUM477StageDays force-app | manifest` shows both classes in the manifest |
| AC6 | `git diff origin/master -- force-app/main/default/objects/Opportunity/fields/Stage_Days_In_Current_Stage__c.field-meta.xml force-app/main/default/permissionsets/SCRUM477_CurrentStageDays_Read.permissionset-meta.xml force-app/main/default/reports/Sales/Chancen_Over_30_Tage.report-meta.xml` is **empty** |
| AC7 | Tester coverage table: one row per T1…T6 with an Observed value; see ADR-3, the ">30 days" row cannot be Observed=0-day-fixture → it is reported as **not covered by the automated layer / release read-back**, not PASS |

## 11. Open decisions for the Developer (defaults chosen, change only with a PR comment)

- [ ] T3's stage transition: default `Prospecting → Value Proposition` (M3 values, both open).
      Must be measured: do the four Opportunity triggers refuse the update under a Standard
      User fixture user (Cause E pattern)? If yes → change the transition per §6, never the grants.
- [ ] T4 primary case: `Closed Won` with blank `Discount_in_Pct__c` (M4: rule stays quiet).
      `Closed Lost` needs `Loss_Reason__c` (default `KeinBudget`, not `Wettbewerber`).
- [ ] Does the `@isTest` method that needs both a fixture Opportunity and a granted User keep
      PSA setup + Opportunity DML in one transaction (SCRUM467 shape) or split via `@TestSetup`?
      Default: SCRUM467 shape, split only if measurement says MIXED_DML.

## 12. For @user (plain words)

**Die zwei Prüf-Programs (SCRUM477StageDaysReadTest, SCRUM477CurrentStageDaysFlsTest — nur
names, nothing a user clicks changes):** they answer "does the counter of days in the current
stage behave as designed" and "can only the right people read it". Today they asked the whole
Salesforce system "how many deals are stuck right now" and "which of these real people can see
the number" — which is why they turned red over a Tuesday and Wednesday and why someone had to
hand a permission to three technical accounts in production to make them pass. After this
ticket they build their own two pretend deals and their own two pretend colleagues, ask only
those, and answer the same on every day and in both systems. Nothing a real person sees or may
do changes: same field, same numbers, same "Chances over 30 days" list, same permission.
What still gets checked by hand at a release is who in production really holds that permission —
that becomes an explicit release step (4 in the test system, 5 in production today), it does not
disappear.
