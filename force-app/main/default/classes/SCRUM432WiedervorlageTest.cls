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
 * TC1  Von = currentUser, Datum = heute         -> true  (AC5 Kern)
 * TC2  Von = currentUser, Datum = morgen        -> false (AC1: Zukunft nicht offen)
 * TC3  Von = currentUser, Datum = gestern       -> true  (Rollover)
 * TC4  Von = currentUser, Datum = leer          -> false (ISBLANK-Guard)
 * TC5  Von = leer,            Datum = heute     -> false (kein Setzer)
 * TC6  Von = anderer User,    Datum = heute     -> false (AC2: nicht übernommen)
 * TC7  Von = anderer User,    Datum = morgen    -> false
 * TC8  Von = anderer User,    Datum = gestern   -> false (kein Rollover für fremde)
 * TC9  CRUD auf Datum/Notiz/Von: setzbar, lesbar, NULL-bar, Formel read-only (AC3)
 * TC10 Bulk: 200 Cases, Datum heute -> alle offen; update auf morgen -> alle nicht offen
 *
 * Die Formel wird beim Lesen berechnet; es gibt keinen Trigger und keinen
 * Backfill (ADR-10). Alles legt sich in der Test-Txn ab und rollt zurück.
 */
@isTest
private class SCRUM432WiedervorlageTest {

    /** Case mit Wiedervorlage anlegen; Formel beim Lesen berechnen. */
    private static Case mkCase(String subject, Id vonId, Date datum) {
        Case c = new Case(
            Subject = subject,
            Status = 'New',
            Wiedervorlage_Von__c = vonId,
            Wiedervorlage_Datum__c = datum
        );
        insert c;
        return c;
    }

    private static Case read(Id id) {
        return [SELECT Wiedervorlage_Datum__c, Wiedervorlage_Notiz__c,
                       Wiedervorlage_Von__c, Wiedervorlage_Heute_Offen__c
                 FROM Case WHERE Id = :id];
    }

    /** TC1: eigener Setzer, Datum heute -> offen. */
    @isTest
    static void open_mineToday_isOpen() {
        Case c = mkCase('[SCRUM-432] TC1 today', UserInfo.getUserId(), Date.today());
        Case r = read(c.Id);
        System.assertEquals(true, r.Wiedervorlage_Heute_Offen__c, 'TC1: own Setzer + today must be open');
    }

    /** TC2: eigener Setzer, Datum morgen -> nicht offen (AC1: strikt heute oder Vergangenheit). */
    @isTest
    static void open_mineTomorrow_notOpen() {
        Case c = mkCase('[SCRUM-432] TC2 tomorrow', UserInfo.getUserId(), Date.today().addDays(1));
        Case r = read(c.Id);
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC2: own Setzer + tomorrow must NOT be open (AC1)');
    }

    /** TC3: eigener Setzer, Datum gestern -> offen (Rollover, AC5). */
    @isTest
    static void open_mineYesterday_isOpen() {
        Case c = mkCase('[SCRUM-432] TC3 yesterday', UserInfo.getUserId(), Date.today().addDays(-1));
        Case r = read(c.Id);
        System.assertEquals(true, r.Wiedervorlage_Heute_Offen__c, 'TC3: own Setzer + yesterday must be open (rollover)');
    }

    /** TC4: eigener Setzer, Datum leer -> nicht offen (ISBLANK-Guard). */
    @isTest
    static void open_mineNoDate_notOpen() {
        Case c = mkCase('[SCRUM-432] TC4 no date', UserInfo.getUserId(), null);
        Case r = read(c.Id);
        System.assertEquals(null, r.Wiedervorlage_Datum__c, 'TC4: date must be null');
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC4: own Setzer + null date must NOT be open');
    }

    /** TC5: kein Setzer, Datum heute -> nicht offen. */
    @isTest
    static void open_noSetzer_today_notOpen() {
        Case c = mkCase('[SCRUM-432] TC5 no setzer', null, Date.today());
        Case r = read(c.Id);
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC5: null Setzer + today must NOT be open');
    }

    /** TC6: fremder Setzer, Datum heute -> nicht offen (AC2: persönliche Wiedervorlage, kein Take-over/Claim). */
    @isTest
    static void open_otherSetzerToday_notOpen() {
        Id otherUserId = createOtherUser('sc432v1');
        Case c = mkCase('[SCRUM-432] TC6 other', otherUserId, Date.today());
        Case r = read(c.Id);
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC6: other user + today must NOT be open for me (AC2)');
    }

