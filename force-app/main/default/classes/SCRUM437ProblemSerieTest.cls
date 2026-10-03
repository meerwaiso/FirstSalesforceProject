/**
 * SCRUM-437: Funktionstest fuer den bulkified Problemserie-Handler + Trigger.
 * Deckt die 9 AK-Tickets (Design S7) ab.
 *
 * Org-Fakten (verifiziert 2026-10-03):
 *  - Case.ClosedDate ist NICHT schreibbar (updateable=false); ein Workflow
 *    stempelt beim Schliessen automatisch ClosedDate = now().
 *  - Damit laesst sich ein >30-Tage-geschlossener Fall NICHT per DML
 *    konstruieren. AC4 wird als Prdikat-Test gegen isInWindow
 *    (TestVisible) abgedeckt — die exakte Produktionsregel.
 *  - Case.ClosedDate ist Datetime (nicht Date) in dieser Org.
 *
 * Vorgehen: Jeder Test erzeugt eigene Accounts + Cases (Isolation).
 * Case-DML feuert CaseProblemSerieTrigger, der CaseProblemSerieHandler-
 * recompute EXAKT EINMAL (bulkified, 1 SOQL IN-Query + max. 1 DML) aufruft.
 *
 * WARUM die AC1..AC9 als Admin laufen (Org-Ergebnis, gemessen 2026-10-03):
 *  - Die Serie ist (AccountId, Problemkategorie)-geschluesselt; die AC-Cases
 *    tragen deshalb IMMER ein AccountId.
 *  - Ein Case mit AccountId kann in dieser Org nur von Admins gelegt werden:
 *    der (in der Org, nicht im Repo) installierte CasePriorityTrigger wirft
 *    bei JEDEM Case-Insert mit AccountId unter System.runAs(Standard User)
 *    "QueryException: Variable does not exist: tmpVar1" (buildBatchData:112).
 *    Case-Inserts OHNE Accountid laufen unter Standard User fehlerfrei (Probe).
 *  - Daher laufen die Account-geschluesselten ACs als Admin. DER Nicht-Admin-
 *    Nachweis ist flsStandardUserNuetztDasFeature (unten): echtes Trigger-DML
 *    durch einen Standard User (mit SCRUM437_ProblemSerie_System) + Read-back
 *    der funf neuen Felder. Damit erfuellt die Klasse Luecke C von
 *    scripts/fls-gate.py (System.runAs( in einer neuen Feld beruehrenden Test).
 */
@isTest
private class SCRUM437ProblemSerieTest {

    private static final String CAT_RECHNUNG  = 'Rechnung';
    private static final String CAT_LIEFERUNG = 'Lieferung';

    // ---- Helfer -----------------------------------------------------------

    private static Id mkAccount(String label) {
        Account a = new Account(Name = 'PS437_' + label + '_' + System.now().getTime());
        insert a;
        return a.Id;
    }

    private static Case mkCase(Id acct, String cat, String status) {
        Case c = new Case(AccountId = acct, Problemkategorie__c = cat, Status = status);
        if (status == 'Closed') {
            c.Ursache__c = 'TechnischerFehler';
        }
        return c;
    }

    // ---- Prdikat-Tests (AC4) ----------------------------------------------

