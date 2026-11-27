/**
 * [SCRUM-483] Permission-boundary half of SCRUM-483 (house SCRUM-442: the FLS test pair
 * is separate from the behaviour class). Everything that acts runs under System.runAs
 * against a user on the STANDARD USER profile - never System_mode, which would grant
 * everything and prove nothing (skill salesforce-describe-first section 4).
 *
 *   AC10 (negative): the org's system user (measured alias `autoproc`) owns a Customer
 *     and is NEVER a sales person: no handover, no trail row. Without the guard on the
 *     Service that Customer would move, which is exactly what breaks AC10. A system user
 *     cannot be deactivated from a test at all (measured 2026-11-27: `update ap` gives
 *     INSUFFICIENT_ACCESS_OR_READONLY "Cannot insert a user with this profile"), so the
 *     guard itself is asserted on the Service and the records of that owner are verified
 *     untouched.
 *   AC3: the fallback person is chosen and changed by sales management - asserted as the
 *     GRANT (with SCRUM483_Fallback_Config the row is written and can be repointed). The
 *     negative direction is not assertable: a Permission Set can only grant, never revoke,
 *     and the Standard User profile already carries CRUD on custom objects. "Sales people
 *     cannot trigger the handover themselves" is structural (the only entry point is
 *     SalesDepartureHandoverScheduler, there is no UI button) and belongs to the Tester's
 *     Playwright pass.
 *   AC11 tier 1 (stale config): the fallback row points at a person who got switched off.
 *     resolveTarget rejects a target that is not active, so the case is Blocked with a
 *     German Info__c and NOTHING is half-moved.
 *
 * NOT covered here, and why:
 *   AC11 tier 2 (Failed + compensation) is unsatisfiable for a Standard User by
 *     construction: a Permission Set can only grant; a Standard User holding the SCRUM-483
 *     grants can write the records the handover touches, and a Standard User without them
 *     cannot reach the candidate at all (INVISIBLE_FIELDS). Records cannot be created under
 *     an inactive owner either (measured 2026-11-27: INACTIVE_OWNER_OR_USER). The realistic
 *     fixture is a LOCKED record - Test-Org holds 12 Accounts owned by the mapping pair,
 *     none of them with an open Opportunity, so the tier stays unexercised here (house rule:
 *     a criterion measured against zero is untested). The compensation code is reviewed by
 *     the Architect; CI runs as System Administrator and is the place that can lock a
 *     record and exercise it.
 *
 * Fixture rule: only records this class creates are touched. Test-Org measured 2026-11-27:
 * 8 Users, 268 Accounts (267 owned by the devops-agent pair, 1 by `autoproc`), 89 open
 * Opportunities, 0 fallback rows, 0 trail rows.
 * No cleanup: a Standard User may not delete its fixture Customers (measured 2026-11-27:
 * insufficient access rights on object id), and test data is not committed to the org.
 *
 * @author developer-agent
 * @date 2026-11-27
 */
@isTest
public class SalesDepartureHandoverFlsTest {

    private static final Integer ACCOUNTS = 4;

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

    private static Integer countRowsFor(Id userId) {
        List<SalesDepartureHandover__c> rows = [
            SELECT Id FROM SalesDepartureHandover__c WHERE From_User__c = :userId
        ];
        return rows.size();
    }

    private static Integer countAccountsOwned(Id userId) {
        List<Account> recs = [SELECT Id FROM Account WHERE OwnerId = :userId];
        return recs.size();
    }

    /* =================================================================== */
    /* T1 - AC10 (negative): the system user owns records and is never     */
    /*      sales; its records stay untouched, no trail row is written.    */
    /* =================================================================== */
    @isTest
    static void systemUserAlias_isNeverSales_andItsRecordsStay() {
        User ap = [SELECT Id, IsActive FROM User WHERE Alias = 'autoproc' LIMIT 1];
        System.assert(ap.IsActive, 'precondition: Automated Process is active');
        // The org's own Customer of Automated Process is not visible to the test
        // runner (measured: count 0), so the fixture creates its own record with the
        // system user as owner - the guard has to spare exactly that one.
        List<Account> systemOwned = new List<Account>();
        Account sysCust = new Account(Name = 'SCRUM483F owned by system user', OwnerId = ap.Id);
        systemOwned.add(sysCust);
        insert systemOwned;
        Integer custBefore = countAccountsOwned(ap.Id);
        System.assertEquals(1, custBefore,
            'fixture: the Customer owned by the system user is visible to the runner');

        System.assert(SalesDepartureHandoverService.isSystemUser(ap.Id),
            'AC10: an org system user is never a sales person');
        User salesPerson = mkUser('sales');
        addMappingRow(salesPerson.Id, salesPerson.Id);
        System.assert(!SalesDepartureHandoverService.isSystemUser(salesPerson.Id),
            'AC10 sanity: a sales person is no system user');

        Test.startTest();
        new SalesDepartureHandoverScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(custBefore, countAccountsOwned(ap.Id),
            'AC10: the Customer of the system user still belongs to it');
        System.assertEquals(0, countRowsFor(ap.Id),
            'AC10: the system user produced no trail row');
        System.assertEquals(0, countRowsFor(salesPerson.Id),
            'AC10 sanity: an ACTIVE sales person causes no handover at all');

        salesPerson.IsActive = false;
        update salesPerson;
    }

