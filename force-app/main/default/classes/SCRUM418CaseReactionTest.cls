/**
 * [SCRUM-418] Case: Reaktivierungszähler + letzte Reaktivierung.
 *
 * Deckt die Gherkin-ACs ab, soweit sie in einer Test-Transaktion deterministisch
 * beweisbar sind. Wiederaufmachen = Statuswechsel aus 'Closed' in einen offenen
 * Status (New/Working/Escalated). Die Erste Öffnung (old != Closed) zählt NICHT.
 *
 * Zentrale Invarianzen:
 *   - AK3: neuer Fall → Reaktivierungszahl 0 (defaultValue), Letzter_Reaktivierung leer.
 *   - AK1/AK4: Wiederaufmachen → Zahl +1 und letztes Datum gesetzt, SOFORT nach dem
 *     Speichern (gleiche Transaktion, kein Batch, kein manueller Trigger).
 *   - AK2 (Sortierung): reine Report-Angelegenheit (caseList, Desc) — hier nicht;
 *     die Zähl-VORLAGE (die Zahl, nach der sortiert wird) wird hier bewiesen.
 *
 * Der wichtigste Test: `secondReopen_accumulates`. Trigger.new trägt in after update
 * für ein Custom-Feld, das im User-DML nicht gesetzt wurde, null IM SPEICHER. Wir
 * lesen daher die aktuelle Zahl aus der DB (CaseReactionHandler) — nur so wird die
 * zweite Wiederaufmachung korrekt auf 2 erhoben statt auf 1 zurückgesetzt. Ein
 * falsches "Trigger.new direkt lesen" bricht genau diesen Test.
 *
 * Re-Entry: der nach-Trigger `update` im Handler feuert einen weiteren after-update;
 * dort ist old.Status == new.Status ⇒ Guard=false ⇒ kein Doppler. `secondReopen_
 * accumulates` beweist das exakt (Zahl 2, nicht 4).
 *
 * Alles, was hier erzeugt wird, rollt mit der Test-Transaktion zurück.
 */
@isTest
private class SCRUM418CaseReactionTest {

    private static Case read(Id id) {
        return [SELECT Id, Status, Reactivation_Count__c, Last_Reactivation__c
                FROM Case WHERE Id = :id LIMIT 1];
    }

    /** Geschlossenen Fall anlegen (Status=Closed). Count startet auf 0 (defaultValue). */
    private static Id newClosed(String tag) {
        Case c = new Case(Subject = 'V418 ' + tag, Status = 'Closed');
        insert c;
        return c.Id;
    }

    /** Status setzen + speichern (ein User-Update; der Trigger zählt). */
    private static void setStatus(Id id, String status) {
        Case c = read(id);
        c.Status = status;
        update c;
    }

    /** AK3: Neuer Fall → Zahl 0, letztes Datum leer. */
    @isTest
    static void ak3_newCase_startsAtZeroAndBlankDate() {
        Case c = new Case(Subject = 'V418 fresh', Status = 'New');
        insert c;
        Case r = read(c.Id);
        System.assertEquals(0, r.Reactivation_Count__c,
            'AK3: neuer (nie zurückgekehrter) Fall → Reaktivierungszahl 0');
        System.assertEquals(null, r.Last_Reactivation__c,
            'AK3: neuer Fall → „Letzte Reaktivierung“ bleibt leer');
    }

    /** AK1 + AK4: Wiederaufmachen eines geschlossenen Falls → +1 und Datum gesetzt,
     *  SOFORT nach dem Speichern (gleiche Transaktion). */
    @isTest
    static void ak1_ak4_reopen_incrementsAndSetsDateImmediately() {
        DateTime start = System.now();
        Id id = newClosed('reopen');
        System.assertEquals(0, read(id).Reactivation_Count__c,
            'Voraussetzung: geschlossener Fall startet bei 0');

        // Wiederaufmachen: Closed → New.
        setStatus(id, 'New');

        Case r = read(id);
        System.assertEquals(1, r.Reactivation_Count__c,
            'AK1: nach einem Wiederaufmachen → Reaktivierungszahl 1');
        System.assertNotEquals(null, r.Last_Reactivation__c,
            'AK1: „Letzte Reaktivierung“ ist gesetzt');
        // AK4: SOFORT = „jetzt" auf Toleranzfenster (2 Min). Der Test-Context
        // kürzt System.now() auf die Minute und kann zwischen den Aufrufen das
        // Minutentik umwälzen — exaktes `>= start` ist dabei flaky. Das Fenster
        // ist eng genug, um „gleiche Transaktion, keine Nacht" zu beweisen.
        System.assert(
            r.Last_Reactivation__c >= start.addSeconds(-120)
                && r.Last_Reactivation__c <= System.now(),
            'AK4: letztes Datum ist der aktuelle Moment (SOFORT, innerhalb 2 Min), ' +
                'keine Nacht, kein späterer Batch');
    }

