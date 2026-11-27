/**
 * [SCRUM-483] Behaviour of the Sales-Austritt-Uebergabe — judged on fixtures the
 * test builds itself, never on the org's data.
 *
 * Fixture counts (they belong in every artefact, AGENTS.md):
 *   1 departed sales person: 4 Customers, 3 OPEN Opportunities, 2 CLOSED Opportunities
 *   circular manager pair (AC7): 4 Customers + 1 open deal each, mapped to each other
 *   AC4/AC12 run: 4 Customers + 2 open + 1 closed (mapped, no manager),
 *                  4 Customers + 2 open (no mapping row at all)
 *   before each test: 0 fallback rows, 0 trail rows for these users
 *   Measured Test-Org volumes (read-back 2026-11-27): 8 Users, 268 Accounts,
 *   89 open Opportunities, 2 mapping rows, 0 fallback rows, 0 trail rows.
 *
 * What is asserted here:
 *   AC1  every Customer and every OPEN deal of the departed person moves — the
 *        counts are asserted, not a sample.
 *   AC5  closed / Won / Lost deals keep the person who worked on them.
 *   AC6  only Owner and the provenance fields change (content snapshot before/after).
 *   AC8/AC9 one trail row per person and run, carrying counts, rule and provenance.
 *   AC7  circular mapping + both persons deactivated in ONE run -> BOTH get the
 *        fallback person, Target_Rule__c=Fallback.
 *   AC10 a deactivated person who owns nothing: no move, no row.
 *   AC12 a sales person forgotten in the mapping: nothing moves, Blocked row.
 *   idempotency: a second scheduler run touches 0 rows (house SCRUM-388/417).
 *
 * NOT asserted here: the ONE-HOUR window of AC2. The detection is a Scheduler
 * (no hook exists on a user deactivation), the CRON entry is an org step — a test
 * cannot observe that cadence. It is measured in the release read-back
 * (@devops-agent) and stated in the release note in plain words (PO, comment
 * 23891). Calling this "assumed" would be a lie: it is simply not covered here.
 *
 * Mixed DML (house SCRUM-442/467): User, PermissionSetAssignment, mapping rows,
 * fallback rows, Account and Opportunity fixtures are System-context setup DML and
 * come FIRST. Every later DML (the deactivation, the handover, the cleanup) runs
 * inside System.runAs of one runner that carries the four SCRUM-483 Permission
 * Sets — the same bundle the scheduled user of the org carries.
 *
 * @author developer-agent
 * @date 2026-11-27
 */
@isTest
public class SalesDepartureHandoverTest {

    private static final Integer ACCOUNTS = 4;
    private static final Integer OPEN_OPPS = 3;
    private static final Integer CLOSED_OPPS = 2;

