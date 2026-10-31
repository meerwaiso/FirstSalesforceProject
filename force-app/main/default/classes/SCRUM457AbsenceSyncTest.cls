/**
 * SCRUM-457: Apex tests for AbsenceSyncHandler (ships in the same PR as the
 * class it covers).
 *
 * Integration-style: real Absence__c records, real Accounts owned by a test
 * user, the trigger does the propagation — the test asserts on the customer
 * page fields, not on the handler's internals.
 *
 * House findings respected here:
 *  - The CLASS carries @isTest and every test method carries its own @isTest,
 *    otherwise "Tests Ran: 0" without an error.
 *  - ONE bulk insert for a seed batch: two separate insert statements would be
 *    two trigger invocations.
 *  - Inside an Apex test, org-wide SOQL sees only the test's own records.
 *  - No System.runAs in this class: the FLS/visibility proofs (AC4, AC5) belong
 *    to the Tester and need PermissionSetAssignment DML in a separate
 *    transaction (MIXED_DML).
 *  - `end` is a reserved identifier in Apex.
 */
@isTest
private class SCRUM457AbsenceSyncTest {

    private static Profile stdProfile() {
        return [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    }

    private static User mkUser(String alias) {
        Profile p = stdProfile();
        String uName = alias + '457.' + DateTime.now().getTime() + '@example.invalid';
        return new User(
            ProfileId = p.Id,
            LastName = 'Scr457',
            Alias = alias,
            Email = uName,
            Username = uName,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    // Seed: one manager, one deputy, n customers of the manager, one absence.
    // ONE insert per object => ONE trigger invocation per event.
    private static Id[] seed(Integer nAccounts, Date startDate, Date untilWhen) {
        User manager = mkUser('mgr');
        User deputy = mkUser('dep');
        List<User> users = new List<User>{manager, deputy};
        insert users;

        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < nAccounts; i++) {
            accts.add(new Account(Name = 'SCRUM457 Akt ' + i, OwnerId = manager.Id));
        }
        insert accts;

        Absence__c a = new Absence__c(
            Absent_User__c = manager.Id,
            Deputy__c = deputy.Id,
            Start__c = startDate,
            End__c = untilWhen
        );
        insert a;

        Id[] ids = new Id[4];
        ids[0] = manager.Id;
        ids[1] = deputy.Id;
        ids[2] = a.Id;
        ids[3] = accts[0].Id;
        return ids;
    }

    private static List<Account> mirrorOf(Id managerId) {
        return [
            SELECT Id, OwnerId, Absence_Start__c, Absence_End__c, Absence_Deputy__c
            FROM Account
            WHERE OwnerId = :managerId
        ];
    }

    @isTest
    static void activeAbsenceMirrorsEveryCustomer() {
        Date startDate = Date.today();
        Date untilWhen = Date.today().addDays(5);
        Id[] ids = seed(3, startDate, untilWhen);

        Account first = [
            SELECT Id, Absence_Start__c, Absence_End__c, Absence_Deputy__c
            FROM Account WHERE Id = :ids[3] LIMIT 1
        ];
        System.assertEquals(startDate, first.Absence_Start__c, 'start must be mirrored');
        System.assertEquals(untilWhen, first.Absence_End__c, 'end must be mirrored');
        System.assert(first.Absence_Deputy__c != null, 'deputy name must be mirrored');
    }

    @isTest
    static void ownerIdIsNeverWritten() {
        Id[] ids = seed(3, Date.today(), Date.today().addDays(5));

        List<Account> rows = mirrorOf(ids[0]);
        System.assertEquals(3, rows.size(), 'every customer of the manager is found');
        for (Account a : rows) {
            System.assertEquals(ids[0], a.OwnerId, 'AC7: owner unchanged');
        }
    }

    @isTest
    static void changedAbsenceFollowsImmediately() {
        Id[] ids = seed(2, Date.today(), Date.today().addDays(5));

        Absence__c a = [SELECT Id FROM Absence__c WHERE Id = :ids[2] LIMIT 1];
        Date moved = Date.today().addDays(20);
        a.End__c = moved;
        update a;

        for (Account row : mirrorOf(ids[0])) {
            System.assertEquals(moved, row.Absence_End__c, 'AC6: new end follows');
        }
    }

    @isTest
    static void cancelledAbsenceClearsMirror() {
        Id[] ids = seed(2, Date.today(), Date.today().addDays(5));

        Absence__c a = [SELECT Id FROM Absence__c WHERE Id = :ids[2] LIMIT 1];
        delete a;

        for (Account row : mirrorOf(ids[0])) {
            System.assertEquals(null, row.Absence_Start__c, 'AC3: cleared start');
            System.assertEquals(null, row.Absence_End__c, 'AC3: cleared end');
            System.assertEquals(null, row.Absence_Deputy__c, 'AC3: cleared deputy');
        }
    }

    @isTest
    static void latestEndWinsAmongSeveralAbsences() {
        User manager = mkUser('mgr2');
        User deputy = mkUser('dep2');
        List<User> users = new List<User>{manager, deputy};
        insert users;

        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            accts.add(new Account(Name = 'SCRUM457 Two ' + i, OwnerId = manager.Id));
        }
        insert accts;

        List<Absence__c> two = new List<Absence__c>();
        two.add(new Absence__c(
            Absent_User__c = manager.Id, Deputy__c = deputy.Id,
            Start__c = Date.today(), End__c = Date.today().addDays(3)
        ));
        two.add(new Absence__c(
            Absent_User__c = manager.Id, Deputy__c = deputy.Id,
            Start__c = Date.today(), End__c = Date.today().addDays(9)
        ));
        insert two;

        Date latest = Date.today().addDays(9);
        for (Account row : mirrorOf(manager.Id)) {
            System.assertEquals(latest, row.Absence_End__c, 'latest open absence wins');
        }

        List<Absence__c> later = [
            SELECT Id FROM Absence__c WHERE Absent_User__c = :manager.Id AND End__c = :latest
        ];
        delete later;

        Date fallback = Date.today().addDays(3);
        for (Account row : mirrorOf(manager.Id)) {
            System.assertEquals(fallback, row.Absence_End__c, 'falls back to the remaining absence');
        }
    }

    @isTest
    static void endedAbsenceIsNotMirrored() {
        Id[] ids = seed(2, Date.today().addDays(-10), Date.today().addDays(-1));
        for (Account row : mirrorOf(ids[0])) {
            System.assertEquals(null, row.Absence_End__c, 'AC3: past absence shows nothing');
        }
    }

    @isTest
    static void bulkStaysWithinGovernorLimits() {
        Id[] ids = seed(50, Date.today(), Date.today().addDays(4));
        System.assertEquals(50, mirrorOf(ids[0]).size(), 'all 50 customers mirrored');
    }
}
