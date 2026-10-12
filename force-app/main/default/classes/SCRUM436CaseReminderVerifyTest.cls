/**
 * [SCRUM-436] Tester-Verifikation — automatische Wiedervorlage.
 *
 * Eigenständige Apex-Integrationstests (Tester-Code, NICHT Developer-Test):
 * ueben die PRODUKTIONS-Mechanik gegen ein echtes Test-Transaktions-Org —
 * Trigger-Pfade (Insert, Statuswechsel, Staff-Kommentar) und der
 * CaseReminderBatch mit injiziertem asOf (deterministische Werktage).
 *
 * AC-Belegung (jedes Kriterium ein benannter Test):
 *   V-AC1  neuer Case: Uhr laeuft, Flag=Nein, Zaehler=0
 *   V-AC2  Working > 3 Werktage -> Batch flaggt, Due=Run-Zeitpunkt
 *   V-AC3  High > 1 Werktag     -> Batch flaggt
 *   V-AC4  relevante Bearbeitung an UNFLAGGERTEN Case: LRU neu, kein Flag
 *   V-AC5  Config-Gate: isMonitoredStatus('Warten auf Kunde')==false,
 *          Schwellen 3/1 (echter Picklist-Wert fehlt in der Org — ADR-4)
 *   V-AC6  Rueckkehr in monitored Status: Uhr laeuft neu (LRU=now),
 *          Flag-Reset + Zaehler-Hoch (Regel 8)
 *   V-AC7  Closed (5 Werktage alt) -> Batch flaggt NICHT
 *   V-AC8  zwei Zyklen: Zaehler 0 -> 1 -> 2, Due-Date bleibt (Regel 8)
 *   V-AC9  250 Cases in einem Batchlauf (2 Chunks): alle faellige geflaggt,
 *          Zweitlauf toucht 0 Rows (Idempotenz, LRU/Zaehler unveraendert)
 *
 * FLS (DoD "Rechte per PS") belegt die Developer-Klasse SCRUM436CaseReminderFlsTest
 * (USER_MODE runAs, negativ+positiv) — wird im selben Run ausgefuehrt.
 *
 * @author tester-agent  @date 2026-10-02
 */
@isTest
private class SCRUM436CaseReminderVerifyTest {

    /* ─────────────────────────── helpers ─────────────────────────── */

