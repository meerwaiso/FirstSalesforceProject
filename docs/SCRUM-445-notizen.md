# SCRUM-445 — Architect-Notizen (hard findings, verified)

- Org: Test-Org / Prod-Org only. Surveyed origin/master @ 537caaf (fetched 2026-10-12).
- Opportunity Test-Org: 56 fields, 120 records, owners 005WU000017tBhRYAU (31) / 005WU000017tEKLYA2 (89). No Discount_* field exists (Test-Org + Prod-Org FieldDefinition query).
- Prod-Org Opportunity custom fields: 13 (TestFeld, Is_Overdue, Loss_Reason, Value_Tier, Days_Close_Date_Overdue, Is_Close_Date_Overdue, Rueckruf_*, ...). No collision with new names.
- `User` sObject: custom fields allowed (Checkbox probe OK), but **Lookup on User rejected** ("Invalid data type", both `Lookup` and `Reference` enum). Direct-Manager-on-User is out.
- Dry-run validated green (Test-Org, check-only): 8 Opportunity fields (Discount_in_Pct__c Percent 3/2; Discount_Approval__c Picklist Pending/Approved/Rejected; Approval_Requested_On__c, Approval_Decided_On__c DateTime; Approval_Decided_By__c Lookup User; Approved_Discount_Value__c Percent; Rejection_Reason__c Text 120; Approval_Waiting_Days__c Number formula w/ NOW()) + ListView Discount_Approval_Waiting + 2 ValRules (Discount_Hard_Cap_25, No_Won_Without_Approval).
- Pitfalls hit: `Datetime` enum invalid → `DateTime`; Lookup needs `<required>false</required>` (house shape CustomerTransfer From_User); picklist needs valueSet/valueSetDefinition (house Loss_Reason__c), `valueMap` invalid; `unique` not allowed on Lookup.
- Mapping object `DiscountApprovalManager__c` (Rep__c/Manager__c Lookup User, AutoNumber name, sharing ReadWrite, house shape CustomerTransfer__c) — dry-run green.
- Drift gate (ci.yml prod-drift, RunLocalTests→check-only, gates component findings only): probe with fields+test class in ONE package → **0 component findings**, test failure "No such column in Prod-Org" = warning only. cls-meta must use `<status>Active</status>` (not `<active>true</active>` — that yields "Invalid api version:0.0" = component error = gate red).
- AssignmentRules: only Standard on Case/Lead — none on Opportunity.
- UserRole: 18 roles, standard demo hierarchy, ForecastUserId all null → role hierarchy NOT usable to derive direct manager. Mapping object is the decision.
- Notification house pattern: OpportunityOverdueScheduler enqueues Queueable OpportunityOverdueNotification → FeedItem on target user's feed, guarded `if (!Test.isRunningTest())`. enqueueJob never inside triggers in repo.
- OWD of Opportunity: not readable via API (object-info has no sharing keys; no REST endpoint). Org-Setup read-back obligation for Developer/Tester instead.
- Test-Org Apex budget: one broad run at a time; Developer uses RunSpecifiedTests --tests SCRUM445*.
- apiVersion: 67.0 (Prod-Org validator, SCRUM-440/442 release fix).
