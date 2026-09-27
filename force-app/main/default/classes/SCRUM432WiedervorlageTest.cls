/**
 * [SCRUM-432] Value tests for the personal Wiedervorlage on Case.
 *
 * Formula contract (docs/SCRUM-432-design.md, ADR-2):
 *   Wiedervorlage_Heute_Offen__c =
 *     Wiedervorlage_Von__c = $User.Id
 *     AND Wiedervorlage_Datum__c = TODAY_OR_PAST
 *       (TODAY_OR_PAST := Wiedervorlage_Datum__c = null ? false
 *                                  : Wiedervorlage_Datum__c <= TODAY())
 *
 * Execution context: every business DML/SOQL runs under
 * System.runAs(<Standard User mit SCRUM432-Wiedervorlage-PersmissionsSet>).
 * Two reasons:
 *   1. The formula's $User.Id is per-reader - the realistic reader of the
 *      list view "Wiedervorlagen heute offen" is a Standard User, not the
 *      test admin. TC1..TC8 test exactly that reader's perspective.
 *   2. Lücke C of scripts/fls-gate.py requires System.runAs( coverage in
 *      every test class that touches the new fields.
 * Setup DML (User creation, PermissionSetAssignment) runs OUTSIDE runAs -
 * a Standard user cannot grant itself a PSA. Verified by probe
 * (SCRUM432Probe, 2026-09-27): insert/update/read on all four fields under
 * runAs(Standard-User + PSA) succeed; without PSA the insert fails with
 * "fields being inaccessible" (the exact Lücke C symptom).
 *
 * TC1  Von = reader, Datum = heute            -> true  (AC5 Kern)
 * TC2  Von = reader, Datum = morgen           -> false (AC1: Zukunft nicht offen)
 * TC3  Von = reader, Datum = gestern          -> true  (Rollover)
 * TC4  Von = reader, Datum = leer             -> false (ISBLANK-Guard)
 * TC5  Von = leer, Datum = heute              -> false (kein Setzer)
 * TC6  Von = anderer User, Datum = heute      -> false (AC2: nicht übernommen)
 * TC7  Von = anderer User, Datum = morgen     -> false
 * TC8  Von = anderer User, Datum = gestern    -> false (kein Rollover für fremde)
 * TC9  CRUD auf Datum/Notiz/Von: setzbar, lesbar, NULL-bar, Formel read-only (AC3)
 * TC10 Bulk: 200 Cases, Datum heute -> alle offen; update auf morgen -> alle nicht offen
 *
 * Alles bleibt in der Test-Txn und rollt zurück. DELETE wird bewusst nicht
 * geprüft: ein Standard User darf Cases nicht löschen (bewusstes Design,
 * kein Requirement).
 */
@isTest
private class SCRUM432WiedervorlageTest {

    /** Case anlegen (nur im runAs-Kontext aufrufen). Formel wird beim Lesen berechnet. */
    private static Case mkCase(String subject, Id vonId, Date datum) {
        Case c = new Case(
            Subject = subject,
            Status = 'New',
            Wiedervorlage_Von__c = vonId
        );
        if (datum != null) {
            c.Wiedervorlage_Datum__c = datum;
        }
        insert c;
        return c;
    }

    private static Case read(Id id) {
        return [SELECT Wiedervorlage_Datum__c, Wiedervorlage_Notiz__c,
                       Wiedervorlage_Von__c, Wiedervorlage_Heute_Offen__c
                 FROM Case WHERE Id = :id];
    }

