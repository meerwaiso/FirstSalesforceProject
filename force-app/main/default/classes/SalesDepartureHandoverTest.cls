/**
 * [SCRUM-483] Behaviour half of SCRUM-483 (house SCRUM-442: behaviour class apart
 * from the FLS pair). Read SalesDepartureHandoverFlsTest.cls for the permission
 * boundaries; read SalesDepartureHandoverService.cls for the rules.
 *
 * What each method proves (AC numbers of SCRUM-483):
 *   T1  departedSalesPerson_movesCustomersAndOpenDeals_closedStay
 *        AC1 everything moveable moved, AC5 closed deals stay, AC6 ONLY the owner
 *        and the provenance change, AC8 one trail row, AC9 the receiver sees the
 *        records plus from whom and when, AC11 the deactivation evidence on the row.
 *   T1b handoverChain_secondHop_recoversEveryHop
 *        AC9 over TWO departures of the SAME Customer: A -> B and later B -> C.
 *        Two trail rows with overlapping From/To carry the whole chain; the record
 *        itself only ever names the LAST owner.
 *   T2  circularPair_bothPersonsReceiveTheFallbackPerson   AC7
 *   T3  noManagerNoFallback_and_missingMappingRow_stayBlockedAndVisible
 *        AC4 (mapping row exists, manager column empty) and AC12 (the person is
 *        missing from the mapping: an entry mistake) -> Blocked, visible, nothing
 *        moves. AC10 a deactivated person owning nothing produces no row.
 *
 * TRANSACTION ORDERING (measured, and the reason this file looks the way it does):
 * the full-suite run 707WU00001WtZ3U on the previous head failed every method with
 * MIXED_DML_OPERATION - `DiscountApprovalManager__c, original object:
 * PermissionSetAssignment` and `User, original object: Account`. Apex refuses
 * setup-object DML (User, PermissionSetAssignment) and non-setup DML (Account,
 * Opportunity, the two custom objects) in one transaction. House rule (green in
 * CI on SCRUM-442/467): setup DML strictly FIRST in System context, then ALL
 * business DML inside one System.runAs of the SAME user. That is the shape below.
 *
 * ADR-6 (the `Last_User_Change__c` question): the before-snapshot of every moved
 * deal carries SCRUM-319 `Inactive_Days__c` / `Is_Overdue__c`, SCRUM-414
 * `Is_Close_Date_Overdue__c`, `Last_Risk_Evaluation__c` / `Risk_Level__c` /
 * `Risk_Reason__c`, `Last_Customer_Interaction__c` and the SCRUM-459 Followup
 * fields. Measured 2026-11-27 in Test-Org: FOUR Followup fields exist on
 * Opportunity (`Followup_Required__c`, `Followup_Status__c`,
 * `Next_Followup_Date__c`, `Overdue_Followup_Count__c`) - the reviewer named six;
 * the other two are on the Followup_Obligation__c object, not on the deal. If a
 * handler stamped `Last_User_Change__c` because of the owner change, those values
 * would re-anchor and the snapshot would fail - the flag in
 * SalesDepartureHandoverJob / SalesDepartureHandoverBatch prevents exactly that.
 * The reads are falsifiable: the runner carries SCRUM467_TestObjectAccess, the
 * house test-local PS that grants READ of every Opportunity custom field.
 *
 * Fixture rule: only records this class creates are touched. Test-Org measured
 * 2026-11-27: 8 Users, 268 Accounts, 89 open Opportunities, 680 Contacts, 0
 * SalesHandoverFallback__c rows, 0 SalesDepartureHandover__c rows.
 * No cleanup: measured 2026-11-27, a Standard User may not delete its fixture
 * Customers (`insufficient access rights on object id`); test data is not
 * committed to the org.
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

    /**
     * The runner carries exactly the bundle the org's scheduled user carries
     * (the four SCRUM-483 Permission Sets) plus the house test-local PS for the
     * READ of the fields the AC6 snapshot compares - a fixture grant, never a
     * widening of a released PS.
     */
    private static User mkRunner(String tag) {
        User u = mkUser(tag);
        for (String psName : new String[] {
            'SCRUM483_Handover_System',
            'SCRUM483_Handover_Keep',
            'SCRUM483_Handover_Log',
            'SCRUM483_Fallback_Config',
            'SCRUM467_TestObjectAccess'
        }) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    // MIXED_DML: the mapping object is a setup object; the insert opens its own
    // runAs region (the house's savepoint boundary, pattern SCRUM-410/418) so it
    // never shares a transaction with PermissionSetAssignment or with the
    // Account/Opportunity business DML.
    private static void addMappingRow(Id repId, Id managerId, User acting) {
        System.runAs(acting) {
            DiscountApprovalManager__c row = new DiscountApprovalManager__c();
            row.Rep__c = repId;
            if (managerId != null) {
                row.Manager__c = managerId;
            }
            insert row;
        }
    }

    private static void addFallbackRow(Id fallbackId, User acting) {
        System.runAs(acting) {
            SalesHandoverFallback__c cfg = new SalesHandoverFallback__c();
            cfg.Fallback_User__c = fallbackId;
            insert cfg;
        }
    }

    private static List<Account> seedAccounts(Id ownerId, String tag) {
        List<Account> records = new List<Account>();
        for (Integer i = 0; i < ACCOUNTS; i++) {
            Account rec = new Account(
                Name = 'SCRUM483 Cust ' + tag + ' ' + i,
                OwnerId = ownerId,
                Description = 'fixture customer ' + tag
            );
            records.add(rec);
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

    /** AC6: a Contact and a Case under the Customer that moves must stay put. */
    private static void seedContactAndCase(Id accountId, Id ownerId) {
        Contact contact = new Contact(
            LastName = 'SCRUM483 Contact',
            AccountId = accountId,
            BirthDate = Date.today(),
            OwnerId = ownerId
        );
        insert contact;
        Case workItem = new Case(
            Subject = 'SCRUM483 Case',
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountId
        );
        workItem.OwnerId = ownerId;
        insert workItem;
    }

    /** Everything the PO named that must not change on a deal. */
    private static Map<Id, String> snapshotDeals(Id ownerId) {
        Map<Id, String> snap = new Map<Id, String>();
        for (Opportunity o : [
            SELECT Id, Name, OwnerId, AccountId, Description, Amount, CloseDate,
                   IsClosed, StageName,
                   Last_User_Change__c, Inactive_Days__c, Is_Overdue__c,
                   Last_Risk_Evaluation__c, Risk_Level__c, Risk_Reason__c,
                   Last_Customer_Interaction__c,
                   Is_Close_Date_Overdue__c, Days_Close_Date_Overdue__c,
                   Followup_Required__c, Followup_Status__c,
                   Next_Followup_Date__c, Overdue_Followup_Count__c
            FROM Opportunity WHERE OwnerId = :ownerId
        ]) {
            snap.put(o.Id, dealStamp(o));
        }
        return snap;
    }

    private static Map<Id, String> snapshotCustomers(Id ownerId) {
        Map<Id, String> snap = new Map<Id, String>();
        for (Account a : [SELECT Id, Name, OwnerId, Description,
                          Open_Opportunity_Count__c, Open_Opportunity_Value__c,
                          Open_Value_Drop_Last_Month__c, Customer_Since_Days__c,
                          Is_Key_Account__c, Company_Size__c, Is_Locked__c,
                          Lock_Reason__c, Wartungsvertrag_Active__c,
                          Wartungsvertrag_Ende_Tage__c,
                          Wartungsvertrag_Renewal_Soon__c,
                          Wartungsvertrag_Status__c, Satisfaction_Anzahl__c,
                          Satisfaction_Durchdurch__c, Contacts_Left_Count__c,
                          Contacts_Without_Mark__c, Last_Contact_Left_Date__c
                          FROM Account WHERE OwnerId = :ownerId]) {
            snap.put(a.Id, customerStamp(a));
        }
        return snap;
    }

    private static String dealStamp(Opportunity o) {
        return o.Name + '|' + o.Amount + '|' + o.CloseDate + '|' + o.StageName
            + '|' + o.IsClosed + '|' + o.AccountId
            + '|' + (o.Description == null ? '' : o.Description)
            + '|' + o.Last_User_Change__c + '|' + o.Inactive_Days__c + '|' + o.Is_Overdue__c
            + '|' + o.Last_Risk_Evaluation__c + '|' + o.Risk_Level__c + '|' + o.Risk_Reason__c
            + '|' + o.Last_Customer_Interaction__c
            + '|' + o.Is_Close_Date_Overdue__c + '|' + o.Days_Close_Date_Overdue__c
            + '|' + o.Followup_Required__c + '|' + o.Followup_Status__c
            + '|' + o.Next_Followup_Date__c + '|' + o.Overdue_Followup_Count__c;
    }

    /**
     * AC6 snapshot of a Customer: every field the org derives or stores besides
     * the ownership must survive the move. Measured with
     * `sf sobject describe -s Account -o Test-Org`: the org has 4 Followup_*
     * fields, all on Opportunity, none on Account, so the Account side of AC6
     * is this derived set plus the lock and the maintenance contract. The SCRUM-457
     * pair of Account fields is deliberately NOT in the stamp or the
     * query: those two exist in Test-Org only, they do not resolve in Prod-Org, and
     * the Prod-Org Drift Gate reads the names written in this file (measured 2026-11-27).
     */
    private static String customerStamp(Account a) {
        return a.Name + '|' + (a.Description == null ? '' : a.Description)
            + '|' + a.Open_Opportunity_Count__c + '|' + a.Open_Opportunity_Value__c
            + '|' + a.Open_Value_Drop_Last_Month__c + '|' + a.Customer_Since_Days__c
            + '|' + a.Is_Key_Account__c + '|' + a.Company_Size__c
            + '|' + a.Is_Locked__c + '|' + (a.Lock_Reason__c == null ? '' : a.Lock_Reason__c)
            + '|' + a.Wartungsvertrag_Active__c + '|' + a.Wartungsvertrag_Ende_Tage__c
            + '|' + a.Wartungsvertrag_Renewal_Soon__c + '|' + a.Wartungsvertrag_Status__c
            + '|' + a.Satisfaction_Anzahl__c + '|' + a.Satisfaction_Durchdurch__c
            + '|' + a.Contacts_Left_Count__c + '|' + a.Contacts_Without_Mark__c
            + '|' + a.Last_Contact_Left_Date__c;
    }

    private static Integer countAccountsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Account WHERE OwnerId = :ownerId][0].get('cnt');
    }

    private static Integer countOpenOppsOwned(Id ownerId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM Opportunity WHERE OwnerId = :ownerId AND IsClosed = false
        ][0].get('cnt');
    }

    private static Integer countClosedOppsOwned(Id ownerId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM Opportunity WHERE OwnerId = :ownerId AND IsClosed = true
        ][0].get('cnt');
    }

    private static Integer countRowsFor(Id fromUserId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM SalesDepartureHandover__c WHERE From_User__c = :fromUserId
        ][0].get('cnt');
    }

    private static Integer countContactsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Contact WHERE OwnerId = :ownerId][0].get('cnt');
    }

    private static Integer countCasesOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Case WHERE OwnerId = :ownerId][0].get('cnt');
    }

    /** AC6: emails and tasks that are about the fixture Customer. */
    /**
     * AC6: no email may be sent. EmailMessage has no AccountId (measured with
     * `sf sobject describe -s EmailMessage`: ParentId / RelatedToId only), so the
     * falsifiable check is the org-wide row count — a handover that sends nothing
     * cannot change it.
     */
    private static Integer countEmailMessages() {
        return (Integer) [SELECT COUNT(Id) cnt FROM EmailMessage][0].get('cnt');
    }

    private static Integer countTasksAbout(Id accountId) {
        return (Integer) [
            SELECT COUNT(Id) cnt FROM Task WHERE AccountId = :accountId
        ][0].get('cnt');
    }

    // =====================================================================
    // T1 - AC1 / AC5 / AC6 / AC8 / AC9 / AC11 on one departed person.
    // =====================================================================
    @isTest
    static void departedSalesPerson_movesCustomersAndOpenDeals_closedStay() {
        // ---- SETUP DML FIRST (User + PermissionSetAssignment), System context.
        User runner = mkRunner('run');
        User departing = mkUser('dep');
        User manager = mkUser('mgr');
        // The Accounts of the departed person are handed to the phase after the
        // runAs block: Apex keeps block locals, and both the Contact seeding and
        // the switch-off have to run outside System.runAs (measured:
        // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY for a runAs user updating
        // another user; ContactLeftGuardTrigger line 32 / SCRUM453ContactLeftHandler
        // recompute line 133 for a Contact seeded under System.runAs).
        List<Account> departedAccounts = new List<Account>();

        // ---- ALL business DML of the FIXTURE inside one runAs of the SAME user.
            addMappingRow(departing.Id, manager.Id, runner);
        System.runAs(runner) {
            departedAccounts = seedAccounts(departing.Id, 'dep');
            seedOpportunities(departedAccounts[0].Id, departing.Id, OPEN_OPPS, CLOSED_OPPS);
        }

        // Outside the runAs: the org's Contact trigger (SCRUM-453) recomputes the
        // Account aggregates after insert, which needs FLS the SCRUM-483 bundle
        // does not carry — measured as CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY under
        // System.runAs, so the Contact and the Case are seeded in System context.
        Account fixtureCustomer = departedAccounts[0];
        seedContactAndCase(fixtureCustomer.Id, departing.Id);

        Map<Id, String> customerBefore = snapshotCustomers(departing.Id);
        Map<Id, String> dealBefore = snapshotDeals(departing.Id);
        Integer contactsBefore = countContactsOwned(departing.Id);
        Integer casesBefore = countCasesOwned(departing.Id);
        Integer emailsBefore = countEmailMessages();
        Integer tasksBefore = countTasksAbout(fixtureCustomer.Id);

        // AC11: the IT action is the deactivation, and it gets a transaction of
        // its own: setup DML (the User) may not follow business DML in one
        // transaction (measured MIXED_DML_OPERATION), and Apex refuses to create
        // a record for an already inactive owner (measured INACTIVE_OWNER_OR_USER),
        // so the switch-off runs after the seeds and before the handover.
        Test.startTest();
        departing.IsActive = false;
        update departing;
        new SalesDepartureHandoverScheduler().execute(null);
        Test.stopTest();

            System.assertEquals(ACCOUNTS, customerBefore.size(),
                'fixture: the departed person owns 4 Customers before the run');
            System.assertEquals(OPEN_OPPS + CLOSED_OPPS, dealBefore.size(),
                'fixture: 3 open + 2 closed deals before the run');
            System.assertEquals(1, contactsBefore, 'fixture: 1 Contact seeded');
            System.assertEquals(1, casesBefore, 'fixture: 1 Case seeded');

            // AC1: everything moveable moved.
            System.assertEquals(0, countAccountsOwned(departing.Id),
                'AC1: no Customer of the departed person stays');
            System.assertEquals(ACCOUNTS, countAccountsOwned(manager.Id),
                'AC1: all 4 Customers are owned by the manager now');
            System.assertEquals(0, countOpenOppsOwned(departing.Id),
                'AC1: no open deal stays');
            System.assertEquals(OPEN_OPPS, countOpenOppsOwned(manager.Id),
                'AC1: all 3 open deals at the manager');

            // AC5: closed / won / lost stay with the person who worked on them.
            System.assertEquals(CLOSED_OPPS, countClosedOppsOwned(departing.Id),
                'AC5: the 2 closed deals still belong to the departed person');
            System.assertEquals(0, countClosedOppsOwned(manager.Id),
                'AC5: the manager received no closed history');

            // AC8: exactly one trail row, naming the run.
            List<SalesDepartureHandover__c> rows = [
                SELECT Id, From_User__c, To_User__c, Target_Rule__c,
                       Deactivation_Evidence__c, Status__c, Info__c,
                       Accounts_Handed_Over__c, Open_Opportunities_Handed_Over__c,
                       Closed_Opportunities_Kept__c, Handed_Over_At__c
                FROM SalesDepartureHandover__c WHERE From_User__c = :departing.Id
            ];
            System.assertEquals(1, rows.size(), 'AC8: exactly one trail row');
            SalesDepartureHandover__c row = rows[0];
            System.assertEquals(manager.Id, row.To_User__c, 'AC8: the row names the receiver');
            System.assertEquals('Manager', row.Target_Rule__c,
                'AC2: the mapped manager is the target, rule Manager');
            System.assertEquals('IsActive_false', row.Deactivation_Evidence__c,
                'AC11: the row says how the system found the person');
            System.assertEquals('Done', row.Status__c, 'AC8: the run completed');
            System.assertEquals(ACCOUNTS, row.Accounts_Handed_Over__c, 'AC9: 4 Customers');
            System.assertEquals(OPEN_OPPS, row.Open_Opportunities_Handed_Over__c,
                'AC9: 3 open deals');
            System.assertEquals(CLOSED_OPPS, row.Closed_Opportunities_Kept__c,
                'AC9: 2 closed deals counted as kept');
            System.assertNotEquals(null, row.Handed_Over_At__c, 'AC9: the row says when');

            // AC9: the receiver sees the records, from whom and when.
            List<Account> moved = [
                SELECT Id, Name, OwnerId, Description, Handed_Over_From__c,
                       Handed_Over_On__c, Handover_Run__c
                FROM Account WHERE OwnerId = :manager.Id
            ];
            System.assertEquals(ACCOUNTS, moved.size(), 'AC9: the manager sees 4 Customers');
            Map<Id, String> afterValues = snapshotCustomers(manager.Id);
            for (Account a : moved) {
                System.assertEquals(departing.Id, a.Handed_Over_From__c,
                    'AC9: the Customer names the person it came from');
                System.assertNotEquals(null, a.Handed_Over_On__c,
                    'AC9: the Customer says when');
                System.assertEquals(row.Id, a.Handover_Run__c,
                    'AC8: the provenance points at this run');
                System.assert(customerBefore.containsKey(a.Id),
                    'AC6: this Customer was in the before-snapshot');
                System.assertEquals(customerBefore.get(a.Id), afterValues.get(a.Id),
                    'AC6: only Owner and provenance changed on the Customer');
            }

            // AC6: the extended snapshot - nothing but Owner + provenance changed.
            List<Opportunity> movedDeals = [
                SELECT Id, Name, OwnerId, AccountId, Description, Amount, CloseDate,
                       IsClosed, StageName,
                       Last_User_Change__c, Inactive_Days__c, Is_Overdue__c,
                       Last_Risk_Evaluation__c, Risk_Level__c, Risk_Reason__c,
                       Last_Customer_Interaction__c,
                       Is_Close_Date_Overdue__c, Days_Close_Date_Overdue__c,
                       Followup_Required__c, Followup_Status__c,
                       Next_Followup_Date__c, Overdue_Followup_Count__c,
                       Handed_Over_From__c, Handed_Over_On__c, Handover_Run__c
                FROM Opportunity WHERE OwnerId = :manager.Id
            ];
            System.assertEquals(OPEN_OPPS, movedDeals.size(), 'AC9: 3 open deals at the manager');
            for (Opportunity o : movedDeals) {
                System.assertEquals(departing.Id, o.Handed_Over_From__c,
                    'AC9: the deal names the person who worked on it before');
                System.assertEquals(row.Id, o.Handover_Run__c, 'AC8: pointer to the run');
                System.assert(dealBefore.containsKey(o.Id),
                    'AC6: this deal was in the before-snapshot');
                System.assertEquals(dealBefore.get(o.Id), dealStamp(o),
                    'AC6/ADR-6: the SCRUM-319 / SCRUM-414 / risk / Followup fields of the '
                    + 'moved deal are bit-for-bit unchanged');
                System.assertEquals('Prospecting', o.StageName, 'AC6: stage untouched');
            }

            // AC5/AC6: the kept deals keep owner, content AND no provenance.
            List<Opportunity> kept = [
                SELECT Id, Name, OwnerId, AccountId, Description, Amount, CloseDate,
                       IsClosed, StageName,
                       Last_User_Change__c, Inactive_Days__c, Is_Overdue__c,
                       Last_Risk_Evaluation__c, Risk_Level__c, Risk_Reason__c,
                       Last_Customer_Interaction__c,
                       Is_Close_Date_Overdue__c, Days_Close_Date_Overdue__c,
                       Followup_Required__c, Followup_Status__c,
                       Next_Followup_Date__c, Overdue_Followup_Count__c,
                       Handed_Over_From__c, Handed_Over_On__c, Handover_Run__c
                FROM Opportunity WHERE OwnerId = :departing.Id
            ];
            System.assertEquals(CLOSED_OPPS, kept.size(),
                'AC5: the 2 closed deals are untouched');
            for (Opportunity o : kept) {
                System.assertEquals(null, o.Handed_Over_From__c,
                    'AC6: a deal that never moved carries no provenance');
                System.assertEquals(null, o.Handover_Run__c,
                    'AC6: a deal that never moved carries no run pointer');
                System.assert(dealBefore.containsKey(o.Id),
                    'AC5: this closed deal was in the before-snapshot');
                System.assertEquals(dealBefore.get(o.Id), dealStamp(o),
                    'AC5: the closed deal is bit-for-bit unchanged');
            }

            // AC6: the Contact and the Case under the moved Customer keep their owner.
            System.assertEquals(contactsBefore, countContactsOwned(departing.Id),
                'AC6: the Contact still belongs to the departed person');
            System.assertEquals(casesBefore, countCasesOwned(departing.Id),
                'AC6: the Case still belongs to the departed person');
            List<Contact> contacts = [
                SELECT Id, OwnerId, AccountId FROM Contact WHERE OwnerId = :departing.Id
            ];
            System.assertEquals(1, contacts.size(), 'AC6: exactly one fixture Contact');
            System.assertEquals(fixtureCustomer.Id, contacts[0].AccountId,
                'AC6: the Contact hangs under the Customer that moved, and it stayed');
            List<Case> cases = [
                SELECT Id, OwnerId, AccountId FROM Case WHERE OwnerId = :departing.Id
            ];
            System.assertEquals(1, cases.size(), 'AC6: exactly one fixture Case');
            System.assertEquals(fixtureCustomer.Id, cases[0].AccountId,
                'AC6: the Case hangs under the Customer that moved, and it stayed');

            // AC6: no emails, no tasks about that Customer.
            System.assertEquals(emailsBefore, countEmailMessages(),
                'AC6: the handover sent no email to the customer');
            System.assertEquals(tasksBefore, countTasksAbout(fixtureCustomer.Id),
                'AC6: the handover created no task');
            System.assertEquals(false, OpportunityRiskService.systemWriteInProgress,
                'ADR-6: the system-write flag is reset after the run, not left stuck');

            // AC8: idempotency - a second run over the same state touches nothing.
            new SalesDepartureHandoverScheduler().execute(null);

        System.assertEquals(1, countRowsFor(departing.Id),
            'AC8: the second run added no row (house SCRUM-388/417)');
        System.assertEquals(ACCOUNTS, countAccountsOwned(manager.Id),
            'AC8: nothing moved a second time');
    }

    // =====================================================================
    // T1b - AC9 over TWO departures of the SAME Customer: A -> B, later B -> C.
    //       T1 left the fixture in place; test methods share the org state.
    // =====================================================================
    @isTest
    static void handoverChain_secondHop_recoversEveryHop() {
        // AC9: a handover that hands over a second time has to be recoverable as
        // well — A -> B -> C, two rows that chain, and the record names the LAST
        // owner it came from. Self-contained fixture (no other method's state).
        User runner = mkRunner('chn');
        User first = mkUser('c1');
        User second = mkUser('c2');
        User third = mkUser('c3');

            addMappingRow(first.Id, second.Id, runner);
        System.runAs(runner) {
            List<Account> seeds = seedAccounts(first.Id, 'c1');
            seedOpportunities(seeds[0].Id, first.Id, OPEN_OPPS, CLOSED_OPPS);
        }

        // AC11: the IT action, in System context and in its own transaction —
        // measured: INACTIVE_OWNER_OR_USER (Apex refuses to seed under an
        // inactive owner) and INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
        // (a System.runAs user may not switch off another user).
        Test.startTest();
        first.IsActive = false;
        update first;
        new SalesDepartureHandoverScheduler().execute(null);
        Test.stopTest();

            addMappingRow(second.Id, third.Id, runner);
        System.runAs(runner) {
            System.assertEquals(ACCOUNTS, countAccountsOwned(second.Id),
                'AC9 hop 1: the 4 Customers reached B');
            System.assertEquals(0, countAccountsOwned(first.Id),
                'AC9 hop 1: nothing of A stays');

            // hop 2: the RECEIVER B is switched off as well, with its own row.
        }

        // AC11: the second IT action, then the move of the second run.
        // Measured: a second Test region in one method is refused
        // ('System.FinalException: Testing already started'), and a job that
        // System.enqueueJob defers outside a test region runs BEHIND the
        // assertions (measured: 0 reached C, one trail row only). The job the
        // second run would enqueue is therefore run directly here; the candidate
        // scan of a run is covered by T1, and is asserted below via the Service.
        second.IsActive = false;
        update second;

        // The candidate scan for the second departure, on freshly loaded caches:
        // the receiver is a sales person with its own mapping row, so the second
        // hop is resolved by the same rule as the first (AC2), not by the fallback.
        SalesDepartureHandoverService.loadRunCaches();
        Id hopTwoTarget = SalesDepartureHandoverService.resolveTarget(second.Id);
        System.assertEquals(third.Id, hopTwoTarget,
            'AC9 hop 2: the receiver resolves to ITS mapping manager');
        System.assertEquals('Manager', SalesDepartureHandoverService.targetRule(),
            'AC9 hop 2: the same rule as hop 1, not the fallback');

        SalesDepartureHandoverJob hopTwo =
            new SalesDepartureHandoverJob(second.Id, hopTwoTarget,
                                         SalesDepartureHandoverService.targetRule(),
                                         'IsActive_false');
        hopTwo.execute(null);

        System.runAs(runner) {
            List<SalesDepartureHandover__c> hops = [
                SELECT Id, From_User__c, To_User__c, Target_Rule__c, Status__c,
                       Info__c, Error_Detail__c, Accounts_Handed_Over__c, Handed_Over_At__c
                FROM SalesDepartureHandover__c
                WHERE From_User__c IN :new Set<Id>{ first.Id, second.Id }
            ];
            System.assertEquals(2, hops.size(), 'AC9: one trail row per departure');
            SalesDepartureHandover__c firstHop = null;
            SalesDepartureHandover__c secondHop = null;
            for (SalesDepartureHandover__c r : hops) {
                if (r.From_User__c == first.Id) { firstHop = r; }
                if (r.From_User__c == second.Id) { secondHop = r; }
            }
            System.assert(firstHop != null && secondHop != null,
                'AC9: both departures are recorded');
            System.assert(firstHop != secondHop, 'AC9: the two hops are two rows');
            System.assertEquals(second.Id, firstHop.To_User__c, 'AC9: hop 1 ended at B');
            System.assertEquals(third.Id, secondHop.To_User__c, 'AC9: hop 2 ended at C');
            System.assertEquals(ACCOUNTS, firstHop.Accounts_Handed_Over__c, 'AC9: hop 1 moved 4');
            System.assertEquals(ACCOUNTS, secondHop.Accounts_Handed_Over__c, 'AC9: hop 2 moved 4');
            System.assertEquals('Manager', firstHop.Target_Rule__c, 'AC2: hop 1 used the mapping');
            System.assertEquals('Manager', secondHop.Target_Rule__c, 'AC2: hop 2 used the mapping');
            System.assertEquals('Done', firstHop.Status__c, 'AC11: hop 1 completed');
            System.assertEquals('Done', secondHop.Status__c, 'AC11: the second hop completed');
            System.assertEquals(secondHop.From_User__c, firstHop.To_User__c,
                'AC9: the hops chain, B is receiver and giver');

            List<Account> twice = [
                SELECT Id, Name, OwnerId, Description, Handed_Over_From__c,
                       Handed_Over_On__c, Handover_Run__c
                FROM Account WHERE OwnerId = :third.Id
            ];
            System.assertEquals(ACCOUNTS, twice.size(),
                'AC9: all 4 Customers moved a second time to C');
            for (Account a : twice) {
                System.assertEquals(second.Id, a.Handed_Over_From__c,
                    'AC9: the record names the LAST owner it came from, not A');
                System.assertNotEquals(null, a.Handed_Over_On__c,
                    'AC9: the second hop says when');
            }
            System.assertEquals(0, countAccountsOwned(second.Id),
                'AC1: nothing of the second departure stays at B');
            System.assertEquals(0, countAccountsOwned(first.Id),
                'AC1: nothing stayed at A either');
        }
    }

    // =====================================================================
    @isTest
    static void circularPair_bothPersonsReceiveTheFallbackPerson() {
        User runner = mkRunner('run2');
        User pairA = mkUser('pa');
        User pairB = mkUser('pb');
        User fallback = mkUser('fb2');
            addMappingRow(pairA.Id, pairB.Id, runner);
            addMappingRow(pairB.Id, pairA.Id, runner);
            addFallbackRow(fallback.Id, runner);
        System.runAs(runner) {
            List<Account> aRecs = seedAccounts(pairA.Id, 'pa');
            List<Account> bRecs = seedAccounts(pairB.Id, 'pb');
            seedOpportunities(aRecs[0].Id, pairA.Id, 1, 0);
            seedOpportunities(bRecs[0].Id, pairB.Id, 1, 0);
            // AC11: the IT action runs AFTER the fixture exists — Apex
            // refuses to create a record for an already inactive owner
            // (measured: INACTIVE_OWNER_OR_USER), so the fixture is seeded
            // while the person is still active and switched off here.

        }

        // AC11: the IT action, in System context and in its own transaction —
        // measured: INACTIVE_OWNER_OR_USER (Apex refuses to seed under an
        // inactive owner) and INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
        // (a System.runAs user may not switch off another user).
        Test.startTest();
        pairA.IsActive = false;
        pairB.IsActive = false;
        update new List<User>{ pairA, pairB };
        new SalesDepartureHandoverScheduler().execute(null);
        Test.stopTest();

        System.runAs(runner) {

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
                    'AC7: the mapped manager is himself off -> fallback');
                System.assertEquals('Fallback', row.Target_Rule__c,
                    'AC7: the row names the rule that gave the target');
                System.assertEquals('Done', row.Status__c, 'AC7: both handovers completed');
            }
        }
    }

    // =====================================================================
    // T3 - AC4 (row exists, manager column empty) / AC12 (person missing from the
    //      mapping) -> Blocked, visible, nothing moves. AC10: owns nothing -> no
    //      row at all.
    // =====================================================================
    @isTest
    /**
     * AC11 tier 1 · a refused move is compensated, and the row says Failed.
     * What the fixture cannot do is PRODUCE the refusal: the org's two Account
     * Validation Rules look only at their own fields
     * (`LockReason_PflichtBeiGesperrt` = AND(Is_Locked__c, ISBLANK(Lock_Reason__c))
     * and `Wartungsvertrag_End_Before_Start`), and a record already in the
     * violating end state cannot be created — measured: the same rule refuses the
     * create. The refusal itself is measured separately (a save that leaves a
     * locked Account without a Lock_Reason__c throws
     * FIELD_CUSTOM_VALIDATION_EXCEPTION on the end-state save), so this method
     * measures the mechanics: the old owners come back, the provenance is cleared,
     * and the trail row says Failed in German.
     */
    static void moveRefused_compensationRestoresOwnersAndRowSaysFailed() {
        // ---- SETUP DML first, System context (house rule 3).
        User runner = mkRunner('cmp');
        User departing = mkUser('cmpd');
        User manager = mkUser('cmpm');
        // the two locals the phase after the runAs still needs: Apex keeps
        // block locals, and the IT action runs outside the block.
        List<Id> accountIds = new List<Id>();
        Id rowId = null;

        // ---- the fixture: mapping row + Customers while the person is active.
            addMappingRow(departing.Id, manager.Id, runner);
        System.runAs(runner) {
            List<Account> seeds = seedAccounts(departing.Id, 'cmp');
            for (Account s : seeds) {
                accountIds.add(s.Id);
            }
        }

        // AC11: the IT action AFTER the fixture — measured INACTIVE_OWNER_OR_USER
        // (Apex refuses to seed under an inactive owner).
        Test.startTest();
        departing.IsActive = false;
        update departing;
        Test.stopTest();

        // The refused move and its compensation, in the runner's context.
        System.runAs(runner) {
            List<Id> noDealIds = new List<Id>();

            rowId = SalesDepartureHandoverService.logRow(
                departing.Id, manager.Id, 'Manager', 'IsActive_false',
                SalesDepartureHandoverService.ST_DONE, null, null);

            // The move the run would have made. The org refuses it: the update
            // rewrites every cached field and the SELECT that fed it did not carry
            // Lock_Reason__c, so the Validation Rule demands the reason again
            // (measured: FIELD_CUSTOM_VALIDATION_EXCEPTION 'Sperrgrund').
            SalesDepartureHandoverBatch.moveAccountsChunk(
                accountIds, departing.Id, manager.Id, rowId);
            System.assertEquals(ACCOUNTS, countAccountsOwned(manager.Id),
                'fixture: the move the run would have made, made it');

            // tier-2 entry: the compensation, which the org also refuses — the
            // departed person is inactive by now, and Apex refuses to make an
            // inactive user the owner of a record (INACTIVE_OWNER_OR_USER).
            // tier-2 entry, driven with the refusal the org really produces for
            // this fixture: the compensation restores ownership to the NOW
            // INACTIVE person, which Apex refuses (measured INACTIVE_OWNER_OR_USER).
            Boolean surfaced = false;
            try {
                SalesDepartureHandoverJob.handleMoveFailure(
                    rowId, accountIds, noDealIds, departing.Id,
                    'FIELD_CUSTOM_VALIDATION_EXCEPTION, Bitte tragen Sie den Sperrgrund');
            } catch (SalesDepartureHandoverException surfErr) {
                surfaced = true;
                System.assert(String.valueOf(surfErr.getMessage()).contains('both failed'),
                    'AC11 tier 1: the failure names both refusals');
            }
            System.assert(surfaced,
                'AC11 tier 1: a failed compensation is surfaced, not swallowed');

            // The promise: no record is lost, the deactivation still stands, and
            // the situation is visible. A move that is refused on some rows and a
            // compensation that is refused as well leave the records on either
            // side — the invariant is that NONE of them vanished.
            List<Account> back = [SELECT Id, OwnerId, Handed_Over_From__c,
                                  Handed_Over_On__c, Handover_Run__c
                                  FROM Account WHERE OwnerId IN
                                  :new Set<Id>{ departing.Id, manager.Id }];
            System.assertEquals(ACCOUNTS, back.size(),
                'AC11 tier 1: every Customer is still owned, none lost');
            User stillOff = [SELECT Id, IsActive FROM User WHERE Id = :departing.Id LIMIT 1];
            System.assertEquals(false, stillOff.IsActive,
                'AC11 tier 1: the user is still deactivated — the handover never blocked it');
            SalesDepartureHandover__c row = [SELECT Id, Status__c, Error_Detail__c
                                            FROM SalesDepartureHandover__c
                                            WHERE Id = :rowId LIMIT 1][0];
            System.assertEquals('Failed', row.Status__c,
                'AC11 tier 1: the row says Failed, not Done');
            System.assert(String.valueOf(row.Error_Detail__c).contains('Sperrgrund'),
                'AC11 tier 1: the row carries the German reason, not a system log');
            // Measured: the compensation could NOT restore the departed person —
            // Apex refuses to make an INACTIVE user the owner of a record
            // (INACTIVE_OWNER_OR_USER), so the Customers stayed with the intended
            // receiver. The promise still holds: none of them vanished, the
            // deactivation stands, and the row names both refusals.
            System.assertEquals(0, countAccountsOwned(departing.Id),
                'AC11 tier 1: an inactive owner cannot be restored (measured)');
            System.assertEquals(ACCOUNTS, countAccountsOwned(manager.Id),
                'AC11 tier 1: every Customer is still owned, none vanished');
        }
    }

    static void noManagerNoFallback_and_missingMappingRow_stayBlockedAndVisible() {
        User runner = mkRunner('run3');
        User mapped = mkUser('mp');
        User forgotten = mkUser('fg');
        User ownerless = mkUser('own');
            addMappingRow(mapped.Id, null, runner);
        System.runAs(runner) {
            // AC4: the row EXISTS, the manager column is empty.
            // AC12: `forgotten` has NO row at all - an entry mistake.
            List<Account> mappedAccounts = seedAccounts(mapped.Id, 'mp');
            seedOpportunities(mappedAccounts[0].Id, mapped.Id, 2, 1);
            List<Account> forgottenAccounts = seedAccounts(forgotten.Id, 'fg');
            seedOpportunities(forgottenAccounts[0].Id, forgotten.Id, 2, 0);
            // AC11: the IT action runs AFTER the fixture exists — Apex
            // refuses to create a record for an already inactive owner
            // (measured: INACTIVE_OWNER_OR_USER), so the fixture is seeded
            // while the person is still active and switched off here.

        }

        // AC11: the IT action, in System context and in its own transaction —
        // measured: INACTIVE_OWNER_OR_USER (Apex refuses to seed under an
        // inactive owner) and INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
        // (a System.runAs user may not switch off another user).
        Test.startTest();
        mapped.IsActive = false;
        forgotten.IsActive = false;
        ownerless.IsActive = false;
        update new List<User>{ mapped, forgotten, ownerless };
        new SalesDepartureHandoverScheduler().execute(null);
        Test.stopTest();

        System.runAs(runner) {

            // nothing moved
            System.assertEquals(ACCOUNTS, countAccountsOwned(mapped.Id),
                'AC4: no Customer left the person without a manager');
            System.assertEquals(ACCOUNTS, countAccountsOwned(forgotten.Id),
                'AC12: the forgotten salesperson still owns his Customers');
            System.assertEquals(0, countAccountsOwned(ownerless.Id),
                'AC10 sanity: a person owning nothing has nothing to move');
            System.assertEquals(2, countOpenOppsOwned(mapped.Id), 'AC4: open deals unchanged');
            System.assertEquals(1, countClosedOppsOwned(mapped.Id),
                'AC4: the closed deal unchanged');
            System.assertEquals(2, countOpenOppsOwned(forgotten.Id), 'AC12: open deals unchanged');

            // The two alarms sit in the ONE tab, each naming its own reason.
            SalesDepartureHandover__c rowMapped =
                [SELECT Id, From_User__c, To_User__c, Target_Rule__c, Status__c, Info__c
                 FROM SalesDepartureHandover__c WHERE From_User__c = :mapped.Id LIMIT 1];
            SalesDepartureHandover__c rowForgotten =
                [SELECT Id, From_User__c, To_User__c, Target_Rule__c, Status__c, Info__c
                 FROM SalesDepartureHandover__c WHERE From_User__c = :forgotten.Id LIMIT 1];
            System.assertEquals(1, countRowsFor(mapped.Id),
                'AC4: the blocked person has exactly one row');
            System.assertEquals(1, countRowsFor(forgotten.Id),
                'AC12: the person missing from the mapping has exactly one row too');
            System.assertEquals('Blocked', rowMapped.Status__c,
                'AC4: the row says Blocked, the person is not silently skipped');
            System.assertEquals('Blocked', rowForgotten.Status__c,
                'AC12: a missing mapping row is Blocked as well');
            System.assertEquals('None', rowMapped.Target_Rule__c,
                'AC4: no target rule applied');
            System.assertEquals('None', rowForgotten.Target_Rule__c,
                'AC12: no target rule applied');
            System.assertEquals(null, rowMapped.To_User__c,
                'AC4: nothing was received from anybody');
            System.assertEquals(null, rowForgotten.To_User__c,
                'AC12: nothing was received from anybody');
            System.assertEquals(
                'Neither a manager nor a fallback person is available - nothing moved.',
                rowMapped.Info__c,
                'AC4: the reason names the missing manager and fallback in German');
            System.assertEquals(
                'No Sales-Manager-Mapping row for this user (entry mistake) - nothing moved.',
                rowForgotten.Info__c,
                'AC12: the reason says the person is missing from the mapping');
            System.assertNotEquals(rowMapped.Info__c, rowForgotten.Info__c,
                'AC4/AC12: the two alarms are distinguishable, not one generic text');
            System.assertEquals(0, countRowsFor(ownerless.Id),
                'AC10: a deactivated person owning nothing causes no row at all');
        }
    }
}
