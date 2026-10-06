/**
 * [SCRUM-438] AC8 / PO-Szenario 11 — Skalierung: «Viele Cases gleichzeitig,
 * periodische Bewertung, keine Abhängigkeit von Einzel-Triggern».
 *
 * Ergaenzt die Developer-Klassen SCRUM438SLATest.ac8 / Batch-Pfad.
 * AC8 ist DOPPELT belegt: (a) Batch-Logik funktioniert (Developer: 1 kleiner
 * Lauf, Closed-Filter) und (b) der Batch läuft auch bei VOLUMEN zuverlässig
 * ab — die periodische Bewertung über ALLE offenen Cases ohne dass ein
 * einzelner Case gerade eröffnet/geändert wird. (b) stand in der Developer-
 * Klasse NICHT (das Design sah eine SCRUM438SLAScaleTest vor, die nicht
 * angelegt wurde) — dieser Test schliesst genau diese Lücke.
 *
 * --------------------------------------------------------------------------
 * WARUM Chunk-für-Chunk execute() und NICHT Database.executeBatch()
 * (1:1 House-Befund SCRUM-367, Run 707WU00001GGEk7, API 62):
 *   Der Test-Kontext dieser Org lässt einen executeBatch-Lauf NUR als
 *   Einzel-Chunk durch; läuft der QueryLocator über die Batch-Grösse hinaus
 *   (echtes Multi-Chunk), verweigert der Framework-Wrapper den Lauf.
 *   Deshalb wird die PRODUKTIONS-Methode execute() Chunk für Chunk auf dem
 *   GLEICHEN Stateful-Objekt angetrieben — exakt der Chunk-Pfad, den das
 *   Batch-Framework laufen lässt — und am Ende finish(). Beweist: der
 *   Stateful-Zähler `processed` SUMMIERT sich über beliebige Chunk-Grenzen.
 *
 * VOLUMEN: 420 offene Cases → ceil(420/200) = 3 Chunks (200+200+20).
 * Governor: ~420 Insert (before-Trigger = 0 Row-DML, 1 bhId-SOQL bulk) +
 * bis zu 420 Batch-Update < 10000. SOQL: wenige, der Batch erhält `bh`
 * injiziert → 0 eigene bhId-SOQL.
 *
 * Org-Isolation: die Test-Org trägt ausserhalb der @isTest-Transaktion andere
 * offene Cases (z. B. Live-Smoke-Records). Deshalb werden die Assertions
 * auf die EIGENEN Cases (Subject-Vorspann) gemünzt — deterministisch — und
 * die Vollbestands-Bearbeitung (Processed == gesamt offener Scope) gesondert.
 *
 * @author tester-agent
 * @date 2026-10-04
 */
@isTest
private class SCRUM438SLAScaleTest {

    // batchSize 200 -> 420 Cases = 3 Chunks (bewusst > batchSize, sonst 1 Chunk).
    private static final Integer VOLUME   = 420;
    private static final Integer BATCH_SIZE = 200;

    private static String prefix(String tag) { return 'SLA-SCALE ' + tag; }

    /**
     * Chunk-Schleife wie das Batch-Framework: Scope in Stücken von `batchSize`
     * auf dem GLEICHEN Stateful-Objekt über die PRODUKTIONS-Methode execute(),
     * danach finish(). ctx wird von execute()/finish() nicht verwendet => null.
     */
    private static void driveBatchAcrossChunks(SLAJobBatch batch,
            List<Case> scope, Integer batchSize) {
        Integer total = scope.size();
        for (Integer startIdx = 0; startIdx < total; startIdx += batchSize) {
            Integer endIdx = (startIdx + batchSize > total)
                    ? total : (startIdx + batchSize);
            List<Case> chunk = new List<Case>();
            for (Integer j = startIdx; j < endIdx; j++) {
                chunk.add(scope[j]);
            }
            batch.execute(null, chunk);
        }
        batch.finish(null);
    }

    private static List<Case> insertOpenCases(String tag) {
        List<Case> toInsert = new List<Case>();
        for (Integer i = 0; i < VOLUME; i++) {
            toInsert.add(new Case(
                Subject         = prefix(tag) + ' #' + i,
                Origin          = 'Phone',
                Priority        = 'High',
                Kundenstatus__c = 'Standard'
            ));
        }
        insert toInsert;   // 1 bulk Insert -> CaseSLATrigger initSLA (0 Row-DML)
        return toInsert;
    }

