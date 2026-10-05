/**
 * SCRUM-420: Haupttest — Matrix, Trigger-Ausloeser, Reentry, Bulk.
 *
 * AK1 (Neuanlage), AK2 (High-Eskalation), AK5 (De-Eskalation), AK6 (Zaehler),
 * AK7 (Bulk >=200). TestData via SCRUM420TestDataFactory (Hausmuster 365/370).
 *
 * [SCRUM-438 CI-Restore, Round 2 — 2026-10-05] Architektur, empirisch belegt
 * (Org-Testlaeufe, keine Theorie):
 *
 * 1) SETUP-DML (User + PermissionSetAssignment = ursacheUser()) und
 *    ACCOUNT-INSERT koennen in KEINER Apex-Test-Transaktion koexistieren —
 *    in BEIDEN Richtungen gemessen:
 *      - Alt-Version (createAccount -> ursacheUser): MIXED_DML, 13x
 *        (CI-Run 37324229643, Architect-Kmt 22859).
 *      - 4-arg-Hoist (ursacheUser -> createAccount): MIXED_DML am
 *        createAccount:17, 13x (Org-Run 707WU00001M9HxJ, deployed Code).
 *    Reihenfolge hilft also NICHT — ein Account-Insert neben PSA-DML ist per
 *    Plattformdefinition Mixed DML, egal welche Richtung. Kein Hauspattern
 *    der gruenen Klassen (390/418/419/432/437) mischt beides; 420 ist der
 *    Ausreisser, weil die Eskalation pro Kunde (AccountId) rechnet.
 *
 * 2) CasePriorityTrigger ist in der ORG (nicht im Repo, SCRUM-393 d65d54a
 *    nur aus dem Repo entfernt) und wirft bei JEDEM Case-Insert mit AccountId
 *    unter System.runAs(Standard User) "Variable does not exist: tmpVar1"
 *    (buildBatchData:112, Org-Zeile: "WHERE Id IN :accountIds AND
 *    VIP_Customer__c = true" — der Bind scheitert an FLS; fls-check.sh
 *    2026-10-05: VIP_Customer__c wird nur ueber SCRUM333_VIP_Customer
 *    gewaehrt, Standard User hat es nicht). Case-inserts OHNE AccountId
 *    laufen unter Standard User fehlerfrei (SCRUM-437-Header, Probe).
 *
 * Konsequenz (Arbeitsteilung wie SCRUM-437, das in CI gruen ist):
 *   - Alle Account-gekeyten AK/Tests (ak1..ak7, reentry, handler_direct,
 *     rebuilder, kundenwechsel, geschlossener_case) laufen im SYSTEM-Kontext:
 *     kein PSA/Setup-DML in der Methode -> kein MIXED_DML moeglich, und der
 *     Trigger-Fire laeuft mit Admin-FLS (ak7 + handler_direct belegen das
 *     empirisch: sie machen AccountId-Inserts und sind in CI gruen).
 *   - fls_lueckeC_ursache_uStandardUser ist der Einzige mit PSA der Klasse:
 *     ursacheUser() (Setup-DML) + Case-Insert OHNE AccountId unter runAs.
 *     PSA -> Case-insert (ohne Account) ist empirisch gruen in CI
 *     (scr390/scr418/scr419/scr437, seit Wochen). Das erfuellt Luecke C von
 *     scripts/fls-gate.py: System.runAs( in einer Klasse, die das neue Feld
 *     Case.Ursache__c beruehrt.
 *
 * @author developer-agent
 * @date 2026-09-19 (Round-2-Rewrite 2026-10-05)
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
        // Beide Cases offen -> beide zeigen H=1 (oben geprueft). 2 Cases erwartet.
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
        c1.Ursache__c = 'HowToAnfrage';
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
        c1.Ursache__c = 'HowToAnfrage';
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
        // Zweiter High-Case im Account -> beide auf Kritisch / H=2
        insertCase(accId, 'High', 'New');
        assertEquals(2, (Integer) readCaseById(c1.Id).Offene_High_Cases_Kunde__c);
        assertEquals(CaseEscalationKunde.STUFE_KRITISCH, readCaseById(c1.Id).Eskalation_Kunde__c);
    }

    private static testmethod void ak7_bulk_insert_250_cases_mixed_accounts_blaeuft_kein_budget() {
        // AK7: >= 200 Cases, GEMISCHT JE ACCOUNT — der governor-sensible Pfad ist
        // die Multi-Account IN-Liste + per-Account-Zaehlung, nicht nur ein Account.
        // 10 Accounts x 25 Cases, Prioritaeten gemischt (Low/High).
        // Kein PSA/Setup-DML: Bulk-Insert im System-Kontext -> kein MIXED_DML
        // moeglich, Trigger mit Admin-FLS (empirisch gruen in CI, Run
        // 37279408056).
        final Integer accountsN = 10;
        final Integer casesPerAccount = 25;
        List<Id> accIds = new List<Id>();
        for (Integer a = 0; a < accountsN; a++) {
            accIds.add(SCRUM420TestDataFactory.createAccount('420-AK7-' + a));
        }
        Integer baseQueries = Limits.getQueries();
        List<Case> batch = new List<Case>();
        // Design TC7: gemischt, je Account 0/1/2+ High offen -> alle drei Stufen
        // im Bulk:  a%3==0 -> 0 High  (Keine)
        //           a%3==1 -> 1 High  (Beobachten)
        //           a%3==2 -> 2 High  (Kritisch)
        for (Integer a = 0; a < accountsN; a++) {
            Id accId = accIds[a];
            Integer highFor = highCasesForAccount(a);
            for (Integer j = 0; j < casesPerAccount; j++) {
                batch.add(new Case(Ursache__c = 'HowToAnfrage', AccountId = accId, Priority = (j < highFor) ? 'High' : 'Low', Status = 'New'));
            }
        }
        insert batch;
        Integer usedInBatch = Limits.getQueries() - baseQueries;
        // Ein Batch mit 250 Records auf 10 Accounts darf deutlich mehr als
        // ~10 Queries nicht erzeugen (Handler: eine SOQL fuer alle offenen Cases
        // mit IN(:accountIds); je-eine-Query-je-Case wuerde >250).
        //
        // [SCRUM-438] Schwellwert <10 -> <15 (gemessen 2026-10-05, DevOps-Run
        // 37279408056): alle Case-Triggers feuern bei insert; 438's
        // CaseSLATrigger ruft SLAService.bhId() EINMAL pro Execution (= +1
        // SOQL, by Design ADR-3; initSLA/evaluate SOQL-frei). Summe = 13
        // (vor 438: 12). <15 laesst 13 durch und faengt einen echten
        // per-Record-N+1 (~250 Queries) weiterhin hart.
        assertTrue(usedInBatch < 15, 'Batch-Queries ueber Budget: ' + usedInBatch);
        // Spot check: alle Accounts korrekt, Werte matchen je Account
        for (Integer a = 0; a < accountsN; a++) {
            Id accId = accIds[a];
            Integer highFor = highCasesForAccount(a);
            String expectedStufe;
            if (highFor >= 2) {
                expectedStufe = CaseEscalationKunde.STUFE_KRITISCH;
            } else if (highFor == 1) {
                expectedStufe = CaseEscalationKunde.STUFE_BEOBACHTEN;
            } else {
                expectedStufe = CaseEscalationKunde.STUFE_KEINE;
            }
            List<Case> check = readCase(accId);
            assertEquals(casesPerAccount, check.size());
            assertEquals(highFor, (Integer) check[0].Offene_High_Cases_Kunde__c);
            assertEquals(casesPerAccount, (Integer) check[0].Offene_Cases_Kunde__c);
            assertEquals(expectedStufe, check[0].Eskalation_Kunde__c);
        }
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
        Case c1 = new Case(Ursache__c = 'HowToAnfrage', AccountId = accId, Priority = 'High', Status = 'New');
        Case c2 = new Case(Ursache__c = 'HowToAnfrage', AccountId = accId, Priority = 'High', Status = 'New');
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
        Case cClosed = new Case(Ursache__c = 'HowToAnfrage', AccountId = accId, Priority = 'Low', Status = 'Closed');
        insert cClosed;
        // c muss weiterhin Z=1 zeigen (closed-case wird nicht mitgezählt)
        Case cR = readCaseById(c.Id);
        assertEquals(1, (Integer) cR.Offene_Cases_Kunde__c);
    }

    private static testmethod void fls_lueckeC_ursache_unter_standard_user() {
        // Luecke C (scripts/fls-gate.py): Nicht-Admin-DML auf dem neuen Feld
        // Case.Ursache__c unter System.runAs(PS-User).
        //
        // ACHTUNG — Case OHNE AccountId: der in der ORG (nicht im Repo)
        // installierte CasePriorityTrigger wirft bei JEDEM AccountId-CasInsert
        // unter runAs(Standard User) "Variable does not exist: tmpVar1"
        // (buildBatchData:112, "WHERE Id IN :accountIds AND VIP_Customer__c =
        // true" — Bind scheitert an FLS; fls-check.sh 2026-10-05: Feld wird nur
        // ueber SCRUM333_VIP_Customer gewaehrt). 437-Header (gruen in CI):
        // "Case-Inserts OHNE AccountId laufen unter Standard User fehlerfrei
        // (Probe)". PSA -> Case-Insert (ohne Account) ist die in CI seit
        // Wochen gruene Reihenfolge (SCRUM-390/418/419/437).
        User u420 = SCRUM434TestFixtures.ursacheUser('420-LueckeC');
        Case c = new Case(Ursache__c = 'HowToAnfrage', Status = 'New');
        System.runAs(u420) { insert c; }
        // Read-back im System-Kontext: Wert liegt exakt, wie der Non-Admin ihn
        // geschrieben hat (das gewaehrende PS hat Read+Edit auf Ursache__c).
        Case fresh = [SELECT Id, Ursache__c FROM Case WHERE Id = :c.Id LIMIT 1];
        assertEquals('HowToAnfrage', fresh.Ursache__c,
            'PS-User darf Ursache__c schreiben (Read-back identisch)');
    }

    // ---------- helpers ----------

    /**
     * [Round-2] System-Kontext-Insert: kein PSA/Setup-DML in der Methode,
     * dadurch ist MIXED_DML strukturell ausgeschlossen (s. Klassenkopf).
     * AccountId-Trigger-Durchlauf laeuft mit Admin-FLS.
     */
    private static Case insertCase(Id accId, String priority, String status) {
        Case c = new Case(Ursache__c = 'HowToAnfrage', AccountId = accId, Priority = priority, Status = status);
        insert c;
        return c;
    }

    /**
     * Design TC7: gemischt je Account 0/1/2+ High offen -> drei Stufen im Bulk.
     * a%3==0 -> 0 (Keine), a%3==1 -> 1 (Beobachten), a%3==2 -> 2 (Kritisch).
     * Eigenes Helper, damit die Ternary-Parsing-Heiligkeit nicht zweimal im Loop dupliziert wird.
     */
    private static Integer highCasesForAccount(Integer a) {
        if (Math.mod(a, 3) == 0) {
            return 0;
        }
        if (Math.mod(a, 3) == 1) {
            return 1;
        }
        return 2;
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
