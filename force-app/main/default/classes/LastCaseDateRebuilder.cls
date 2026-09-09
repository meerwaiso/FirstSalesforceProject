/**
 * SCRUM-403: Bestandsmigration — rückwirkendes Befüllen von `Last_Case_Date__c`.
 *
 * Der LastCaseDateTrigger (SCRUM-403) pflegt das Feld nur bei Case-Events NACH
 * seinem Deploy. Bestandssätze (Cases, die davor angelegt wurden) haben das Feld
 * nie angefasst → `Last_Case_Date__c` ist NULL (= «leer»), auch bei Contacts mit
 * alten Fällen.
 *
 * Dieser Batch heilt ALLE Kontakte in einem Durchlauf (ADR-3: kein LastModified-
 * Filter — AC «Bestand rückwirkend», nächste Woche nicht alles leer):
 *   - QueryLocator über den VOLLSTÄNDIGEN Contact-Stock
 *   - pro Chunk (200) der BESTEHENDE bulkified Handler LastCaseDateTrigger.recompute
 *     → eine einzige Definition von «jüngster Fall», exakte Neu-Berechnung statt
 *     Delta, keine kumulativen Drifts
 *   - kurze DML-Transactions pro Chunk, kein SELECT FOR UPDATE
 *
 * ADR-6: KEINE UI-Auslösung (kein Custom Button), KEINE Lauf-Log-Zeile
 * (`CaseRebuildRun__c` gehört zu SCRUM-365 und wird NICHT wiederverwendet).
 * Idempotent: 2. Lauf ändert 0 (mustWrite-Schutz des Handlers).
 *
 * without sharing — konsistent mit der Handler-Klasse: die Migration muss ALLE
 * Kontakte heilen, unabhängig vom Sharing; Systemwrites umgehen FLS.
 *
 * @author developer-agent
 * @date 2026-09-09
 */
public without sharing class LastCaseDateRebuilder
        implements Database.Batchable<SObject>, Database.Stateful {

    /** Batch-Größe (Kontakte pro Chunk). 200 = Governor-Limit-Vollauslastung. */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    @SuppressWarnings('unused')
    public LastCaseDateRebuilder() {
        // Batchable-Konstruktor (executeBatch-Instanz). Stateful → Instanz-Variablen
        // überleben Chunk-Grenzen.
    }

    /**
     * Startpunkt: Batch starten, Batch-Id zurückliefern (für Verifikation /
     * DevOps-Release-Schritt). KEINE Log-Zeile (ADR-6), KEIN Button (ADR-6).
     *
     * @return die Batch-Job-Id (String, 18/15-stellig)
     */
    public static String runOnce() {
        return Database.executeBatch(new LastCaseDateRebuilder(), DEFAULT_BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // ALLE Kontakte, KEIN Filter auf LastModified — die Bestands-Migration ist
        // unabhängig von «wann zuletzt etwas passiert ist» (ADR-3, AC «Bestand»).
        return Database.getQueryLocator('SELECT Id FROM Contact');
    }

    public void execute(Database.BatchableContext ctx, List<Contact> scope) {
        // Exakt das Budget des bestehenden Handlers: der recompute-Call macht
        // 1 AGGREGATE-SOQL + 1 SOQL + 1 DML, unabhängig von der Chunk-Größe.
        Set<Id> ids = new Set<Id>();
        for (Contact c : scope) {
            ids.add(c.Id);
        }
        LastCaseDateTrigger.recompute(ids);
    }

    public void finish(Database.BatchableContext ctx) {
        // ADR-6: bewusst no-op — keine Log-Zeile, kein Status-Feld.
    }
}
