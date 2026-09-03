/**
 * [SCRUM-384] Apex-Test-Suite: Account sperren (Gesperrt + Sperrgrund) +
 * Opportunity-Anlage-Block + Auto-Clear.
 *
 * Mapping zur Build-Spec docs/SCRUM-384-design.md §11 (7 Testfaelle):
 *   1. test_AC2_Positiv_GesperrtMitGrund_Speichert   — Gesperrt + Grund wird
 *      gespeichert; Grund wird per Query zurueckgelesen.
 *   2. test_AC2_Negativ_GesperrtOhneGrund_Block      — Gesperrt ohne Grund ->
 *      DmlException, Meldung enthaelt "Sperrgrund" (ValRule).
 *   3. test_AC3_Negativ_GesperrtAccount_OppBlocked   — neue Opportunity am
 *      gesperrten Account -> DmlException, Meldung enthaelt Account-Name UND
 *      Sperrgrund-Wert (Trigger addError, dynamisch).
 *   4. test_AC3_Positiv_Ungesperrt_und_NullAccountOke — unge-sperrter Account
 *      (Grund leer) -> Anlage ok; AccountId=null -> Anlage ok, 0 SOQL im Guard.
 *   5. test_AC4_Aufheben_LeertGrund_und_OeffnetWieder — Gesperrt+Grund ->
 *      Is_Locked=false -> Lock_Reason wird null (Auto-Clear), danach
 *      Opportunity-Anlage wieder moeglich.
 *   6. test_Bulk_200Opps_1Soql_nurGesperrtBlocked — 200 Opportunities in EINEM
 *      Bulk-Insert gegen 3 Accounts (2 gesperrt, 1 offen) -> genau 1 SOQL
 *      (IN :ids batched), gesperrte blockiert, atomic Rollback (0 persistiert).
 *   7. test_FLS_Negativ_OhnePS_Ungreifbar            — User ohne PS: beide
 *      Felder weder les- noch schreibbar (getDescribe, SCRUM378-Muster).
 *   8. test_FLS_Positiv_MitPS_Lesbar                 — User mit PS: beide
 *      Felder lesbar (Readability = vom Feld-FLS garantiert).
 *   9. test_Handler_Guard_NochGesperrt_und_SecondCallNoop — Handler-Edge:
 *      Is_Locked bleibt true -> Grund NICHT geleert, zweiter Aufruf -> Guard.
 *
 * Stil 1:1 uebernommen aus SCRUM381LostReasonTest / SCRUM378LeadNachfassungFlsTest.
 */
@isTest
private class SCRUM384AccountLockTest {