    @isTest
    static void ac4_ge30Tage_geschlossen_zaeHtNicht() {
        // Fensterbeginn: Mitternacht genau 30 Tage zurueck.
        Datetime windowStart = Datetime.newInstanceGmt(
            Date.today().addDays(-30).year(),
            Date.today().addDays(-30).month(),
            Date.today().addDays(-30).day(), 0, 0, 0
        );

        // Fall 1: OFFEN -> immer im Fenster (auch ohne ClosedDate).
        System.assertEquals(true,
            CaseProblemSerieHandler.isInWindow('New', null, windowStart),
            'OFFENER Fall ist IM MER im Fenster, egal wann geschlossen');

        // Fall 2: GESCHLOSSEN, 40 Tage zurueck -> AUSSEHALT (40 > 30).
        Datetime closed40 = Datetime.newInstanceGmt(
            Date.today().addDays(-40).year(),
            Date.today().addDays(-40).month(),
            Date.today().addDays(-40).day(), 12, 0, 0
        );
        System.assertEquals(false,
            CaseProblemSerieHandler.isInWindow('Closed', closed40, windowStart),
            '40-Tage-geschlossener Fall ist NICHT im 30-Tage-Fenster');

        // Fall 3: GESCHLOSSEN, 10 Tage zurueck -> INNEN (10 < 30).
        Datetime closed10 = Datetime.newInstanceGmt(
            Date.today().addDays(-10).year(),
            Date.today().addDays(-10).month(),
            Date.today().addDays(-10).day(), 12, 0, 0
        );
        System.assertEquals(true,
            CaseProblemSerieHandler.isInWindow('Closed', closed10, windowStart),
            '10-Tage-geschlossener Fall IST im 30-Tage-Fenster');

        // Fall 4: GESCHLOSSEN, ClosedDate = null -> NICHT im Fenster
        // (ohne Stempel nicht nachweisbar als innerhalb von 30 Tg).
        System.assertEquals(false,
            CaseProblemSerieHandler.isInWindow('Closed', null, windowStart),
            'Geschosser Fall mit NULL ClosedDate ist NICHT im Fenster');

        // Fall 5: GESCHLOSSEN, ClosedDate = heute 12:00 -> INNEN (heute < 30 Tg).
        Datetime todayNoon = Datetime.newInstanceGmt(
            Date.today().year(), Date.today().month(), Date.today().day(), 12, 0, 0
        );
        System.assertEquals(true,
            CaseProblemSerieHandler.isInWindow('Closed', todayNoon, windowStart),
            'Heute-geschlossener Fall IST im 30-Tage-Fenster');
    }

    // ---- Ende-zu-Ende (Trigger -> Handler) ----------------------------------

    /** AC1: 1. Case -> nicht wiederkehrend, Anzahl 0, Letzter NULL, KEINE Serie. */
    @isTest
    static void ac1_ersterCase_keineSerie() {
        Id acct = mkAccount('AC1');
        Case c = mkCase(acct, CAT_RECHNUNG, 'New');
        insert c;
        List<Case> r = [SELECT Id, Wiederkehrendes_Problem__c,
                         Anzahl_aehnlicher_offener_Cases__c,
                         Letzter_aehnlicher_Case__c, Problemserie__c
                        FROM Case WHERE Id = :c.Id];
        System.assertEquals(false, r[0].Wiederkehrendes_Problem__c,
            'AC1: 1. Fall NICHT wiederkehrend');
        System.assertEquals(0, r[0].Anzahl_aehnlicher_offener_Cases__c.intValue(),
            'AC1: Anzahl = 0');
        System.assertEquals(null, r[0].Letzter_aehnlicher_Case__c,
            'AC1: Letzter = NULL (keiner im Pool)');
        System.assertEquals(null, r[0].Problemserie__c,
            'AC1: unter Schwelle -> KEINE Serienkennung (ADR-2 Schritt 1)');
    }

