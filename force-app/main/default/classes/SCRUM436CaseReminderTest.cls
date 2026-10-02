/**
 * [SCRUM-436] Apex-Test — automatische Wiedervorlage (Werktags-Logik +
 * Trigger + Batch + Service).
 *
 * Haus-Pattern (gemessen, keine geratenen Feld-/API-Namen):
 *   - Case unter System.runAs(kunde)          -> Case.CreatedById = kunde
 *   - Kommentar unter System.runAs(mitarb)    -> cc.CreatedById = mitarb
 *     -> ADR-3-Staff-Guard (cc.CreatedById != c.CreatedById) deterministisch.
 *   - Last_Relevant_Update__c wird im Test DIREKT backdated (System-Modus
 *     uebt FLS ueber den laufenden Test-User aus — admin, volle FLS), weil
 *     der before-Insert-Trigger es nur setzt, wenn null.
 *
 * AC-Coverage:
 *   workingDaysBetween  ADR-2 (Mo-Fr, kein Feiertag, kein BusinessHours)
 *   AC1  Uhr startet bei Eroeffnung
 *   AC4  relevante Bearbeitung ohne Wiedervorlage (ungeflaggt)
 *   AC5  (teil) Batch filtert Closed + monitored-Status
 *   AC6  (teil) Config.isMonitoredStatus-Mechanik (echter Wert = PO-Offen #1)
 *   AC8  relevante Bearbeitung setzt Flag + zaehlt hoch, Due-Date bleibt
 *   AC9  Batch ueber Bestand, idempotent (zweiter Lauf toucht 0), bulk-safe
 *   FLS  => SCRUM436CaseReminderFlsTest (separate Klasse, USER_MODE)
 *
 * @author developer-agent
 * @date 2026-10-02
 */
@isTest
private class SCRUM436CaseReminderTest {

    private static User makeUser(String alias, String ln) {
        Profile standard = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        return new User(
            ProfileId         = standard.Id,
            LastName          = ln,
            Alias             = alias,               // max 8 Zeichen
            Email             = alias + sfx + '@x.invalid',
            Username          = alias + sfx + '@x.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'Europe/Berlin'
        );
    }
    private static User svc()  { User u = makeUser('svc436',  'Service436');  insert u; return u; }
    private static User cust() { User u = makeUser('cust436', 'Customer436'); insert u; return u; }

    private static DateTime at(Integer y, Integer mo, Integer d, Integer h) {
        // DateTime.newInstance: org-verifiziert (sf apex run, 2026-10-02).
        return DateTime.newInstance(y, mo, d, (h == null ? 0 : h), 0, 0);
    }

    /** Case owned by `owner`, Last_Relevant_Update__c backdated auf `lastUpdate`. */
    private static Case plantCase(User owner, String status, String priority, DateTime lastUpdate) {
        Case c = new Case(Subject='SCR436', Origin='Phone',
            Status=status, Priority=priority, Last_Relevant_Update__c=lastUpdate);
        if (status != null && status.equalsIgnoreCase('Closed')) {
            // Org-Validierung auf Case (CUSTOM-Feld!): ein geschlossener Case
            // braucht zwingend eine Ursache (Feld Ursache__c, org-verifiziert
            // via sf sobject describe; NICHT Standard-Reason).
            // FLS: Ursache__c wird NUR vom Permission Set SCRUM434_Ursache
            // gewaehrt (1 Zeile in FieldPermissions, IsOwnedByProfile=false) —
            // das Standard-User-Profil hat KEINE Profil-FLS, also kann der
            // runAs-Standard-User das Feld nicht schreiben und die Validierung
            // feuert weiter. Der Closed-Case dient in AC5 nur als NEGATIVER
            // Batch-Filter-Kontrollfall — sein Owner/FLS ist fuer die
            // Assertion (Reminder_Required__c bleibt false) irrelevant.
            // Daher im SYSTEM-Modus pflanzen (volle FLS, Validierung erfüllt),
            // statt das Fremd-PS SCRUM434_Ursache an den Test-User zu hängen.
            c.Ursache__c = 'TechnischerFehler';
            insert c;               // SYSTEM-Modus
        } else {
            System.runAs(owner) { insert c; }
        }
        return c;
    }

