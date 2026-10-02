/**
 * [SCRUM-436] Schedulable fuer den naechtlichen Wiedervorlage-Batch.
 *
 * Startet nur den Batch, keine eigene Logik (house Shape
 * AccountReactivationScheduler, SCRUM-388).
 *
 * CRON-Vorschlag: 0 0 1 * * ?  (taeglich, 1 Uhr nachts).
 * Reserviert: 02:00 = SCRUM-388, 03:00 = SCRUM-417, 06:00 =
 * Opportunity-Overdue -> 01:00 ist frei (Architect-Befund).
 *
 * WICHTIG: Scheduled Jobs sind LAUFZEIT-Objekte, KEINE Metadata — der
 * CRON-Eintrag wird NICHT per Deploy angelegt und muss in der Org gesetzt
 * werden:
 *
 *   System.schedule('SCRUM-436 CaseReminder', '0 0 1 * * ?',
 *                   new CaseReminderScheduler());
 *
 * OHNE diesen Org-Schritt ist der Code deployed, laeuft aber NIE.
 * -> @devops-agent (Test-Org beim Deploy, Prod-Org beim Release).
 *
 * @author developer-agent
 * @date 2026-10-02
 */
global class CaseReminderScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        Id batchId = Database.executeBatch(new CaseReminderBatch(),
                CaseReminderBatch.DEFAULT_BATCH_SIZE);
        System.debug('CaseReminderScheduler: Batch gestartet, Id=' +
                batchId);
    }
}