    /**
     * AC8-Skalierung: ein periodischer Batch-Lauf bewertet den VOLLSTÄNDIGEN
     * offenen Case-Bestand (> batchSize, multi-Chunk) ohne Timeout, der
     * Stateful-Zähler summiert über alle Chunk-Grenzen, und jeder eigene Case
     * trägt danach einen gültigen Checkpoint.
     */
    @isTest
    static void ac8_scale_multiChunk_evaluatesFullOpenPopulation() {
        Id bh = SLAService.bhId();          // 1x, dem Batch injiziert
        insertOpenCases('A');

        // VOLLSTÄNDIGER offener Scope — exakt wie SLAJobBatch.start():
        List<Case> scope = [
            SELECT Id, Status, Priority, Kundenstatus__c, CreatedDate,
                   SLA_Zielzeit__c, SLA_Status__c, SLA_Eskalation__c,
                   SLA_Ueberschritten__c, SLA_Akkumulierte_WorkingMins__c,
                   SLA_Last_Checked__c, SLA_Uhr_gestoppt__c
            FROM Case WHERE ClosedDate = null
        ];
        Integer fullOpen = scope.size();

        // Batch über ALLE Chunks. Timeout / Governor-Limit hier => Test rot —
        // genau das ist der Skalierungs-Beweis (PO: keine Eskalation verloren).
        SLAJobBatch batch = new SLAJobBatch(System.now(), BATCH_SIZE, bh);
        driveBatchAcrossChunks(batch, scope, BATCH_SIZE);

        // KERN: Stateful-Zähler summiert über 3 Chunk-Grenzen auf den vollen
        // offenen Bestand (pro-Chunk-Reset würde < fullOpen liefern).
        System.assertEquals(fullOpen, batch.getProcessed(),
            'processed muss über ALLE Chunk-Grenzen den vollen offenen Bestand ' +
            'abbilden. Erwartet ' + fullOpen + ', erhalten '
            + batch.getProcessed());

        // Batch hat echt gearbeitet (Änderungen geschrieben, kein no-op).
        System.assert(batch.getChanged() > 0,
            'Der periodische Lauf muss Änderungen schreiben (changed>0). '
            + 'changed=' + batch.getChanged());

        // EIGENE Cases: jede der 420 trägt jetzt Checkpoint (letzter Lauf +
        // Zielzeit) — keine wurde vom periodischen Lauf übersehen.
        Integer mineWithCheckpoint = [
            SELECT COUNT() FROM Case
            WHERE Subject LIKE 'SLA-SCALE A%'
              AND SLA_Last_Checked__c != null
              AND SLA_Zielzeit__c != null
        ];
        System.assertEquals(VOLUME, mineWithCheckpoint,
            'Jede eigene offene Case muss vom Lauf einen Checkpoint tragen. '
            + 'Erwartet ' + VOLUME + ', erhalten ' + mineWithCheckpoint);

        System.debug('SCRUM438SLAScaleTest A: fullOpen=' + fullOpen
            + ' processed=' + batch.getProcessed()
            + ' changed=' + batch.getChanged());
    }

    /**
     * AC8-Idempotenz/Terminierung auf VOLUMEN: zwei aufeinanderfolgende
     * Batch-Läufe über denselben Bestand müssen beide sauber terminieren
     * (kein Hang/Timeout, kein unendlicher Änderungs-Loop). Jeder @isTest
     * läuft in eigener Transaktion — dieser Test ist daher selbsttragend.
     */
    @isTest
    static void ac8_scale_secondRun_terminates() {
        Id bh = SLAService.bhId();
        insertOpenCases('B');

        List<Case> scope = [
            SELECT Id, Status, Priority, Kundenstatus__c, CreatedDate,
                   SLA_Zielzeit__c, SLA_Status__c, SLA_Eskalation__c,
                   SLA_Ueberschritten__c, SLA_Akkumulierte_WorkingMins__c,
                   SLA_Last_Checked__c, SLA_Uhr_gestoppt__c
            FROM Case WHERE ClosedDate = null
        ];

        SLAJobBatch first  = new SLAJobBatch(System.now(), BATCH_SIZE, bh);
        driveBatchAcrossChunks(first,  scope, BATCH_SIZE);
        SLAJobBatch second = new SLAJobBatch(System.now(), BATCH_SIZE, bh);
        driveBatchAcrossChunks(second, scope, BATCH_SIZE);

        System.assertEquals(scope.size(), first.getProcessed(),
            '1. Lauf: voller Bestand abgearbeitet.');
        System.assertEquals(scope.size(), second.getProcessed(),
            '2. Lauf: ebenfalls voller Bestand, saubere Terminierung.');
    }
}