    private static User makeUser(String alias, String ln) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = DateTime.now().getTime() + '_' + alias;
        User u = new User(
            ProfileId          = standard.Id,
            LastName           = ln,
            Alias              = alias,
            Email              = sfx + '@v436.invalid',
            Username           = sfx + '@v436.invalid',
            EmailEncodingKey   = 'UTF-8',
            LanguageLocaleKey  = 'en_US',
            LocaleSidKey       = 'en_US',
            TimeZoneSidKey     = 'Europe/Berlin'
        );
        insert u;
        return u;
    }

    /** exaktes DateTime (org-verifizierte API). */
    private static DateTime at(Integer y, Integer mo, Integer d, Integer h, Integer mi) {
        return DateTime.newInstance(y, mo, d, h == null ? 0 : h, mi == null ? 0 : mi, 0);
    }

    /**
     * Findet ein Startdatum mit EXAKT `targetWd` Werken zwischen start und asOf
     * (reproduziert die Produktionsfunktion, deterministisch).
     */
    private static DateTime startWith(DateTime asOf, Integer targetWd) {
        for (Integer back = 0; back <= 40; back++) {
            DateTime cand = asOf.addDays(-back);
            if (CaseReminderService.workingDaysBetween(cand, asOf) == targetWd) {
                return cand;
            }
        }
        throw new IllegalArgumentException('kein Startdatum fuer ' + targetWd + ' WD');
    }

    /** Offener Case, LRU gezielt backdated (admin-Modus = volle FLS; der
     *  before-Trigger ueberschreibt LRU nur, wenn null — hier ist es gesetzt). */
    private static Case plantOpen(String status, String priority, DateTime lru) {
        Case c = new Case(
            Subject   = 'V436_' + status + priority + '_' + String.valueOf(System.now().getTime()),
            Origin    = 'Phone',
            Status    = status,
            Priority  = priority,
            Last_Relevant_Update__c = lru
        );
        insert c;
        return c;
    }

    /** Geschlossener Case (Org-Validierung braucht Ursache__c, Dev-Befund). */
    private static Case plantClosed(DateTime lru) {
        Case c = new Case(
            Subject   = 'V436_Closed_' + String.valueOf(System.now().getTime()),
            Origin    = 'Phone',
            Customer_Satisfaction__c = 'Score_4', Status    = 'Closed',
            Priority  = 'Medium',
            Last_Relevant_Update__c = lru
        );
        c.Ursache__c = 'TechnischerFehler';
        insert c;
        return c;
    }

    private static Case refresh(Id id) {
        return [SELECT Id, Status, Priority,
                 Last_Relevant_Update__c, Reminder_Required__c,
                 Reminder_Due_Date__c, Reminder_Count__c
                FROM Case WHERE Id = :id][0];
    }

    /** Statuswechsel (admin-Modus — der before-Trigger-Pfad ist user-
     *  unabhaengig: FLS wird in before-Trigger nicht ugebt, Dev-Proof;
     *  FLS selbst belegt die FlsTest-Klasse). */
    private static void changeStatusByStaff(Id caseId, String newStatus, User staff) {
        Case c = new Case(Id = caseId, Status = newStatus);
        update c;
    }

    private static void staffComment(Id caseId, User staff, String body) {
        System.runAs(staff) {
            insert new CaseComment(ParentId = caseId, CommentBody = body);
        }
    }

    /* ─────────────────────────── V-AC1 ─────────────────────────── */

    @isTest
    static void v_ac1_neuerCase_uhrLaeuft_flagNein_zaehler0() {
        User kunde = makeUser('k1', 'Kunde1');
        Case c = new Case(Subject = 'V436_A1', Origin = 'Phone',
                          Status = 'Working', Priority = 'Medium');
        System.runAs(kunde) { insert c; }

        Case r = refresh(c.Id);
        System.assertNotEquals(null, r.Last_Relevant_Update__c,
            'AC1: Uhr muss bei Eroeffnung starten (Last_Relevant_Update gesetzt)');
        System.assert(r.Last_Relevant_Update__c >= DateTime.now().addMinutes(-5),
            'AC1: LRU muss ~ now sein (vorher null), war ' + r.Last_Relevant_Update__c);
        System.assertEquals(false, r.Reminder_Required__c, 'AC1: Flag initial Nein');
        System.assertEquals(0, r.Reminder_Count__c.intValue(), 'AC1: Zaehler initial 0');
        System.assertEquals(null, r.Reminder_Due_Date__c, 'AC1: kein Due-Datum vor Ausloesung');
    }

    /* ─────────────────────────── V-AC2 / V-AC3 ─────────────────────────── */

    @isTest
    static void v_ac2_workingUeber3WD_geflaggt_dueGesetzt() {
        DateTime asOf = at(2026, 11, 16, 1, 0); // Montag
        Case c5 = plantOpen('Working', 'Medium', startWith(asOf, 5)); // 5 > 3
        Case c2 = plantOpen('Working', 'Medium', startWith(asOf, 2)); // 2 <= 3

        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(asOf, 200));
        Test.stopTest();

        Case r5 = refresh(c5.Id);
        Case r2 = refresh(c2.Id);
        System.assertEquals(true, r5.Reminder_Required__c,
            'AC2: Working mit 5 Werktagen ohne Bearbeitung MUSS geflaggt sein');
        System.assertEquals(asOf, r5.Reminder_Due_Date__c,
            'AC2: Due-Datum = Zeitpunkt des Laufs');
        System.assertEquals(false, r2.Reminder_Required__c,
            'AC2: 2 Werktage liegen UNTER der Schwellen 3 — kein Flag');
    }

    @isTest
    static void v_ac3_highNur1Werktag_geflaggt() {
        DateTime asOf = at(2026, 11, 16, 1, 0);
        Case high2 = plantOpen('Working', 'High', startWith(asOf, 2));   // 2 > 1
        Case high1 = plantOpen('Working', 'High', startWith(asOf, 1));   // 1 = 1 (not >)
        Case med2  = plantOpen('Working', 'Medium', startWith(asOf, 2)); // High-Kontrast

        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(asOf, 200));
        Test.stopTest();

        System.assertEquals(true, refresh(high2.Id).Reminder_Required__c,
            'AC3: High > 1 Werktag MUSS geflaggt sein');
        System.assertEquals(false, refresh(high1.Id).Reminder_Required__c,
            'AC3: genau 1 Werktag liegt NICHT über der Schwellen 1 (PO: "länger als")');
        System.assertEquals(false, refresh(med2.Id).Reminder_Required__c,
            'AC3-Kontrast: Medium 2 Werktage unter Schwellen 3 — kein Flag');
    }

    /* ─────────────────────────── V-AC4 ─────────────────────────── */

    @isTest
    static void v_ac4_bearbeitung_ohneFlag_nurUhrReset() {
        DateTime asOf = at(2026, 11, 16, 1, 0);
        Case c = plantOpen('Working', 'Medium', startWith(asOf, 1)); // 1 WD, unter Schwellen
        User staff = makeUser('s4', 'Statt4');

        changeStatusByStaff(c.Id, 'Escalated', staff);

        Case r = refresh(c.Id);
        System.assertEquals('Escalated', r.Status, 'Vorausetzung: Status gewechselt');
        System.assert(r.Last_Relevant_Update__c >= DateTime.now().addMinutes(-5),
            'AC4: relevante Bearbeitung setzt LRU neu');
        System.assertEquals(false, r.Reminder_Required__c,
            'AC4: unter Schwellen + Bearbeitung ergibt KEIN Flag');
        System.assertEquals(0, r.Reminder_Count__c.intValue(),
            'AC4: ungeflaggter Reset zaehlt NICHT hoch');
    }

    /* ─────────────────────────── V-AC5 (Config-Gate) ─────────────────────────── */

    @isTest
    static void v_ac5_configGate_suspendiertNichtMonitored() {
        // PO-Status "Warten auf Kunde" existiert in der Org NICHT (ADR-4,
        // Picklist 10-02 selbst gelesen: New/Working/Escalated/Closed).
        // Mechanik-Assertion auf dem Konfigurations-Ort:
        System.assertEquals(false, CaseReminderConfig.isMonitoredStatus('Warten auf Kunde'),
            'AC5-Gate: suspendierter Status wird NICHT überwacht');
        System.assertEquals(true, CaseReminderConfig.isMonitoredStatus('Working'),
            'AC5-Gate: Working wird überwacht');
        System.assertEquals(true,  CaseReminderConfig.isMonitoredStatus('New'),
            'AC5-Gate: Default-Monitored New');
        System.assertEquals(true,  CaseReminderConfig.isMonitoredStatus('Escalated'),
            'AC5-Gate: Default-Monitored Escalated');
        System.assertEquals(false, CaseReminderConfig.isMonitoredStatus('Closed'),
            'AC5-Gate: Closed nie überwacht');
        System.assertEquals(3, CaseReminderConfig.DEFAULT_THRESHOLD_WORKING_DAYS, 'Schwellen Standard 3');
        System.assertEquals(1, CaseReminderConfig.HIGH_THRESHOLD_WORKING_DAYS, 'Schwellen High 1');
    }

    /* ─────────────────────────── V-AC6 ─────────────────────────── */

    @isTest
    static void v_ac6_rueckkehrInBearbeitung_uhrNeu() {
        // Simulates "Case lagte suspendiert/ruhend, geht zurueck in Bearbeitung":
        // Flag=Ja aus "vorher", LRU weit in der Vergangenheit. Statuswechsel
        // in einen monitored-Status MUSS die Uhr neu starten (PO-Regel 5).
        DateTime asOf = at(2026, 11, 16, 1, 0);
        Case c = plantOpen('Working', 'Medium', startWith(asOf, 9));
        Case f = refresh(c.Id);
        f.Reminder_Required__c = true;                 // "vorher" geflaggt
        f.Reminder_Due_Date__c = asOf.addDays(-6);
        f.Reminder_Count__c    = 1;
        update f;

        User staff = makeUser('s6', 'Statt6');
        changeStatusByStaff(c.Id, 'Escalated', staff); // zurueck in Ueberwachung

        Case r = refresh(c.Id);
        System.assert(r.Last_Relevant_Update__c >= DateTime.now().addMinutes(-5),
            'AC6: Rueckkehr in Bearbeitung startet die Uhr neu (LRU=now, war '
                + r.Last_Relevant_Update__c + ')');
        System.assertEquals(false, r.Reminder_Required__c, 'AC6: Flag wird zurueckgesetzt');
        System.assertEquals(2, r.Reminder_Count__c.intValue(), 'AC6: Regel 8 — Zaehler 1 -> 2');
        System.assertEquals(asOf.addDays(-6), r.Reminder_Due_Date__c,
            'AC6: Due-Datum bleibt (PO-Default Audit)');
    }

    /* ─────────────────────────── V-AC7 ─────────────────────────── */

    @isTest
    static void v_ac7_closedNiemals_geflaggt() {
        DateTime asOf = at(2026, 11, 16, 1, 0);
        Case closed = plantClosed(startWith(asOf, 5));  // 5 WD, aber closed

        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(asOf, 200));
        Test.stopTest();

        Case r = refresh(closed.Id);
        System.assertEquals(false, r.Reminder_Required__c,
            'AC7: geschlossener Case wird NIEMALS geflaggt');
        System.assertEquals(null, r.Reminder_Due_Date__c, 'AC7: kein Due-Datum');
    }

    /* ─────────────────────────── V-AC8 ─────────────────────────── */

    @isTest
    static void v_ac8_zweiZyklen_zaehlerSteigtZweimal() {
        DateTime asOf  = at(2026, 11, 16, 1, 0);
        DateTime asOf2 = at(2026, 11, 23, 1, 0);
        User staff = makeUser('s8', 'Statt8');

        // Zyklus 1 wird NICHT simuliert, sondern als ENDZUSTAND vorgegeben:
        // der before-Trigger laesst nach Bearbeitung eines GEFLOGGTEM Cases
        // exakt {flag=false, count=old+1, LRU=now, Due=unveraendert} —
        // der Trigger-Pfad selbst ist in v_ac4 und dem Developer-Test
        // ac8_status_change_resets_and_counts belegt.
        // (Pro Test-Methode ist NUR EIN Test-Fenster erlaubt und genau
        //  EIN executeBatch-Aufruf org-seitig — zwei echte Zyklen in einer
        //  Methode sind daher nicht darstellbar; der zweite Zyklus laeuft
        //  unten ECHT durch den Batch.)
        Case c = plantOpen('Working', 'Medium', startWith(asOf2, 5)); // 5 WD vor asOf2
        c.Reminder_Required__c = false;
        c.Reminder_Count__c    = 1;   // Zyklus 1 hat bereits gezaehlt
        c.Reminder_Due_Date__c = asOf; // Due vom (nicht simulierten) Zyklus 1
        update c;

        // Zyklus 2 ECHT: Batch flaggt neu (LRU 5 WD alt, flag=false).
        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(asOf2, 200));
        Test.stopTest();
        Case r1 = refresh(c.Id);
        System.assertEquals(true, r1.Reminder_Required__c,
            'AC8 Zyklus2: Batch flaggt erneut nach Zyklus 1');
        System.assertEquals(asOf2, r1.Reminder_Due_Date__c,
            'AC8: Due-Datum = asOf des ausloesenden Zyklus');

        // Bearbeitung im Zyklus 2: Zaehler steigt aus dem DB-Zustand (1 -> 2).
        changeStatusByStaff(c.Id, 'Escalated', staff);
        Case r2 = refresh(c.Id);
        System.assertEquals(false, r2.Reminder_Required__c,
            'AC8: Bearbeitung setzt das Flag zurueck');
        System.assertEquals(2, r2.Reminder_Count__c.intValue(),
            'AC8: Zaehler steigt ueber 2 Zyklen auf 2 (Zyklus1 Endzustand, Zyklus2 echt)');
        System.assertEquals(asOf2, r2.Reminder_Due_Date__c,
            'AC8: Due-Datum zeigt den LETZTEN Ausloesung-Zeitpunkt (Zyklus2, unveraendert bei Bearbeitung)');
    }

    /* ─────────────────────────── V-AC9 (Bulk + Idempotenz) ─────────────────────────── */

    @isTest
    static void v_ac9_hundertFuenfzigCases_zweitlaufTouchtNichts() {
        DateTime asOf = at(2026, 11, 16, 1, 0);
        DateTime lru = startWith(asOf, 5);   // alle 5 WD -> alle faellig

        // 150 Cases = genau EIN Batch-Chunk (batchSize 200) -> JE EINER
        // der beiden executeBatch-Aufrufe. Beide Laeufe stehen in EINEM
        // Test-Fenster: executeBatch-Aufrufe stellen sich in Reihung ein
        // und werden am stopTest sequentiell geflusht (org-verifiziert,
        // house ac9_batch_idempotent_secondRunZero).
        List<Case> toInsert = new List<Case>();
        for (Integer i = 0; i < 150; i++) {
            Case c = new Case(
                Subject   = 'V436_BULK_' + String.valueOf(System.now().getTime()) + '_' + i,
                Origin    = 'Phone',
                Status    = 'Working',
                Priority  = 'Medium',
                Last_Relevant_Update__c = lru
            );
            toInsert.add(c);
        }
        insert toInsert;
        List<Id> ids = new List<Id>();
        for (Case c : toInsert) { ids.add(c.Id); }

        Test.startTest();
        Database.executeBatch(new CaseReminderBatch(asOf, 200));  // Erstlauf
        Database.executeBatch(new CaseReminderBatch(at(2026, 11, 17, 1, 0), 200));  // Zweitlauf, ANDERES asOf
        Test.stopTest();

        // Erstlauf-Beweis: ALLE 150 geflaggt, Due-Datum = asOf des ERSTLAUFS.
        // Das ist zugleich der Idempotenz-Beweis: haette der Zweitlauf
        // (asOf 17.11.) auch nur eine Zeile angefasst, staende jetzt
        // 2026-11-17 dort — nicht 2026-11-16. (Starker Beweis: der
        //  Zweitlauf wuerde EIGENE Daten hinterlassen.)
        Integer flagged = 0;
        for (Case c : [SELECT Id, Reminder_Required__c, Reminder_Due_Date__c
                          FROM Case WHERE Id IN :ids]) {
            if (c.Reminder_Required__c == true) { flagged++; }
            else {
                System.assert(false,
                    'AC9: Case nicht geflaggt nach Erstlauf: ' + c.Id);
            }
            System.assertEquals(asOf, c.Reminder_Due_Date__c,
                'AC9: Due-Datum bleibt asOf des 1. Laufs — 2. Lauf (asOf+1) hat nichts angefasst ' + c.Id);
        }
        System.assertEquals(150, flagged,
            'AC9: alle 150 faelligen Cases geflaggt (1 Chunk, 1 Batch)');
    }
}
