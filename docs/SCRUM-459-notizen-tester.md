# SCRUM-459 — Tester notizen

Verified facts only; command named beside each.

## Org measurements (VERIFIED by me, 2026-10-31)
- open Opportunities total: 76 — `sf data query -o Test-Org --query "SELECT Id FROM Opportunity WHERE IsClosed=false" --use-total-size` (totalSize)
- open with Amount > 50000: 13 — same query + `AND Amount > 50000`
- Followup_Obligation__c records before my fixtures: 0 — `SELECT Id FROM Followup_Obligation__c`
- ApexTestQueueItem last 24h: 34 rows (ceiling 500) — `sf data query -o Test-Org -t --query "SELECT COUNT(Id) FROM ApexTestQueueItem WHERE CreatedDate = LAST_N_DAYS:1"` -> expr0=34

## State at handoff
- Branch feature/SCRUM-459-followup-monitoring, head e62c995, PR #181 APPROVED by Architect.
- CI on e62c995: all 4 checks green per Architect read-back (gh pr checks 181).
- Apex test classes: SCRUM459FollowupMonitorTest, SCRUM459FollowupFlsTest — 15/15 green in CI smoke.
- 3 Permission Sets: SCRUM459_FollowupMonitoring_Read (read/edit=false), SCRUM459_FollowupMonitoring_Write (read/edit=true), SCRUM459_FollowupObligation_Rep — each assigned to devops-agent@cline.test + meerwais.osmani@resourceful-bear-6f1u4j.com.
- Object: Followup_Obligation__c (fields Opportunity__c, Status__c Outstanding/Completed, Due_Date__c, Completed_Date__c, Next_Action__c).
- Opportunity fields: Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c, Last_Customer_Interaction__c, Followup_Status__c (Up to Date/Due Soon/Overdue), Needs_Manager_Attention__c.
- List view: Follow_up_Monitoring (pre-filtered overdue count > 0).

## Findings while testing (verified, command named)
- GAP A — Followup_Obligation__c has NO usable record page. `/lightning/o/Followup_Obligation__c/new` renders only "Obligation Number"+"Owner" (probe-459.mjs: getByLabel/getByText for Due Date/Next Action/Status/Opportunity = 0, twice incl. after 30s polling probe-459b.mjs). Record view of existing record a05WU00001AsgK9YAJ: Details tab shows only Number/Owner/Created/Modified (probe-459d.mjs). Opportunity page has no "New Follow-up Obligation" action (Lookup relationship, no related list). => Rep cannot create/complete obligations via UI. House precedent: manifest/scr411-recordpage.xml deploys FlexiPage record pages for custom objects; force-app/main/default/flexipages/ has NO file for Followup_Obligation__c (ls).
- GAP B — the six monitoring fields are NOT rendered on the Opportunity record page. Details tab getByText for all six labels = 0 (probe-459c.mjs, before and after Details-tab click). They ARE in the list view Follow_up_Monitoring (all six columns render values, each cell shows "Locked").
- List view locators VERIFIED: /lightning/o/Opportunity/list?filterName=Follow_up_Monitoring; header row ariaSnapshot "Select N item(s)"; data rows: value BEFORE label ("1 Locked Overdue Follow-ups"); dates locale DD.MM.YYYY (probe-459c.mjs).
- Guard refusal message carries the API name (e.g. Overdue_Followup_Count__c) — FollowupMonitoringHandler.assertNoUserTypedValues -> refuseTypedValue(field); CLI save refused, stored value unchanged (spec AC6 run).
- Trigger fires on obligation saves incl. CLI saves (AC5/AC8 spec: CLI update of obligation recomputed count/status/last-interaction on Opportunity without touching it).
- Fixture cleanup: all TEST-SCRUM459-E2E-* records deleted in afterAll + manual sweep (sf data delete record); Followup_Obligation__c back to 0.

## Findings while testing (append one line each, with the command)
- ROUND 2 (2026-11-01, after SCRUM-460 fix — record pages are Layouts, not FlexiPages, ADR 8):
- FIXED GAP A — `/lightning/o/Followup_Obligation__c/new` now renders the full form: dialog "New Follow-up Obligation", textbox "Next Action", combobox "Opportunity", combobox "Status" (default Outstanding), textbox "Due Date"+"Completed On", buttons "Save & New"/"Save" (probe-459e.mjs, fresh storageState after smoke run). Record view shows inline buttons "Edit Status"/"Edit Completed On"/"Edit Due Date"/"Edit Next Action"/"Edit Opportunity"; dates render DD.MM.YYYY.
- FIXED GAP B — /ui-api/record-ui on Opportunity 006WU00000Q2RZqYAN (sf api request rest, scratch/recordui-opp.json): 9 sections incl. "Follow-up Monitoring" with all six fields; existing sections (Discount Approval, Risk Level, ...) intact.
- Obligation layout via record-ui on probe record a05WU00001AtOGLYA3 (created+deleted by me): Name editableForNew/Update=false, Opportunity__c/Status__c/Due_Date__c/Next_Action__c/Completed_Date__c all true.
- Apex budget 24h before round-2 run: 52 rows (ceiling 500).
- CI on new head fbef189: gh pr checks 181 -> all 4 green (incl. Prod-Org Drift Gate).