    /** ErSTes Öffnen zählt NICHT (old != Closed) — z. B. New → Working. */
    @isTest
    static void firstOpen_doesNotCount() {
        Case c = new Case(Subject = 'V418 first-open', Status = 'New');
        insert c;
        c.Status = 'Working';      // offenes → offenes
        update c;
        System.assertEquals(0, read(c.Id).Reactivation_Count__c,
            'New → Working ist kein Wiederaufmachen (old != Closed) → Zahl bleibt 0');
        System.assertEquals(null, read(c.Id).Last_Reactivation__c,
            'Datum bleibt leer');
    }

    /** Schließen zählt NICHT (offenes → Closed). */
    @isTest
    static void close_doesNotCount() {
        Case c = new Case(Subject = 'V418 close', Status = 'New');
        insert c;
        c.Status = 'Closed';
        update c;
        System.assertEquals(0, read(c.Id).Reactivation_Count__c,
            'New → Closed ist Schließen, kein Wiederaufmachen → Zahl bleibt 0');
    }

    /**
     * DER Schlüsselfall: zweites Wiederaufmachen sammelt auf 2 (nicht zurück auf 1,
     * nicht auf 4 durch Re-Entry). Beweist DB-Lese (Trigger.new-Pitfall) + Re-Entry-Guard
     * (old==new ⇒ kein Doppler).
     */
    @isTest
    static void secondReopen_accumulates() {
        Id id = newClosed('twice');
        System.assertEquals(0, read(id).Reactivation_Count__c, 'Start: 0');

        // 1. Wiederaufmachen: Closed → Working.
        setStatus(id, 'Working');
        System.assertEquals(1, read(id).Reactivation_Count__c, '1. Wiederaufmachen → 1');

        // Zwischenschließen: Working → Closed (zählt NICHT).
        setStatus(id, 'Closed');
        System.assertEquals(1, read(id).Reactivation_Count__c,
            'Zwischenschließen → Zahl bleibt 1');

        // 2. Wiederaufmachen: Closed → Escalated.
        //
        // SCRUM-419: das Grace-Fenster (REACTIVATION_GRACE_SECONDS, s.
        // Handler) unterdrückt eine Reopen, wenn Last_Reactivation__c
        // kürzlich (<5 s) gesetzt wurde — die zweite Feuerung *desselben*
        // Reopens im externen Pfad. Eine echte Zweitreaktivierung (mit
        // Closed-Phase dazwischen) liegt im Menschen-Zeitabstand. Apex
        // kann nicht schlafen → Fenster per Backdaten ablaufen lassen.
        Case c = read(id);
        c.Last_Reactivation__c = System.now()
            - (CaseReactionHandler.REACTIVATION_GRACE_SECONDS + 1) * 1000;
        update c;

        setStatus(id, 'Escalated');
        Case r = read(id);
        System.assertEquals(2, r.Reactivation_Count__c,
            '2. Wiederaufmachen → 2 (auf dem DB-Wert, NICHT zurück auf 1, NICHT 4)');
        System.assert(r.Last_Reactivation__c != null, 'letztes Datum gesetzt');
    }

    /** 1 SOQL für alle übergebenen Ids (Bulk-Governor: kein Einzel-Lese-Loop). */
    private static Map<Id, Case> readAll(List<Id> ids) {
        Map<Id, Case> byId = new Map<Id, Case>();
        for (Case c : [
            SELECT Id, Status, Reactivation_Count__c, Last_Reactivation__c
            FROM Case WHERE Id IN :ids
        ]) {
            byId.put(c.Id, c);
        }
        return byId;
    }

    /** Bulk 200: 200 geschlossene Fälle, alle gleichzeitig wieder geöffnet → je 1. */
    @isTest
    static void bulk200_reopens() {
        List<Case> closed = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            closed.add(new Case(Subject = 'V418bulk ' + i, Status = 'Closed'));
        }
        insert closed;

        // 1 SOQL für alle 200 (kein Einzel-Ladung pro Case — Governor-Limits).
        List<Id> ids = new List<Id>();
        for (Case c : closed) {
            ids.add(c.Id);
        }
        Map<Id, Case> current = readAll(ids);
        for (Case c : current.values()) {
            c.Status = 'New';
        }
        Test.startTest();
        update current.values();
        Test.stopTest();

        // Pro Fall genau 1 (Bulk-200-sicher, kein Drift, kein Doppler).
        // 1 SOQL für die Verifikation.
        Integer ones = 0;
        for (Case c : readAll(ids).values()) {
            if (c.Reactivation_Count__c == 1) {
                ones++;
            }
        }
        System.assertEquals(200, ones,
            'Bulk: alle 200 Wiederaufmachungen → genau 1 (kein Doppler, kein Verlust)');
    }

    /** Guard (Trigger.new-Pitfall / Robustheit): null-/leere Liste → 0, ohne DML. */
    @isTest
    static void recompute_nullAndEmptyList_guard() {
        System.assertEquals(0, CaseReactionHandler.recompute(null), 'null → 0');
        System.assertEquals(0, CaseReactionHandler.recompute(new List<Case>()),
            'leere Liste → 0');
    }
}
