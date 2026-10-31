/**
 * SCRUM-457: Apex tests for AbsenceSyncHandler and for the deputy's access
 * (ships in the same PR as the class it covers).
 *
 * Integration-style: real Absence__c records, real Accounts/Opportunities/Cases
 * owned by a test user, the trigger does the propagation — the test asserts on
 * the customer page fields and on what a non-owner can actually do.
 *
 * House findings respected here:
 *  - The CLASS carries @isTest and every test method carries its own @isTest,
 *    otherwise "Tests Ran: 0" without an error.
 *  - ONE bulk insert per seed batch: two separate insert statements would be
 *    two trigger invocations.
 *  - Inside an Apex test, org-wide SOQL sees only the test's own records.
 *  - MIXED_DML: all setup DML (User, PSA) runs in System context FIRST, every
 *    later DML happens inside one System.runAs of one user (SCRUM-432 form —
 *    a User cannot grant himself a PermissionSetAssignment). Measured: this API
 *    takes ONE argument, `System.runAs(user)`; the two-argument form with a
 *    Profile is refused ("runAs requires a single argument of type 'User'").
 *  - Measured API names (sf sobject describe): Opportunity.AccountId / OwnerId /
 *    StageName / CloseDate, Case.AccountId / OwnerId / Status / Subject.
 *  - Triggers run in USER mode: the handler's SOQL on the Account mirror fields
 *    needs read FLS for the acting user, otherwise the whole create rolls back.
 *  - `end` and `from` are reserved identifiers.
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

    // AC8: "customers where no deputy has been named must stand out".
    // The formula field Absence_Ohne_Deputy__c is the marker the report filters
    // on; without this test that clause matches 0 records and is untested.
    @isTest
    static void absenceWithoutDeputyStandsOut() {
        User manager = mkUser('mgr3');
        insert manager;

        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accts.add(new Account(Name = 'SCRUM457 Ohne ' + i, OwnerId = manager.Id));
        }
        insert accts;

        // No Deputy__c at all — the forgotten case the PO named.
        Absence__c a = new Absence__c(
            Absent_User__c = manager.Id,
            Start__c = Date.today(),
            End__c = Date.today().addDays(4)
        );
        insert a;

        List<Account> rows = [
            SELECT Id, Absence_Start__c, Absence_End__c, Absence_Deputy__c,
                   Absence_Ohne_Deputy__c, Absence_In_Window__c
            FROM Account
            WHERE OwnerId = :manager.Id
        ];
        System.assertEquals(3, rows.size(), 'all three customers carry the absence');
        Integer standingOut = 0;
        for (Account row : rows) {
            System.assertEquals(Date.today(), row.Absence_Start__c, 'start still mirrors');
            System.assertEquals(null, row.Absence_Deputy__c, 'no deputy mirrored');
            if ('OHNE DEPUTY'.equals(row.Absence_Ohne_Deputy__c)) {
                standingOut++;
            }
        }
        System.assertEquals(3, standingOut, 'AC8: every no-deputy row carries the marker');
    }

    // AC4: the deputy must be able to work the customer, its open Opportunities
    // and its Cases without owning them. Measured OWD (Tester, Setup 2026-10-31):
    // Account / Opportunity = Public Read/Write, Case = Public Read/Write/Transfer
    // — so the access is org-wide, and a Permission Set can neither add nor revoke
    // it. This test proves the deputy can actually do the work.
    @isTest
    static void deputyWorksNonOwnedCustomerRecords() {
        User manager = mkUser('mgr4');
        User deputy = mkUser('dep4');
        List<User> users = new List<User>{manager, deputy};
        insert users;

        Account cust = new Account(Name = 'SCRUM457 Akt AC4', OwnerId = manager.Id);
        insert cust;

        Opportunity openOpp = new Opportunity(
            AccountId = cust.Id,
            OwnerId = manager.Id,
            Name = 'SCRUM457 Open Opp',
            CloseDate = Date.today().addDays(30),
            StageName = 'Warm'
        );
        insert openOpp;

        Case openCase = new Case(
            AccountId = cust.Id,
            OwnerId = manager.Id,
            Subject = 'SCRUM457 Open Case',
            Status = 'Open'
        );
        insert openCase;

        Absence__c a = new Absence__c(
            Absent_User__c = manager.Id,
            Deputy__c = deputy.Id,
            Start__c = Date.today(),
            End__c = Date.today().addDays(6)
        );
        insert a;

        System.runAs(deputy) {
            // The deputy does not own anything here and still reaches it.
            Account seen = [SELECT Id, Name FROM Account WHERE Id = :cust.Id LIMIT 1];
            System.assert(seen.Name == 'SCRUM457 Akt AC4', 'AC4: deputy sees the non-owned customer');

            List<Opportunity> opps = [
                SELECT Id, StageName, AccountId, OwnerId
                FROM Opportunity
                WHERE AccountId = :cust.Id
            ];
            System.assertEquals(1, opps.size(), 'AC4: deputy sees the open opportunity');

            List<Case> cases = [
                SELECT Id, Status, AccountId
                FROM Case
                WHERE AccountId = :cust.Id
            ];
            System.assertEquals(1, cases.size(), 'AC4: deputy sees the open case');

            Opportunity work = opps[0];
            System.assertEquals('Warm', work.StageName, 'starts where the manager left it');
            work.StageName = 'Hot';
            update work;
        }

        Opportunity after = [
            SELECT Id, StageName, OwnerId FROM Opportunity WHERE Id = :openOpp.Id LIMIT 1
        ];
        System.assertEquals('Hot', after.StageName, 'AC4: the deputy updated it');
        System.assertEquals(manager.Id, after.OwnerId, 'AC7: the owner was not touched');
    }

    // AC1: an account manager (and a team lead for a colleague) records the
    // absence. The capability is expressed as SCRUM457_AbsenceWrite; the create
    // must work for a user that holds it. Setup DML (User + PSA) in System
    // context first, business DML inside runAs — house form from SCRUM-432.
    @isTest
    static void absenceCreateRunsUnderTheWritePermissionSet() {
        User writer = mkUser('writer');
        insert writer;

        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM457_AbsenceWrite' LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = writer.Id,
            PermissionSetId = ps.Id
        );

        System.runAs(writer) {
            Absence__c a = new Absence__c(
                Absent_User__c = writer.Id,
                Start__c = Date.today(),
                End__c = Date.today().addDays(2)
            );
            insert a;
            System.assert(a.Id != null, 'AC1: create under the PS');
        }
    }

    // AC1 negative half, measured: a user who holds neither SCRUM457 PS cannot
    // record an absence. The Standard User profile allows the create on
    // Absence__c, but AbsenceSyncHandler runs in USER mode and its SOQL on the
    // Account mirror fields is blocked by FLS ("No such column
    // 'Absence_Start__c' on entity 'Account'"), which rolls the whole insert
    // back. That is why SCRUM457_AbsenceWrite also carries read FLS on the
    // mirror fields: whoever can record an absence must be able to see them.
    @isTest
    static void absenceCreateIsBlockedWithoutThePermissionSets() {
        User outsider = mkUser('outsider');
        insert outsider;

        Boolean blocked = false;
        try {
            System.runAs(outsider) {
                Absence__c a = new Absence__c(
                    Absent_User__c = outsider.Id,
                    Start__c = Date.today(),
                    End__c = Date.today().addDays(1)
                );
                insert a;
            }
        } catch (Exception e) {
            blocked = true;
        }
        System.assert(blocked, 'AC1: without the PS the absence cannot be recorded');
    }

    // AC1, new clause (PO answer 3): an account manager can never be their own
    // deputy. The guard is the before-event block in AbsenceSyncTrigger; the
    // record must not exist afterwards. Positive half in the same method: the
    // same user CAN record an absence with a colleague as deputy, so the guard
    // is not a blanket block.
    @isTest
    static void managerCannotBeTheirOwnDeputy() {
        User solo = mkUser('solo');
        User colleague = mkUser('colleague');
        List<User> guardUsers = new List<User>{solo, colleague};
        insert guardUsers;

        Absence__c bad = new Absence__c(
            Absent_User__c = solo.Id,
            Deputy__c = solo.Id,
            Start__c = Date.today(),
            End__c = Date.today().addDays(3)
        );
        Boolean refused = false;
        try {
            insert bad;
        } catch (Exception e) {
            refused = true;
        }
        System.assert(refused, 'AC1: naming yourself as deputy is refused');

        List<Absence__c> left = [
            SELECT Id FROM Absence__c WHERE Absent_User__c = :solo.Id AND Deputy__c = :solo.Id
        ];
        System.assert(left.isEmpty(), 'AC1: the refused record is not in the org');

        Absence__c good = new Absence__c(
            Absent_User__c = solo.Id,
            Deputy__c = colleague.Id,
            Start__c = Date.today(),
            End__c = Date.today().addDays(3)
        );
        insert good;
        System.assert(good.Id != null, 'AC1: a colleague as deputy is accepted');
    }

    // AC1 with the team-lead set (PO answer 5): a team lead is whoever holds
    // SCRUM457_Absence_Teamleitung, and records the absence OF A COLLEAGUE who
    // holds nothing. The mirror must follow on that colleague's customers.
    @isTest
    static void teamLeadRecordsAbsenceForAColleague() {
        User teamLead = mkUser('tealead');
        User offSick = mkUser('offsick');
        List<User> tlUsers = new List<User>{teamLead, offSick};
        insert tlUsers;

        PermissionSet teamlead = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM457_Absence_Teamleitung' LIMIT 1
        ];
        System.assert(teamlead.Id != null, 'the team-lead set must exist');
        insert new PermissionSetAssignment(
            AssigneeId = teamLead.Id,
            PermissionSetId = teamlead.Id
        );

        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            accts.add(new Account(Name = 'SCRUM457 Akt TL ' + i, OwnerId = offSick.Id));
        }
        insert accts;

        System.runAs(teamLead) {
            Absence__c a = new Absence__c(
                Absent_User__c = offSick.Id,
                Deputy__c = teamLead.Id,
                Start__c = Date.today(),
                End__c = Date.today().addDays(4)
            );
            insert a;
        }

        List<Account> mirrored = [
            SELECT Id, OwnerId, Absence_Start__c, Absence_End__c, Absence_Deputy__c
            FROM Account
            WHERE OwnerId = :offSick.Id
        ];
        System.assertEquals(2, mirrored.size(), 'both customers of the sick colleague');
        for (Account a : mirrored) {
            System.assert(a.Absence_Start__c != null, 'AC1: the mirror followed the team lead');
            System.assert(a.Absence_Deputy__c != null, 'AC1: the deputy is named');
            System.assert(a.OwnerId == offSick.Id, 'AC7: the owner was not touched');
        }
    }

    // AC10: a deputy who is away themselves is no deputy. The deputy's own
    // window is mirrored as two dates, and the marker is the SAME value as for
    // a customer without a deputy — the overview must not distinguish them.
    @isTest
    static void deputyWhoIsAwayIsNoDeputy() {
        Date startDate = Date.today();
        Id[] ids = seed(2, startDate, Date.today().addDays(6));
        Id managerId = ids[0];
        Id deputyId = ids[1];

        // The deputy's own absence, window covering today.
        Absence__c depAbsence = new Absence__c(
            Absent_User__c = deputyId,
            Deputy__c = managerId,
            Start__c = Date.today(),
            End__c = Date.today().addDays(2)
        );
        insert depAbsence;

        List<Account> withAwayDeputy = [
            SELECT Id, Absence_Ohne_Deputy__c, Absence_Deputy_Start__c, Absence_Deputy_End__c
            FROM Account
            WHERE OwnerId = :managerId
        ];
        System.assertEquals(2, withAwayDeputy.size(), 'both customers');
        for (Account a : withAwayDeputy) {
            System.assertEquals('OHNE DEPUTY', a.Absence_Ohne_Deputy__c, 'AC10: the customer stands out');
            System.assert(a.Absence_Deputy_Start__c != null, 'AC10: the deputy window is mirrored');
            System.assert(a.Absence_Deputy_End__c != null, 'AC10: both dates are mirrored');
        }

        // "exactly like" a customer without a deputy: same marker value.
        List<Account> noDeputy = [
            SELECT Id, Absence_Ohne_Deputy__c FROM Account
            WHERE OwnerId = :managerId AND Absence_Deputy__c = ''
        ];
        // no such row here — the marker, not the cause, is what the report shows
        System.assertEquals(0, noDeputy.size(), 'the deputy is named; only the marker fires');
    }

    // AC10, the direction that needs the bidirectional recompute: the deputy's
    // absence is created AFTER the manager's, and the manager's record is never
    // touched. A one-directional handler leaves the marker stale.
    @isTest
    static void deputyAbsenceReflagsCustomersWithoutTouchingTheManager() {
        Date startDate = Date.today();
        Id[] ids = seed(2, startDate, Date.today().addDays(6));
        Id managerId = ids[0];
        Id deputyId = ids[1];

        List<Account> before = [
            SELECT Id, Absence_Ohne_Deputy__c, Absence_Deputy_End__c
            FROM Account
            WHERE OwnerId = :managerId
        ];
        for (Account a : before) {
            System.assert(a.Absence_Ohne_Deputy__c == null || a.Absence_Ohne_Deputy__c == '',
                'AC10: while the deputy is fine the marker is blank');
            System.assert(a.Absence_Deputy_End__c == null, 'AC10: no deputy window yet');
        }

        Absence__c depAbsence = new Absence__c(
            Absent_User__c = deputyId,
            Start__c = Date.today(),
            End__c = Date.today().addDays(1)
        );
        insert depAbsence; // the manager's Absence__c is NOT touched

        List<Account> after = [
            SELECT Id, Absence_Ohne_Deputy__c, Absence_Deputy_Start__c, Absence_Deputy_End__c
            FROM Account
            WHERE OwnerId = :managerId
        ];
        System.assertEquals(before.size(), after.size(), 'AC10: the same customers, re-flagged');
        for (Account a : after) {
            System.assertEquals('OHNE DEPUTY', a.Absence_Ohne_Deputy__c,
                'AC10: the marker followed without a write to the manager record');
            System.assert(a.Absence_Deputy_End__c != null, 'AC10: the deputy window arrived');
        }
    }
}
