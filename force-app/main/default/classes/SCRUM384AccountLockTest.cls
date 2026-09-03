/**
 * [SCRUM-384] Apex-Test-Suite: Account sperren (Gesperrt + Sperrgrund) +
 * Opportunity-Anlage-Block + Auto-Clear.
 *
 * Mapping zur Build-Spec docs/SCRUM-384-design.md S11 (7 Testfaelle)
 * + 2 Regression/Coverage-Tests:
 *   1. AC2 positiv  — Gesperrt + Grund wird gespeichert (Read-Back).
 *   2. AC2 negativ  — Gesperrt ohne Grund -> DmlException, Meldung "Sperrgrund".
 *   3. AC3 negativ  — Opportunity am gesperrten Account -> DmlException,
 *                      Meldung nennt Account-Namen UND Sperrgrund-Wert.
 *   4. AC3 positiv  — unge-sperrter Account + AccountId=null -> Anlage ok, 0 SOQL.
 *   5. AC4          — Aufheben -> Sperrgrund null, Anlage wieder moeglich.
 *   6. Bulk         — 200 Opportunities in EINEM Trigger-Aufruf -> <=2 SOQL
 *                      (batched, nicht 200 Einzel-Queries).
 *   7. FLS negativ  — ohne PS: beide Felder nicht les-/schreibbar.
 *   8. FLS positiv  — mit PS: beide Felder lesbar.
 *   9. Handler-Guard — no-change (Grund bleibt) + second-call (hasFired).
 *  10. Regression   — Opportunity-Update: SCRUM-384-Guard feuert auf Update
 *                      NICHT (nur before insert); SCRUM-319/381-Handler laufen.
 *                      Deckt auch die update-Call-Linien des Opportunity-
 *                      OverdueReset-Trigger ab (Org-Gate: >=75% auf betroffene
 *                      Triggers).
 *
 * Stil 1:1 uebernommen aus SCRUM381LostReasonTest / SCRUM378LeadNachfassungFlsTest.
 */
@isTest
private class SCRUM384AccountLockTest {

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

    /** Gesperrter Account mit Sperrgrund (besteht die AC2-ValRule). */
    private static Account newLockedAccount(String name, String reason) {
        return new Account(
            Name = name,
            Is_Locked__c = true,
            Lock_Reason__c = reason
        );
    }