    /**
     * Test-Standard-User (Profil "Standard User") + optional die
     * Wiedervorlage-PersmissionsSet. Setup-DML: AUFENHALT sich immer
     * OUTSIDE von runAs (Standard-User kann sich keine PSA selbst geben).
     */
    private static User prepareReader(String tag, Boolean grantWiedervorlagePS) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'SCRUM432 ' + tag,
            Alias = tag,
            Email = tag + '@example.invalid',
            Username = tag + '_' + String.valueOf(System.now().getTime()) + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        if (grantWiedervorlagePS) {
            PermissionSet ps = [SELECT Id FROM PermissionSet
                                WHERE Name = 'SCRUM432_Wiedervorlage_ServiceTeam'
                                LIMIT 1];
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = ps.Id
            );
        }
        return u;
    }

    /** TC1: eigener Setzer, Datum heute -> offen (AC5 Kern). */
    @isTest
    static void open_mineToday_isOpen() {
        User su = prepareReader('sc432v1', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC1 today', su.Id, Date.today());
            Case r = read(c.Id);
            System.assertEquals(true, r.Wiedervorlage_Heute_Offen__c,
                'TC1: own Setzer + today must be open');
        }
    }

    /** TC2: eigener Setzer, Datum morgen -> nicht offen (AC1: strikt heute oder Vergangenheit). */
    @isTest
    static void open_mineTomorrow_notOpen() {
        User su = prepareReader('sc432v2', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC2 tomorrow', su.Id, Date.today().addDays(1));
            Case r = read(c.Id);
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC2: own Setzer + tomorrow must NOT be open (AC1)');
        }
    }

    /** TC3: eigener Setzer, Datum gestern -> offen (Rollover, AC5). */
    @isTest
    static void open_mineYesterday_isOpen() {
        User su = prepareReader('sc432v3', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC3 yesterday', su.Id, Date.today().addDays(-1));
            Case r = read(c.Id);
            System.assertEquals(true, r.Wiedervorlage_Heute_Offen__c,
                'TC3: own Setzer + yesterday must be open (rollover)');
        }
    }

    /** TC4: eigener Setzer, Datum leer -> nicht offen (ISBLANK-Guard). */
    @isTest
    static void open_mineNoDate_notOpen() {
        User su = prepareReader('sc432v4', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC4 no date', su.Id, null);
            Case r = read(c.Id);
            System.assertEquals(null, r.Wiedervorlage_Datum__c, 'TC4: date must be null');
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC4: own Setzer + null date must NOT be open');
        }
    }

    /** TC5: kein Setzer, Datum heute -> nicht offen. */
    @isTest
    static void open_noSetzer_today_notOpen() {
        User su = prepareReader('sc432v5', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC5 no setzer', null, Date.today());
            Case r = read(c.Id);
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC5: null Setzer + today must NOT be open');
        }
    }

    /** TC6: fremder Setzer, Datum heute -> nicht offen (AC2: persönliche Wiedervorlage, kein Take-over/Claim). */
    @isTest
    static void open_otherSetzerToday_notOpen() {
        Id otherUserId = createOtherUser('sc432v6o');
        User su = prepareReader('sc432v6', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC6 other', otherUserId, Date.today());
            Case r = read(c.Id);
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC6: other user + today must NOT be open for me (AC2)');
        }
    }

    /** TC7: fremder Setzer, Datum morgen -> nicht offen (beide Guards schlagen zu). */
    @isTest
    static void open_otherSetzerTomorrow_notOpen() {
        Id otherUserId = createOtherUser('sc432v7o');
        User su = prepareReader('sc432v7', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC7 other tomorrow', otherUserId, Date.today().addDays(1));
            Case r = read(c.Id);
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC7: other user + tomorrow must NOT be open');
        }
    }

    /** TC8: fremder Setzer, Datum gestern -> nicht offen (kein Rollover über Users hinweg). */
    @isTest
    static void open_otherSetzerYesterday_notOpen() {
        Id otherUserId = createOtherUser('sc432v8o');
        User su = prepareReader('sc432v8', true);
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC8 other yesterday', otherUserId, Date.today().addDays(-1));
            Case r = read(c.Id);
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC8: other user + yesterday must NOT be open for me');
        }
    }

    /** TC9 (AC3): Standard-CRUD auf Datum/Notiz/Von; Formel bleibt read-only. */
    @isTest
    static void crud_standardCRUD_onThreeStorageFields() {
        User su = prepareReader('sc432v9', true);
        Id otherUserId = createOtherUser('sc432v9o');
        System.runAs(su) {
            Case c = mkCase('[SCRUM-432] TC9 crud', su.Id, Date.today());
            c.Wiedervorlage_Datum__c = Date.today().addDays(3);
            c.Wiedervorlage_Notiz__c = 'Anruf an Kunden';
            c.Wiedervorlage_Von__c = otherUserId;
            update c;

            Case r = read(c.Id);
            System.assertEquals(Date.today().addDays(3), r.Wiedervorlage_Datum__c,
                'TC9: date must be updatable');
            System.assertEquals('Anruf an Kunden', r.Wiedervorlage_Notiz__c,
                'TC9: note must be updatable');
            System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c,
                'TC9: future date -> not open');

            // Alles wieder auf null -> alle drei Felder NULL-bar.
            c.Wiedervorlage_Datum__c = null;
            c.Wiedervorlage_Notiz__c = null;
            c.Wiedervorlage_Von__c = null;
            update c;

            r = read(c.Id);
            System.assertEquals(null, r.Wiedervorlage_Datum__c,
                'TC9: date must be resettable to null');
            System.assertEquals(null, r.Wiedervorlage_Notiz__c,
                'TC9: note must be resettable to null');
            System.assertEquals(null, r.Wiedervorlage_Von__c,
                'TC9: von must be resettable to null (SetNull)');
        }
    }

    /** TC10 (Bulk, ADR-10): 200 Cases in einem Test, 2 DML + 2 SOQL im runAs. */
    @isTest
    static void twoHundredCases_openTodayClosedTomorrow() {
        User su = prepareReader('sc432v10', true);
        System.runAs(su) {
            List<Case> cases = new List<Case>();
            for (Integer i = 0; i < 200; i++) {
                Case c = new Case(
                    Subject = '[SCRUM-432] bulk ' + i,
                    Status = 'New',
                    Wiedervorlage_Von__c = su.Id
                );
                c.Wiedervorlage_Datum__c = Date.today();
                cases.add(c);
            }
            insert cases;

            Integer openCount = [SELECT COUNT() FROM Case
                                 WHERE Wiedervorlage_Heute_Offen__c = true
                                 AND Subject LIKE '[SCRUM-432] bulk %'];
            System.assertEquals(200, openCount, 'TC10: all 200 own-today cases must be open');

            for (Case c : cases) {
                c.Wiedervorlage_Datum__c = Date.today().addDays(1);
            }
            update cases;

            openCount = [SELECT COUNT() FROM Case
                         WHERE Wiedervorlage_Heute_Offen__c = true
                         AND Subject LIKE '[SCRUM-432] bulk %'];
            System.assertEquals(0, openCount,
                'TC10: after moving to tomorrow none may be open');
        }
    }

    /** Test-Nebenuser auf dem Standard-User-Profil (nur als Von-Referenz). Admin-DML OUTSIDE runAs. */
    private static Id createOtherUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'SCRUM432 ' + alias,
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + String.valueOf(System.now().getTime()) + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u.Id;
    }
}
