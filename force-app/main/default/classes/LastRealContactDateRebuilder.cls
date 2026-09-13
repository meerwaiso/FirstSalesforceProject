/**
 * SCRUM-413: Bestandsmigration — rückwirkendes Befüllen von `Last_Real_Contact_Date__c`.
 *
 * Der LastRealContactDateTrigger pflegt das Feld nur bei Call-Events NACH Deploy.
 * Bestandssätze haben das Feld nie angefasst → NULL (= "nie erreicht"), auch bei
 * Contacts mit alten abgeschlossenen Calls.
 *
 * Dieser Batch heilt ALLE Kontakte in einem Durchlauf (kein LastModified-Filter —
 * "Bestand rückwirkend", AC6). Pro Chunk (200) wird der bestehende Handler
 * LastRealContactDateTrigger.recompute aufgerufen → eine einzige Definition von
 * "neuester Call", exakte Neu-Berechnung statt Delta, keine kumulativen Drifts.
 *
 * ADR-6: KEINE UI-Auslösung (kein Custom Button), KEINE Lauf-Log-Zeile.
 * Idempotent: 2. Lauf ändert 0 (mustWrite-Schutz des Handlers).
 *
 * without sharing — die Migration muss ALLE Kontakte heilen.
 *
 * @author developer-agent
 * @date 2026-09-13
 */
public without sharing class LastRealContactDateRebuilder
        implements Database.Batchable<SObject>, Database.Stateful {

    /** Batch-Größe (Kontakte pro Chunk). 200 = Governor-Limit-Vollauslastung. */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    @SuppressWarnings('unused')
    public LastRealContactDateRebuilder() {
        // Batchable-Konstruktor (executeBatch-Instanz).
    }

    /**
     * Startpunkt: Batch starten, Batch-Id zurückliefern. KEINE Log-Zeile, KEIN Button.
     *
     * @return die Batch-Job-Id (String, 18/15-stellig)
     */
    public static String runOnce() {
        return Database.executeBatch(new LastRealContactDateRebuilder(), DEFAULT_BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // ALLE Kontakte, KEIN Filter auf LastModified.
        return Database.getQueryLocator('SELECT Id FROM Contact');
    }

    public void execute(Database.BatchableContext ctx, List<Contact> scope) {
        Set<Id> ids = new Set<Id>();
        for (Contact c : scope) {
            ids.add(c.Id);
        }
        LastRealContactDateTrigger.recompute(ids);
    }

    public void finish(Database.BatchableContext ctx) {
        // ADR-6: bewusst no-op.
    }
}
