/**
 * [SCRUM-436] Naechtlicher Batch-Lauf ueber ALLE offenen, relevanten Cases.
 *
 * Prueft einmal taeglich (01:00, CaseReminderScheduler) den kompletten
 * offenen Case-Bestand (AC9) und flaggt, was fällig ist:
 *   Status in CaseReminderConfig.MONITORED_STATUSES  UND
 *   Reminder_Required__c = false                     (Idempotenz)  UND
 *   workingDaysBetween(Last_Relevant_Update__c, now) > threshold
 *     threshold = 1 Werktag bei Priority High, sonst 3 Werktage (PO).
 *
 * Haus-Shape (house SCRUM-388 AccountReactivationBatch): QueryLocator ueber
 * den VOLLSTAENDIGEN Bestand, 200er-Chunks, kurze DML-Transaction je Chunk
 * -> kein Timeout bei groessen Stocks (AC9). Pro Chunk 0 SOQL (QueryLocator
 * liefert die Zeilen) + 1 konditionales Bulk-DML (nur geaenderte Rows).
 *
 * Idempotenz (AC8, house SCRUM-388/365): nur ungeflaggte Cases werden
 * geflaggt -> zweiter Lauf ohne Datenaeanderung toucht 0 Rows.
 *
 * Closed ist im SOQL filtert (PO-Regel 7: geschlossene Cases nie); SUSPENDED
 * (PO-Offenpunkt #1, Default leer, ADR-4) wird in execute() ueber
 * CaseReminderConfig.isMonitoredStatus gefiltert (AC5).
 *
 * without sharing: deterministisch ueber den BESTAND, unabhaengig vom
 * Sharing des Scheduled-Users (house SCRUM-365/388). Ueberwindet OHNE
 * SHARING NICHT FLS -> der Batch-Executor braucht das Write-PS
 * SCRUM436_CaseReminderSystem (ADR-5).
 *
 * Deterministische Testbarkeit: `now` per @testVisible-Konstruktor
 * injizierbar (CaseReminderBatch(DateTime, Integer)).
 *
 * @author developer-agent
 * @date 2026-10-02
 */
public without sharing class CaseReminderBatch
        implements Database.Batchable<SObject>, Database.Stateful {
    // Batchable<SObject>, nicht <Case>: wie house AccountReactivationBatch.
    // start liefert Database.QueryLocator (= Iterable<SObject>); mit dem
    // konkreten <Case> erwartet der Compiler Iterable<Case> und lehnt den
    // QueryLocator ab (invariante Generics, org-verifiziert 2026-10-02).
    // execute nimmt List<Case> entgegen (house-Praxis, kompiliert).

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private final DateTime asOf;
    private final Integer batchSize;
    private Integer flagged;
    private Integer processed;

    public CaseReminderBatch() {
        this(System.now(), DEFAULT_BATCH_SIZE);
    }

    @testVisible
    public CaseReminderBatch(DateTime asOf, Integer batchSize) {
        this.asOf      = (asOf == null)      ? System.now() : asOf;
        this.batchSize = (batchSize == null) ? DEFAULT_BATCH_SIZE : batchSize;
        this.flagged   = 0;
        this.processed = 0;
    }

    @testVisible public Integer getFlagged()   { return flagged; }
    @testVisible public Integer getProcessed() { return processed; }

    @testVisible public Integer getBatchSize() { return batchSize; }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // Vollbestand (200er-Chunks, house SCRUM-388). Closed = PO-Regel 7
        // (geschlossene Cases nie); Last_Relevant_Update__c != null = jede
        // relevante Uhr braucht einen Startzeitpunkt (AC1: Trigger setzt es
        // bei der Eroeffnung; Legacy-Cases ohne Wert = nicht evaluiert).
        return Database.getQueryLocator(
            'SELECT Id, Status, Priority, Last_Relevant_Update__c, ' +
            'Reminder_Required__c, Reminder_Due_Date__c, Reminder_Count__c ' +
            'FROM Case ' +
            'WHERE Status != \'Closed\' AND Last_Relevant_Update__c != null');
    }

    public void execute(Database.BatchableContext ctx, List<Case> scope) {
        List<Case> toFlag = new List<Case>();
        for (Case c : scope) {
            processed++;

            // AC5: suspendierter Status (PO-Offenpunkt #1; Default: Menge
            // leer, d.h. alle nicht-geschlossenen Status sind monitored) ->
            // keine Wiedervorlage. 1-Zeilen-Änderung, wenn der PO den Wert
            // festlegt (ADR-4, CaseReminderConfig.SUSPENDED_STATUSES).
            if (!CaseReminderConfig.isMonitoredStatus(c.Status)) {
                continue;
            }

            // Idempotenz (AC8, house SCRUM-388): nur ungeflaggte werden
            // geflaggt -> zweiter Lauf toucht 0 Rows.
            if (c.Reminder_Required__c == true) {
                continue;
            }

            Integer threshold = isHighPriority(c.Priority)
                    ? CaseReminderConfig.HIGH_THRESHOLD_WORKING_DAYS
                    : CaseReminderConfig.DEFAULT_THRESHOLD_WORKING_DAYS;

            Integer days =
                    CaseReminderService.workingDaysBetween(c.Last_Relevant_Update__c, asOf);

            if (days > threshold) {
                c.Reminder_Required__c = true;
                c.Reminder_Due_Date__c = asOf;
                toFlag.add(c);
            }
        }
        if (!toFlag.isEmpty()) {
            update toFlag;   // 1 Bulk-DML je Chunk
        }
        flagged += toFlag.size();
    }

    private static Boolean isHighPriority(String priority) {
        return 'High'.equalsIgnoreCase(priority);
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('CaseReminderBatch: processed=' + processed
                   + ' flagged=' + flagged
                   + ' batchSize=' + batchSize);
    }
}