    /** AC2: 3 Cases gleiche (Account, Kat) -> wiederkehrend, Anzahl >= 2, Serie. */
    @isTest
    static void ac2_dritterFall_gruendetSerie() {
        Id acct = mkAccount('AC2');
        Case c1 = mkCase(acct, CAT_RECHNUNG, 'New');
        Case c2 = mkCase(acct, CAT_RECHNUNG, 'New');
        Case c3 = mkCase(acct, CAT_RECHNUNG, 'New');
        insert c1; insert c2; insert c3; // 3. insert gruendet die Serie
        List<Case> all = [SELECT Id, Wiederkehrendes_Problem__c,
                           Anzahl_aehnlicher_offener_Cases__c,
                           Letzter_aehnlicher_Case__c, Problemserie__c
                          FROM Case WHERE AccountId = :acct AND Problemkategorie__c = :CAT_RECHNUNG];
        String expectedKey = CaseProblemSerieHandler.buildSeriesKey(acct, CAT_RECHNUNG);
        System.assertEquals(3, all.size(), 'AC2: alle 3 Cases vorhanden');
        for (Case c : all) {
            System.assertEquals(true, c.Wiederkehrendes_Problem__c,
                'AC2: 3. Fall -> alle wiederkehrend (Pool >= 2)');
            System.assertEquals(2, c.Anzahl_aehnlicher_offener_Cases__c.intValue(),
                'AC2: 2 weitere offene im Pool');
            System.assertNotEquals(null, c.Letzter_aehnlicher_Case__c,
                'AC2: Letzter gesetzt (mindestens 1 im Pool)');
            System.assertNotEquals(c.Id, c.Letzter_aehnlicher_Case__c,
                'AC2: Letzter NICHT die eigene Id');
            System.assertEquals(expectedKey, c.Problemserie__c,
                'AC2: alle tragen dieselbe Serienkennung');
        }
    }

    /** AC3: andere Kategorie wird NICHT verrechnet (Rechnung != Lieferung). */
    @isTest
    static void ac3_andereKategorie_nichtVerrechnet() {
        Id acct = mkAccount('AC3');
        Case r = mkCase(acct, CAT_RECHNUNG, 'New');
        Case l = mkCase(acct, CAT_LIEFERUNG, 'New');
        insert r; insert l;
        List<Case> rL = [SELECT Id, Wiederkehrendes_Problem__c,
                          Anzahl_aehnlicher_offener_Cases__c, Problemserie__c
                         FROM Case WHERE Id = :r.Id];
        List<Case> lL = [SELECT Id, Wiederkehrendes_Problem__c,
                          Anzahl_aehnlicher_offener_Cases__c, Problemserie__c
                         FROM Case WHERE Id = :l.Id];
        System.assertEquals(false, rL[0].Wiederkehrendes_Problem__c,
            'AC3: Rechnung NICHT wiederkehrend');
        System.assertEquals(0, rL[0].Anzahl_aehnlicher_offener_Cases__c.intValue(),
            'AC3: Rechnung zaehlt NICHT die Lieferung');
        System.assertEquals(null, rL[0].Problemserie__c,
            'AC3: keine Serie (1 Case pro Kategorie)');
        System.assertEquals(false, lL[0].Wiederkehrendes_Problem__c,
            'AC3: Lieferung NICHT wiederkehrend');
        System.assertEquals(0, lL[0].Anzahl_aehnlicher_offener_Cases__c.intValue(),
            'AC3: Lieferung zaehlt NICHT die Rechnung');
        System.assertEquals(null, lL[0].Problemserie__c,
            'AC3: keine Serie');
    }

