/**
 * OpenOpportunityHistoryScheduler — Schedulable für den nächtlichen
 * Vollrecompute des Offenen Chancen-Verlaufs je Kunde (SCRUM-417).
 * Startet nur den Rebuilder, keine eigene Logik (House-Pattern
 * AccountReactivationScheduler, SCRUM-388).
 *
 * CRON-Vorschlag: 0 0 3 * * ?  (täglich, 3 Uhr nachts).
 * 2 Uhr = SCRUM-388 Reaktivierung, 6 Uhr = SCRUM-319/414 Overdue → 3 Uhr frei.
 * (@devops-agent prüft Kollision in der Org.)
 *
 * WICHTIG: Scheduled Jobs sind LAUFZEIT-Objekte, KEINE Metadata — der CRON-
 * Eintrag wird NICHT per Deploy angelegt und muss in der Org gesetzt werden:
 *
 *   System.schedule('SCRUM-417 Offene Chancen Verlauf', '0 0 3 * * ?',
 *                   new OpenOpportunityHistoryScheduler());
 *
 * OHNE diesen Org-Schritt ist der Code deployed, läuft aber NIE.
 * → @devops-agent (Org-Schritt, siehe Design-Doc „Offene Punkte“).
 *
 * @author developer-agent
 * @date 2026-09-15
 */
global class OpenOpportunityHistoryScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        OpenOpportunityHistoryRebuilder.run();
        System.debug('OpenOpportunityHistoryScheduler: Vollrecompute abgeschlossen');
    }
}
