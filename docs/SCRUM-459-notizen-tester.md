# SCRUM-459 — Tester notizen

Verified facts only; command named beside each.

## Org measurements (pending — fill in)
- open Opportunities with >=1 overdue obligation: PENDING
- of those, Amount > 50000: PENDING
- open Opportunities total: 76 (Architect comment, not yet re-measured by me)
- open Opportunities with Amount > 50000: 13 (Architect comment, not yet re-measured by me)

## State at handoff
- Branch feature/SCRUM-459-followup-monitoring, head e62c995, PR #181 APPROVED by Architect.
- CI on e62c995: all 4 checks green per Architect read-back (gh pr checks 181).
- Apex test classes: SCRUM459FollowupMonitorTest, SCRUM459FollowupFlsTest — 15/15 green in CI smoke.
- 3 Permission Sets: SCRUM459_FollowupMonitoring_Read (read/edit=false), SCRUM459_FollowupMonitoring_Write (read/edit=true), SCRUM459_FollowupObligation_Rep — each assigned to devops-agent@cline.test + meerwais.osmani@resourceful-bear-6f1u4j.com.
- Object: Followup_Obligation__c (fields Opportunity__c, Status__c Outstanding/Completed, Due_Date__c, Completed_Date__c, Next_Action__c).
- Opportunity fields: Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c, Last_Customer_Interaction__c, Followup_Status__c (Up to Date/Due Soon/Overdue), Needs_Manager_Attention__c.
- List view: Follow_up_Monitoring (pre-filtered overdue count > 0).

## Findings while testing (append one line each, with the command)
- (pending)