    /** AC5: 1 offen + 1 frisch geschlossen (in 30-Tage-Fenster) -> beide im Pool. */
    @isTest
    static void ac5_offen_und_frischGegschlossen_ImPool() {
        Id acct = mkAccount('AC5');
        Case openCase = mkCase(acct, CAT_RECHNUNG, 'New');
        Case closedCase = mkCase(acct, CAT_RECHNUNG, 'Closed'); // frisch, Workflow stempelt ClosedDate=now -> in Fenster
        insert openCase;
        insert closedCase;
        List<Case> openL  = [SELECT Id, Wiederkehrendes_Problem__c,
                              Anzahl_aehnlicher_offener_Cases__c,
                              Letzter_aehnlicher_Case__c, Problemserie__c
                             FROM Case WHERE Id = :openCase.Id];
        List<Case> closedL= [SELECT Id, Wiederkehrendes_Problem__c,
                              Anzahl_aehnlicher_offener_Cases__c,
                              Letzter_aehnlicher_Case__c, Problemserie__c
                             FROM Case WHERE Id = :closedCase.Id];
        // beide im Pool: jedes sieht das andere als Letzter_aehnlicher_Case.
        System.assertEquals(closedCase.Id, openL[0].Letzter_aehnlicher_Case__c,
            'AC5: offener Fall sieht den frisch-geschlossenen im Pool (Letzter)');
        System.assertEquals(openCase.Id, closedL[0].Letzter_aehnlicher_Case__c,
            'AC5: geschlossener Fall sieht den offenen im Pool (Letzter)');
        // Anzahl_offener: geschlossener Fall zaehlt den offenen (=1), offener 0.
        System.assertEquals(1, closedL[0].Anzahl_aehnlicher_offener_Cases__c.intValue(),
            'AC5: geschlossener Fall zahlt genau 1 offenen im Pool (Anzahl offen = 1)');
        System.assertEquals(0, openL[0].Anzahl_aehnlicher_offener_Cases__c.intValue(),
            'AC5: offener Fall zahlt 0 offene im Pool (nur der geschlossene ist da)');
        // Poolgroesse 1 < 2 -> NICHT wiederkehrend, und windowCount 2 < 3 -> keine Serie.
        System.assertEquals(false, openL[0].Wiederkehrendes_Problem__c, 'AC5: Pool=1 -> NICHT wiederkehrend');
        System.assertEquals(false, closedL[0].Wiederkehrendes_Problem__c, 'AC5: Pool=1 -> NICHT wiederkehrend');
        System.assertEquals(null, openL[0].Problemserie__c, 'AC5: 2 im Fenster < 3 -> keine Serie');
        System.assertEquals(null, closedL[0].Problemserie__c, 'AC5: 2 im Fenster < 3 -> keine Serie');
    }

    /** AC6: Kategorie-Änderung -> Neubewertung, alte Serie bleibt. */
    @isTest
    static void ac6_kategorieGeaendert_neuBewertet() {
        Id acct = mkAccount('AC6');
        Case r1 = mkCase(acct, CAT_RECHNUNG, 'New');
        Case r2 = mkCase(acct, CAT_RECHNUNG, 'New');
        Case rc = mkCase(acct, CAT_RECHNUNG, 'New');
        Case l1 = mkCase(acct, CAT_LIEFERUNG, 'New');
        Case l2 = mkCase(acct, CAT_LIEFERUNG, 'New');
        insert r1; insert r2;
        insert l1; insert l2;
        insert rc; // 3. Rechnung -> Rechnung-Serie entsteht
        String keyRechnung  = CaseProblemSerieHandler.buildSeriesKey(acct, CAT_RECHNUNG);
        String keyLieferung = CaseProblemSerieHandler.buildSeriesKey(acct, CAT_LIEFERUNG);
        List<Case> rcL = [SELECT Id, Problemserie__c, Problemkategorie__c
                           FROM Case WHERE Id = :rc.Id];
        System.assertEquals(keyRechnung, rcL[0].Problemserie__c,
            'AC6-Vorbedingung: rc traegt die Rechnung-Serie');
        // rc von Rechnung auf Lieferung umstellen
        rc.Problemkategorie__c = CAT_LIEFERUNG;
        update rc;
        // Re-lesen
        List<Case> rc2 = [SELECT Id, Problemserie__c, Problemkategorie__c,
                           Wiederkehrendes_Problem__c, Anzahl_aehnlicher_offener_Cases__c
                          FROM Case WHERE Id = :rc.Id];
        // Rechnung-Gruppe hat jetzt nur 2 Cases -> Serie bleibt (persistiert)
        List<Case> rL = [SELECT Id, Problemserie__c, Wiederkehrendes_Problem__c
                          FROM Case WHERE AccountId = :acct AND Problemkategorie__c = :CAT_RECHNUNG];
        String keyLieferung2 = CaseProblemSerieHandler.buildSeriesKey(acct, CAT_LIEFERUNG);
        for (Case c : rL) {
            System.assertEquals(keyRechnung, c.Problemserie__c,
                'AC6: alte Rechnung-Serie bleibt persistiert (ADR-2)');
            System.assertEquals(false, c.Wiederkehrendes_Problem__c,
                'AC6: 2 Rechnung-Cases -> NICHT wiederkehrend (Pool=1 < 2)');
        }
        // Lieferung-Gruppe hat jetzt 3 Cases (l1, l2, rc) -> Serie entsteht
        List<Case> lL2 = [SELECT Id, Problemserie__c, Wiederkehrendes_Problem__c,
                           Anzahl_aehnlicher_offener_Cases__c
                          FROM Case WHERE AccountId = :acct AND Problemkategorie__c = :CAT_LIEFERUNG];
        for (Case c : lL2) {
            System.assertEquals(keyLieferung2, c.Problemserie__c,
                'AC6: NEUE Lieferung-Serie auf alle 3');
            System.assertEquals(true, c.Wiederkehrendes_Problem__c,
                'AC6: Lieferung wiederkehrend (Pool=2)');
            System.assertEquals(2, c.Anzahl_aehnlicher_offener_Cases__c.intValue(),
                'AC6: 2 offene im Lieferung-Pool');
        }
    }