    private static Case refresh(Id id) {
        return [SELECT Id, Status, Priority,
                 Last_Relevant_Update__c, Reminder_Required__c,
                 Reminder_Due_Date__c, Reminder_Count__c
                FROM Case WHERE Id = :id LIMIT 1][0];
    }

    private static void staffComment(Id caseId, User svcU, String body) {
        CaseComment cc = new CaseComment(ParentId = caseId, CommentBody = body);
        System.runAs(svcU) { insert cc; }
    }

    /* ================================================================
     * ADR-2 — workingDaysBetween ist reine Werktag-Arithmetik (Mo-Fr).
     * ================================================================ */
    @isTest
    static void adr2_workingDays_pureArithmetic() {
        // Mo 05.01 -> Fr 09.01  =  (Mo, Fr] = Di,Mi,Do,Fr = 4 Werktage.
        System.assertEquals(4, CaseReminderService.workingDaysBetween(
                at(2026,1,5,9), at(2026,1,9,1)),
            'Mo->Fr ueber Di/Mi/Do/Fr = 4 Werktage');
        // Fr 09.01 -> Mo 12.01  =  (Fr, Mo] = Sa,So,Mo -> nur Mo = 1 Werktag.
        System.assertEquals(1, CaseReminderService.workingDaysBetween(
                at(2026,1,9,18), at(2026,1,12,1)),
            'Fr->Mo ueber das Wochenende = 1 Werktag (Mo)');
        // Do 08.01 -> Mo 12.01  =  (Do, Mo] = Fr,Sa,So,Mo -> Fr+Mo = 2 Werktage.
        System.assertEquals(2, CaseReminderService.workingDaysBetween(
                at(2026,1,8,9), at(2026,1,12,1)),
            'Do->Mo = 2 Werktage (Fr, Mo)');
        // null / invertiert -> 0.
        System.assertEquals(0, CaseReminderService.workingDaysBetween(null, at(2026,1,9,1)),
            'from=null -> 0');
        System.assertEquals(0, CaseReminderService.workingDaysBetween(
                at(2026,1,9,1), at(2026,1,5,9)),
            'to <= from -> 0');
    }

    /* ================================================================
     * AC1 — Uhr startet bei Eroeffnung (before insert).
     * ================================================================ */
    @isTest
    static void ac1_open_case_starts_clock() {
        User cu = cust();
        // AC1: Uhr startet bei Eroeffnung — der before-insert Trigger setzt
        // Last_Relevant_Update__c = System.now() (nur wenn null), schreibt
        // DIREKT auf Trigger.new (before-Kontext = veränderlich, 0 DML).
        // (Der "0 SOQL"-Nachweis laesst sich NICHT isoliert testen: jeder
        // Case-Insert feuert die ~6 anderen Case-Trigger der Org, die je
        // eigene SOQL fahren — eine absolute getQueries()-Gleichheit waere
        // also durch fremde Kontexte verunreinigt. Der governor-Nachweis
        // fuer die Bulk-Pfade steht in ac9_bulk_*.)
        Test.startTest();
        Case c = plantCase(cu, 'New', 'Medium', null);  // null -> Trigger setzt now
        Test.stopTest();
        Case r = refresh(c.Id);
        System.assertNotEquals(null, r.Last_Relevant_Update__c,
            'AC1: Last_Relevant_Update bei Eroeffnung gesetzt');
        System.assertEquals(false, r.Reminder_Required__c, 'AC1: Flag initial false');
        System.assertEquals(0, r.Reminder_Count__c.intValue(), 'AC1: Zähler initial 0');
    }