    /** TC7: fremder Setzer, Datum morgen -> nicht offen (beide Guards schlagen zu). */
    @isTest
    static void open_otherSetzerTomorrow_notOpen() {
        Id otherUserId = createOtherUser('sc432v2');
        Case c = mkCase('[SCRUM-432] TC7 other tomorrow', otherUserId, Date.today().addDays(1));
        Case r = read(c.Id);
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC7: other user + tomorrow must NOT be open');
    }

    /** TC8: fremder Setzer, Datum gestern -> nicht offen (kein Rollover über Users hinweg). */
    @isTest
    static void open_otherSetzerYesterday_notOpen() {
        Id otherUserId = createOtherUser('sc432v3');
        Case c = mkCase('[SCRUM-432] TC8 other yesterday', otherUserId, Date.today().addDays(-1));
        Case r = read(c.Id);
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC8: other user + yesterday must NOT be open for me');
    }

    /** TC9 (AC3): Standard-CRUD auf Datums-, Notiz- und From-Feld; Formel bleibt read-only. */
    @isTest
    static void crud_standardCRUD_onThreeStorageFields() {
        Case c = mkCase('[SCRUM-432] TC9 crud', UserInfo.getUserId(), Date.today());
        c.Wiedervorlage_Datum__c = Date.today().addDays(3);
        c.Wiedervorlage_Notiz__c = 'Anruf an Kunden';
        c.Wiedervorlage_Von__c = createOtherUser('sc432v4');
        update c;

        Case r = read(c.Id);
        System.assertEquals(Date.today().addDays(3), r.Wiedervorlage_Datum__c, 'TC9: date must be updatable');
        System.assertEquals('Anruf an Kunden', r.Wiedervorlage_Notiz__c, 'TC9: note must be updatable');
        System.assertEquals(false, r.Wiedervorlage_Heute_Offen__c, 'TC9: future date -> not open');

        // Alles wieder auf null -> alle drei Pflichtfeld-Null-bar.
        c.Wiedervorlage_Datum__c = null;
        c.Wiedervorlage_Notiz__c = null;
        c.Wiedervorlage_Von__c = null;
        update c;

        r = read(c.Id);
        System.assertEquals(null, r.Wiedervorlage_Datum__c, 'TC9: date must be resettable to null');
        System.assertEquals(null, r.Wiedervorlage_Notiz__c, 'TC9: note must be resettable to null');
        System.assertEquals(null, r.Wiedervorlage_Von__c, 'TC9: von must be resettable to null (SetNull)');

        // Die Formel bleibt read-only: ein DML auf sie muss scheitern.
        c.Wiedervorlage_Heute_Offen__c = true;
        try {
            update c;
            System.assert(false, 'TC9: updating the read-only formula must throw DmlException');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('read-only') || e.getMessage().contains('Read-Only')
                || e.getMessage().contains('read only'),
                'TC9: expected a read-only DmlException, got: ' + e.getMessage());
        }
    }

    /** TC10 (Bulk, ADR-10): 200 Cases in einem Test, 2 DML + 2 SOQL. */
    @isTest
    static void bulk_twoHundredCases_openTodayClosedTomorrow() {
        List<Case> bulk = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            bulk.add(new Case(
                Subject = '[SCRUM-432] bulk ' + i,
                Status = 'New',
                Wiedervorlage_Von__c = UserInfo.getUserId(),
                Wiedervorlage_Datum__c = Date.today()
            ));
        }
        insert bulk;

        Integer openCount = [SELECT COUNT() FROM Case
                             WHERE Wiedervorlage_Heute_Offen__c = true
                             AND Subject LIKE '[SCRUM-432] bulk %'].size();
        System.assertEquals(200, openCount, 'TC10: all 200 own-today cases must be open');

        for (Case c : bulk) {
            c.Wiedervorlage_Datum__c = Date.today().addDays(1);
        }
        update bulk;

        openCount = [SELECT COUNT() FROM Case
                     WHERE Wiedervorlage_Heute_Offen__c = true
                     AND Subject LIKE '[SCRUM-432] bulk %'].size();
        System.assertEquals(0, openCount, 'TC10: after moving to tomorrow none may be open');
    }

    /** Test-Nebenuser auf dem Standard-User-Profil (nur als Von-Referenz). */
    private static Id createOtherUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'SCRUM432 ' + alias,
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u.Id;
    }
}