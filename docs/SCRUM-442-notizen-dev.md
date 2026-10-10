# SCRUM-442 dev notes (Developer) — verified facts, 2026-10-10

- Target org = Test-Org (alias), user devops-agent@cline.test, api v68.0, CLI 2.150.6.
- Case.Status: New/Working/Escalated/Closed. Task.Status: Not Started/...; Task.Priority: High/Normal/Low. Task has NO DueDate -> ActivityDate.
- Case.ClosedDate is a DATETIME in this org (house CaseProblemSerieHandler). Date.valueOf(dt.format('yyyy-MM-dd')) verified probe11.
- TreatBlanksAs valid enum: BlankAsZero/BlankAsBlank/#N/A (NO BlankAsNull!). Arger formula uses Satisfaction_Anzahl__c = 0 for no-data.
- Inner classes NOT allowed by org compiler (probe8) -> parallel maps in Rebuilder.
- setScale(1) single arg OK (probe9: 11/3 -> 3.7). (Iterable<SObject>) Database.getQueryLocator + (Account) o cast OK (probe7 n=187).
- Rebuilder QueryLocator SELECT MUST carry the compared fields (SObject row error otherwise).
- Deploy order: phase1 fields alone, then phase2 referencing (ValRule+PS+Layouts+Apex+Trigger), Report LAST alone (fields must resolve in org). Report member prefix `Sales/Name`; columns/filter/sortColumn need `Account.` prefix; dateColumn of an AccountList report must be an Account field (CLOSED_DATE rejected).
- `sf project deploy validate` has NO NoTestsRun; `deploy start -l NoTestRun` works. Org test budget spent -> RunRelevantTests ran the FULL suite (37 red from the new ValRule on other tickets' closings). Own tests: deploy start --manifest scr442-apextests.xml -l RunSpecifiedTests -t <3 classes> -> 19/19 green.
- ValRule + PS descriptions max 255 chars. User Alias max 8 chars.
- Closing a Case needs BOTH ValRules: SCRUM-434 Ursache__c AND SCRUM-442 score. Test closers get SCRUM434_Ursache + SCRUM442_Satisfaction_Write; FLS error "fields being inaccessible on Sobject" = missing field FLS, not missing CRUD.
- PS already assigned to devops-agent + meerwais.osmani (Read/Write); System PS assigned to devops-agent only. fls-check.sh read-back: Case.Customer_Satisfaction__c exists (Picklist), granted by Read+Write, 2 users each.
- Report live: Miserable_Kunde_Satisfaction (AccountList, filter Arger=Ärger, sort Durchdurch asc, timeFrameFilter INTERVAL_LAST90 on Satisfaction_Fenster_Start__c).
- Nightly schedule: System.schedule('SCRUM-442 Satisfaction','0 0 4 * * ?', new AccountSatisfactionScheduler()) ran OK (no compile error). CronTrigger NOT queryable via Tooling API ("sObject type not supported") -> schedule read-back not verifiable from CLI; DevOps/PO to confirm in Setup UI at Release.
- Initial Rebuilder.run() over the org: processed=187, non-zero counts 0 (no existing closed Case carries a score yet; 46 closed Cases all NULL). No-data state correct: Arger reads "Kein Daten".
- Org test budget: CUMULATIVE_LIMIT_USAGE hit in anonymous Apex runs; keep Apex runs minimal.

- Probe 2026-10-10 (SCRUM442ProbeTest, deleted after use): a Standard User holding all 4 PS (psa=5, sat.access/update + urs.access all true) STILL fails a Case insert WITH AccountId: "fields being inaccessible on Sobject Case" = missing cross-object (Account) access, not the field itself. Same insert WITHOUT AccountId: OK. Consequence: seed inserts with cross-refs stay in System context (setup DML), the Rebuilder writes + read-back SOQL run under runAs(u) — that is the shape the FLS-Gate and Prod check-only exercise. RollupTest restructured accordingly, 19/19 green (RunSpecifiedTests, own 3 classes).