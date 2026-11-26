# SCRUM-482 notizen (Architect, 2026-11-26) — hard-won findings, one line each

- Field formula (verbatim, `git show origin/master:force-app/main/default/objects/Opportunity/fields/Stage_Days_In_Current_Stage__c.field-meta.xml`):
  `IF(OR(ISPICKVAL(StageName,"Closed Won"),ISPICKVAL(StageName,"Closed Lost")), NULL, TODAY() - DATEVALUE(IF(ISBLANK(LastStageChangeDate), CreatedDate, LastStageChangeDate)))`
- `CreatedDate` and `LastStageChangeDate` are `createable: false` in **Test-Org AND Prod-Org**
  (`sf sobject describe --target-org <org> -s Opportunity --json`) → a test record always anchors on the run day
  → **no self-created fixture can ever be 31+ days old.** T2's magnitude is unreachable, by platform, not by design shortcut.
- Createable, non-autofilled Date fields on Opportunity are only CloseDate, Last_Customer_Interaction__c,
  Next_Followup_Date__c, Offer_Sent_On__c, Offer_Valid_Until__c — none feeds this formula.
- StageName values (org describe picklistValues): Prospecting, Qualification, Needs Analysis, Value Proposition,
  Id. Decision Makers, Perception Analysis, Proposal/Price Quote, Negotiation/Review, Closed Won, Closed Lost.
- New CI gate `scripts/test-hygiene-gate.py` (master d4c310b) blocks only `SeeAllData = true` and a literal
  Username/Email inside a `FROM User` query. Run: `python3 scripts/test-hygiene-gate.py --files <cls>` →
  **5 findings, all SeeAllData, on the two SCRUM-477 classes; 0 on SCRUM449/SCRUM467 model classes.**
  It does NOT block an org-wide `SELECT ... FROM Opportunity` → isolation must come from `SeeAllData=false` + `WHERE Id = :fixtureId`.
- PS holders re-read 2026-11-26 with `sf data query --target-org <org> --use-tooling-api -q "SELECT AssigneeId, IsActive, IsRevoked
  FROM PermissionSetAssignment WHERE PermissionSetId = '<id>'"` → **4 active Test-Org / 5 active Prod-Org, none revoked**
  (PO's counts reproduce). `PermissionSetName` does NOT exist on PermissionSetAssignment (query failed: "No such column");
  the entity's fields are Id, PermissionSetId, PermissionSetGroupId, AssigneeId, SystemModstamp, ExpirationDate, IsActive, IsRevoked.
- House shape for User+PS+Opportunity in one test class = SCRUM467OfferFlsTest (2026-11-21): `mkUser(tag, psNames)` inserts
  User + PSA in System context, business DML inside `System.runAs` (the runAs is the savepoint boundary, SCRUM-442 Cause E says
  PSA + Account/Case/User DML cannot share a transaction in either order). `Alias` ≤ 8 chars, en_US locale, America/Los_Angeles tz
  (others rejected in this org).
- Apex does not enforce FLS on its own writes (SCRUM467 AC13 measured): assert `getDescribe().isAccessible()/isUpdateable()`
  + a rejected SOQL read, never a refused Apex update. The counter is additionally `createable: false`, so a write-refusal test
  would pass even with a useless Permission Set.
- 4 Opportunity triggers run on every fixture save (OpportunityFollowupGuard/Monitor, OpportunityOverdueReset, OpportunityRisk)
  → the SCRUM-442 "fields being inaccessible on Sobject" runtime wall is a live risk for a Standard-User fixture save; fix by
  fixture transition, never by a new grant.
- Jira mangles double underscores even in code fences; verbatim names only in backticks or from the org.
- **CORRECTION 2026-11-26, after @user's challenge — `createable:false` does NOT make an autofill anchor untestable.**
  Measured with `sf apex run` in Test-Org (probe file scratch/probe_backdate.apex, both probe records deleted,
  0 leftovers named `TEST-SCRUM-482-PROBE*`): a fresh Opportunity insert reads `LastStageChangeDate` **null**
  (`FRESH rows=1 LASTSTAGE=null COUNTER=0`), so the formula takes the `CreatedDate` branch; setting
  `LastStageChangeDate` in Apex is refused at COMPILE time (`Field is not writeable: Opportunity.LastStageChangeDate`);
  `Test.setCreatedDate(id, dt)` compiles and throws `Use Test.setCreatedDate() within tests.` outside a test — test-context only.
  House precedent already on master and green: `SCRUM398EskalationsstufeTest` L42 and `SCRUM424FirstResponseTest` L62
  call `Test.setCreatedDate(<id>, DateTime.now().addDays(-n))` right after the insert on a `TODAY() - DATEVALUE(CreatedDate)`
  formula. Therefore T2 (">30 days shows the right number") is automatable: insert, backdate 40, expect 40; then change
  stage, expect 0. ADR-3 of the design doc was rewritten accordingly.
