/**
 * [SCRUM-459] SCRUM459FollowupMonitorTest - the six derived values (AC1-AC11).
 *
 * House shape (SCRUM416OpenOpportunityRollupTest / SCRUM449OpportunityRiskTest):
 * fixtures in @TestSetup (own transaction, MIXED_DML rule SCRUM-442), looked up
 * by Name - TestSetup statics are not visible from test methods.
 *
 * The rollup is written by the triggers, which run in USER mode: the write passes
 * FLS because SCRUM459_FollowupMonitoring_Write grants edit on the six fields to
 * the acting user (measured in PR round 1 - without that PS every trigger write
 * failed). "Never typed by a human" is the guard trigger, tested in
 * SCRUM459FollowupFlsTest.ac6_userTypedMonitoringValue_refusedAndStoredValueUnchanged.
 * readBackUnderSalesRepPermissions runs the read path under System.runAs of a
 * user holding both Permission Sets, which is also what CI's fls-gate demands
 * for a class touching fresh fields (house lesson SCRUM-430 CI #367).
 *
 * Dates are relative to Date.today() (PO decision: due date today = Due Soon,
 * overdue = due date has fully passed).
 *
 * @author developer-agent
 * @date 2026-10-31
 */
@isTest
private class SCRUM459FollowupMonitorTest {

    private static final Date CLOSE_DATE = Date.today() + 90;

    @TestSetup
    static void setup_fixtures() {
        Account a = new Account(Name = '459 Fixture Account');
        insert a;
        List<Opportunity> ops = new List<Opportunity>{
            new Opportunity(Name = '459 AC1', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC2', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC3-overdue', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC3-soon', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC3-today', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC3-later', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC4', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC5', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC7', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC8', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC9-high', AccountId = a.Id, StageName = 'Prospecting', Amount = 75000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC9-low', AccountId = a.Id, StageName = 'Prospecting', Amount = 40000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC9-exact', AccountId = a.Id, StageName = 'Prospecting', Amount = 50000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC11', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC-D', AccountId = a.Id, StageName = 'Prospecting', Amount = 1000, CloseDate = CLOSE_DATE),
            new Opportunity(Name = '459 AC-RB', AccountId = a.Id, StageName = 'Prospecting', Amount = 60000, CloseDate = CLOSE_DATE)
        };
        insert ops;
    }

    private static Opportunity byName(String n) {
        List<Opportunity> l = [SELECT Id, Name, IsClosed, Amount,
                                      Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c,
                                      Last_Customer_Interaction__c, Followup_Status__c, Needs_Manager_Attention__c
                               FROM Opportunity WHERE Name = :n];
        System.assertEquals(1, l.size(), 'fixture ' + n + ' must exist exactly once');
        return l[0];
    }

    private static Followup_Obligation__c mk(Id parentId, String status, Date due, Date done, String action) {
        Followup_Obligation__c ob = new Followup_Obligation__c(
            Opportunity__c = parentId,
            Status__c = status,
            Due_Date__c = due,
            Completed_Date__c = done,
            Next_Action__c = action
        );
        return ob;
    }

    private static List<Followup_Obligation__c> ofOpp(Id oppId) {
        return [SELECT Id, Opportunity__c, Status__c, Due_Date__c, Completed_Date__c, Next_Action__c
                FROM Followup_Obligation__c WHERE Opportunity__c = :oppId];
    }

    @isTest
    static void ac1_createObligation_setsFollowupRequired() {
        Opportunity o = byName('459 AC1');
        insert mk(o.Id, 'Outstanding', Date.today() + 1, null, 'Call customer about the quote');
        o = byName('459 AC1');
        System.assertEquals(1, ofOpp(o.Id).size(), 'AC1: an obligation exists on that opportunity');
        System.assertEquals(true, o.Followup_Required__c, 'AC1: opportunity shows follow-up required');
        System.assertEquals(Date.today() + 1, o.Next_Followup_Date__c, 'AC1: next follow-up date = the due date');
        System.assertEquals(0, (Integer) o.Overdue_Followup_Count__c, 'AC1: nothing overdue yet');
        System.assertEquals('Due Soon', o.Followup_Status__c, 'AC1: due tomorrow -> Due Soon');
    }

