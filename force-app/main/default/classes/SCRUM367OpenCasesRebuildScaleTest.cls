/**
 * SCRUM-367: AC 5 (Skalierung / Multi-Chunk) — Tester-Apex-Tests.
 *
 * Ergaenzt die Developer-Klasse SCRUM367OpenCasesRebuildTest: deren No-Code-
 * Lauf prueft in der kleinen Test-Org nur EINEN Batch-Chunk (~25 Kontakte,
 * batch 200). AC 5 — «50k Kontakte => 250 Chunks ohne Timeout» — lebt dagegen
 * DARIN, dass die Stateful-Parameter processed/corrected ueber ALLE Chunk-
 * Grenzen exakt aufsummieren statt pro Chunk ueberschrieben zu werden. Genau
 * die Summations-Logik prueft diese Klasse.
 *
 * --------------------------------------------------------------------------
 * WARUM hier nicht Database.executeBatch() (empirisch in der Test-Org belegen):
 *   SCRUM367ChunkProbeTest (Run 707WU00001GGEk7, API 62) zeigt:
 *     - oneChunk  (QueryLocator <= batchSize => 1 Chunk)  => PASS
 *     - twoChunks (QueryLocator >  batchSize => 2 Chunks) => FAIL:
 *         System.UnexpectedException: No more than one executeBatch ...
 *   Der Test-Kontext dieser Org laesst einen executeBatch-Lauf NUR als
 *   Einzel-Chunk durch; laeuft der QueryLocator ueber die Batch-Groesse hinaus
 *   (echtes Multi-Chunk), verweigert der Framework-Wrapper den Lauf —
 *   unabhaengig von der Anzahl der executeBatch-Aufrufe.
 *
 *   Deshalb wird hier die PRODUKTIONS-Methode execute() auf dem GLEICHEN
 *   Instanz-Objekt (das ist die Bedeutung von Database.Stateful) Chunk fuer
 *   Chunk angetrieben — exakt die Chunk-Schleife, die das Batch-Framework
 *   ausfuehren wuerde — und am Ende finish(). Damit steht unter Beweis, dass
 *   die Stateful-Zaehler ueber beliebige Chunk-Grenzen addieren. Die reale
 *   executeBatch->QueryLocator-Maschinerie ist getrennt belegt (Probe
 *   oneChunk=Pass; Developer noCodePath; echter Run-1 in der Org).
 *   Timeout-bei-50k ist eine Laufzeit-/Architektur-Eigenschaft (kurze DML-
 *   Transaktionen pro Chunk, kein SELECT FOR UPDATE), kein deterministisch
 *   unit-testbarer Wert — und wird im Jira-Kommentar als solches benannt.
 *
 * @author tester-agent
 * @date 2026-08-28
 */
@isTest
private class SCRUM367OpenCasesRebuildScaleTest {

    /**
     * Fahren der Chunk-Schleife wie das Batch-Framework: die uebergebene
     * Scope-Liste wird in Stuecken von `chunkSize` auf dem GLEICHEN Batch-
     * Objekt ueber die PRODUKTIONS-Methode execute() verarbeitet (Stateful:
     * dieselbe Instanz ueberlebt Chunk-Grenzen), danach finish(). ctx wird
     * von execute()/finish() nicht verwendet => null ist erlaubt.
     */
    private static void driveBatchAcrossChunks(CaseOpenCountRebuilder batch,
            List<Contact> scope, Integer chunkSize) {
        Integer totalRecords = scope.size();
        for (Integer startIdx = 0; startIdx < totalRecords; startIdx += chunkSize) {
            Integer endIdx = (startIdx + chunkSize > totalRecords)
                    ? totalRecords : (startIdx + chunkSize);
            List<Contact> chunk = new List<Contact>();
            for (Integer j = startIdx; j < endIdx; j++) {
                chunk.add(scope[j]);
            }
            batch.execute(null, chunk);
        }
        batch.finish(null);
    }

