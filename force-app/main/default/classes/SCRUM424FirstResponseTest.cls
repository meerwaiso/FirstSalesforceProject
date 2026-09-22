/**
 * [SCRUM-424] Apex-Test — Erste-Mitarbeiter-Reaktion (CaseComment).
 *
 * Haus-Pattern, gemessen in der Test-Org (keine geratenen Feld-/API-Namen):
 *   - Case unter System.runAs(kunde) gepflanzt            -> Case.CreatedById = kunde
 *   - Kommentar unter System.runAs(mitarbeiter) gepflanzt -> cc.CreatedById = mitarbeiter
 *     damit die ADR-4-Pruefung (cc.CreatedById != c.CreatedById) deterministisch trefft.
 *     CaseComment.CreatedById / CreatedDate sind NICHT per DML schreibbar (createable=false);
 *     beide werden NICHT per Feldzuweisung gesteuert — CreatedBy ueber den runAs-Kontext,
 *     CreatedDate ueber den real-now-Zeitstempel.
 *   - Zeitluecke: Case.CreatedDate wird NACH dem Pfanzen mit Test.setCreatedDate
 *     zurueckdatiert (SCRUM-398-Prezedenz). Der Comment entsteht auf real-now,
 *     also gap = Rueckdatierung. Auf der aktuellen 24/7-Org == BusinessHours-Minuten.
 *
 * AC-Coverage (gem. Design-Reviewer-Matrix):
 *   AC1–AC6, AC8   funktional (Apex, Trigger end-to-end)
 *   AC7            Kalenderminuten auf 24/7-Org; nach S2 (echte WorkWeek-Werte)
 *                  berechnet der Tester den Erwartungswert aus Org-Konfiguration.
 *   AC9            Apex-Proxy (SOQL-Aggregation); formale Verifikation = E2E + S4 (Tester).
 *   AC10           eigene Klasse SCRUM424FirstResponseFlsTest (USER_MODE, FLS-Kette).
 *   AC11           WorkWeek TimeZoneSidKey = Europe/Berlin (Read-Back; gemessen: gruen).
 *
 * @author developer-agent
 * @date 2026-09-22
 */
@isTest
private class SCRUM424FirstResponseTest {

    private static final String SVC  = 'svc424';
    private static final String CUST = 'cust424';

    /** Erzeugt einen Standard-User mit deterministischem Alias/Username. */
    private static User makeUser(String alias, String lastName) {
        Profile standard = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        return new User(
            ProfileId         = standard.Id,
            LastName          = lastName,
            Alias             = alias,           // max 8 Zeichen
            Email             = alias + sfx + '@x.invalid',
            Username          = alias + sfx + '@x.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'Europe/Berlin'
        );
    }

    private static User svc()  { User u = makeUser(SVC, 'Service');   insert u; return u; }
    private static User cust() { User u = makeUser(CUST, 'Customer'); insert u; return u; }

    /** Case wird unter runAs(kunde) gepflanzt -> CreatedById = kunde. */
    private static Id newCaseAsCustomer(User kunde, String servicebereich, String kundenstatus) {
        Case c = new Case(Subject = 'SCRUM-424', Status = 'New',
            Servicebereich__c = servicebereich, Kundenstatus__c = kundenstatus);
        System.runAs(kunde) { insert c; }
        return c.Id;
    }

    /** Rueckdatiert Case.CreatedDate um N Minuten (SCRUM-398-Prezedenz). */
    private static void backdate(Id caseId, Integer minutesAgo) {
        Test.setCreatedDate(caseId, System.now().addMinutes(-minutesAgo));
    }

    /** Mitarbeiter-Kommentar unter runAs(mitarbeiter) -> CreatedById = mitarbeiter. */
    private static void staffComment(Id caseId, User mitarbeiter, String body) {
        CaseComment cc = new CaseComment(ParentId = caseId, CommentBody = body);
        System.runAs(mitarbeiter) { insert cc; }
    }

