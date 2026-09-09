/**
 * SCRUM-404: CaseSlaScheduler — 15-min-Batch für den Überfälligkeits-Alert.
 * ADR-6: Such-Kriterium = Frist gesetzt, KEINE erste Rückmeldung, Frist < NOW(),
 * Alert noch nicht gesendet. Dedup über Sla_Alert_Sent__c (2. Lauf findet die
 * Fälle nicht mehr). finish() enqueuet CaseSlaNotification (Queueable).
 *
 * Schedulable-Wrapper (Cron) wie Hausmuster OpportunityOverdueScheduler.
 */
public without sharing class CaseSlaScheduler implements Database.Batchable<Case> {
    private Set<Id> collectedIds = new Set<Id>();

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator(
            'SELECT Id, Reaktionsfrist__c ' +
            'FROM Case ' +
            'WHERE Reaktionsfrist__c != null ' +
            'AND Erste_Rueckmeldung__c = null ' +
            'AND Reaktionsfrist__c < :DateTime.now() ' +
            'AND Sla_Alert_Sent__c = false'
        );
    }

    public void execute(Database.BatchableContext ctx, List<Case> scope) {
        if (scope == null || scope.isEmpty()) return;
        Boolean oldFlag = CaseSlaGuard.WRITING_ALERT;
        CaseSlaGuard.WRITING_ALERT = true;
        try {
            for (Case c : scope) {
                c.Sla_Alert_Sent__c = true;
                collectedIds.add(c.Id);
            }
            update scope;
        } finally {
            CaseSlaGuard.WRITING_ALERT = oldFlag;
        }
    }

    public void finish(Database.BatchableContext ctx) {
        if (!collectedIds.isEmpty()) {
            System.enqueueJob(new CaseSlaNotification(new List<Id>(collectedIds)));
        }
    }

    global class Cron implements Schedulable {
        global void execute(SchedulableContext ctx) {
            Database.executeBatch(new CaseSlaScheduler(), 200);
        }
    }
}