    /* =================================================================== */
    /* T2 - AC3: the fallback person is chosen and changed by sales         */
    /*      management (the grant is what SCRUM483_Fallback_Config gives).  */
    /* =================================================================== */
    @isTest
    static void fallbackPerson_chosenAndChangedBySalesManagement() {
        User first = mkUser('first');
        User second = mkUser('second');
        PermissionSet cfgPs = [SELECT Id FROM PermissionSet
                               WHERE Name = 'SCRUM483_Fallback_Config' LIMIT 1];
        System.assert(cfgPs != null, 'precondition: SCRUM483_Fallback_Config is deployed');
        insert new PermissionSetAssignment(AssigneeId = first.Id, PermissionSetId = cfgPs.Id);

        Test.startTest();
        System.runAs(first) {
            SalesHandoverFallback__c cfg = new SalesHandoverFallback__c();
            cfg.Fallback_User__c = first.Id;
            insert cfg;
        }
        Test.stopTest();

        List<SalesHandoverFallback__c> rows = [
            SELECT Id, Fallback_User__c FROM SalesHandoverFallback__c
        ];
        System.assertEquals(1, rows.size(),
            'AC3: sales management chose a fallback person');
        System.assertEquals(first.Id, rows[0].Fallback_User__c,
            'AC3: the chosen person is the one in the row');

        System.runAs(first) {
            SalesHandoverFallback__c change = rows[0];
            change.Fallback_User__c = second.Id;
            update change;
        }
        List<SalesHandoverFallback__c> again = [
            SELECT Id, Fallback_User__c FROM SalesHandoverFallback__c
        ];
        System.assertEquals(1, again.size(),
            'AC3: changing the person stays one row (the person can be changed)');
        System.assertEquals(second.Id, again[0].Fallback_User__c,
            'AC3: sales management changed the fallback person without asking IT');

        first.IsActive = false;
        update first;
    }

    /* =================================================================== */
    /* T3 - AC11 tier 1 / AC7: a stale fallback row gives no usable target. */
    /*      The case is Blocked and nothing is half-moved.                 */
    /* =================================================================== */
    @isTest
    static void staleFallbackRow_resolvesBlocked_andNothingHalfMoves() {
        User runner = mkRunner('runner');
        User departing = mkUser('departed');
        User brokenTarget = mkUser('stale');
        addMappingRow(departing.Id, departing.Id);
        addMappingRow(brokenTarget.Id, brokenTarget.Id);
        List<Account> mine = seedAccounts(departing.Id);
        seedOpportunities(mine[0].Id, departing.Id, 2, 0);

        // The records exist BEFORE IT switches anyone off: a Customer cannot even be
        // created with an inactive owner (measured 2026-11-27, INACTIVE_OWNER_OR_USER).
        brokenTarget.IsActive = false;
        update brokenTarget;
        departing.IsActive = false;
        update departing;
        addFallbackRow(brokenTarget.Id);

        Test.startTest();
        System.runAs(runner) {
            new SalesDepartureHandoverScheduler().execute(null);
        }
        Test.stopTest();

        List<SalesDepartureHandover__c> rows = [
            SELECT Id, From_User__c, To_User__c, Target_Rule__c, Status__c, Info__c
            FROM SalesDepartureHandover__c
            WHERE From_User__c = :departing.Id OR From_User__c = :brokenTarget.Id
        ];
        System.assertEquals(1, rows.size(),
            'AC11: only the person who owns records gets a row; the stale fallback person '
            + 'owns nothing and causes no handover at all');
        System.assertEquals(4, countAccountsOwned(departing.Id),
            'AC11: all 4 Customers stay with the departed person, nothing moved into '
            + 'the broken fallback');
        System.assertEquals(0, countAccountsOwned(brokenTarget.Id),
            'AC11: the broken fallback person received nothing and got no row');
        for (SalesDepartureHandover__c row : rows) {
            System.assertEquals(SalesDepartureHandoverService.ST_BLOCKED, row.Status__c,
                'AC11: a stale fallback gives no usable target - Blocked, tier 1, no DML');
            System.assertEquals(SalesDepartureHandoverService.ST_TARGET_NONE, row.Target_Rule__c,
                'AC11: no rule produced a target');
            System.assert(row.Info__c != null && row.Info__c.length() > 0,
                'AC11: the Blocked row carries a German explanation');
        }
        System.assertEquals(2, countOpenDealsOwned(departing.Id),
            'AC11: both open deals still belong to the departed person');

        runner.IsActive = false;
        update runner;
    }

    private static Integer countOpenDealsOwned(Id userId) {
        List<Opportunity> recs = [SELECT Id FROM Opportunity
                                  WHERE OwnerId = :userId AND IsClosed = false];
        return recs.size();
    }
}
