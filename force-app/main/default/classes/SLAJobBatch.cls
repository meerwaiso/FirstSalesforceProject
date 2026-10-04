/**
 * [SCRUM-438] Stundlicher Batch-Lauf ueber ALLE offenen Cases.
 *
 * Prueft zyklisch (SLAJobScheduler, stündlich) den kompletten offenen
 * Case-Bestand und setzt die SLA-Felder (Status, Eskalation, Zielzeit,
 * kumulierte Werkmin, letzter Lauf, Uhr_gestoppt) — ADR-2: Batch +
 * reaktiver Trigger, EINE Logik im Service (AC8, keine Duplikation).
 *
 * Haus-Shape 1:1 CaseReminderBatch (SCRUM-436): QueryLocator ueber den
 * VOLLSTAENDIGEN Bestand, 200er-Chunks, without sharing, @testVisible-
 * Konstruktor mit injizierbarem `now` + batchSize. Pro Chunk 1 konditionales
 * Bulk-DML (NUR geaenderte Rows via Change-Detection -> Idempotenz).
 *
 * Re-Entry (house SCRUM-419/436): das `update toChange` feuert den
 * Case-Trigger RE-ENTRANT. SLAService.isRunning=true ueber die DML macht
 * den re-entrant Trigger-Lauf inert.
 *
 * Closed = ISNULL(ClosedDate) im SOQL (PO-Regel: geschlossene Cases nie).
 *
 * without sharing: deterministisch ueber den Bestand, unabhaengig vom
 * Sharing des Scheduled-Users. Ueberwindet WITHOUT SHARING NICHT FLS ->
 * der Batch-Executor braucht SCRUM438_SLA_System (ADR-6).
 *
 * @author developer-agent
 * @date 2026-10-04
 */
public without sharing class SLAJobBatch
        implements Database.Batchable<SObject>, Database.Stateful {
    // Batchable<SObject>, nicht <Case>: house — start liefert
    // Database.QueryLocator (= Iterable<SObject>); invariante Generics.
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private final DateTime asOf;
    private final Integer batchSize;
    private Integer processed;
    private Integer changed;
    // BusinessHours-Id einmal pro LAUF holen (Stateful -> gilt fuer alle
    // Chunks), damit der Service keine pro-Row SOQL mehr braucht.
    private Id bh;

    public SLAJobBatch() {
        this(System.now(), DEFAULT_BATCH_SIZE);
    }

    @testVisible
    public SLAJobBatch(DateTime asOf, Integer batchSize) {
        this(asOf, batchSize, null);
    }

    @testVisible
    public SLAJobBatch(DateTime asOf, Integer batchSize, Id bh) {
        this.asOf      = (asOf == null)      ? System.now() : asOf;
        this.batchSize = (batchSize == null) ? DEFAULT_BATCH_SIZE : batchSize;
        this.processed = 0;
        this.changed   = 0;
        this.bh        = bh;   // null -> resolve im ersten execute
    }

    @testVisible public Integer getProcessed() { return processed; }
    @testVisible public Integer getChanged()   { return changed; }
    @testVisible public Integer getBatchSize() { return batchSize; }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // Alle OFFENEN Cases (geschlossene nie), inkl. aller SLA-Buchungs-
        // Felder + der Inputs (Status/Priority/Kundenstatus/CreatedDate).
        return Database.getQueryLocator(
            'SELECT Id, Status, Priority, Kundenstatus__c, CreatedDate, ' +
            'SLA_Zielzeit__c, SLA_Status__c, SLA_Eskalation__c, ' +
            'SLA_Ueberschritten__c, SLA_Akkumulierte_WorkingMins__c, ' +
            'SLA_Last_Checked__c, SLA_Uhr_gestoppt__c ' +
            'FROM Case WHERE ClosedDate = null');
    }

    public void execute(Database.BatchableContext ctx, List<Case> scope) {
        if (bh == null) { bh = SLAService.bhId(); }   // 1x pro LAUF (Stateful)
        List<Case> toChange = new List<Case>();
        for (Case c : scope) {
            processed++;

            // Change-Detection (Idempotenz): originalen Stand merken,
            // danach vergleichen — nur geaenderte Rows werden gedml-t.
            Decimal origWorked  = c.SLA_Akkumulierte_WorkingMins__c;
            DateTime origChecked = c.SLA_Last_Checked__c;
            Boolean origStopped  = c.SLA_Uhr_gestoppt__c;
            String  origStatus   = c.SLA_Status__c;
            String  origEsc      = c.SLA_Eskalation__c;
            Boolean origOver     = c.SLA_Ueberschritten__c;
            DateTime origDeadline = c.SLA_Zielzeit__c;

            SLAService.evaluate(c, asOf);

            // Nur wenn sich AETWAS an einem Feld geaendert hat -> DML.
            // (Die arbeitete-Uhr laeuft waehrend ein Fall offen ist weiter;
            // das ist korrekt — es ist eine Live-Uhr, kein Einmal-Flag.
            // Idempotenz = keine ueberfluessigen Rows, wenn nichts laeuft,
            // z. B. Case in Pause mit unveraendertem Status.)
            if (!equals(c.SLA_Akkumulierte_WorkingMins__c, origWorked)
                    || !dtEq(c.SLA_Last_Checked__c, origChecked)
                    || !boolEq(c.SLA_Uhr_gestoppt__c, origStopped)
                    || !strEq(c.SLA_Status__c, origStatus)
                    || !strEq(c.SLA_Eskalation__c, origEsc)
                    || !boolEq(c.SLA_Ueberschritten__c, origOver)
                    || !dtEq(c.SLA_Zielzeit__c, origDeadline)) {
                toChange.add(c);
            }
        }
        if (!toChange.isEmpty()) {
            SLAService.isRunning = true;
            try {
                update toChange;   // 1 Bulk-DML je Chunk
            } finally {
                SLAService.isRunning = false;
            }
        }
        changed += toChange.size();
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('SLAJobBatch: processed=' + processed
                   + ' changed=' + changed + ' batchSize=' + batchSize);
    }

    private static Boolean equals(Decimal a, Decimal b) {
        if (a == null || b == null) { return a == null && b == null; }
        return a == b;
    }
    private static Boolean dtEq(DateTime a, DateTime b) {
        if (a == null || b == null) { return a == null && b == null; }
        return a.getTime() == b.getTime();
    }
    private static Boolean boolEq(Boolean a, Boolean b) {
        if (a == null || b == null) { return a == null && b == null; }
        return a == b;
    }
    private static Boolean strEq(String a, String b) {
        if (a == null || b == null) { return a == null && b == null; }
        return a == b;
    }
}
