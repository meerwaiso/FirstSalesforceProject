/**
 * ChurnDetectionScheduler — Scheduled Apex für tägliche Churn-Prüfung
 * 
 * Läuft täglich nach Geschäftsschluss (22:00) und ermittelt inaktive Accounts.
 * Cron-Ausdruck: 0 0 22 * * ? (täglich um 22:00)
 */
global class ChurnDetectionScheduler implements Schedulable {

    /**
     * Führt die tägliche Churn-Erkennung aus
     */
    global void execute(SchedulableContext ctx) {
        Integer inactiveCount = ChurnDetectionService.findAndMarkInactiveAccounts();

        // Optional: Log-Eintrag via System.debug
        System.debug('ChurnDetectionScheduler: ' + inactiveCount + ' inaktive Accounts erkannt und markiert.');
    }
}