    private static User mkUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr483 ' + tag,
            Alias = ('s483' + tag).left(8),
            Email = 'scr483_' + tag + '_' + stamp + '@example.invalid',
            Username = 'scr483_' + tag + '_' + stamp + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Europe/Berlin'
        );
        insert u;
        return u;
    }

    /** The runner carries exactly the bundle the org's scheduled user carries. */
    private static User mkRunner(String tag) {
        User u = mkUser(tag);
        for (String psName : new String[] {
            'SCRUM483_Handover_System',
            'SCRUM483_Handover_Keep',
            'SCRUM483_Handover_Log',
            'SCRUM483_Fallback_Config'
        }) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static void addMappingRow(Id repId, Id managerId) {
        DiscountApprovalManager__c row = new DiscountApprovalManager__c();
        row.Rep__c = repId;
        if (managerId != null) {
            row.Manager__c = managerId;
        }
        insert row;
    }

    private static void addFallbackRow(Id fallbackId) {
        SalesHandoverFallback__c cfg = new SalesHandoverFallback__c();
        cfg.Fallback_User__c = fallbackId;
        insert cfg;
    }

    private static List<Account> seedAccounts(Id ownerId) {
        List<Account> records = new List<Account>();
        for (Integer i = 0; i < ACCOUNTS; i++) {
            records.add(new Account(Name = 'SCRUM483 Cust ' + i, OwnerId = ownerId));
        }
        insert records;
        return records;
    }

    private static void seedOpportunities(Id accountId, Id ownerId, Integer open,
                                          Integer closed) {
        for (Integer i = 0; i < open; i++) {
            Opportunity deal = new Opportunity(
                Name = 'SCRUM483 open ' + i,
                AccountId = accountId,
                StageName = 'Prospecting',
                Amount = 1000.00 + i,
                CloseDate = Date.today().addDays(30)
            );
            // OWNER_NOT_INHERITED: a deal needs its own owner (measured)
            deal.OwnerId = ownerId;
            insert deal;
        }
        for (Integer i = 0; i < closed; i++) {
            Opportunity done = new Opportunity(
                Name = 'SCRUM483 closed ' + i,
                AccountId = accountId,
                StageName = 'Closed Won',
                Amount = 2000.00 + i,
                CloseDate = Date.today().addDays(-5)
            );
            done.OwnerId = ownerId;
            insert done;
        }
    }

    private static Integer countAccountsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Account WHERE OwnerId = :ownerId][0].get('cnt');
    }

    private static Integer countOpenOppsOwned(Id ownerId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM Opportunity
            WHERE OwnerId = :ownerId AND IsClosed = false
        ][0].get('cnt');
    }

    private static Integer countClosedOppsOwned(Id ownerId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM Opportunity
            WHERE OwnerId = :ownerId AND IsClosed = true
        ][0].get('cnt');
    }

    private static Integer countRowsFor(Id fromUserId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM SalesDepartureHandover__c WHERE From_User__c = :fromUserId
        ][0].get('cnt');
    }

    // T1 — AC1 / AC5 / AC6 / AC8 / AC9 and idempotency on one departed person.
    @isTest
    static void departedSalesPerson_movesCustomersAndOpenDeals_closedStay() {
        User runner = mkRunner('run');
        User departing = mkUser('dep');
        User manager = mkUser('mgr');
        addMappingRow(departing.Id, manager.Id);
        List<Account> accountRecords = seedAccounts(departing.Id);
        seedOpportunities(accountRecords[0].Id, departing.Id, OPEN_OPPS, CLOSED_OPPS);

        // AC6 before-snapshot: the content of every in-scope record.
        Map<Id, String> customerBefore = new Map<Id, String>();
        for (Account a : [
            SELECT Id, Name, OwnerId, Description FROM Account WHERE OwnerId = :departing.Id
        ]) {
            customerBefore.put(a.Id, a.Name + '|' + (a.Description == null ?
                    '' : a.Description));
        }
        Map<Id, String> dealBefore = new Map<Id, String>();
        for (Opportunity o : [
            SELECT Id, Name, OwnerId, Amount, CloseDate, StageName, Description
            FROM Opportunity WHERE OwnerId = :departing.Id
        ]) {
            dealBefore.put(o.Id, o.Name + '|' + o.Amount + '|' + o.CloseDate + '|' + o.StageName
                + '|' + (o.Description == null ? '' : o.Description));
        }

        // AC11: IT deactivates the person — a System-context action, and the
        // handover never writes a User field, so this save cannot fail.
        departing.IsActive = false;
        update departing;

        Test.startTest();
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        Test.stopTest();

        // AC1: everything of the departed person that may move, moved.
        System.assertEquals(0, countAccountsOwned(departing.Id),
            'AC1: alle 4 Customers moved away from the departed person');
        System.assertEquals(ACCOUNTS, countAccountsOwned(manager.Id),
            'AC1: alle 4 Customers now owned by the manager');
        System.assertEquals(0, countOpenOppsOwned(departing.Id),
            'AC1: alle 3 open Opportunities moved');
        System.assertEquals(OPEN_OPPS, countOpenOppsOwned(manager.Id),
            'AC1: 3 open Opportunities at the manager');

        // AC5: closed / Won / Lost keep their person.
        System.assertEquals(CLOSED_OPPS, countClosedOppsOwned(departing.Id),
            'AC5: the 2 closed deals still belong to the departed person');
        System.assertEquals(0, countClosedOppsOwned(manager.Id),
            'AC5: the manager received no closed history');

        // AC8/AC9: exactly one trail row, carrying the counts of the run.
        List<SalesDepartureHandover__c> rows = [
            SELECT Id, From_User__c, To_User__c, Target_Rule__c, Deactivation_Evidence__c,
                   Status__c, Accounts_Handed_Over__c,
                   Open_Opportunities_Handed_Over__c, Closed_Opportunities_Kept__c,
                   Handed_Over_At__c
            FROM SalesDepartureHandover__c WHERE From_User__c = :departing.Id
        ];
        System.assertEquals(1, rows.size(), 'AC8: exactly one trail row for the departed person');
        SalesDepartureHandover__c row = rows[0];
        System.assertEquals(manager.Id, row.To_User__c, 'AC8: the row names the receiver');
        System.assertEquals('Manager', row.Target_Rule__c,
            'AC2: the mapped manager is the target, rule Manager');
        System.assertEquals('IsActive_false', row.Deactivation_Evidence__c,
            'AC11: the row says how the system found the person');
        System.assertEquals('Done', row.Status__c, 'AC8: the run completed');
        System.assertEquals(ACCOUNTS, row.Accounts_Handed_Over__c, 'AC9: 4 Customers handed over');
        System.assertEquals(OPEN_OPPS, row.Open_Opportunities_Handed_Over__c,
            'AC9: 3 open Opportunities handed over');
        System.assertEquals(CLOSED_OPPS, row.Closed_Opportunities_Kept__c,
            'AC9: 2 closed deals counted as kept, not moved');
        System.assertNotEquals(null, row.Handed_Over_At__c, 'AC9: the row says when');

        // AC9: the receiver sees the records plus from whom and when.
        List<Account> moved = [
            SELECT Id, Name, OwnerId, Description, Handed_Over_From__c, Handed_Over_On__c,
                   Handover_Run__c
            FROM Account WHERE OwnerId = :manager.Id
        ];
        System.assertEquals(ACCOUNTS, moved.size(), 'AC9: the manager sees its 4 Customers');
        for (Account a : moved) {
            System.assertEquals(departing.Id, a.Handed_Over_From__c,
                'AC9: every moved Customer says which person it came from');
            System.assertNotEquals(null, a.Handed_Over_On__c,
                'AC9: every moved Customer says when it was handed over');
            System.assertEquals(row.Id, a.Handover_Run__c,
                'AC8: the provenance points at the trail row of this run');
            System.assert(customerBefore.containsKey(a.Id),
                'AC6: this Customer was in the before-snapshot');
            System.assertEquals(customerBefore.get(a.Id),
                a.Name + '|' + (a.Description == null ? '' : a.Description),
                'AC6: only Owner and the provenance fields changed on this Customer');
        }

        List<Opportunity> movedDeals = [
            SELECT Id, Name, OwnerId, Description, Amount, CloseDate, StageName,
                   Handed_Over_From__c, Handed_Over_On__c, Handover_Run__c
            FROM Opportunity WHERE OwnerId = :manager.Id
        ];
        System.assertEquals(OPEN_OPPS, movedDeals.size(), 'AC9: 3 open deals at the manager');
        for (Opportunity o : movedDeals) {
            System.assertEquals(departing.Id, o.Handed_Over_From__c,
                'AC9: the deal says which person worked on it before');
            System.assertEquals(row.Id, o.Handover_Run__c,
                'AC8: the deal points at the trail row');
            System.assertEquals(dealBefore.get(o.Id),
                o.Name + '|' + o.Amount + '|' + o.CloseDate + '|' + o.StageName
                    + '|' + (o.Description == null ? '' : o.Description),
                'AC6: only Owner and the provenance fields changed on the deal');
            System.assertEquals('Prospecting', o.StageName,
                'AC6: the stage of a moved deal is untouched');
        }

        // AC5/AC6: the closed deals keep owner, content AND no provenance.
        List<Opportunity> kept = [
            SELECT Id, Name, OwnerId, Description, Amount, CloseDate, StageName,
                   Handed_Over_From__c, Handed_Over_On__c, Handover_Run__c
            FROM Opportunity WHERE OwnerId = :departing.Id
        ];
        System.assertEquals(CLOSED_OPPS, kept.size(), 'AC5: the 2 closed deals are untouched');
        for (Opportunity o : kept) {
            System.assertEquals(null, o.Handed_Over_From__c,
                'AC6: a closed deal gets no provenance, it never moved');
            System.assertEquals(null, o.Handover_Run__c,
                'AC6: a closed deal carries no run pointer');
            System.assertEquals(dealBefore.get(o.Id),
                o.Name + '|' + o.Amount + '|' + o.CloseDate + '|' + o.StageName
                    + '|' + (o.Description == null ? '' : o.Description),
                'AC5: the closed deal is bit-for-bit unchanged');
        }

        // idempotency: a second run over the same state touches nothing.
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        System.assertEquals(1, countRowsFor(departing.Id),
            'idempotency: the second run added no row (house SCRUM-388/417)');
        System.assertEquals(ACCOUNTS, countAccountsOwned(manager.Id),
            'idempotency: nothing moved a second time');

        // cleanup: the fixtures leave no Customers behind (they cascade to their deals).
        System.runAs(runner) {
            delete accountRecords;
        }
    }

    // T2 — AC7: the circular mapping the org really carries, both persons off.
    @isTest
    static void circularPair_bothPersonsReceiveTheFallbackPerson() {
        User runner = mkRunner('run2');
        User pairA = mkUser('pa');
        User pairB = mkUser('pb');
        User fallback = mkUser('fb2');
        addMappingRow(pairA.Id, pairB.Id);
        addMappingRow(pairB.Id, pairA.Id);
        addFallbackRow(fallback.Id);
        List<Account> accountsA = seedAccounts(pairA.Id);
        List<Account> accountsB = seedAccounts(pairB.Id);
        seedOpportunities(accountsA[0].Id, pairA.Id, 1, 0);
        seedOpportunities(accountsB[0].Id, pairB.Id, 1, 0);

        pairA.IsActive = false;
        pairB.IsActive = false;
        update new List<User>{ pairA, pairB };

        Test.startTest();
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        Test.stopTest();

        System.assertEquals(0, countAccountsOwned(pairA.Id), 'AC7: nothing stays at person A');
        System.assertEquals(0, countAccountsOwned(pairB.Id), 'AC7: nothing stays at person B');
        System.assertEquals(ACCOUNTS * 2, countAccountsOwned(fallback.Id),
            'AC7: the Customers of both persons end up at the fallback person');
        System.assertEquals(2, countOpenOppsOwned(fallback.Id),
            'AC7: both open deals end up at the fallback person');

        List<SalesDepartureHandover__c> rows = [
            SELECT Id, From_User__c, To_User__c, Target_Rule__c, Status__c
            FROM SalesDepartureHandover__c
            WHERE From_User__c IN :new Set<Id>{ pairA.Id, pairB.Id }
        ];
        System.assertEquals(2, rows.size(), 'AC7: one row per deactivated person');
        for (SalesDepartureHandover__c row : rows) {
            System.assertEquals(fallback.Id, row.To_User__c,
                'AC7: the mapped manager is himself deactivated in this run -> fallback');
            System.assertEquals('Fallback', row.Target_Rule__c,
                'AC7: the row names the rule that gave the target');
            System.assertEquals('Done', row.Status__c, 'AC7: both handovers completed');
        }

        System.runAs(runner) {
            delete accountsA;
            delete accountsB;
        }
    }

    // T3 — AC4 (mapped, manager field empty, no fallback row) and AC12 (no mapping
    // row = entry mistake): Blocked, visible, nothing moves. AC10: owns nothing.
    @isTest
    static void noManagerNoFallback_and_missingMappingRow_stayBlockedAndVisible() {
        User runner = mkRunner('run3');
        User mapped = mkUser('mp');
        User forgotten = mkUser('fg');
        User ownerless = mkUser('ownerless'); // deactivated, owns nothing (AC10)

        addMappingRow(mapped.Id, null); // the row exists, the manager column is empty
        List<Account> mappedAccounts = seedAccounts(mapped.Id);
        seedOpportunities(mappedAccounts[0].Id, mapped.Id, 2, 1);
        List<Account> forgottenAccounts = seedAccounts(forgotten.Id);
        seedOpportunities(forgottenAccounts[0].Id, forgotten.Id, 2, 0);

        mapped.IsActive = false;
        forgotten.IsActive = false;
        ownerless.IsActive = false;
        update new List<User>{ mapped, forgotten, ownerless };

        Test.startTest();
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        Test.stopTest();

        // nothing moved
        System.assertEquals(ACCOUNTS, countAccountsOwned(mapped.Id),
            'AC4: no Customer left the person without a manager');
        System.assertEquals(ACCOUNTS, countAccountsOwned(forgotten.Id),
            'AC12: the forgotten salesperson still owns his Customers');
        System.assertEquals(2, countOpenOppsOwned(mapped.Id), 'AC4: open deals unchanged');
        System.assertEquals(1, countClosedOppsOwned(mapped.Id), 'AC4: the closed deal unchanged');
        System.assertEquals(2, countOpenOppsOwned(forgotten.Id), 'AC12: open deals unchanged');

        // visible in the one tab, not hidden in a system log
        List<SalesDepartureHandover__c> rows = [
            SELECT Id, From_User__c, Target_Rule__c, Status__c, Info__c
            FROM SalesDepartureHandover__c
            WHERE From_User__c IN :new Set<Id>{ mapped.Id, forgotten.Id }
        ];
        System.assertEquals(2, rows.size(),
            'AC4/AC12: both cases are listed in the same one place');
        for (SalesDepartureHandover__c row : rows) {
            System.assertEquals('Blocked', row.Status__c, 'AC4/AC12: the row says Blocked');
            System.assertEquals('None', row.Target_Rule__c, 'AC4/AC12: no rule applied');
            System.assert(row.Info__c != null,
                'AC4/AC12: the row carries a German explanation of the alarm');
        }

        // AC10: a deactivated person who owns nothing produces no row at all
        System.assertEquals(0, countRowsFor(ownerless.Id),
            'AC10: no handover and no row for a person without records');

        System.runAs(runner) {
            delete mappedAccounts;
            delete forgottenAccounts;
        }
    }
}