    /* ================================================================
     * AC8 — Mitarbeiter-Kommentar = relevante Bearbeitung:
     *   - ungeflaggt: nur Uhr läuft, Flag false, Zähler bleibt (AC4)
     *   - geflaggt : Flag auf false, Zähler +1, Due-Date bleibt (PO)
     * ================================================================ */
    @isTest
    static void ac8_staff_comment_resets_and_counts() {
        User svcU = svc(), cu = cust();
        Case c = plantCase(cu, 'Working', 'Medium', at(2026,9,1,10));

        // (a) ungeflaggt: Zähler/Flag unverändert, nur Uhr.
        staffComment(c.Id, svcU, 'erstes, ungeflaggt');
        Case unflag = refresh(c.Id);
        System.assertEquals(false, unflag.Reminder_Required__c, 'AC8a: ungeflaggt bleibt ungeflaggt');
        System.assertEquals(0, unflag.Reminder_Count__c.intValue(), 'AC8a: Zähler bleibt 0');

        // (b) direkt geflaggt (System-Modus, volle FLS), dann Mitarbeiter-Kommentar.
        Case flag = new Case(Id = c.Id, Reminder_Required__c = true,
                Reminder_Count__c = 5, Reminder_Due_Date__c = at(2026,9,1,12));
        update flag;

        staffComment(c.Id, svcU, 'zweites, arbeitet ab');
        Case after = refresh(c.Id);
        System.assertEquals(false, after.Reminder_Required__c, 'AC8b: Flag nach Bearbeitung false');
        System.assertEquals(6, after.Reminder_Count__c.intValue(), 'AC8b: Zähler 5 -> 6');
        System.assertEquals(at(2026,9,1,12), after.Reminder_Due_Date__c,
            'AC8b: Reminder_Due_Date bleibt (PO-Offen #5 Default: beibehalten)');
    }

    /* ================================================================
     * AC4 / Staff-Guard — Kunden-Kommentar (Creator == Case-Ersteller)
     *   zaehlt NICHT: Flag/Zähler bleiben, nur Mitarbeiter zahlt zurück.
     * ================================================================ */
    @isTest
    static void customer_comment_not_counted_staff_guard() {
        User svcU = svc(), cu = cust();
        Case c = plantCase(cu, 'Working', 'Medium', at(2026,9,1,10));
        // direkt geflaggt, Zähler 7:
        update new Case(Id = c.Id, Reminder_Required__c = true, Reminder_Count__c = 7);

        // Kunden-Kommentar (Creator == Case-Ersteller) -> NICHT gezählt.
        CaseComment kcomm = new CaseComment(ParentId = c.Id, CommentBody = 'Kunde');
        System.runAs(cu) { insert kcomm; }
        Case afterCust = refresh(c.Id);
        System.assertEquals(true, afterCust.Reminder_Required__c,
            'Kunden-KC: Flag bleibt true (zählt nicht)');
        System.assertEquals(7, afterCust.Reminder_Count__c.intValue(),
            'Kunden-KC: Zähler bleibt 7 (zählt nicht)');

        // Mitarbeiter-Kommentar -> zählt.
        staffComment(c.Id, svcU, 'Mitarbeiter antwortet');
        Case afterSvc = refresh(c.Id);
        System.assertEquals(false, afterSvc.Reminder_Required__c, 'Mitarbeiter-KC: Flag false');
        System.assertEquals(8, afterSvc.Reminder_Count__c.intValue(), 'Mitarbeiter-KC: Zähler 7 -> 8');
    }

    /* ================================================================
     * AC8 (Trigger-Pfad) — Statuswechsel = relevante Bearbeitung:
     *   Uhr zurück + (wenn geflaggt) Flag false + Zähler +1.
     * ================================================================ */
    @isTest
    static void ac8_status_change_resets_and_counts() {
        User svcU = svc(), cu = cust();
        Case c = plantCase(cu, 'New', 'Medium', at(2026,9,1,10));
        update new Case(Id = c.Id, Reminder_Required__c = true,
                Reminder_Count__c = 2, Reminder_Due_Date__c = at(2026,9,1,11));

        DateTime beforeStatus = refresh(c.Id).Last_Relevant_Update__c;
        Case updStatus = new Case(Id = c.Id, Status = 'Working');
        update updStatus;

        Case after = refresh(c.Id);
        System.assertNotEquals(beforeStatus, after.Last_Relevant_Update__c,
            'AC8: Statuswechsel setzt Last_Relevant_Update neu');
        System.assertEquals(false, after.Reminder_Required__c, 'AC8: Flag nach Statuswechsel false');
        System.assertEquals(3, after.Reminder_Count__c.intValue(), 'AC8: Zähler 2 -> 3');

        // Nicht-relevante Änderung (nur ein neutrales Feld) ändert nichts.
        DateTime t0 = refresh(c.Id).Last_Relevant_Update__c;
        Case updPriority = new Case(Id = c.Id, Priority = 'Low');
        update updPriority;   // keine Status-Änderung -> Uhr bleibt
        System.assertEquals(t0, refresh(c.Id).Last_Relevant_Update__c,
            'Nicht-relevante Änderung (Priority) rührt die Uhr nicht an');
    }