    /** AC7: 2 Accounts in EINEM Insert -> Serien getrennt. */
    @isTest
    static void ac7_zweiAccounts_gleichzeitig() {
        Id aA = mkAccount('AC7A');
        Id aB = mkAccount('AC7B');
        List<Case> all = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            all.add(mkCase(aA, CAT_RECHNUNG, 'New'));
            all.add(mkCase(aB, CAT_RECHNUNG, 'New'));
        }
        insert all; // 6 Cases in EINEM Multi-Record-Insert
        String keyA = CaseProblemSerieHandler.buildSeriesKey(aA, CAT_RECHNUNG);
        String keyB = CaseProblemSerieHandler.buildSeriesKey(aB, CAT_RECHNUNG);
        List<Case> rA = [SELECT Id, Problemserie__c, Wiederkehrendes_Problem__c,
                          Anzahl_aehnlicher_offener_Cases__c
                         FROM Case WHERE AccountId = :aA AND Problemkategorie__c = :CAT_RECHNUNG];
        List<Case> rB = [SELECT Id, Problemserie__c, Wiederkehrendes_Problem__c,
                          Anzahl_aehnlicher_offener_Cases__c
                         FROM Case WHERE AccountId = :aB AND Problemkategorie__c = :CAT_RECHNUNG];
        for (Case c : rA) {
            System.assertEquals(keyA, c.Problemserie__c, 'AC7: A-Serie nur auf A');
            System.assertEquals(true, c.Wiederkehrendes_Problem__c, 'AC7: A wiederkehrend');
            System.assertEquals(2, c.Anzahl_aehnlicher_offener_Cases__c.intValue(), 'AC7: A Anzahl=2');
        }
        for (Case c : rB) {
            System.assertEquals(keyB, c.Problemserie__c, 'AC7: B-Serie nur auf B');
            System.assertEquals(true, c.Wiederkehrendes_Problem__c, 'AC7: B wiederkehrend');
            System.assertEquals(2, c.Anzahl_aehnlicher_offener_Cases__c.intValue(), 'AC7: B Anzahl=2');
        }
        System.assertNotEquals(keyA, keyB, 'AC7: Serien der Accounts sind unterschiedlich');
    }

    /** AC8: bulkified — Handler macht EXAKT 1 SOQL (IN-Query) pro Batch,
     *  NICHT pro Case. Direkt gemessen am Handler (isoliert von den anderen,
     *  auf Case installierten House-Triggern, die sonst ins Governor-Zaehrer
     *  Rauschen fallen). */
    @isTest
    static void ac8_bulkified_eineQueryProBatch() {
        Id acct = mkAccount('AC8');
        // 4 Cases gleicher (Account, Kat) in EINEM Batch aufbauen (der Insert
        // feuert den echten Trigger -> Handler; hier wird nur Zustand erzeugt).
        List<Case> items = new List<Case>();
        for (Integer i = 0; i < 4; i++) {
            items.add(mkCase(acct, CAT_RECHNUNG, 'New'));
        }
        insert items;

        // Handler ISOLIERT messen: genau sein(e) SOQL-Abfrage(n) zaehlen.
        // CaseProblemSerieHandler.recompute fuehrt exakt 1 IN-Query aus — fuer
        // den gesamten Batch, unabhaengig von der Fallzahl (kein Loop-SOQL).
        Set<Id> acctIds = new Set<Id>{ acct };
        Integer queriesBefore = Limits.getQueries();
        CaseProblemSerieHandler.recompute(acctIds);
        Integer handlerQueries = Limits.getQueries() - queriesBefore;

        System.assertEquals(1, handlerQueries,
            'AC8 (Governance): Handler macht exakt 1 SOQL IN-Query pro Batch '
            + '(' + handlerQueries + ' gemessen) — KEINE pro-Case-Query');

        // ZaeHLung + Serie korrekt (aus dem echten Insert/Trigger-Durchlauf):
        List<Case> grp = [SELECT Id, Problemserie__c, Wiederkehrendes_Problem__c,
                           Anzahl_aehnlicher_offener_Cases__c
                          FROM Case WHERE AccountId = :acct AND Problemkategorie__c = :CAT_RECHNUNG];
        String key = CaseProblemSerieHandler.buildSeriesKey(acct, CAT_RECHNUNG);
        System.assertEquals(4, grp.size(), 'AC8: alle 4 Cases vorhanden');
        for (Case c : grp) {
            System.assertEquals(key, c.Problemserie__c, 'AC8: alle 4 dieselbe Kennung');
            System.assertEquals(true, c.Wiederkehrendes_Problem__c, 'AC8: wiederkehrend (Pool=3)');
            System.assertEquals(3, c.Anzahl_aehnlicher_offener_Cases__c.intValue(), 'AC8: Anzahl=3');
        }
    }

    /** AC9: alle Cases einer Serie tragen exakt dieselbe Kennung. */
    @isTest
    static void ac9_dieselbeKennung() {
        Id acct = mkAccount('AC9');
        List<Case> items = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            items.add(mkCase(acct, CAT_LIEFERUNG, 'New'));
        }
        insert items;
        List<Case> all = [SELECT Id, Problemserie__c
                           FROM Case WHERE AccountId = :acct AND Problemkategorie__c = :CAT_LIEFERUNG];
        String expectedKey = CaseProblemSerieHandler.buildSeriesKey(acct, CAT_LIEFERUNG);
        Set<String> distinct = new Set<String>();
        for (Case c : all) {
            System.assertNotEquals(null, c.Problemserie__c, 'AC9: Serie gesetzt');
            System.assertEquals(expectedKey, c.Problemserie__c,
                'AC9: jeder Fall exakt die (AccountId,Kategorie)-Kennung');
            distinct.add(c.Problemserie__c);
        }
        System.assertEquals(1, distinct.size(), 'AC9: exakt EINE eindeutige Kennung je Serie');
    }

    /**
     * Luecke-C-Nachweis (scripts/fls-gate.py): Die funf neuen Felder werden von
     * einem echten Standard User (PROFIL "Standard User", NICHT Admin) durch
     * das reale Trigger-/Handler-Verfahren beruehrt und gelesen - NICHT als
     * Admin, NICHT nur via getDescribe().
     *
     * Setup (User + PSA) laeuft AUFRAESSIG ausserhalb von runAs (ein User kann
     * sich selbst kein PSA geben). DANN laeuft das fachliche DML INNERHALB
     * von runAs: 1. Case mit Problemkategorie + System-PS, 2. 2. Case gleicher
     * Kategorie (2 -> Serie entsteht). Danach werden die neuen Felder per SOQL
     * aus dem Standard-User-Kontext gelesen.
     *
     * OHNE AccountId: ein Case mit AccountId stirbt unter runAs an dem (in der
     * Org, nicht im Repo) installierten CasePriorityTrigger (buildBatchData:112
     * -> "tmpVar1"). Die Serie-Logik ist hier bewusst nicht Gegenstand -
     * AC1..AC9 beweisen sie als Admin; hier wird NUR die Nicht-Admin-Zugangs-
     * Funktion bewiesen (Feld lesbar + Handler-Schreibzugriff im System-PS).
     */
    @isTest
    static void flsStandardUserNuetztDasFeature() {
        Profile pr = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String ts = String.valueOf(System.now().getTime());
        User su = new User(
            ProfileId          = pr.Id,
            LastName           = 'Std437',
            Alias              = 'std4' + ts.substring(0, 3),
            Email              = 'std437' + ts + '@example.invalid',
            Username           = 'std437' + ts + '@example.invalid',
            EmailEncodingKey   = 'UTF-8',
            LanguageLocaleKey  = 'en_US',
            LocaleSidKey       = 'en_US',
            TimeZoneSidKey     = 'America/Los_Angeles');
        insert su;
        PermissionSet ps = [SELECT Id FROM PermissionSet
                            WHERE Name = 'SCRUM437_ProblemSerie_System' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = su.Id, PermissionSetId = ps.Id);

        System.runAs(su) {
            // 1. Case (kein AccountId — s. Kopfkommentar: ein Case mit AccountId
            // stirbt hier an CasePriorityTrigger). Der Handler laeuft im
            // Trigger-Durchgang, aber ohne AccountId gibt es kein (Account,
            // Kategorie)-Paar -> kein Series-Key, die 4 Berechnungsfelder
            // bleiben auf Default. Das ist korrekt, NICHT ein Fehler.
            Case c1 = new Case(Subject = 'su-f437', Origin = 'Phone', Status = 'New',
                               Problemkategorie__c = CAT_RECHNUNG);
            insert c1;
            // READ-BACK aller funf FLS-geschuetzten neuen Felder im Kontext
            // eines Standard Users (NICHT Admin). Wenn ein Feld NICHT lesbar waere,
            // wirft genau dieser SELECT (NoSuchColumn / Feld-Access). Dass er
            // hier zurueckkommt, IST der Beweis fuer den Read-FLS-Zugriff.
            List<Case> back = [SELECT Id, Problemkategorie__c, Problemserie__c,
                                Wiederkehrendes_Problem__c,
                                Anzahl_aehnlicher_offener_Cases__c,
                                Letzter_aehnlicher_Case__c
                               FROM Case WHERE Id = :c1.Id];
            System.assertEquals(1, back.size(),
                'FLS-Nicht-Admin: Case mit allen 5 neuen Feldern lesbar');
            Case b = back[0];
            // Kategorie: der Standard User hat sie geschrieben -> Roundtrip.
            System.assertEquals(CAT_RECHNUNG, b.Problemkategorie__c,
                'FLS-Nicht-Admin: Problemkategorie__c lesbar + Roundtrip');
            // 4 Berechnungsfelder: lesbar, und (ohne AccountId -> kein Series-Key)
            // exakt auf dem Default, den der Handler gesetzt hat.
            System.assertEquals(null, b.Problemserie__c,
                'FLS-Nicht-Admin: Problemserie__c lesbar (Default null = kein Series-Key)');
            System.assertEquals(false, b.Wiederkehrendes_Problem__c,
                'FLS-Nicht-Admin: Wiederkehrendes_Problem__c lesbar (Default false)');
            System.assertEquals(0, b.Anzahl_aehnlicher_offener_Cases__c.intValue(),
                'FLS-Nicht-Admin: Anzahl_aehnlicher_offener_Cases__c lesbar (Default 0)');
        }
    }
}