    /**
     * AC 5 (Hauptbeleg): normalisierter Bestand + 500 stale Kontakte (Zaehler
     * NULL, je 1 offener Fall), Batch-Groesse 200 => mehrere Chunk-Grenzen.
     * processed muss exakt aufsummieren, alle 500 geheilt, corrected genau
     * 500 (Bestand war vorher exakt).
     */
    @isTest
    static void multiChunk_staleStock_summationStateful() {
        // 1) Bestand exakt normalisieren => danach 0 Korrekturen am Stock.
        Set<Id> stockIds = new Set<Id>();
        for (Contact ct : [SELECT Id FROM Contact]) {
            stockIds.add(ct.Id);
        }
        CaseOpenCountTrigger.recompute(stockIds);
        Integer stockContacts =
                (Integer)[SELECT COUNT(Id) cnt FROM Contact].get(0).get('cnt');

        // 2) 500 stale Kontakte anlegen, je 1 offener Fall, Zaehler => NULL.
        Integer n = 500;
        Set<Id> staleIds = new Set<Id>();
        List<Contact> contacts = new List<Contact>();
        // IDs NACH dem Insert sammeln — vorher ist c.Id noch null und die
        // Set waere ein einziger null-Eintrag (WHERE Id IN matcht nichts).
        for (Integer i = 0; i < n; i++) {
            Contact c = new Contact(LastName = 'SCRUM367Scale ' + String.valueOf(i));
            contacts.add(c);
        }
        insert contacts;
        for (Contact c : contacts) {
            staleIds.add(c.Id);
        }
        List<Case> cases = new List<Case>();
        for (Contact c : contacts) {
            cases.add(new Case(ContactId = c.Id, Status = 'New', Subject = 'scale-open'));
        }
        insert cases;
        List<Contact> toNull =
                [SELECT Id, Open_Cases_Count__c FROM Contact WHERE Id IN :staleIds];
        for (Contact u : toNull) {
            u.Open_Cases_Count__c = null;
        }
        update toNull;

        // 3) Produktions-Klasse, Produktions-Batch-Groesse (200): 500+Stock
        //    => mehrere Chunks.
        Integer batchSize = CaseOpenCountRebuilder.DEFAULT_BATCH_SIZE;
        CaseRebuildRun__c run = new CaseRebuildRun__c();
        run.Status__c = CaseOpenCountRebuilder.STATUS_RUNNING;
        insert run;
        CaseOpenCountRebuilder batch = new CaseOpenCountRebuilder(run.Id, batchSize);

        // Gesamter Scope, den der QueryLocator sehen wuerde (Stock + 500).
        List<Contact> fullScope = [SELECT Id FROM Contact];
        driveBatchAcrossChunks(batch, fullScope, batchSize);

        CaseRebuildRun__c done = [
            SELECT Id, Status__c, ContactsProcessed__c, ContactsCorrected__c,
                   FinishedAt__c
            FROM CaseRebuildRun__c WHERE Id = :run.Id
        ];
        System.assertEquals(CaseOpenCountRebuilder.STATUS_DONE, done.Status__c,
                'Der Lauf muss Abgeschlossen sein');
        System.assert(done.FinishedAt__c != null, 'FinishedAt muss gesetzt sein');

        // DER AC-5-BELEG: exakte Summe ueber ALLE Chunk-Grenzen — der letzte
        // Chunk ueberschreibt die vorherigen nicht.
        System.assertEquals(stockContacts + n, done.ContactsProcessed__c,
                'AC 5: ContactsProcessed muss exakt dem Gesamtbestand '
                + '(Stock + ' + n + ') entsprechen; Stateful-Summation ueber '
                + 'mehrere Chunks. Erwartet ' + (stockContacts + n) + ', ist '
                + done.ContactsProcessed__c);

        // Alle 500 stale Kontakte zeigen danach exakt 1 (je 1 offener Fall).
        Integer healed =
                (Integer)[
                    SELECT COUNT(Id) cnt FROM Contact
                    WHERE Id IN :staleIds AND Open_Cases_Count__c = 1
                ].get(0).get('cnt');
        System.assertEquals(n, healed,
                'AC 5: alle 500 stale Kontakte muessten exakt 1 zeigen. '
                + 'Geheilt: ' + healed);

        // Genau die 500 stale wurden korrigiert (Stock war exakt normalisiert).
        System.assertEquals(n, done.ContactsCorrected__c,
                'AC 5: korrekt = exakt die 500 stale (keine Stock-Korrektur). '
                + 'Ist: ' + done.ContactsCorrected__c);
    }