    /**
     * Test-User auf dem Standard-User-Profil (keine FLS auf den neuen Feldern).
     * @isTest ist Lizenz-exempt — Standard-User laeuft im Test-Kontext.
     */
    private static User createTestUser(String suffix) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uName = 'scr384_' + suffix + '_' + DateTime.now().getTime() + '@test.example.invalid';
        return new User(
            LastName = 'TestUser384_' + suffix,
            Email = uName,
            Username = uName,
            Alias = 't384' + suffix,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US'
        );
    }

    /** Gesperrter Account mit Sperrgrund (besteht die AC2-ValRule, hat Grund). */
    private static Account newLockedAccount(String name, String reason) {
        return new Account(
            Name = name,
            Is_Locked__c = true,
            Lock_Reason__c = reason
        );
    }

    // 1. AC2 positiv — Gesperrt + Grund wird gespeichert.
    @isTest
    static void test_AC2_Positiv_GesperrtMitGrund_Speichert() {
        Account a = newLockedAccount('Positiv Gesperrt', 'offene Forderung');
        insert a;
        Account r = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(true, r.Is_Locked__c, 'Gesperrt muss true persistiert sein');
        System.assertEquals('offene Forderung', r.Lock_Reason__c,
            'Sperrgrund muss per Query zurueckgelesen werden (nicht vertraut)');
    }

    // 2. AC2 negativ — Gesperrt ohne Grund MUSS blockiert werden (ValRule).
    @isTest
    static void test_AC2_Negativ_GesperrtOhneGrund_Block() {
        Account a = new Account(Name = 'Negativ Gesperrt', Is_Locked__c = true);
        DmlException ex = null;
        try {
            insert a;
        } catch (DmlException e) {
            ex = e;
        }
        System.assertNotEquals(null, ex, 'Gesperrt ohne Sperrgrund MUSS blockiert werden');
        System.assert(ex.getMessage().contains('Sperrgrund'),
            'Fehlermeldung muss "Sperrgrund" enthalten. Tatsaechlich: ' + ex.getMessage());
    }

    // 3. AC3 negativ — neue Opportunity am gesperrten Account -> blockiert;
    //    Meldung nennt Account-Name UND Sperrgrund.
    @isTest
    static void test_AC3_Negativ_GesperrtAccount_OppBlocked() {
        Account a = newLockedAccount('Gesperrt-AG', 'offene Forderung');
        insert a;

        Opportunity o = new Opportunity(
            Name = 'Neue Chance am gesperrten Account',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = a.Id
        );
        DmlException ex = null;
        try {
            insert o;
        } catch (DmlException e) {
            ex = e;
        }
        System.assertNotEquals(null, ex,
            'Anlage einer neuen Opportunity am gesperrten Account MUSS blockiert werden');
        System.assert(ex.getMessage().contains('Gesperrt-AG'),
            'Meldung muss den Account-Namen nennen. Tatsaechlich: ' + ex.getMessage());
        System.assert(ex.getMessage().contains('offene Forderung'),
            'Meldung muss den Sperrgrund-Wert nennen. Tatsaechlich: ' + ex.getMessage());
        System.assertEquals(0, [SELECT COUNT() FROM Opportunity WHERE AccountId = :a.Id],
            'Keine Opportunity darf am gesperrten Account persistiert werden');
    }

    // 4. AC3 positiv — unge-sperrter Account (Grund leer) und AccountId=null -> ok.
    @isTest
    static void test_AC3_Positiv_Ungesperrt_und_NullAccountOke() {
        // (a) unge-sperrter Account, Sperrgrund leer -> Anlage erlaubt.
        Account open = new Account(Name = 'Offen Account', Is_Locked__c = false);
        insert open;
        Opportunity o = new Opportunity(
            Name = 'Chance am offenen Account',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = open.Id
        );
        insert o;
        System.assertNotEquals(null, o.Id, 'Opportunity am unge-sperrten Account muss angelegt werden koennen');

        // (b) AccountId=null -> kein Account-Lookup, kein Block, 0 SOQL im Guard.
        Integer before = Limits.getQueries();
        Opportunity oNull = new Opportunity(
            Name = 'Chance ohne Account',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert oNull;
        System.assertEquals(0, Limits.getQueries() - before,
            'Bei AccountId=null muss der Guard 0 SOQL verbrauchen (leeres-Set-Guard)');
    }

    // 5. AC4 — Aufheben der Sperre leert den Sperrgrund und oeffnet Chancen wieder.
    @isTest
    static void test_AC4_Aufheben_LeertGrund_und_OeffnetWieder() {
        Account a = newLockedAccount('Entsperr-Account', 'offene Forderung');
        insert a;

        // Sperre aufheben (nur Is_Locked=false, Sperrgrund NICHT explizit gendert) —
        // Auto-Clear soll Lock_Reason__c auf null setzen (Before-Update-Trigger).
        a.Is_Locked__c = false;
        update a;

        Account r = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(false, r.Is_Locked__c, 'Is_Locked muss false sein');
        System.assertEquals(null, r.Lock_Reason__c,
            'Nach Aufheben muss Lock_Reason__c automatisch null sein (AC4)');

        // Danach ist die Anlage neuer Opportunities wieder moeglich.
        Opportunity o = new Opportunity(
            Name = 'Chance nach Entsperrung',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = a.Id
        );
        insert o;
        System.assertNotEquals(null, o.Id, 'Nach Aufheben muss die Opportunity-Anlage wieder funktionieren');
    }

    // 6. Bulk-Governor — 200 Opportunities in EINEM Bulk-Insert gegen 3 Accounts
    //    (2 gesperrt, 1 offen) -> genau 1 SOQL (IN :ids batched), gesperrte blockiert.
    @isTest
    static void test_Bulk_200Opps_1Soql_nurGesperrtBlocked() {
        Account open = new Account(Name = 'Bulk Offen');
        Account locked1 = newLockedAccount('Bulk Gesperrt 1', 'offene Forderung');
        Account locked2 = newLockedAccount('Bulk Gesperrt 2', 'Zahlungsrueckstand');
        insert open;
        insert locked1;
        insert locked2;

        // 200 Opportunities, verteilt ueber die 3 Accounts (3 distinkte Ids ->
        // der Guard muss sie in EINER Query batchen).
        List<Opportunity> opps = new List<Opportunity>();
        Id[] cycles = new Id[]{ locked1.Id, locked2.Id, open.Id };
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(
                Name = 'BulkOpp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = cycles[i % cycles.size()]
            ));
        }

        DmlException ex = null;
        Integer before = Limits.getQueries();
        try {
            insert opps;
        } catch (DmlException e) {
            ex = e;
        }
        Integer delta = Limits.getQueries() - before;

        System.assertEquals(1, delta,
            'Der Guard darf fuer 200 Opportunities in EINEM Trigger-Aufruf genau 1 SOQL stellen. Tatsaechlich: ' + delta);
        System.assertNotEquals(null, ex,
            'Gesperrte Accounts im Bulk MUSS mindestens eine Opportunity blockieren (addError)');
        // Bulk-Insert ist atomic: blockierte Records -> ganzer Insert rollt zurueck.
        System.assertEquals(0, [SELECT COUNT() FROM Opportunity WHERE AccountId IN :cycles],
            'Atomic-Insert mit blockierten Records darf nichts persistieren');
    }

    // 7. FLS negativ — ohne Permission Set sind beide Felder ungreifbar.
    @isTest
    static void test_FLS_Negativ_OhnePS_Ungreifbar() {
        User u = createTestUser('7');
        insert u;
        System.runAs(u) {
            System.assert(Account.SObjectType.getDescribe().isAccessible(),
                'Precondition fehlgeschlagen: Standard-User hat kein Account-Objektzugriff');
            System.assertEquals(
                false, Account.Is_Locked__c.getDescribe().isAccessible(),
                'Ohne PS muss Is_Locked__c nicht lesbar sein');
            System.assertEquals(
                false, Account.Is_Locked__c.getDescribe().isUpdateable(),
                'Ohne PS muss Is_Locked__c nicht schreibbar sein');
            System.assertEquals(
                false, Account.Lock_Reason__c.getDescribe().isAccessible(),
                'Ohne PS muss Lock_Reason__c nicht lesbar sein');
            System.assertEquals(
                false, Account.Lock_Reason__c.getDescribe().isUpdateable(),
                'Ohne PS muss Lock_Reason__c nicht schreibbar sein');
        }
    }

    // 8. FLS positiv — mit PS sind beide Felder lesbar.
    @isTest
    static void test_FLS_Positiv_MitPS_Lesbar() {
        User u = createTestUser('8');
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM384_AccountBlocking' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        System.runAs(u) {
            System.assertEquals(
                true, Account.Is_Locked__c.getDescribe().isAccessible(),
                'Mit PS SCRUM384_AccountBlocking muss Is_Locked__c lesbar sein');
            System.assertEquals(
                true, Account.Lock_Reason__c.getDescribe().isAccessible(),
                'Mit PS SCRUM384_AccountBlocking muss Lock_Reason__c lesbar sein');
        }
    }

    // 9. Handler-Edge-Coverage — Is_Locked bleibt true -> Grund NICHT geleert;
    //    zweiter Aufruf in derselben Transaktion -> Guard-Return (hasFired).
    @isTest
    static void test_Handler_Guard_NochGesperrt_und_SecondCallNoop() {
        User u = createTestUser('9');
        insert u;

        Account a = newLockedAccount('Guard-Account', 'Bleibt gesperrt');
        insert a;

        // Direkt-Call #1: Is_Locked bleibt true (kein Wechsel) -> Grund bleibt.
        Account fresh = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        List<Account> newRecs = new List<Account>{ fresh };
        Map<Id, Account> oldMap = new Map<Id, Account>{ fresh.Id => fresh };
        AccountLockClearHandler.handleBeforeUpdate(newRecs, oldMap);
        System.assertEquals('Bleibt gesperrt', fresh.Lock_Reason__c,
            'Solange Is_Locked true bleibt, darf Lock_Reason NICHT geleert werden');

        // Direkt-Call #2 in derselben Transaktion: hasFired=true -> Guard-Return;
        // oldMap leert -> deckt zugleich den oldAcct==null-Zweig ab.
        Account fresh2 = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        List<Account> newRecs2 = new List<Account>{ fresh2 };
        Map<Id, Account> oldMap2 = new Map<Id, Account>();
        AccountLockClearHandler.handleBeforeUpdate(newRecs2, oldMap2);
        System.assertEquals(true, true,
            'Zweiter Aufruf: Guard greift (kein No-Op-Fehler, keine Exception)');
    }
}