    @isTest
    static void ac2_overdueCount_countsOnlyFullyPassedDates() {
        // PO example: due 20.10., 25.10., 28.10., today 23.10. -> overdue count 1.
        Opportunity o = byName('459 AC2');
        List<Followup_Obligation__c> obligations = new List<Followup_Obligation__c>{
            mk(o.Id, 'Outstanding', Date.today() - 3, null, 'a'),
            mk(o.Id, 'Outstanding', Date.today() + 2, null, 'b'),
            mk(o.Id, 'Outstanding', Date.today() + 5, null, 'c')
        };
        insert obligations;
        o = byName('459 AC2');
        System.assertEquals(1, (Integer) o.Overdue_Followup_Count__c, 'AC2: only the fully passed due date counts');
        System.assertEquals(Date.today() - 3, o.Next_Followup_Date__c, 'AC2: earliest still open due date');
        System.assertEquals('Overdue', o.Followup_Status__c, 'AC2: one overdue -> Overdue');
    }

    @isTest
    static void ac3_statusPrecedenceOverdueDueSoonUpToDate() {
        Opportunity o = byName('459 AC3-overdue');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        o = byName('459 AC3-overdue');
        System.assertEquals('Overdue', o.Followup_Status__c, 'AC3: overdue beats everything');

        o = byName('459 AC3-soon');
        insert mk(o.Id, 'Outstanding', Date.today() + 2, null, 'a');
        o = byName('459 AC3-soon');
        System.assertEquals('Due Soon', o.Followup_Status__c, 'AC3: due in two days -> Due Soon');

        // PO decision: a due date TODAY is Due Soon, not Overdue.
        o = byName('459 AC3-today');
        insert mk(o.Id, 'Outstanding', Date.today(), null, 'a');
        o = byName('459 AC3-today');
        System.assertEquals(0, (Integer) o.Overdue_Followup_Count__c, 'AC3: due today is not overdue');
        System.assertEquals('Due Soon', o.Followup_Status__c, 'AC3: due today -> Due Soon');

        o = byName('459 AC3-later');
        insert mk(o.Id, 'Outstanding', Date.today() + 3, null, 'a');
        o = byName('459 AC3-later');
        System.assertEquals('Up to Date', o.Followup_Status__c, 'AC3: later than the window -> Up to Date');
    }

    @isTest
    static void ac4_lastInteractionIsLatestCompletedDate() {
        // PO example: completed 05.10. and 18.10. -> last interaction 18.10.
        Opportunity o = byName('459 AC4');
        List<Followup_Obligation__c> obligations = new List<Followup_Obligation__c>{
            mk(o.Id, 'Completed', Date.today() - 26, Date.today() - 26, 'a'),
            mk(o.Id, 'Completed', Date.today() - 13, Date.today() - 13, 'b')
        };
        insert obligations;
        o = byName('459 AC4');
        System.assertEquals(Date.today() - 13, o.Last_Customer_Interaction__c, 'AC4: max Completed_Date__c');
        System.assertEquals(false, o.Followup_Required__c, 'AC4: completed obligations -> none outstanding');
    }

    @isTest
    static void ac5_completingObligationUpdatesOpportunityWithoutTouchingIt() {
        Opportunity o = byName('459 AC5');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        o = byName('459 AC5');
        System.assertEquals(1, (Integer) o.Overdue_Followup_Count__c, 'AC5: precondition, one overdue');
        System.assertEquals('Overdue', o.Followup_Status__c, 'AC5: precondition');

        // The rep touches ONLY the obligation record - no Opportunity DML here.
        Followup_Obligation__c ob = ofOpp(o.Id)[0];
        ob.Status__c = 'Completed';
        ob.Completed_Date__c = Date.today();
        update ob;

        o = byName('459 AC5');
        System.assertEquals(0, (Integer) o.Overdue_Followup_Count__c, 'AC5: overdue count recomputed');
        System.assertEquals(false, o.Followup_Required__c, 'AC5: no obligation outstanding');
        System.assertEquals('Up to Date', o.Followup_Status__c, 'AC5: status recomputed');
        System.assertEquals(Date.today(), o.Last_Customer_Interaction__c, 'AC5: last interaction = completion today');
    }

