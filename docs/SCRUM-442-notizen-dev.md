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

20|- Probe 2026-10-10 (SCRUM442ProbeTest, deleted after use): a Standard User holding all 4 PS (psa=5, sat.access/update + urs.access all true) STILL fails a Case insert WITH AccountId: "fields being inaccessible on Sobject Case" = missing cross-object (Account) access, not the field itself. Same insert WITHOUT AccountId: OK. Consequence: seed inserts with cross-refs stay in System context (setup DML), the Rebuilder writes + read-back SOQL run under runAs(u) — that is the shape the FLS-Gate and Prod check-only exercise. RollupTest restructured accordingly, 19/19 green (RunSpecifiedTests, own 3 classes).
21|
22|# 2026-10-11 (Cause E Rework4, measured to exhaustion)
23|- MIXED_DML: PSA is NOT a setup object. BOTH orders throw in one transaction: seeds-first -> "... PermissionSetAssignment, original object: Account"; PSA-first + System-context seeds after -> "... Account, original object: PermissionSetAssignment". Case DML alone MAY follow a PSA insert (SatisfactionTest ac1..ac5 green). Account DML may NOT share a PSA transaction at all.
24|- Consequence: the AC5/AC6 rollup proof (needs Account seeds) runs as an ORG user that already carries SCRUM442_Satisfaction_Write (existingCloser() READS PermissionSetAssignment, zero PSA DML in the tx). FLS-negative proof stays in SCRUM442SatisfactionFlsTest = different transaction. closer() fails loudly if no such user exists (never vacuous).
25|- PermissionSetAssignment columns: AssigneeId / PermissionSetId. There is NO 'Assignee' column and NO PermissionSet.Name join (measured compile error). House pattern: SCRUM424/434 fixtures.
26|- Deploy order for a helper + its consumers: helper ALONE first (manifest scr442-fixtures.xml), consumers in a SECOND deploy — same-batch compiles consumers against the OLD live helper ("Method does not exist ... existingCloser").
27|- Fixture user carries SCRUM436_CaseReminderSystem + SCRUM437_ProblemSerie_System (editable variants): closing a Case fires those rules and they WRITE Case fields; the Read-only variants do not cover a trigger write.
28|- CI smoke step: Playwright loads EVERY spec file even with --grep "[SMOKE]". test.describe(name); single-arg is NOT a Playwright signature (house: test.describe(name, () => { ... })) — it threw "expected object, got undefined" at file load and reddened the smoke step. Fixed spec to house block form.
29|- CI Apex gate 2026-10-11 run 38145500272: 133 tests, 1 fail = SCRUM367OpenCasesRebuildScaleTest.multiChunk_staleStock_summationStateful (Apex CPU time limit). Standalone rerun of that class: 2/2 green in 47s -> contention flake in the 450s full run, not a defect of SCRUM-442. If it recurs, name it in the handoff; do NOT touch another ticket's scale test.
30|- Org test budget: full-suite CI runs consume it; keep own runs RunSpecifiedTests only.