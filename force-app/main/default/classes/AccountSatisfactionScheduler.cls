/**
 * AccountSatisfactionScheduler — Schedulable für den nächtlichen Vollrecompute
 * der Account.Satisfaction_*-Felders (SCRUM-442). Startet nur den Rebuilder,
 * no own logic (House-Pattern OpenOpportunityHistoryScheduler SCRUM-417,
 * AccountReactivationScheduler SCRUM-388).
 *
 * CRON-Vorschlag: 0 0 4 * * ?  (täglich, 4 Uhr nachts).
 * Taken slots: 01:00 SCRUM-436, 02:00 SCRUM-388, 03:00 SCRUM-417,
 * 06:00 SCRUM-319/414 -> 04:00 proposed. (@devops-agent prüft Kollision in
 * der Org.)
 *
 * WICHTIG: Scheduled Jobs are LAUFTIME-Objects, KEINE Metadata — der CRON-
 * Entry is NOT created by a deploy and must be set in the Org:
 *
 *   System.schedule('SCRUM-442 Satisfaction', '0 0 4 * * ?',
 *                   new AccountSatisfactionScheduler());
 *
 * OHNE this Org step the code is deployed but runs NIE. -> @devops-agent.
 *
 * The scheduled user needs the System-PS SCRUM442_Satisfaction_System: the
 * Rebuilder writes the Account fields via Apex DML, and DML checks FLS even
 * in without-sharing classes (ADR-5).
 *
 * @author developer-agent
 * @date 2026-10-10
 */
global class AccountSatisfactionScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        AccountSatisfactionRebuilder.run();
        System.debug('AccountSatisfactionScheduler: SCRUM-442 Vollrecompute abgeschlossen');
    }
}
