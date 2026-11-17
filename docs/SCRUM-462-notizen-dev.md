# SCRUM-462 — Developer notes (average-gap report column)

Branch `fix/SCRUM-462-average-gap` (cut from `feature/SCRUM-461-competitor-loss` @ `8cd12a1`), PR #183, head `18ed54c`.

## What the defect was

`<aggregateTypes>Average` on `Opportunity.Competitor_Gap__c` divides Σgap by the **row count**; `Competitor_Gap__c` is NULL when `Competitor_Price__c` is empty, so a price-unknown deal enters the average as 0. Nordwind: 70000/6 = 11666.67 shown, 70000/5 = 14000 wanted.

## Fix shape (deployed to Test-Org, 2026-11-17)

- `Opportunity.Competitor_Price_Known__c` — Number formula field `IF(ISBLANK(Competitor_Price__c), 0, 1)`, read-only, added to `SCRUM461_Competitor_Lost` (read=true/edit=false).
- Both reports: `<aggregates>` custom summary formula instead of the Average column.

## Verified against the org (each fact is an error message or a deploy report)

- `sf project deploy validate --manifest manifest/scr462-phase2-referencing.xml -o Test-Org --test-level RunRelevantTests` rejected, in order:
  - `custom summary formula developerName must begin with 'FORMULA'` → `FORMULA1`
  - `Value too long for field: Description maximum length is:255` (report `<description>`)
  - `aggregates-downGroupingContext: Invalid row summary level specified` for `0` → the grouping column token `Opportunity.Competitor_Lost_To__c` validates and deploys
  - `no CustomField named Opportunity.Competitor_Price_Known__c found` → deploy the field (phase1) before PS + reports (phase2)
- `--test-level NoTestRun` is accepted by `deploy start` (its `--help` lists `NoTestRun|RunSpecifiedTests|RunLocalTests|...`), but `deploy validate` rejects it — validate always runs tests.
- `scripts/fls-check.sh Opportunity Competitor_Price_Known__c`: exists (Formula Number) · granted read=true/edit=false by `SCRUM461_Competitor_Lost` · assigned to `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com`.
- Field evaluates: SOQL `SELECT Competitor_Lost_To__r.Name, Competitor_Gap__c, Competitor_Price_Known__c` → `Competitor_Price__c = null` ⇒ marker 0. Lookup traversal needs `__r` (`Competitor_Lost_To__r.Name`), not `__c.Name`.
- Report filter reproduced in SOQL: `Loss_Reason__c = 'Wettbewerber' AND Lost_Last_12M__c = TRUE` → 9 records (the 10th seeded deal is outside the window).

## NOT verified

- The rendered cell. No CLI path runs a report; whether `downGroupingContext` shows the formula per group row or only at the grand-summary row is settled by the Tester's screenshot, not by anything here.
