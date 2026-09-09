/**
 * SCRUM-404: CaseSlaAlertBatch — Batchable für den Überfälligkeits-Alert.
 * ADR-6: Such-Kriterium = Frist gesetzt, KEINE erste Rückmeldung,
 * Frist < NOW(), Alert noch nicht gesendet. Dedup über Sla_Alert_Sent__c.
 * finish() enqueuet CaseSlaNotification (Queueable).
 */
public without sharing class CaseSlaAlertBatch implements Database.Batchable<Case>, Database.Stateful {
    private Set<Id> collectedIds = new Set<Id>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String soql = 'SELECT Id, Reaktionsfrist__c ' +
            'FROM Case ' +
            'WHERE Reaktionsfrist__c != null ' +
            'AND Erste_Rueckmeldung__c = null ' +
            'AND Reaktionsfrist__c < ' + DateTime.now().format() + ' ' +
            'AND Sla_Alert_Sent__c = false';
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<Case> scope) {
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

    public void finish(Database.BatchableContext bc) {
        if (!collectedIds.isEmpty()) {
            System.enqueueJob(new CaseSlaNotification(new List<Id>(collectedIds)));
        }
    }
}
