# SCRUM-436 — Tester-Notizen

## Org-Befunde (Test-Org, 2026-10-02, selbst abgefragt)
- 4 Felder vorhanden: `Last_Relevant_Update__c`, `Reminder_Due_Date__c`, `Reminder_Required__c`, `Reminder_Count__c` (FieldDefinition, Case).
- Triggers aktiv: `CaseReminderTrigger` (Case), `CaseCommentReminderTrigger` (CaseComment).
- ApexClassen aktiv: CaseReminderService/Batch/Config/Scheduler + 2 Test-Klassen.
- PS-Zuweisung 4/4: `SCRUM436_CaseReminder`/`...System` × (devops-agent@cline.test, meerwais.osmani@resourceful-bear-6f1u4j.com).
- **0 Scheduled Apex-Jobs** → System.schedule nie gesetzt (Design Punkt 4, @devops). Code läuft deployed aber NIE.
- Case.Status: New/Working/Escalated/Closed — **„Warten auf Kunde" existiert NICHT** (REST /sobjects/Case/describe, 10-02). SUSPENDED_STATUSES = leer.
- Default-Org = Test-Org (devops-agent@cline.test) → Playwright auth.setup funktioniert direkt.

## AC-Plan
- AC1/2/3/4/6/7/8: eigenes Apex-Integrations-Test (executeBatch mit backdated Cases, inject asOf).
- AC5: NUR Config-Gate (`isMonitoredStatus('Warten auf Kunde')==false`) — echter Org-Status fehlt → NOT FULLY COVERED (Begründung in Abschluss).
- AC9: Bulk 250 Cases in einem executeBatch-Lauf.
- Layout-AC: Playwright E2E — 4 Felder sichtbar auf Case-Record (Details), read-only (kein Inline-Edit).
- Negativ-FLS: Developer-Test `SCRUM436CaseReminderFlsTest` neu ausführen + eigener runAs-Check (ohne PS → isAccessible false).

## Befehle
- Batch direkt: `sf apex run -f <(echo "Id b = Database.executeBatch(new CaseReminderBatch(), 200); System.debug('BATCH=' + b);")`
- Batch-Lauf prüfen: AsyncApexJob WHERE ApexClass.Name='CaseReminderBatch'.
- Status-Werte via REST describe (sf sobject field get existiert nicht in 2.150).

## Offene Punkte für Handoff
- CRON-Job fehlt in Org (DevOps, vor Release — Test-Org-Deployment-Gap, kein Code-Defekt).
- ADR-4: „Warten auf Kunde" als Picklist-Wert anlegen + in CaseReminderConfig eintragen (PO-Entscheidung, dann 1 Zeile).