    /* ================================================================
     * AC5 — Batch: nur offene, MONITORED, ungeflaggte Cases; Closed nie.
     * ================================================================ */
    @isTest
    static void ac5_batch_filters_closed_and_monitored() {
        User cu = cust();
        // Mo 05.01 -> asOf Mo 12.01 = 5 Werktage > 3 -> wäre fällig.
        Case high5  = plantCase(cu, 'Working', 'High',   at(2026,1,5,9));   // 5 WD, High (Schwelle 1)
        Case std5   = plantCase(cu, 'Working', 'Medium', at(2026,1,5,9));   // 5 WD, Standard (Schwelle 3)
        Case std1   = plantCase(cu, 'Working', 'Medium', at(2026,1,9,18));  // 1 WD -> NICHT fällig
        Case closed = plantCase(cu, 'Closed',  'High',   at(2026,1,5,9));   // Closed -> nie

        Test.startTest();
        CaseReminderBatch b = new CaseReminderBatch(at(2026,1,12,1), 200);
        Database.executeBatch(b);
        Test.stopTest();

        System.assertEquals(true,  refresh(high5.Id).Reminder_Required__c,  'AC5: High/5WD geflaggt');
        System.assertEquals(true,  refresh(std5.Id ).Reminder_Required__c,  'AC5: Standard/5WD geflaggt');
        System.assertEquals(false, refresh(std1.Id ).Reminder_Required__c,  'AC5: 1WD nicht geflaggt');
        System.assertEquals(false, refresh(closed.Id).Reminder_Required__c, 'AC5: Closed nie geflaggt');
        // (Das "exakt 2" steht in den vier DB-Assertions oben — zwei true,
        //  zwei false. Der Batch-Counter getFlagged() ist NICHT pruefbar:
        //  Database.executeBatch() laeuft auf einer deserialisierten Kopie,
        //  der Stateful-Counter auf dem lokalen Objekt `b` bleibt 0.)
        // Due-Date = asOf gesetzt.
        System.assertEquals(at(2026,1,12,1), refresh(high5.Id).Reminder_Due_Date__c,
            'AC5: Reminder_Due_Date = Batch-now (asOf)');
    }

    /* ================================================================
     * AC9 — Batch idempotent: zweiter Lauf toucht 0 Rows.
     * ================================================================ */
    @isTest
    static void ac9_batch_idempotent_secondRunZero() {
        User cu = cust();
        Case c1 = plantCase(cu, 'Working',   'High',   at(2026,1,5,9));
        Case c2 = plantCase(cu, 'Escalated', 'Medium', at(2026,1,5,9));

        // Erstlauf: beide fällig -> geflaggt.
        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(at(2026,1,12,1), 200));
        Test.stopTest();
        System.assertEquals(true, refresh(c1.Id).Reminder_Required__c, 'AC9/1: c1 nach Erstlauf geflaggt');
        System.assertEquals(true, refresh(c2.Id).Reminder_Required__c, 'AC9/1: c2 nach Erstlauf geflaggt');

        // Ist-Zustand vor dem Zweitlauf festhalten.
        DateTime lru1  = refresh(c1.Id).Last_Relevant_Update__c;
        DateTime due1  = refresh(c1.Id).Reminder_Due_Date__c;
        Decimal count1 = refresh(c1.Id).Reminder_Count__c;