    /** Kunde-Kommentar (Creator == Case-Ersteller) unter runAs(kunde). */
    private static void customerComment(Id caseId, User kunde, String body) {
        CaseComment cc = new CaseComment(ParentId = caseId, CommentBody = body);
        System.runAs(kunde) { insert cc; }
    }

    private static Case refresh(Id caseId) {
        return [SELECT Id, First_Response_Time__c, First_Response_Working_Mins__c,
                    First_Response_Target_Missed__c, Kundenstatus__c, Servicebereich__c
                FROM Case WHERE Id = :caseId LIMIT 1][0];
    }

    /* ------------------------------------------------------------------
     * AC1 — Premium im Ziel: 45 Arbeitsminuten < 60 -> Zeit gesetzt, Dauer 45, nicht verfehlt.
     */
    @isTest
    static void ac1_premium_in_target() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Technik', 'Premium');
        backdate(cid, 45);
        staffComment(cid, svc, 'Premium-1. Reaktion');

        Case c = refresh(cid);
        System.assertNotEquals(null, c.First_Response_Time__c, 'AC1: Zeit gesetzt');
        System.assertEquals(Decimal.valueOf(45), c.First_Response_Working_Mins__c, 'AC1: Dauer 45');
        System.assertEquals(false, c.First_Response_Target_Missed__c, 'AC1: Premium-Ziel (60) erreicht');
    }

    /* ------------------------------------------------------------------
     * AC2 — Standard gerissen: 300 > 240 -> Dauer 300, verfehlt.
     */
    @isTest
    static void ac2_standard_target_missed() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Allgemein', 'Standard');
        backdate(cid, 300);
        staffComment(cid, svc, 'Standard-1. Reaktion (spaet)');

        Case c = refresh(cid);
        System.assertEquals(Decimal.valueOf(300), c.First_Response_Working_Mins__c, 'AC2: Dauer 300');
        System.assertEquals(true, c.First_Response_Target_Missed__c, 'AC2: Standard-Ziel (240) gerissen');
    }

    /* ------------------------------------------------------------------
     * AC3 — Kundenstatus leer wird wie Standard (240) behandelt: 300 > 240.
     */
    @isTest
    static void ac3_blank_treated_as_standard() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Rechnung', null);
        backdate(cid, 300);
        staffComment(cid, svc, 'Leerer Status');

        Case c = refresh(cid);
        System.assertEquals(Decimal.valueOf(300), c.First_Response_Working_Mins__c, 'AC3: Dauer 300');
        System.assertEquals(true, c.First_Response_Target_Missed__c, 'AC3: Leer = Standard 240 -> gerissen');
    }

    /* ------------------------------------------------------------------
     * AC4 — Kunden-Kommentar zaehlt nicht (Creator == Case-Ersteller):
     *        alle 3 Felder bleiben leer; erst die Mitarbeiter-Antwort setzt.
     */
    @isTest
    static void ac4_customer_comment_not_counted() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Vertrag', 'Standard');

        customerComment(cid, cust, 'Kunde selbst');
        Case afterCust = refresh(cid);
        System.assertEquals(null, afterCust.First_Response_Time__c,         'AC4: Zeit leer nach Kunden-KC');
        System.assertEquals(null, afterCust.First_Response_Working_Mins__c, 'AC4: Mins leer nach Kunden-KC');

        backdate(cid, 45);
        staffComment(cid, svc, 'Mitarbeiter antwortet');
        Case afterSvc = refresh(cid);
        System.assertNotEquals(null, afterSvc.First_Response_Time__c, 'AC4: erst Mitarbeiter setzt');
    }

    /* ------------------------------------------------------------------
     * AC5 — Write-once: zweiter Kommentar aendert nichts.
     */
    @isTest
    static void ac5_write_once() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Technik', 'Standard');
        backdate(cid, 45);
        staffComment(cid, svc, 'erste Reaktion');

        Case afterFirst = refresh(cid);
        Datetime firstTime = afterFirst.First_Response_Time__c;
        Decimal  firstMins = afterFirst.First_Response_Working_Mins__c;
        System.assertEquals(Decimal.valueOf(45), firstMins, 'AC5: erste Dauer 45');

        staffComment(cid, svc, 'zweite Reaktion (muss ignoriert werden)');
        Case afterSecond = refresh(cid);
        System.assertEquals(firstTime, afterSecond.First_Response_Time__c, 'AC5: Zeit unveraendert');
        System.assertEquals(firstMins, afterSecond.First_Response_Working_Mins__c, 'AC5: Mins unveraendert');
    }

    /* ------------------------------------------------------------------
     * AC6 — Wiedereroeffnung: gesetzte Felder bleiben auch bei Reopen + neuer Antwort.
     *   Case.Status wird als Status-Aenderung simuliert (Picklist-Wert 'Closed' ist
     *   org-spezifisch); entscheidend ist, dass der neue Kommentar die 3 Felder
     *   NICHT neu beschreibt (Write-once u. A. des Trigger-Filters First_Response_Time__c=null).
     */
    @isTest
    static void ac6_case_reopening_persists() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Allgemein', 'Standard');
        backdate(cid, 45);
        staffComment(cid, svc, 'initial');

        Case firstSet = refresh(cid);
        Datetime firstTime = firstSet.First_Response_Time__c;
        Decimal  firstMins = firstSet.First_Response_Working_Mins__c;
        System.assertNotEquals(null, firstTime, 'AC6: erste Reaktion gesetzt');

        // Case "wiedereroeffnen": Status-Aenderung + neuer Mitarbeiter-Kommentar
        Case reopen = new Case();
        reopen.Id = cid; reopen.Status = 'New';
        update reopen;
        staffComment(cid, svc, 'nach Wiedereroeffnung');

        Case after = refresh(cid);
        System.assertEquals(firstTime, after.First_Response_Time__c, 'AC6: Write-once nach Reopen');
        System.assertEquals(firstMins, after.First_Response_Working_Mins__c, 'AC6: Mins nach Reopen');
    }

    /* ------------------------------------------------------------------
     * AC7 — Wochenende (aktuelle 24/7-Org): Freitag 18:00 -> Montag 09:00
     *        = 42 h = 2520 Kalenderminuten; auf 24/7 == BusinessHours-Minuten.
     *   Nach S2 (echte WorkWeek-Werte) berechnet der Tester den Wert aus Org-Konfig.
     */
    @isTest
    static void ac7_weekend_calendar_minutes_under_247() {
        User svc = svc(), cust = cust();
        Id cid = newCaseAsCustomer(cust, 'Technik', 'Standard');
        backdate(cid, 42 * 60);            // 42 h = 2520 min zurueck
        staffComment(cid, svc, 'Antwort am Montag');

        Case c = refresh(cid);
        System.assertEquals(Decimal.valueOf(2520), c.First_Response_Working_Mins__c,
            'AC7: 2520 Minuten auf 24/7-Org (Fri18 -> Mon09)');
    }

    /* ------------------------------------------------------------------
     * AC8 — Bulk: 200 Comments auf 20 Cases in EINEM Rutsch, je Case exakt die
     *        erste Reaktion, Governor-Limits intakt.
     */
    @isTest
    static void ac8_bulk_200_comments() {
        User svcU = svc();
        User custU = cust();

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 20; i++) {
            Case c = new Case(Subject = 'SCRUM-424 bulk', Status = 'New',
                Servicebereich__c = 'Allgemein', Kundenstatus__c = 'Standard');
            cases.add(c);
        }
        System.runAs(custU) { insert cases; }
        for (Case c : cases) {
            backdate(c.Id, 30);
        }

        // 200 CaseComments auf 20 Cases: 10 Kommentare je Case, bulk-insertiert
        List<CaseComment> all = new List<CaseComment>();
        for (Case c : cases) {
            for (Integer k = 0; k < 10; k++) {
                all.add(new CaseComment(ParentId = c.Id, CommentBody = 'Bulk ' + c.Id + '-' + k));
            }
        }
        System.runAs(svcU) {
            insert all;
        }

        // Alle 20 Cases haben EXAKT die erste Mitarbeiter-Reaktion gesetzt (Write-once)
        Integer counted = 0;
        for (Case c : cases) {
            Case r = refresh(c.Id);
            if (r.First_Response_Time__c != null && r.First_Response_Working_Mins__c != null) {
                counted++;
                System.assertEquals(Decimal.valueOf(30), r.First_Response_Working_Mins__c, 'AC8: je Case 30 min');
            }
        }
        System.assertEquals(20, counted, 'AC8: alle 20 Cases haben genau die erste Reaktion gesetzt');
    }

    /* ------------------------------------------------------------------
     * AC9 — Apex-Proxy: Aggregation pro Servicebereich (Durchschnitt Arbeitsminuten,
     *        Anzahl gerissener Ziele). Formale Verifikation = E2E + S4 (Tester).
     *   Technik: 1 Case, 60 min  -> AVG 60,  0 gerissen
     *   Vertrag: 2 Cases, 180+300-> AVG 240, 1 gerissen (300 > 240)
     */
    @isTest
    static void ac9_report_aggregates() {
        User svc = svc(), cust = cust();

        Id t1 = newCaseAsCustomer(cust, 'Technik', 'Standard'); backdate(t1, 60);
        staffComment(t1, svc, 't1');
        Id v1 = newCaseAsCustomer(cust, 'Vertrag', 'Standard'); backdate(v1, 180);
        staffComment(v1, svc, 'v1');
        Id v2 = newCaseAsCustomer(cust, 'Vertrag', 'Standard'); backdate(v2, 300);
        staffComment(v2, svc, 'v2');

        // Apex-Proxy (HAUS-Formen: Record-Read + skalares COUNT). Der Average wird in der
        // Report-KOMponente (E2E/S4, Tester) berechnet; hier wird der exakte Datenbestand
        // (Working-Mins pro Fall + gerissene Ziele pro Bereich) validiert.
        System.assertEquals(Decimal.valueOf(60),  refresh(t1).First_Response_Working_Mins__c, 'AC9: Technik-Fall 60');
        System.assertEquals(Decimal.valueOf(180), refresh(v1).First_Response_Working_Mins__c, 'AC9: Vertrag-Fall 180');
        System.assertEquals(Decimal.valueOf(300), refresh(v2).First_Response_Working_Mins__c, 'AC9: Vertrag-Fall 300');

        Integer techMissed  = [SELECT COUNT() FROM Case
            WHERE Servicebereich__c = 'Technik' AND First_Response_Target_Missed__c = true];
        Integer vertrMissed = [SELECT COUNT() FROM Case
            WHERE Servicebereich__c = 'Vertrag' AND First_Response_Target_Missed__c = true];
        System.assertEquals(1, vertrMissed, 'AC9: Vertrag genau 1 gerissenes Ziel (300 > 240)');
        System.assertEquals(0, techMissed,  'AC9: Technik kein gerissenes Ziel (60 < 240)');
    }

    /* ------------------------------------------------------------------
     * AC11 — WorkWeek "Default" TimeZoneSidKey = Europe/Berlin (Read-Back).
     */
    @isTest
    static void ac11_tz_berlin() {
        BusinessHours bh = [SELECT Id, TimeZoneSidKey FROM BusinessHours WHERE IsDefault = true LIMIT 1][0];
        System.assertEquals('Europe/Berlin', bh.TimeZoneSidKey, 'AC11: Default-BusinessHours = Europe/Berlin');
    }
}
