/**
 * SCRUM-413: Bestandsmigration — rückwirkendes Befüllen von Last_Real_Contact_Date__c.
 *
 * Batch über ALLE Kontakte (Chunk 200), pro Chunk recompute(Ids).
 * ADR-6: kein Button, kein Log-Zeile, finish=no-op. Idempotent.
 */
public without sharing class LastRealContactDateRebuilder
        implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    @SuppressWarnings('unused')
    public LastRealContactDateRebuilder() {}

    public static String runOnce() {
        return Database.executeBatch(new LastRealContactDateRebuilder(), DEFAULT_BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator('SELECT Id FROM Contact');
    }

    public void execute(Database.BatchableContext ctx, List<Contact> scope) {
        Set<Id> ids = new Set<Id>();
        for (Contact c : scope) {
            ids.add(c.Id);
        }
        LastRealContactDateTrigger.recompute(ids);
    }

    public void finish(Database.BatchableContext ctx) {}
}