    @isTest
    static void ac7_fourOutstandingTwoOverdue() {
        Opportunity o = byName('459 AC7');
        List<Followup_Obligation__c> obligations = new List<Followup_Obligation__c>{
            mk(o.Id, 'Outstanding', Date.today() - 5, null, 'a'),
            mk(o.Id, 'Outstanding', Date.today() - 2, null, 'b'),
            mk(o.Id, 'Outstanding', Date.today() + 4, null, 'c'),
            mk(o.Id, 'Outstanding', Date.today() + 9, null, 'd')
        };
        insert obligations;
        o = byName('459 AC7');
        System.assertEquals(2, (Integer) o.Overdue_Followup_Count__c, 'AC7: two of four overdue');
        System.assertEquals('Overdue', o.Followup_Status__c, 'AC7: status Overdue');
        System.assertEquals(Date.today() - 5, o.Next_Followup_Date__c, 'AC7: earliest still open due date');
        System.assertEquals(true, o.Followup_Required__c, 'AC7: follow-up required');
    }

    @isTest
    static void ac8_closedStageClearsValuesAndLaterCompletionKeepsThem() {
        Opportunity o = byName('459 AC8');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        insert mk(o.Id, 'Outstanding', Date.today() + 6, null, 'b');
        o = byName('459 AC8');
        System.assertEquals(1, (Integer) o.Overdue_Followup_Count__c, 'AC8: precondition');
        System.assertEquals('Overdue', o.Followup_Status__c, 'AC8: precondition');

        // Fresh sObject: the byName record carries IsClosed, which is not
        // writeable (measured: "Field is not writeable: Opportunity.IsClosed";
        // the update then fails as "fields being inaccessible").
        Opportunity closeUpd = new Opportunity(Id = o.Id);
        closeUpd.StageName = 'Closed Won';
        update closeUpd;

        o = byName('459 AC8');
        System.assertEquals(true, o.IsClosed, 'AC8: stage Won -> closed');
        System.assertEquals(false, o.Followup_Required__c, 'AC8: cleared');
        System.assertEquals(null, o.Next_Followup_Date__c, 'AC8: cleared');
        System.assertEquals(0, (Integer) o.Overdue_Followup_Count__c, 'AC8: cleared');
        System.assertEquals(null, o.Last_Customer_Interaction__c, 'AC8: cleared');
        System.assertEquals(null, o.Followup_Status__c, 'AC8: cleared (blank)');
        System.assertEquals(false, o.Needs_Manager_Attention__c, 'AC8: cleared');

        // A later obligation completion must not change the cleared values.
        Followup_Obligation__c ob = ofOpp(o.Id)[0];
        ob.Status__c = 'Completed';
        ob.Completed_Date__c = Date.today();
        update ob;
        o = byName('459 AC8');
        System.assertEquals(0, (Integer) o.Overdue_Followup_Count__c, 'AC8: still cleared');
        System.assertEquals(null, o.Last_Customer_Interaction__c, 'AC8: still cleared');
        System.assertEquals(null, o.Followup_Status__c, 'AC8: still cleared');
    }

    @isTest
    static void ac9_attentionFlagStrictlyAbove50000() {
        Opportunity o = byName('459 AC9-high');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        o = byName('459 AC9-high');
        System.assertEquals(true, o.Needs_Manager_Attention__c, 'AC9: 75000 with 1 overdue -> flagged');

        o = byName('459 AC9-low');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        insert mk(o.Id, 'Outstanding', Date.today() - 2, null, 'b');
        o = byName('459 AC9-low');
        System.assertEquals(2, (Integer) o.Overdue_Followup_Count__c, 'AC9: 2 overdue');
        System.assertEquals(false, o.Needs_Manager_Attention__c, 'AC9: 40000 -> not flagged');

        // 0 records in Test-Org carry Amount exactly 50000 - this fixture is the
        // only proof of the strict boundary (Architect finding 2026-10-31).
        o = byName('459 AC9-exact');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        o = byName('459 AC9-exact');
        System.assertEquals(1, (Integer) o.Overdue_Followup_Count__c, 'AC9: 1 overdue');
        System.assertEquals(false, o.Needs_Manager_Attention__c, 'AC9: exactly 50000 -> NOT flagged');
    }

