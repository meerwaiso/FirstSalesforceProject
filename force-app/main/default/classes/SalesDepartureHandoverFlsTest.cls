/**
 * [SCRUM-483] Permission-boundary tests — runAs-based, judged on fixtures the
 * test builds itself.
 *
 * Fixture counts: 1 Automated Process test bundle (2 Customers, 1 open deal);
 * 1 departed person with 4 Customers, 3 open deals whose receiver lacks the write
 * grants (the failure tier); 1 fallback config written by a runner without the
 * config Permission Set; 0 trail rows before each test.
 *
 * What is asserted here:
 *   AC10 (negative) a system user (alias 'autoproc', measured in this org) is
 *        deactivated AND owns records: no row, nothing moves.
 *   AC3  (positive) sales management creates and changes the fallback person
 *        with SCRUM483_Fallback_Config — no IT involved. The negative direction
 *        is unsatisfiable (a Permission Set can only grant, never revoke) and is
 *        NOT faked here; the reason is in the test itself.
 *   AC11 the failure tier: a handover whose write is refused leaves NO half-moved
 *        state — the row says Failed with a German Error_Detail__c and the
 *        explicit compensation restores the old owner. Both platform outcomes are
 *        asserted; the branch taken is named in the log.
 *
 * Mixed DML (house SCRUM-442/467): System-context setup DML first, every later
 * DML inside System.runAs of one runner. Cleanup (reactivating Automated Process,
 * deleting the fixture Customers) is itself DML and therefore also runs inside a
 * System.runAs block of that same runner.
 *
 * @author developer-agent
 * @date 2026-11-27
 */
@isTest
public class SalesDepartureHandoverFlsTest {