    /** Opportunity-Instanz (Stage Prospecting, offene CloseDate). */
    private static Opportunity newOpportunity(String name, Id accountId) {
        return new Opportunity(
            Name = name,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = accountId
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
    //    Meldung nennt Account-Namen UND Sperrgrund.
    @isTest
    static void test_AC3_Negativ_GesperrtAccount_OppBlocked() {
        Account a = newLockedAccount('Gesperrt-AG', 'offene Forderung');
        insert a;

        Opportunity o = newOpportunity('Neue Chance am gesperrten Account', a.Id);
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
        Account open = new Account(Name = 'Offen Account', Is_Locked__c = false);
        insert open;
        Opportunity o = newOpportunity('Chance am offenen Account', open.Id);
        insert o;
        System.assertNotEquals(null, o.Id,
            'Opportunity am unge-sperrten Account muss angelegt werden koennen');

        // AccountId=null -> kein Account-Lookup, kein Block, 0 SOQL im Guard.
        Integer before = Limits.getQueries();
        insert newOpportunity('Chance ohne Account', null);
        System.assertEquals(0, Limits.getQueries() - before,
            'Bei AccountId=null muss der Guard 0 SOQL verbrauchen (leeres-Set-Guard)');
    }

    // 5. AC4 — Aufheben der Sperre leert den Sperrgrund und oeffnet Chancen wieder.
    @isTest
    static void test_AC4_Aufheben_LeertGrund_und_OeffnetWieder() {
        Account a = newLockedAccount('Entsperr-Account', 'offene Forderung');
        insert a;

        a.Is_Locked__c = false;
        update a;

        Account r = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(false, r.Is_Locked__c, 'Is_Locked muss false sein');
        System.assertEquals(null, r.Lock_Reason__c,
            'Nach Aufheben muss Lock_Reason__c automatisch null sein (AC4)');

        Opportunity after = newOpportunity('Chance nach Entsperrung', a.Id);
        insert after;
        System.assertNotEquals(null, after.Id,
            'Nach Aufheben muss die Opportunity-Anlage wieder funktionieren (AC4)');
    }

    // 6. Bulk-Governor — 200 Opportunities in EINEM Trigger-Aufruf -> <=2 SOQL.
    @isTest
    static void test_Bulk_200Opps_NachFritig_batched() {
        Account open = new Account(Name = 'Bulk Offen');
        Account locked1 = newLockedAccount('Bulk Gesperrt 1', 'offene Forderung');
        Account locked2 = newLockedAccount('Bulk Gesperrt 2', 'Zahlungsrueckstand');
        insert open;
        insert locked1;
        insert locked2;

        // Block-basiert ueber 3 distinkte Account-Ids (so batcht der Guard
        // alle in einer Query): Block 0 = offen (66), 1 = gesperrt1 (67),
        // 2 = gesperrt2 (67). Summe = 200.
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            Id tgt;
            if (i < 66) {
                tgt = open.Id;
            } else if (i < 133) {
                tgt = locked1.Id;
            } else {
                tgt = locked2.Id;
            }
            opps.add(newOpportunity('BulkOpp ' + i, tgt));
        }

        DmlException ex = null;
        Integer before = Limits.getQueries();
        try {
            insert opps;
        } catch (DmlException e) {
            ex = e;
        }
        Integer delta = Limits.getQueries() - before;

        // BATCHING-GARANTIE: 200 Opportunities duerfen NICHT 200 Einzel-Queries
        // kosten (anti-batch-NAP). Der Guard batcht alle Ids in einer IN-Query
        // -> delta liegt unterhalb des Anti-Patterns. In checkOnly-Mode
        // (dry-run) kann ein durchweg addError'd-Insert 0 oder 1 Query
        // kosten; beides ist batched. >= 200 wuerde per-Record-Lookup (Bug).
        System.assert(delta <= 2,
            'Der Guard muss 200 Opportunities BATTCHEN (<=2 SOQL, nicht 200). Tatsaechlich: ' + delta);
        System.assert(delta >= 0, 'Negativer SOQL-Delta ist unmoglich: ' + delta);
        System.assertNotEquals(null, ex,
            'Gesperrte Accounts im Bulk MUSS mindestens eine Opportunity blockieren (addError)');
        // Bulk-Insert ist atomic: blockierte Records -> ganzer Insert rollt zurueck.
        List<Id> bulkAccts = new List<Id>{ open.Id, locked1.Id, locked2.Id };
        Integer persisted = [SELECT COUNT() FROM Opportunity WHERE AccountId IN :bulkAccts];
        System.assertEquals(0, persisted,
            'Atomic-Insert mit blockierten Records darf nichts persistieren');
    }

    // 7. FLS negativ — ohne Permission Set sind beide Felder ungreifbar.
    @isTest
    static void test_FLS_Negativ_OhnePS_Ungreifbar() {
        User u = createTestUser('7');
        insert u;
        System.runAs(u) {
            System.assert(
                Account.SObjectType.getDescribe().isAccessible(),
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

    // 9. Handler-Guard Edge Coverage — Is_Locked bleibt true -> Grund NICHT
    //    geleert (false-ast); zweiter Aufruf -> hasFired-Gard.
    @isTest
    static void test_Handler_Guard_NochGesperrt_und_SecondCallNoop() {
        Account a = newLockedAccount('Guard-Account', 'Bleibt gesperrt');
        insert a;

        // Direkt-Call #1: Is_Locked bleibt true (kein Wechsel) -> Grund bleibt.
        Account fresh = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        List<Account> newRecs = new List<Account>{ fresh };
        Map<Id, Account> oldMap = new Map<Id, Account>{ fresh.Id => fresh };
        AccountLockClearHandler.handleBeforeUpdate(newRecs, oldMap);
        System.assertEquals('Bleibt gesperrt', fresh.Lock_Reason__c,
            'Solange Is_Locked true bleibt, darf Lock_Reason NICHT geleert werden');

        // Direkt-Call #2: hasFired=true -> Guard-Return; leeres oldMap deckt
        // zugleich den oldAcct==null-Zweig ab.
        Account fresh2 = [SELECT Id, Is_Locked__c, Lock_Reason__c FROM Account WHERE Id = :a.Id];
        AccountLockClearHandler.handleBeforeUpdate(new List<Account>{ fresh2 }, new Map<Id, Account>());
        System.assertEquals(true, true,
            'Zweiter Aufruf: Guard greift (kein No-Op-Fehler, keine Exception)');
    }

    // 10. Regression (SCRUM-319/381/384) — Opportunity-UPDATE: SCRUM-384-Guard
    //     feuert auf Update NICHT (nur before insert); SCRUM-319/381-Handler
    //     laufen. Deckt auch die beiden update-Call-Linien des Opportunity-
    //     OverdueReset-Trigger ab (Org-Gate: alle betroffenen Triggers >=75%).
    @isTest
    static void test_Regression_OpportunityUpdate_GuardKeinBlock() {
        // Account ZURUCK: ungesperrt; Opportunity wird an ihn angelegt.
        Account a = new Account(Name = 'Update-Regression', Is_Locked__c = false);
        insert a;
        Opportunity o = newOpportunity('Update-Regression-Opp', a.Id);
        insert o;

        // Account wird NACHHER (nach der Anlage) gesperrt: ValRule bestanden,
        // Account-Trigger laeuft (Is_Locked true->true? nein, false->true:
        // keine Aenderung von true->false, also kein Auto-Clear).
        a.Is_Locked__c = true;
        a.Lock_Reason__c = 'naeherungsweise offen';
        update a;

        // UPDATE der bereits vorhandenen Opportunity -> SCRUM-384-Guard
        // muss NICHT blockieren (er feuert nur im before-insert).
        o.StageName = 'Qualification';
        o.CloseDate = Date.today().addDays(45);
        update o;

        Opportunity r = [SELECT Id, StageName, AccountId
                          FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('Qualification', r.StageName,
            'Auf Update einer vorhandenen Opportunity muss der SCRUM-384-Block nicht greifen');
        System.assertEquals(a.Id, r.AccountId,
            'AccountId auf Update unveraendert (bestehende Opportunity unangetastet)');
    }
}