    /**
     * AC 5 + Idempotenz: auf einem exakt normalisierten Bestand (Stock + 500
     * sauber gesetzte Kontakte) verarbeitet der Multi-Chunk-Lauf den vollen
     * Bestand und korrigiert GERADE 0; die Werte driften nicht.
     */
    @isTest
    static void multiChunk_cleanStock_correctsNothing_noDrift() {
        Set<Id> stockIds = new Set<Id>();
        for (Contact ct : [SELECT Id FROM Contact]) {
            stockIds.add(ct.Id);
        }
        CaseOpenCountTrigger.recompute(stockIds);
        Integer stockContacts =
                (Integer)[SELECT COUNT(Id) cnt FROM Contact].get(0).get('cnt');

        // 500 korrekt gesetzte Kontakte (je 1 offener Fall, Zaehler => 1).
        Integer n = 500;
        Set<Id> ids = new Set<Id>();
        List<Contact> contacts = new List<Contact>();
        // IDs NACH dem Insert sammeln — vorher ist c.Id noch null.
        for (Integer i = 0; i < n; i++) {
            Contact c = new Contact(LastName = 'SCRUM367Scale2 ' + String.valueOf(i));
            contacts.add(c);
        }
        insert contacts;
        for (Contact c : contacts) {
            ids.add(c.Id);
        }
        List<Case> cases = new List<Case>();
        for (Contact c : contacts) {
            cases.add(new Case(ContactId = c.Id, Status = 'New', Subject = 'scale2-open'));
        }
        insert cases;
        // Sicherstellen, dass alle 500 exakt zeigen (Trigger + explizit).
        List<Contact> setOne =
                [SELECT Id, Open_Cases_Count__c FROM Contact WHERE Id IN :ids];
        for (Contact u : setOne) {
            u.Open_Cases_Count__c = 1;
        }
        update setOne;

        Integer batchSize = CaseOpenCountRebuilder.DEFAULT_BATCH_SIZE;
        CaseRebuildRun__c run = new CaseRebuildRun__c();
        run.Status__c = CaseOpenCountRebuilder.STATUS_RUNNING;
        insert run;
        CaseOpenCountRebuilder batch = new CaseOpenCountRebuilder(run.Id, batchSize);

        List<Contact> fullScope = [SELECT Id FROM Contact];
        driveBatchAcrossChunks(batch, fullScope, batchSize);

        CaseRebuildRun__c done = [
            SELECT Id, Status__c, ContactsProcessed__c, ContactsCorrected__c,
                   FinishedAt__c
            FROM CaseRebuildRun__c WHERE Id = :run.Id
        ];
        System.assertEquals(CaseOpenCountRebuilder.STATUS_DONE, done.Status__c,
                'Der Lauf muss Abgeschlossen sein');

        System.assertEquals(stockContacts + n, done.ContactsProcessed__c,
                'AC 5: ContactsProcessed == Gesamtbestand (Stock + ' + n + '). '
                + 'Erwartet ' + (stockContacts + n) + ', ist '
                + done.ContactsProcessed__c);

        // Idempotenz: auf exaktem Bestand wird NICHTS korrigiert (kein Drift).
        System.assertEquals(0, done.ContactsCorrected__c,
                'AC 5: Lauf auf korrektem Bestand muss genau 0 korrigieren '
                + '(Idempotenz, kein Drift). Ist: ' + done.ContactsCorrected__c);

        Integer stillCorrect =
                (Integer)[
                    SELECT COUNT(Id) cnt FROM Contact
                    WHERE Id IN :ids AND Open_Cases_Count__c = 1
                ].get(0).get('cnt');
        System.assertEquals(n, stillCorrect,
                'Werte duerfen nicht driften. Korrekt geblieben: ' + stillCorrect);
    }
}
