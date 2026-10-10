# SCRUM-442 — Developer-Notizen

Verified-Org-Facts (Test-Org, sf CLI 2.150.6, api 68.0):
- `Case.Status` picklist: New / Working / Escalated / Closed (via `sf sobject describe -s Case -o Test-Org`)
- `Task.Status`: Not Started / In Progress / Completed / Waiting on someone else / Deferred; `Task.Priority`: High / Normal / Low (same command, -s Task)
- CLI target-org user: devops-agent@cline.test (System Admin), org id 00DWU00000oibVJ2AY
- House reports in repo use ONLY `INTERVAL_CUSTOM` — no INTERVAL_LAST3MONTHS anywhere in repo or CLI registry; interval token set NOT verifiable from CLI (no schema in metadataRegistry.json). Plan: deploy-validate is the oracle; fallback = drop timeFrameFilter (window is enforced by the Rebuilder fields themselves).
- `ACCOUNT.NAME` is the only cross-object token in deployed repo reports (Betreuungslast_nach_Firma, deployed green). `CASES.*` tokens: NOT found in any deployed report -> avoid; use `CASE_NUMBER`/`SUBJECT` (deployed in SCRUM-424 report).
- Reports named in repo (Betreuungslast_nach_Firma etc.) are NOT retrievable by name from Test-Org ("cannot be found") — org reports live in folders; do not chase.
- ValidationRule house (SCRUM-434, deployed green): errorConditionFormula `AND(OR(IsClosed, ISPICKVAL(Status, 'Closed')), ISBLANK(TEXT(Ursache__c)))`.
- Formula-field house (SCRUM-398): type Text, formula, formulaTreatBlanksAs, NO length, NO precision/scale. PS 398 lists the formula field with editable=false/readable=true -> formula fields DO take FLS read entries.
- Working-day convention (SCRUM-436 CaseReminderService, org-verified): epoch anchor 1970-01-01 = Thursday, w=mod(days,7), Mo-Fr = w>=4 || w<=1. Apex Date has NO dayOfWeek().
- FLS test house: SCRUM440RueckrufwunschFlsTest / SCRUM436CaseReminderFlsTest — temp User on 'Standard User' profile, precondition object-access assert, negative block (invisible without PS), positive block with PS assigned via PermissionSetAssignment. en_US locale, America/Los_Angeles TZ (de_DE/UTC rejected in this org).
- Task house handler: RueckrufTaskHandler (SCRUM-440) — 1 SOQL WHERE WhatId IN :ids AND Subject LIKE prefix, bulk insert/update, hasFired guard try/finally. Task has NO DueDate -> ActivityDate. Task.OwnerId required.
- Rebuilder house: OpenOpportunityHistoryRebuilder (417) / AccountReactivationBatch (388) — QueryLocator, 200-chunks, conditional bulk DML, without sharing (does NOT bypass FLS).
- Date-bind cast caveat (SCRUM-417): Date bind -> midnight of that day.
- Manifest pattern: scr440-phase1-fields.xml (CustomField), phase2 (ValidationRule+PS+ApexClass+ApexTrigger), apextests separate. version 67.0 in repo manifests; sfdx-project sourceApiVersion 67.0.
- Deploy order (memory): CustomField ALONE first, then everything referencing it. `sf project deploy start --manifest` is the only safe path (registry bug).
- Layout house: new <layoutSections> block before System Information; Case layout sections at line ~335 (Rückschau), Account layout Kundenreaktivierung section ~185, System Information ~204.
- fls-gate.py requires: every changed field named in a PS; PS assigned to BOTH "Meerwais Osmani" AND "devops-agent" (name match); test classes touching new fields must contain System.runAs( in comment-stripped source.
- sf project deploy validate supports -l RunSpecifiedTests -t <classes> (NOT NoTestRun).