    @isTest
    static void ac11_obligationsSaveOfTwentyObligationsCountsEachOnce() {
        Opportunity o = byName('459 AC11');
        List<Followup_Obligation__c> obligations = new List<Followup_Obligation__c>();
        for (Integer i = 1; i <= 10; i++) {
            obligations.add(mk(o.Id, 'Outstanding', Date.today() - i, null, 'overdue ' + i));
        }
        for (Integer i = 1; i <= 10; i++) {
            obligations.add(mk(o.Id, 'Outstanding', Date.today() + i, null, 'future ' + i));
        }
        System.assertEquals(20, obligations.size(), 'AC11: 20 obligations in ONE save');
        insert obligations; // one statement -> one trigger invocation
        o = byName('459 AC11');
        System.assertEquals(20, ofOpp(o.Id).size(), 'AC11: all 20 stored');
        System.assertEquals(10, (Integer) o.Overdue_Followup_Count__c, 'AC11: each counted exactly once');
        System.assertEquals(Date.today() - 10, o.Next_Followup_Date__c, 'AC11: earliest open due date');
        System.assertEquals('Overdue', o.Followup_Status__c, 'AC11: status Overdue');
        System.assertEquals(true, o.Followup_Required__c, 'AC11: required');
    }

    @isTest
    static void obligationDeleteRecomputesTheParent() {
        Opportunity o = byName('459 AC-D');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'a');
        insert mk(o.Id, 'Outstanding', Date.today() + 1, null, 'b');
        o = byName('459 AC-D');
        System.assertEquals(1, (Integer) o.Overdue_Followup_Count__c, 'precondition: one overdue');
        System.assertEquals('Overdue', o.Followup_Status__c, 'precondition: Overdue');

        // Delete is System Administrator only - System context here.
        List<Followup_Obligation__c> doomed = [SELECT Id FROM Followup_Obligation__c
                                               WHERE Opportunity__c = :o.Id AND Due_Date__c < :Date.today()];
        System.assertEquals(1, doomed.size(), 'exactly one overdue obligation to delete');
        delete doomed;

        o = byName('459 AC-D');
        System.assertEquals(1, ofOpp(o.Id).size(), 'the deleted record is gone');
        System.assertEquals(0, (Integer) o.Overdue_Followup_Count__c, 'parent recomputed after delete');
        System.assertEquals(Date.today() + 1, o.Next_Followup_Date__c, 'next date moved');
        System.assertEquals('Due Soon', o.Followup_Status__c, 'status recomputed after delete');
    }

    @isTest
    static void readBackUnderSalesRepPermissions() {
        // The read path under the two Permission Sets (also what CI's fls-gate
        // demands for a class touching fresh fields, house SCRUM-430 CI #367).
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls459Rb',
            Alias = 'fls459rb',
            Email = 'fls459rb@example.invalid',
            Username = 'fls459rb_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        PermissionSet repPs = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM459_FollowupObligation_Rep' LIMIT 1];
        PermissionSet readPs = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM459_FollowupMonitoring_Read' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = repPs.Id);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = readPs.Id);

        Opportunity o = byName('459 AC-RB');
        insert mk(o.Id, 'Outstanding', Date.today() - 1, null, 'Call customer, sensitive note');

        System.runAs(u) {
            Opportunity r = [SELECT Id, Followup_Required__c, Overdue_Followup_Count__c, Followup_Status__c
                                    FROM Opportunity WHERE Name = '459 AC-RB'][0];
            System.assertEquals(true, r.Followup_Required__c, 'RB: monitoring value readable');
            System.assertEquals(1, (Integer) r.Overdue_Followup_Count__c, 'RB: overdue count readable');
            System.assertEquals('Overdue', r.Followup_Status__c, 'RB: status readable');
            List<Followup_Obligation__c> obs = [SELECT Id, Next_Action__c FROM Followup_Obligation__c
                                                WHERE Opportunity__c = :r.Id];
            System.assertEquals(1, obs.size(), 'RB: obligation record readable with the PS');
            System.assertEquals('Call customer, sensitive note', obs[0].Next_Action__c, 'RB: sensitive text readable via the PS');
        }
    }
}
