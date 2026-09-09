/**
 * [SCRUM-403] Kontakt: Datum des letzten Anliegens + Dauer — Apex-Funktionaltests.
 *
 * Deckt die 8 Gherkin-ACs ab, soweit sie in einer Test-Transaktion deterministisch
 * beweisbar sind. WICHTIGE ORG-EGENSCHEFT (empirisch geprüf, 2026-09-09):
 * `Case.CreatedDate` ist in dieser Org NICHT per DML setzbar (Compile-Fehler
 * „Field is not writeable") — das ist die gleiche Determinierungs-Grenze, die
 * SCRUM-382 beim Account.CreatedDate hatte. Jede in @isTest-Transaktion neu
 * erzeugte Case trägt daher immer `CreatedDate = heute`.
 *
 * Folgerungen für die Tests (bewusst, nicht Zufall):
 *   - AC 1, 4, 5, 6: „jüngster Fall" ist in der Transaktion immer = heute →
 *     das Feld muss `Date.today()` tragen. Die zeitliche REIHENFOLGE zweier
 *     Fälle an verschiedenen Tagen (z. B. „neues Anliegen rückt das Datum vom
 *     1. auf den 15.") lässt sich hier NICHT per Unit-Test belegen, weil
 *     CreatedDate nicht backdatet werden kann — ADR-2/403-Feststellung.
 *     Stattdessen wird die Logik als MAX-Invariante geprüft: mehrere Fälle →
 *     Feld = MAX(CreatedDate) = heute; letzter gelöschter Fall → NULL.
 *     Die Reihenfolge-Läufe (2025-06 → 2025-07, „vor N Tagen") werden zusätzlich
 *     LIVE (Org-Daten mit echten historischen Cases) verifiziert und im
 *     Handoff-Kommentar belegt.
 *   - AC 2, 7: leer + FLS read-only — voll deterministisch, hier bewiesen.
 *   - AC 8: Record-View/List-View = Tester-Auftrag (E2E), hier nicht.
 *
 * Alles, was hier erzeugt wird, rollt mit der Test-Transaction zurück.
 */
@isTest
private class SCRUM403LastCaseDateTest {

    /** Contact anlegen, Id zurückgeben. */
    private static Id newContact(String tag) {
        Contact c = new Contact(LastName = 'V403 ' + tag);
        insert c;
        return c.Id;
    }

    /** Liest `Last_Case_Date__c` (null-safe). */
    private static Date lastDateOf(Id contactId) {
        return [SELECT Last_Case_Date__c FROM Contact WHERE Id = :contactId].Last_Case_Date__c;
    }

    /** Liest `Time_Since_Last_Case__c` (Textformel, null-safe). Formelfelder
     *  sind nicht auf dem in-memory SObject nach DML — deshalb Query. */
    private static String sinceOf(Id contactId) {
        return [SELECT Time_Since_Last_Case__c FROM Contact WHERE Id = :contactId].Time_Since_Last_Case__c;
    }

    /**
     * AC 1: Ein Kontakt mit einem Fall (offen UND/ODER erledigt, beide Status
     *  relevant) zeigt das Feld = heute (Case.CreatedDate = heute) und die
     *  Formel „heute". Beweist auch die Formel-Textlogik für die heute-Differenz.
     */
    @isTest
    static void existingCase_showsDateAndHumanDuration() {
        // Open Case.
        Id a = newContact('Open');
        insert new Case(ContactId = a, Status = 'New', Subject = 'a-open');
        System.assertEquals(Date.today(), lastDateOf(a),
            'AC1: Kontakt mit offenem Fall → Last_Case_Date__c = heute (CreatedDate = heute)');
        System.assertEquals('heute', sinceOf(a),
            'AC1: heute-datierte Case → Formel «Wie lange her» = „heute"');

        // Closed Case (zweiter Kontakt) — Status spielt für das Datum keine Rolle.
        Id b = newContact('Closed');
        insert new Case(ContactId = b, Status = 'Closed', Subject = 'b-closed');
        System.assertEquals(Date.today(), lastDateOf(b),
            'AC1: erledigter Fall zählt ebenso → Last_Case_Date__c = heute');
    }