        // Zweitlauf (gleicher asOf): die execute()-Zeile `if (c.Reminder_Required
        // == true) continue;` ist der strukturelle 0-Rows-Guard — beides ist
        // bereits true, also wird toFlag leer -> KEIN update-DML. Observable
        // Konsequenz: der Org-Stand bleibt bitstabil. (Der Stateful-Counter
        // getFlagged() ist NICHT pruefbar: executeBatch laeuft auf einer
        // deserialisierten Kopie, der lokale Counter bleibt 0.)
        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(at(2026,1,12,1), 200));
        Test.stopTest();

        Case again = refresh(c1.Id);
        System.assertEquals(true,    again.Reminder_Required__c, 'AC9/2: c1 bleibt geflaggt (idempotent)');
        System.assertEquals(lru1,    again.Last_Relevant_Update__c, 'AC9/2: LRU unveraendert');
        System.assertEquals(due1,    again.Reminder_Due_Date__c,   'AC9/2: Due-Date unveraendert');
        System.assertEquals(count1,  again.Reminder_Count__c,      'AC9/2: Zähler unveraendert (Zweitlauf toucht nichts)');
    }

    /* ================================================================
     * AC9 — Bulk: 200 Mitarbeiter-Kommentare auf 20 Cases, Governor intakt.
     * ================================================================ */
    @isTest
    static void ac9_bulk_staff_comments_governorSafe() {
        User svcU = svc(), cu = cust();
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 20; i++) {
            Case c = new Case(Subject='SCR436 bulk', Origin='Phone',
                Status='Working', Priority='Medium', Last_Relevant_Update__c=at(2026,9,1,10));
            System.runAs(cu) { insert c; }
            cases.add(c);
        }
        List<CaseComment> all = new List<CaseComment>();
        for (Case c : cases) {
            for (Integer k = 0; k < 10; k++) {
                all.add(new CaseComment(ParentId = c.Id, CommentBody = 'bulk ' + k));
            }
        }
        Integer soqlBefore = Limits.getQueries();
        System.runAs(svcU) { insert all; }
        Integer soqlUsed = Limits.getQueries() - soqlBefore;

        // 20 Cases -> je genau 1 Parent-Update (dedup), also 20 + 200 Comments.
        // ACHTUNG: die 20 Parent-Updates feuern auch die ANDEREN Case-Trigger
        // der Org (CaseReaction, CaseOpenCount, ...); deren SOQL mischt sich
        // in diese Messung. Eigener Service: 1 SOQL pro Trigger-Exec
        // (Trigger.new = alle 200 in 1 Batch) -> ohne N+1. Groesszuehiger
        // Rahmen gegen fremde Org-Trigger, streng genug gegen eine echte
        // Per-Row-Query (>= 200). Limits.getQueries(): house-Idiom.
        Integer counted = 0;
        for (Case c : cases) {
            if (refresh(c.Id).Last_Relevant_Update__c != null) counted++;
        }
        System.assertEquals(20, counted, 'AC9: alle 20 Cases haben Last_Relevant_Update gesetzt');
        System.assert(soqlUsed <= 25, 'AC9: Service-SOQL bulk-safe (kein Per-Row-N+1), war ' + soqlUsed);
    }

    /* ================================================================
     * AC6 (Mechanik) — Config.isMonitoredStatus treibt die Suspend-Logik.
     *   Echter Suspend-Wert („Warten auf Kunde") = PO-Offen #1, fehlt in
     *   der Org. Hier wird die 1-Zeilen-Gate-Funktion unit-getestet:
     *   alles Monitored = true, alles andere = false.
     * ================================================================ */
    @isTest
    static void ac6_config_monitoredGate() {
        System.assertEquals(true,  CaseReminderConfig.isMonitoredStatus('New'),       'New monitored');
        System.assertEquals(true,  CaseReminderConfig.isMonitoredStatus('Working'),   'Working monitored');
        System.assertEquals(true,  CaseReminderConfig.isMonitoredStatus('Escalated'), 'Escalated monitored');
        System.assertEquals(false, CaseReminderConfig.isMonitoredStatus('Closed'),    'Closed nie monitored');
        System.assertEquals(false, CaseReminderConfig.isMonitoredStatus('Warten auf Kunde'),
            'Suspend-Platzhalter (PO-Offen #1) = NICHT monitored');
        System.assertEquals(false, CaseReminderConfig.isMonitoredStatus(null), 'null = nie monitored');
        // Schwellen konstant.
        System.assertEquals(3, CaseReminderConfig.DEFAULT_THRESHOLD_WORKING_DAYS, 'Default 3 Werktage');
        System.assertEquals(1, CaseReminderConfig.HIGH_THRESHOLD_WORKING_DAYS,    'High 1 Werktag');
    }
}
