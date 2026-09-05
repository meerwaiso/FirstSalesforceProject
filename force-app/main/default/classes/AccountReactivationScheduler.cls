/**
 * AccountReactivationScheduler — Schedulable für den nächtlichen
 * Reaktivierungs-Lauf (SCRUM-388). Startet nur den Batch, keine eigene Logik.
 *
 * CRON-Vorschlag: 0 0 2 * * ?  (täglich, 2 Uhr nachts).
 * 6 Uhr ist OpportunityOverdueScheduler reserviert → 2 Uhr hält den
 * ggf. längeren Reaktivierungs-Lauf davon fern.
 *
 * WICHTIG: Scheduled Jobs sind LAUFZEIT-Objekte, KEINE Metadata — der CRON-
 * Eintrag wird NICHT per Deploy angelegt und muss in der Org gesetzt werden:
 *
 *   System.schedule('SCRUM-388 AccountReactivation', '0 0 2 * * ?',
 *                   new AccountReactivationScheduler());
 *
 * OHNE diesen Org-Schritt ist der Code deployed, läuft aber NIE.
 * → @devops-agent (Org-Schritt, siehe Design-Doc „Offene Punkte“).
 *
 * @author developer-agent
 * @date 2026-09-05
 */
global class AccountReactivationScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        Id batchId = Database.executeBatch(new AccountReactivationBatch(),
                                           AccountReactivationBatch.DEFAULT_BATCH_SIZE);
        System.debug('AccountReactivationScheduler: Batch gestartet, Id=' + batchId);
    }
}