    /**
     * AC 2: Kontakt OHNE Cases bleibt VOLLSTÄNDIG leer — kein „heute", keine 0.
     *  BOTH fields null. (ADR-4: NULL = „kein Fall je".)
     */
    @isTest
    static void contactWithoutCases_staysBlank() {
        Id a = newContact('NoCases');
        // Der Trigger ist aktiv; ein bloßer Contact ohne Case hat das Feld nie berührt.
        System.assertEquals(null, lastDateOf(a),
            'AC2: Kontakt ohne Fälle → Last_Case_Date__c bleibt NULL (kein „heute")');
        System.assertEquals(null, sinceOf(a),
            'AC2: Kontakt ohne Fälle → Time_Since_Last_Case__c bleibt NULL (keine 0 / kein Text)');
    }

    /**
     * AC 4 + MAX-Invariante: Ein NEUES Anliegen verschiebt das Feld auf das
     *  CreatedDate der Case (= heute in der Transaktion). Weitere Cases ändern
     *  es nicht (MAX ist stabil auf heute). Beweist die „Datum rückt auf das
     *  jüngste CreatedDate"-Logik innerhalb des in der Org möglichen Rahmens.
     */
    @isTest
    static void newCase_setsDateToNewestCreatedDate() {
        Id a = newContact('Update');
        insert new Case(ContactId = a, Status = 'New', Subject = 'old');
        System.assertEquals(Date.today(), lastDateOf(a),
            'AC4: nach erstem Fall → Feld = heute (CreatedDate)');

        // Zweiter (neuerer) Fall anlegen — MAX(CreatedDate) bleibt heute → Feld bleibt heute.
        insert new Case(ContactId = a, Status = 'Working', Subject = 'newer');
        System.assertEquals(Date.today(), lastDateOf(a),
            'AC4: zweiter Fall → Feld = MAX(CreatedDate) = heute (stabil); Reihenfolge-Abstand ist live verifiziert');
    }

    /**
     * AC 5 (innerhalb des Transaktionsrahmens): Wird der JÜNGSTE (hier: einzige)
     *  Fall gelöscht, fällt das Feld auf NULL zurück (MAX über 0 Fälle = null).
     *  Der Fall „jüngster von zwei → älterer" wäre zeitlich ein anderes Datum —
     *  das ist live geprüft; hier der deterministische NULL-Rückfall.
     */
    @isTest
    static void lastCaseDeleted_fallsBackToNull() {
        Id a = newContact('Delete');
        Case c = new Case(ContactId = a, Status = 'New', Subject = 'only');
        insert c;
        System.assertEquals(Date.today(), lastDateOf(a), 'vor Delete: Feld = heute');

        delete c;
        System.assertEquals(null, lastDateOf(a),
            'AC5: letzter Fall gelöscht → Last_Case_Date__c = NULL (Rückfall, nicht „heute")');
        System.assertEquals(null, sinceOf(a), 'AC5: Formel folgt dem NULL-Datum → leer');
    }

    /**
     * AC 6 (Umbuchung, ADR-3: Relevanz = NUR ContactId-Änderung): Ein Fall wird
     *  von Kontakt A auf B verschoben → B trägt das Datum, A fällt zurück
     *  (hier: auf NULL, weil A keine weiteren Fälle hat). Status-Wechsel wäre
     *  irrelevant — der Test ändert bewusst NICHT den Status (nur ContactId).
     */
    @isTest
    static void reassign_movesDateNewGetsOldFallsBack() {
        Id a = newContact('ReassignOld');
        Id b = newContact('ReassignNew');
        Case c = new Case(ContactId = a, Status = 'New', Subject = 'move');
        insert c;
        System.assertEquals(Date.today(), lastDateOf(a), 'vor Umhänge: A = heute');
        System.assertEquals(null, lastDateOf(b), 'vor Umhänge: B = NULL');

        // ContactId wechseln (Umbuchung) — Status bleibt, nur der Kontakt.
        c.ContactId = b;
        update c;
        System.assertEquals(Date.today(), lastDateOf(b),
            'AC6: nach Umbuchung → B trägt das Datum (heute)');
        System.assertEquals(null, lastDateOf(a),
            'AC6: nach Umbuchung → A fällt zurück (kein Fall mehr) = NULL');
    }

    /**
     * Inert-Check (ADR-3): Ein Update, das NICHT die ContactId ändert (nur
     *  Status/Subject), darf das Datum NICHT verändern bzw. auslösen.
     */
    @isTest
    static void statusChange_isInertForLastDate() {
        Id a = newContact('Inert');
        Case c = new Case(ContactId = a, Status = 'New', Subject = 's');
        insert c;
        Date before = lastDateOf(a);

        c.Status = 'Closed';
        update c;
        System.assertEquals(before, lastDateOf(a),
            'ADR-3: Status-Wechsel eines bestehenden Falls ist für das Datum irrelevant');
        c.Subject = 'irrelevant';
        update c;
        System.assertEquals(before, lastDateOf(a),
            'ADR-3: Subject-Wechsel ist ebenfalls irrelevant');
    }

