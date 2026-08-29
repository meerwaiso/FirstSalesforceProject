/**
 * SCRUM-367: Vollkorrektur des Fallzählers «Offene Fälle» — wiederholbarer Batch-Rebuilder.
 *
 * Der CaseOpenCountTrigger (SCRUM-365) pflegt den Zähler nur bei Case-Events NACH
 * seinem Deploy. Bestandssätze (Cases, die davor angelegt wurden) haben den Zähler
 * nie angefasst → Open_Cases_Count__c ist NULL (= «leer») oder veraltet.
 *
 * Diese Klasse heilt ALLE Kontakte in einem Durchlauf:
 *   - QueryLocator über den VOLLSTÄNDIGEN Contact-Stock (kein LastModified-Filter)
 *   - pro Chunk (200) der BESTEHENDE bulkified Handler CaseOpenCountTrigger.recompute
 *     → eine einzige Definition von «offen», keine duplizierte Zähllogik, exakte
 *     Neu-Zählung statt Delta, keine kumulativen Drifts
 *   - kurze DML-Transactions pro Chunk, kein SELECT FOR UPDATE → laufende
 *     Fallbearbeitungen blockieren nicht (AC 4), auch 50k Kontakte schaffen
 *     250 Chunks ohne Timeout (AC 5)
 *
 * No-Code-Auslösung: Custom Button (Classic) ruft sforce.apex.execute auf
 * startRebuild() — idempotent, wiederholbar, ohne Deploy (AC 3).
 * Ergebnis: eine Zeile in CaseRebuildRun__c (gezahlte/geheilte, Status, Batch-Id),
 * für Servicemitarbeiter sichtbar (AC 6, Tab + List View «Letzte Läufe»).
 *
 * without sharing — konsistent mit CaseOpenCountTrigger (SCRUM-365 ADR): die
 * Vollkorrektur muss ALLE Kontakte heilen, unabhängig vom Sharing des Starts;
 * Systemwrites umgehen FLS, daher braucht keine Person Update-FLS auf
 * Contact.Open_Cases_Count__c.
 *
 * Bekannte, dokumentierte Einschränkung (Architect-ADR): schlägt der Batch-Mittelaufgabe
 * fehl, bleibt die Logzeile bei «Laufend» — nachverfolgbar über BatchId__c in
 * Setup › Apex Jobs. Bewusst so (kein Fehler-Handler) — Blockade von Follow-up
 * Läufe ist nicht nötig, die nächste Korrektur heilt erneut.
 *
 * @author developer-agent
 * @date 2026-08-27
 */
public without sharing class CaseOpenCountRebuilder
        implements Database.Batchable<SObject>, Database.Stateful {

    /** Laufende Status-Werte für CaseRebuildRun__c.Status__c. */
    public static final String STATUS_RUNNING = 'Laeuft';
    public static final String STATUS_DONE = 'Abgeschlossen';
    public static final String STATUS_ERROR = 'Fehler';

    /** Batch-Größe (Kontakte pro Chunk). 200 = Governor-Limit-Vollauslastung. */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /** Id der Run-Logzeile, die dieser Batch-Instanz gehört. */
    private final Id runId;
    /** Für Tests: Batch-Größe wählbar (Small-Runs). */
    private final Integer batchSize;

    /** Anzahl verarbeiteter Kontakte (summiert über alle Chunks). */
    private Integer processed;
    /** Anzahl tatsächlich geänderter Kontakte (summiert über alle Chunks). */
    private Integer corrected;

    /** Produktion: Standardgröße 200. */
    public CaseOpenCountRebuilder(Id runId) {
        this.runId = runId;
        this.batchSize = DEFAULT_BATCH_SIZE;
        initCounters();
    }

    /** Test-Konstruktor: kleinere Chunk-Größe für deterministische Runs. */
    public CaseOpenCountRebuilder(Id runId, Integer batchSize) {
        this.runId = runId;
        this.batchSize = batchSize;
        initCounters();
    }

    private void initCounters() {
        this.processed = 0;
        this.corrected = 0;
        // State-Persistenz in Batch: processed/corrected überleben Chunk-Grenzen,
        // weil Database.Stateable die Instanz-Variablen zwischen execute-Läufen
        // serialisiert. (Kein Transient-Modifier, bewusst Stateable.)
    }

    /**
     * No-Code-Ausloeser (Custom Button, sforce.apex.execute).
     *
     * Legt die Run-Logzeile an, startet die Batch und liefert die Batch-ID
     * zurueck — sie wird auf der Logzeile festgehalten (BatchId__c).
     *
     * @return die Batch-Id (String, 18-stellig)
     */
    public static String startRebuild() {
        CaseRebuildRun__c run = new CaseRebuildRun__c();
        run.Status__c = STATUS_RUNNING;
        insert run;

        // Database.executeBatch() liefert die Batch-Job-Id (String, 18) —
        // kein BatchableContext. Kein getId(): die Id ist der Return-Wert.
        String batchId =
                Database.executeBatch(new CaseOpenCountRebuilder(run.Id), DEFAULT_BATCH_SIZE);

        run.BatchId__c = batchId;
        update run;

        return batchId;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // ALLE Kontakte, KEIN Filter auf LastModified — AC 1 (30+-Tage-alt) ist
        // damit automatisch gedeckt und die Vollkorrektur ist unabhängig von der
        // Fallanzahl pro Kontakt.
        return Database.getQueryLocator('SELECT Id FROM Contact');
    }

    public void execute(Database.BatchableContext ctx, List<Contact> scope) {
        // Exakt das Budget des bestehenden Handlers: der recompute-Call macht
        // 1 AGGREGATE-SOQL + 1 SOQL + 1 DML, unabhängig von der Chunk-Größe.
        Set<Id> ids = new Set<Id>();
        for (Contact c : scope) {
            ids.add(c.Id);
        }
        Integer chunkCorrected = CaseOpenCountTrigger.recompute(ids);
        corrected = corrected + (chunkCorrected == null ? 0 : chunkCorrected);
        processed = processed + scope.size();
    }

    public void finish(Database.BatchableContext ctx) {
        CaseRebuildRun__c run =
                [SELECT Id, Status__c FROM CaseRebuildRun__c WHERE Id = :runId];
        run.Status__c = STATUS_DONE;
        run.ContactsProcessed__c = processed;
        run.ContactsCorrected__c = corrected;
        run.FinishedAt__c = DateTime.now();
        update run;
    }
}
