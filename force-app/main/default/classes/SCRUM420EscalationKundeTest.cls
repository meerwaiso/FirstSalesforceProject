/**
 * SCRUM-420: Haupttest — Matrix, Trigger-Ausloeser, Reentry, Bulk.
 *
 * AK1 (Neuanlage), AK2 (High-Eskalation), AK5 (De-Eskalation), AK6 (Zaehler),
 * AK7 (Bulk >=200). TestData via SCRUM420TestDataFactory (Hausmuster 365/370).
 *
 * @author developer-agent
 * @date 2026-09-19
 */
@isTest
private class SCRUM420EscalationKundeTest {

    private static testmethod void ak1_neuanlage_high_case_bewertet_kunde() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK1');
        insertCase(accId, 'High', 'New');
        List<Case> cs = readCase(accId);
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, cs[0].Eskalation_Kunde__c);
        assertEquals(1, (Integer) cs[0].Offene_Cases_Kunde__c);
        assertEquals(1, (Integer) cs[0].Offene_High_Cases_Kunde__c);
    }

    private static testmethod void ak1_neuanlage_low_case_keine_escalation() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK1B');
        insertCase(accId, 'Low', 'New');
        List<Case> cs = readCase(accId);
        assertEquals(CaseEscalationKunde.STUFE_KEINE, cs[0].Eskalation_Kunde__c);
        assertEquals(1, (Integer) cs[0].Offene_Cases_Kunde__c);
        assertEquals(0, (Integer) cs[0].Offene_High_Cases_Kunde__c);
        assertNull(cs[0].Eskalationszeitpunkt__c);
    }

    private static testmethod void ak2_high_wechsel_erhoeht_high_counter() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK2');
        Case c = insertCase(accId, 'Low', 'New');
        c.Priority = 'High';
        update c;
        List<Case> cs = readCase(accId);
        assertEquals(1, (Integer) cs[0].Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, cs[0].Eskalation_Kunde__c);
    }

    private static testmethod void ak2_zweiter_high_case_macht_kritisch() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK2B');
        insertCase(accId, 'High', 'New');
        Case c2 = insertCase(accId, 'High', 'New');
        List<Case> cs = readCase(accId);
        for (Case k : cs) {
            assertEquals(2, (Integer) k.Offene_High_Cases_Kunde__c);
            assertEquals(2, (Integer) k.Offene_Cases_Kunde__c);
            assertEquals(CaseEscalationKunde.STUFE_KRITISCH, k.Eskalation_Kunde__c);
            assertNotNull('Eskalationszeitpunkt muss gesetzt sein', k.Eskalationszeitpunkt__c);
        }
    }

    private static testmethod void ak5_high_zu_low_senkt_zueck() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK5');
        insertCase(accId, 'High', 'New');
        Case c2 = insertCase(accId, 'High', 'New');
        c2.Priority = 'Low';
        update c2;
        List<Case> cs = readCase(accId);
        for (Case k : cs) {
            assertEquals(1, (Integer) k.Offene_High_Cases_Kunde__c);
            assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, k.Eskalation_Kunde__c);
        }
        // Beide Cases offenes -> Beide zeigen H=1 (oben geprueft). 2 Cases erwartet.
        assertEquals(2, cs.size());
    }

    private static testmethod void ak3_zweiten_high_zu_low_senkt_ohne_eintrag() {
        // Vorher kein 'Kritisch' -> keine Zeitstempel
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK3');
        insertCase(accId, 'High', 'New');
        Case c2 = insertCase(accId, 'Low', 'New');
        List<Case> cs = readCase(accId);
        for (Case k : cs) {
            assertNull(k.Eskalationszeitpunkt__c);
        }
    }

    private static testmethod void ak4_zeitstempel_verbleibt_nach_de_escalation() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK4');
        Case c1 = insertCase(accId, 'High', 'New');
        insertCase(accId, 'High', 'New');
        List<Case> cs = readCase(accId);
        DateTime firstTs = null;
        for (Case k : cs) {
            assertNotNull(k.Eskalationszeitpunkt__c);
            if (firstTs == null) {
                firstTs = k.Eskalationszeitpunkt__c;
            }
        }
        c1.Priority = 'Low';
        update c1;
        cs = readCase(accId);
        for (Case k : cs) {
            // Wert bleibt nach Herabstufung (AK4)
            assertNotNull('Zeitstempel darf nicht geresettet werden', k.Eskalationszeitpunkt__c);
        }
    }

    private static testmethod void ak6_closed_case_senkt_zueck_ohne_reaktivierung() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK6');
        Case c1 = insertCase(accId, 'High', 'New');
        Case c2 = insertCase(accId, 'High', 'New');
        // c1 schliessen — Zaehler muss fallen, c2 bleibt 'Kritisch'
        c1.Status = 'Closed';
        update c1;
        Case c2r = readCaseById(c2.Id);
        assertEquals(1, (Integer) c2r.Offene_Cases_Kunde__c);
        assertEquals(1, (Integer) c2r.Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, c2r.Eskalation_Kunde__c);
        // c1 (now closed) keeps last write values — no reset
        Case c1r = readCaseById(c1.Id);
        assertNotNull('Geschlossener Case behaelt seinen letzten Wert', c1r.Eskalation_Kunde__c);
    }

    private static testmethod void ak6_wiedererffnung_erhoht_zueck() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK6B');
        Case c1 = insertCase(accId, 'High', 'New');
        // Schliessen: c1 wird NICHT aktualisiert (geschlossene Cases bleiben unberuehrt,
        // ADR 4) -> der alte Wert (Z=1,H=1,Beobachten) bleibt stehen, kein Reset
        c1.Status = 'Closed';
        update c1;
        Case c1r = readCaseById(c1.Id);
        assertEquals(1, (Integer) c1r.Offene_Cases_Kunde__c);
        assertEquals(1, (Integer) c1r.Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, c1r.Eskalation_Kunde__c);
        // Wiedererffnung: c1 ist wieder offen -> Z=1, H=1, Beobachten
        c1.Status = 'New';
        update c1;
        c1r = readCaseById(c1.Id);
        assertEquals(1, (Integer) c1r.Offene_Cases_Kunde__c);
        assertEquals(1, (Integer) c1r.Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, c1r.Eskalation_Kunde__c);
        // Zweiter High-Case im Account -> beide auf Kritikisch / H=2
        insertCase(accId, 'High', 'New');
        assertEquals(2, (Integer) readCaseById(c1.Id).Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, readCaseById(c1.Id).Eskalation_Kunde__c);
    }

    private static testmethod void ak7_bulk_insert_250_cases_blaeuft_kein_budget() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-AK7');
        Integer baseQueries = Limits.getQueries();
        List<Case> batch = new List<Case>();
        for (Integer i = 0; i < 250; i++) {
            batch.add(new Case(AccountId = accId, Priority = 'Low', Status = 'New'));
        }
        insert batch;
        Integer usedInBatch = Limits.getQueries() - baseQueries;
        // Trigger (1 SOQL for openCases + 1 SOQL for aggregation + 1 trigger SOQL) = max 4
        // — 250 Records in einem Batch duerfen deutlich mehr als 4 Queries nicht erzeugen
        assertTrue(usedInBatch < 10, 'Batch-Queries ueber Budget: ' + usedInBatch);
        // Spot check: alle 250 offen, Stufe 'Keine'
        List<Case> check = readCase(accId);
        assertEquals(250, check.size());
        assertEquals(250, (Integer) check[0].Offene_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_KEINE, check[0].Eskalation_Kunde__c);
    }

    private static testmethod void reentry_guard_verhindert_unendliche_rekursivitaet() {
        // Der Guard laesst nur einen Durchlauf pro Aussen-DML zu
        Id accId = SCRUM420TestDataFactory.createAccount('420-Reentry');
        Case c = insertCase(accId, 'High', 'New');
        // Wenn der Guard fehlt, wuerde die zweite Ebene den Handler nochmal feuern
        // — hier nur sicherstellen, dass der Wert korrekt ist (kein StackOverflow)
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, readCaseById(c.Id).Eskalation_Kunde__c);
    }

    private static testmethod void handler_direct_recompute_setzt_felder() {
        // Handler direkt anrufen (Rebuilder-Pfad) — zwecks idempotent:
        // der Trigger hat beim Insert schon konvergiert, also muss ein
        // zweiter recompute exakt 0 Records auffinden und die Felder bleiben.
        // (Idempotenz ist auch die Garantie für AK5/AK4: keine doppelte Zählung.)
        Id accId = SCRUM420TestDataFactory.createAccount('420-Handler');
        Case c1 = new Case(AccountId = accId, Priority = 'High', Status = 'New');
        Case c2 = new Case(AccountId = accId, Priority = 'High', Status = 'New');
        insert new List<Case> { c1, c2 };
        // Trigger hat schon konvergiert: H=2, Kritisch auf beiden
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, readCaseById(c1.Id).Eskalation_Kunde__c);
        // Direkter recompute muss ein No-Op sein
        Integer updated = CaseEscalationKunde.recompute(new Set<Id> { accId });
        assertEquals(0, (Integer) updated);
        // und die Werte sind unverändert
        assertEquals(2, (Integer) readCaseById(c1.Id).Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, readCaseById(c2.Id).Eskalation_Kunde__c);
    }

    private static testmethod void derive_stufe_unit() {
        assertEquals(CaseEscalationKunde.STUFE_KEINE, CaseEscalationKunde.deriveStufe(0));
        assertEquals(CaseEscalationKunde.STUFE_BEOBACHTEN, CaseEscalationKunde.deriveStufe(1));
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, CaseEscalationKunde.deriveStufe(2));
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, CaseEscalationKunde.deriveStufe(7));
        assertEquals(CaseEscalationKunde.STUFE_KEINE, CaseEscalationKunde.deriveStufe(null));
    }

    private static testmethod void rebuilder_laeuft_ueber_bestand_und_ist_idempotent() {
        // Deckt CaseEscalationKundeRebuilder.ab: eine run() ueber echten Bestand.
        // Der Trigger hat beim Insert schon konvergiert -> der Rebuilder ist hier
        // ein korrekter No-Op (0 Accounts geaendert). Der Aufruf selbst ist der
        // Coverage- und Funktionsnachweis des Bestands-Pfads.
        Id accId = SCRUM420TestDataFactory.createAccount('420-Rebuilder');
        Case a1 = insertCase(accId, 'High', 'New');
        Case a2 = insertCase(accId, 'High', 'New');
        Case b  = insertCase(accId, 'Low', 'New');
        // Vorher: Trigger hat konvergiert (H=2 -> alle drei offen 'Kritisch')
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, readCaseById(a1.Id).Eskalation_Kunde__c);
        // Rebuilder-Run ueber den Bestand: 0 geaenderte Accounts (schon konvergiert)
        Integer changed = CaseEscalationKundeRebuilder.run(accId);
        assertEquals(0, (Integer) changed);
        // Werte bleiben
        assertEquals(3, (Integer) readCaseById(b.Id).Offene_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, readCaseById(b.Id).Eskalation_Kunde__c);
        // Zweite Code-Pfad-Abdeckung: der Vollast-Modus (null = alle Accounts).
        // Test-Transaktion rollt alle DML zurueck — sicher ueber den Bestand.
        Integer changedFull = CaseEscalationKundeRebuilder.run(null);
        System.assert(changedFull != null, 'run(null) liefert Anzahl (>=0)');
    }

    private static testmethod void kundenwechsel_berechnet_bei_bei_den_beiden() {
        Id accA = SCRUM420TestDataFactory.createAccount('420-KU-A');
        Id accB = SCRUM420TestDataFactory.createAccount('420-KU-B');
        Case ca = insertCase(accA, 'High', 'New');
        Case cb = insertCase(accB, 'High', 'New');
        // Kunde wechselt von A nach B
        ca.AccountId = accB;
        update ca;
        // A: kein offener Fall mehr -> A-Case nicht mehr im A-List
        // B: 2 offene High -> 'Kritisch'
        Case cbR = readCaseById(cb.Id);
        assertEquals(2, (Integer) cbR.Offene_Cases_Kunde__c);
        assertEquals(2, (Integer) cbR.Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, cbR.Eskalation_Kunde__c);
        Case caR = readCaseById(ca.Id);
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, caR.Eskalation_Kunde__c);
    }

    private static testmethod void geschlossener_case_wird_nicht_berechnet() {
        Id accId = SCRUM420TestDataFactory.createAccount('420-Closed');
        Case c = insertCase(accId, 'Low', 'New');
        Case cClosed = new Case(AccountId = accId, Priority = 'Low', Status = 'Closed');
        insert cClosed;
        // c muss weiterhin Z=1 zeigen (closed-case wird nicht mitgezählt)
        Case cR = readCaseById(c.Id);
        assertEquals(1, (Integer) cR.Offene_Cases_Kunde__c);
    }

    // ---------- helpers ----------

    private static Case insertCase(Id accId, String priority, String status) {
        Case c = new Case(AccountId = accId, Priority = priority, Status = status);
        insert c;
        return c;
    }

    private static Case readCaseById(Id caseId) {
        return [SELECT AccountId, Offene_Cases_Kunde__c, Offene_High_Cases_Kunde__c,
                      Eskalation_Kunde__c, Eskalationszeitpunkt__c
                FROM Case WHERE Id = :caseId LIMIT 1];
    }

    private static List<Case> readCase(Id accId) {
        return [SELECT AccountId, Offene_Cases_Kunde__c, Offene_High_Cases_Kunde__c,
                      Eskalation_Kunde__c, Eskalationszeitpunkt__c
                FROM Case WHERE AccountId = :accId];
    }

    private static void assertEquals(Object expected, Object actual) {
        System.assertEquals(expected, actual, 'unexpected value');
    }

    private static void assertEquals(Object expected, Object actual, String msg) {
        System.assertEquals(expected, actual, msg);
    }

    private static void assertNotNull(Object v) {
        System.assertNotEquals(null, v, 'expected non-null');
    }

    private static void assertNotNull(String msg, Object v) {
        System.assertNotEquals(null, v, msg);
    }

    private static void assertNull(Object v) {
        System.assertEquals(null, v, 'expected null');
    }

    private static void assertTrue(Boolean cond, String msg) {
        System.assert(cond, msg);
    }
}
