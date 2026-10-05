/**
 * [SCRUM-438] Schedulable fuer den stundlichen SLA-Batch.
 *
 * Startet nur den Batch, keine eigene Logik (house SCRUM-436
 * CaseReminderScheduler / SCRUM-388 AccountReactivationScheduler).
 *
 * CRON-Vorschlag (PO: stündlich): 0 0 * * * ?  (min=0 jeder Stunde).
 * Reserviert: 01:00 = SCRUM-436, 02:00 = SCRUM-388, 03:00 = SCRUM-417,
 * 06:00 = Opportunity-Overdue -> stündlich mit min=0 umgeht Kollisionen mit
 * den Tageseinträgen zur vollen Stunde nur, wo sie nicht fallen; PO-Entscheidung
 * zur exakten Minute = Offener Punkt (Default: 0 15 * * * ? = jeder Std 15 Min,
 * frei). => CRON-String hier nur Vorschlag.
 *
 * WICHTIG: Scheduled Jobs sind LAUFZEIT-Objekte, KEINE Metadata — der
 * CRON-Eintrag wird NICHT per Deploy angelegt und muss in der Org gesetzt
 * werden:
 *
 *   System.schedule('SCRUM-438 SLA', '0 15 * * * ?', new SLAJobScheduler());
 *
 * OHNE diesen Org-Schritt ist der Code deployed, laeuft aber NIE.
 * -> @devops-agent (Test-Org beim Deploy, Prod-Org beim Release).
 *
 * @author developer-agent
 * @date 2026-10-04
 */
global class SLAJobScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        Id batchId = Database.executeBatch(new SLAJobBatch(),
                SLAJobBatch.DEFAULT_BATCH_SIZE);
        System.debug('SLAJobScheduler: Batch gestartet, Id=' + batchId);
    }
}
