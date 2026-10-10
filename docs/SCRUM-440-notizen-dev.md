# SCRUM-440 — Developer-Notizen (hard findings, one line each)

- Worktree: `feature/SCRUM-440-rueckruf-opportunity` off origin/master (eac7cee). Shared checkout stays untouched.
- Design doc read from `git show 3fa10b57:docs/SCRUM-440-design.md` (Architect branch `feature/SCRUM-440-rueckrufwunsch`, NOT on master).
- Design table row 1 prints `Rückruf_desired__c` with umlaut, but the XML shape, the PS snippet and both ValRule formulas in the same doc say ASCII `Rueckruf_desired__c`. Implemented ASCII (house SCRUM-430 `Rueckruf_Zeitfenster__c`). The umlaut lives only in `<label>`.
- Org verified by me (not copied from Architect): `sf api request rest /services/data/v68.0/sobjects/Task/describe` → NO `DueDate`; `ActivityDate` type=date; `Status` picklist = Not Started / In Progress / Completed / Waiting on someone else / Deferred (NO "Abgebrochen"); `Priority` = High/Normal/Low; `WhatId` reference; `Subject` combobox.
- `sf api request rest /services/data/v68.0/sobjects/Opportunity/describe` → no Rueckruf*/Callback* field; existing custom fields incl. `MeinNeuesFeld__c` (not on master). No collision.
- `sf api request get ...` writes 0 bytes — the subcommand is `api request rest` (CLI 2.150.6). Cost: one wasted call.
- Target org = Test-Org (alias), user devops-agent@cline.test, api v68.0.
- ValRule house on the SAME object: `objects/Opportunity/validationRules/LossReason_PflichtBeiClosedLost.validationRule-meta.xml` (SCRUM-381). Checkbox+date pair shape: SCRUM-359 pair on Contact.
- Trigger house rule confirmed: ONE Opportunity trigger `OpportunityOverdueReset` (before insert/update, after insert/update/delete) dispatching to handlers. SCRUM-440 adds a handler call there, no second trigger.
- PS house = field-only: SCRUM430_RueckrufZeitfenster / SCRUM381_LeadFollowUp carry ONLY `<fieldPermissions>`, no objectPermissions.
- Layout house: `layouts/Opportunity-Opportunity Layout.layout-meta.xml` already carries `Loss_Reason__c` and `Is_Overdue__c` as Edit items.
- Manifest house: `manifest/scrNNN-phase1-fields.xml` (CustomField members prefixed `Opportunity.X__c`), phase2-apex-ps, phase3-layout, scrNNN-apextests.