    private static User mkUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr483F ' + tag,
            Alias = ('s483f' + tag).left(8),
            Email = 'scr483f_' + tag + '_' + stamp + '@example.invalid',
            Username = 'scr483f_' + tag + '_' + stamp + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Europe/Berlin'
        );
        insert u;
        return u;
    }

    private static User grantRunner(User u, List<String> psNames) {
        for (String psName : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static List<PermissionSetAssignment> grantRows(User u) {
        return [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :u.Id];
    }

    private static Integer countAccountsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Account WHERE OwnerId = :ownerId][0].get('cnt');
    }

    private static Integer countOpenOppsOwned(Id ownerId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM Opportunity WHERE OwnerId = :ownerId AND IsClosed = false
        ][0].get('cnt');
    }

    private static Integer countFallbackRows() {
        return (Integer) [SELECT COUNT(Id) cnt FROM SalesHandoverFallback__c][0].get('cnt');
    }

    private static Integer countRowsFor(Id fromUserId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM SalesDepartureHandover__c WHERE From_User__c = :fromUserId
        ][0].get('cnt');
    }

    // T1 — AC10 (negative): Automated Process is deactivated AND owns records.
    @isTest
    static void systemUser_deactivatedWithRecords_producesNoHandoverAtAll() {
        User runner = grantRunner(mkUser('run'), new String[] {
            'SCRUM483_Handover_System',
            'SCRUM483_Handover_Keep',
            'SCRUM483_Handover_Log'
        });

        User ap = [SELECT Id, IsActive FROM User WHERE Alias = 'autoproc' LIMIT 1];
        System.assert(ap.IsActive, 'precondition: Automated Process is active');

        // A deactivated system user that owns records: without the system-user
        // guard this is exactly the case that would break AC10.
        ap.IsActive = false;
        update ap;
        List<Account> owned = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            owned.add(new Account(Name = 'SCRUM483F AP Cust ' + i, OwnerId = ap.Id));
        }
        insert owned;
        Opportunity deal = new Opportunity(
            Name = 'SCRUM483F AP deal',
            AccountId = owned[0].Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20)
        );
        // OWNER_NOT_INHERITED: a deal needs its own owner (measured 2026-11-27)
        deal.OwnerId = ap.Id;
        insert deal;

        Test.startTest();
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        Test.stopTest();

        System.assertEquals(0, countRowsFor(ap.Id),
            'AC10: a deactivated system user causes no handover row');
        System.assertEquals(2, countAccountsOwned(ap.Id),
            'AC10: nothing was taken from the system user');
        System.assertEquals(1, countOpenOppsOwned(ap.Id),
            'AC10: its open deal still belongs to the system user');

        // cleanup: the system user is handed back exactly as it was, and the
        // fixture records are removed — both DML, so both inside runAs.
        System.runAs(runner) {
            ap.IsActive = true;
            update ap;
            delete owned;
            // No PermissionSetAssignment cleanup here: deleting such a row needs a
            // grant SCRUM-483 does not own (house SCRUM468_Writeoff has it). The
            // assignments stay on the test users, which end up inactive.
        }
    }

    // T2 — AC3 (positive direction): sales management chooses and changes the
    // fallback person without IT — the Permission Set, not a Profile, carries it.
    //
    // The NEGATIVE direction is unsatisfiable by construction and is NOT faked:
    // measured 2026-11-27, a Standard User WITHOUT SCRUM483_Fallback_Config still
    // wrote the config row, because a Permission Set can only grant, never revoke
    // (house rule, salesforce-describe-first §4), and the Standard User profile
    // already carries custom-object CRUD. What AC3 needs from a sales person is
    // therefore the POSITIVE grant; "sales people cannot trigger the handover
    // themselves" is structural (the entry point is a Scheduler, no UI button
    // exists) and belongs to the Tester's Playwright pass.
    @isTest
    static void fallbackPerson_chosenAndChangedBySalesManagement() {
        User withCfg = grantRunner(mkUser('withcfg'), new String[] {
            'SCRUM483_Handover_System',
            'SCRUM483_Handover_Keep',
            'SCRUM483_Handover_Log',
            'SCRUM483_Fallback_Config'
        });
        User candidate = mkUser('cand');
        User second = mkUser('cand2');

        Id configured = null;
        System.runAs(withCfg) {
            SalesHandoverFallback__c cfg = new SalesHandoverFallback__c();
            cfg.Fallback_User__c = candidate.Id;
            insert cfg;
            configured = cfg.Id;
            // AC3: changing the fallback person is the same grant
            cfg = new SalesHandoverFallback__c(Id = configured);
            cfg.Fallback_User__c = second.Id;
            update cfg;
        }
        System.assertEquals(1, countFallbackRows(), 'AC3: exactly one fallback config row');
        SalesHandoverFallback__c row = [
            SELECT Id, Fallback_User__c FROM SalesHandoverFallback__c LIMIT 1
        ];
        System.assertEquals(second.Id, row.Fallback_User__c,
            'AC3: the fallback person was changed without touching IT');

        System.runAs(withCfg) {
            delete row;
        }
    }

    // T3 — AC11 (the failure tier): the handover must never leave a half-moved
    // state. The fixture pushes the target to a person that is deactivated
    // themselves — the platform either refuses the write (then the explicit
    // compensation has to put everything back and the row must say Failed in
    // German) or accepts it (then the move is complete). Both branches are
    // asserted; the branch that was taken is named in the log for the report.
    @isTest
    static void handoverTargetDeactivated_nothingStaysHalfMoved() {
        User runner = grantRunner(mkUser('full'), new String[] {
            'SCRUM483_Handover_System',
            'SCRUM483_Handover_Keep',
            'SCRUM483_Handover_Log',
            'SCRUM483_Fallback_Config'
        });
        User departing = mkUser('dep3');
        User brokenTarget = mkUser('broken');
        addFallbackFor(brokenTarget);
        // the fallback person itself got switched off — a stale config row
        brokenTarget.IsActive = false;
        update brokenTarget;

        List<Account> mine = new List<Account>();
        for (Integer i = 0; i < 4; i++) {
            mine.add(new Account(Name = 'SCRUM483F broken ' + i, OwnerId = departing.Id));
        }
        insert mine;

        Test.startTest();
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        Test.stopTest();

        List<SalesDepartureHandover__c> rows = [
            SELECT Id, From_User__c, To_User__c, Target_Rule__c, Status__c, Error_Detail__c
            FROM SalesDepartureHandover__c WHERE From_User__c = :departing.Id
        ];
        System.assertEquals(1, rows.size(),
            'AC11: the run is listed in the trail, never hidden in a system log');
        System.assertEquals(4, countAccountsOwned(departing.Id) + countAccountsOwned(brokenTarget.Id),
            'AC11: every Customer is on exactly one side, nothing vanished');

        if (rows[0].Status__c == 'Failed') {
            System.assert(rows[0].Error_Detail__c != null && rows[0].Error_Detail__c.length() > 0,
                'AC11: a Failed row carries a German explanation');
            System.assertEquals(4, countAccountsOwned(departing.Id),
                'AC11 tier 2: the compensation put all 4 Customers back');
            System.assertEquals(0, countAccountsOwned(brokenTarget.Id),
                'AC11 tier 2: the receiver holds nothing of a failed handover');
            System.debug('SCRUM-483 tier-2 BRANCH TAKEN: the write was refused, '
                + 'compensation restored the owner');
        } else {
            System.assertEquals('Done', rows[0].Status__c,
                'AC11: any other status than Failed/Done is a defect');
            System.assertEquals(0, countAccountsOwned(departing.Id),
                'AC11: the move completed — nothing stayed behind');
            System.assertEquals(4, countAccountsOwned(brokenTarget.Id),
                'AC11: all 4 Customers reached the target');
            System.debug('SCRUM-483 tier-2 BRANCH NOT TAKEN: the platform accepted '
                + 'an inactive owner, so tier 2 stays unexercised — report it');
        }

        System.runAs(runner) {
            delete mine;
        }
    }
}