    /**
     * Bulk 200 + Governor: 200 neue Fälle auf 25 Kontakte (je 8) — kein Abbruch,
     *  Feld = MAX(CreatedDate) = heute für alle. 1 Trigger-Fanout → 1 recompute.
     */
    @isTest
    static void bulk200_insertKeepsMaxDate() {
        List<Contact> contacts = new List<Contact>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 25; i++) {
            Contact c = new Contact(LastName = 'V403Bulk ' + i);
            contacts.add(c);
        }
        insert contacts;
        for (Contact c : contacts) {
            ids.add(c.Id);
        }
        List<Case> bigBatch = new List<Case>();
        for (Integer round = 0; round < 8; round++) {
            for (Integer k = 0; k < ids.size(); k++) {
                bigBatch.add(new Case(ContactId = ids.get(k), Status = 'New', Subject = 'bulk403-' + round + '-' + k));
            }
        }
        insert bigBatch; // 1 DML, 200 Zeilen → Trigger → 1 recompute (MAX)
        for (Id cid : ids) {
            System.assertEquals(Date.today(), lastDateOf(cid),
                'Bulk: jeder der 25 Kontakte → Last_Case_Date__c = heute');
        }
    }

    /**
     * Guard-Rückgabewerte (SCRUM-367-kompatibel): null- / leeres Set → 0, ohne DML.
     */
    @isTest
    static void recompute_nullAndEmptySet_guard() {
        System.assertEquals(0, LastCaseDateTrigger.recompute(null), 'null-Set → 0');
        System.assertEquals(0, LastCaseDateTrigger.recompute(new Set<Id>()), 'leeres Set → 0');
    }

    /**
     * AC 3 (Bestand rückwirkend, Batch) + Idempotenz: Bestands-Kontakte mit alten
     *  Fällen (hier simuliert: Cases heute, Feld danach bewusst NULL = „nie
     *  gezählt") werden durch runOnce() geheilt → Feld = heute.
     *  2. Auswertung (recompute auf die geheilten) = 0 geänderte (Idempotenz).
     *
     *  WICHTIG: In der Test-Transaktion sind ALLE Cases heute-datiert (CreatedDate
     *  nicht backdatierbar), daher zeigen geheilte Contacts „heute", nicht ihr
     *  historisches CreatedDate. Der reale Bestands-Lauf mit echten alten Fällen
     *  (2025/2026) wird live verifiziert und im Handoff belegt.
     */
    @isTest
    static void batchRun_healsStaleContacts_andIsIdempotent() {
        // Stale: Case (heute), Feld danach auf NULL = „Trigger hat nie gezählt".
        Id a = newContact('StaleA');
        Id b = newContact('StaleB');
        insert new Case(ContactId = a, Status = 'New', Subject = 'stale-a');
        insert new Case(ContactId = b, Status = 'Closed', Subject = 'stale-b');
        Contact upA = [SELECT Id, Last_Case_Date__c FROM Contact WHERE Id = :a];
        upA.Last_Case_Date__c = null;   // Bestandszustand simulieren
        update upA;
        Contact upB = [SELECT Id, Last_Case_Date__c FROM Contact WHERE Id = :b];
        upB.Last_Case_Date__c = null;
        update upB;
        System.assertEquals(null, lastDateOf(a), 'Vor Batch: a = NULL (stale)');

        // Bestands-Migration: Batch über ALLE Kontakte (kein LastModified-Filter).
        String batchId;
        Test.startTest();
        batchId = LastCaseDateRebuilder.runOnce();
        Test.stopTest();
        System.assert(String.isNotBlank(batchId), 'runOnce() muss eine Batch-Id liefern');

        // Geheilt: beide Stale-Kontakte zeigen heute.
        System.assertEquals(Date.today(), lastDateOf(a), 'AC3: Stale-A (Fall heute) geheur → heute');
        System.assertEquals(Date.today(), lastDateOf(b), 'AC3: Stale-B (erledigter Fall) geheur → heute');

        // Idempotenz: erneute Neuberechnung der (nun korrekten) Kontakte → 0 geändert.
        Integer changed = LastCaseDateTrigger.recompute(new Set<Id>{a, b});
        System.assertEquals(0, changed, 'AC3: 2. Auswertung → 0 geänderte Kontakte (Idempotenz)');
    }
}
