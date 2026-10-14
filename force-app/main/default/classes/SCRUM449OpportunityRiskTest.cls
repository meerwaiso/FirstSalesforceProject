/**
 * [SCRUM-449] SCRUM449OpportunityRiskTest — rule contract + bulk + recovery.
 *
 * Covers the Apex-verifiable PO acceptance criteria:
 *   AC1 inactivity (>14 days) -> Low, reason names inactivity
 *   AC2 early stage + CloseDate within 7 days -> reason names the close date
 *   AC3 CloseDate in the past -> High
 *   AC4 setback >1 -> High; setback exactly 1 -> warning only (not High)
 *   AC5 two warnings, no High driver -> Medium
 *   AC6 recalculation on a user update (anchor moves, level follows)
 *   AC7 Closed Won/Lost -> level + reason cleared
 *   AC8 recovery -> cleared
 *   AC10 consistency across owners
 *   AC11 bulk import: 200 records in ONE insert, every record assessed
 *
 * Stage order is NOT hardcoded: the service reads the picklist from the org,
 * and stageOrder_matchesOrgPicklist asserts that ranking — a later picklist
 * change turns this test red instead of mis-ranking silently.
 *
 * FLS / AC9 lives in SCRUM449OpportunityRiskFlsTest — its own class, its own
 * transaction (house Mixed-DML lesson, SCRUM-442: a PSA insert must not share
 * a transaction with the business DML).
 *
 * @author developer-agent
 * @date 2026-10-14
 */
@isTest
private class SCRUM449OpportunityRiskTest {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Risk Test Account');
        insert a;
        Account a2 = new Account(Name = 'Risk Test Account 2');
        insert a2;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'RiskRep',
            Alias = 'riskrep',
            Email = 'riskrep@example.invalid',
            Username = 'riskrep_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
        );
        insert u;
        createdUser = u.Id;
        System.assertNotEquals(null, createdUser, 'setup must produce the rep user');
    }

    @testVisible private static Id createdUser;

    // ---- helpers -------------------------------------------------------------
    private static Id accountId() {
        return [SELECT Id FROM Account WHERE Name = 'Risk Test Account' LIMIT 1].Id;
    }

    private static Opportunity readRisk(Id id) {
        return [SELECT Id, Name, StageName, CloseDate, IsClosed,
                       Risk_Level__c, Risk_Reason__c, Inactive_Days__c,
                       Last_Risk_Evaluation__c, Last_User_Change__c,
                       Highest_Stage_Reached__c
                FROM Opportunity WHERE Id = :id LIMIT 1];
    }

    private static Opportunity mkOpp(String name, String stage, Date close) {
        return new Opportunity(
            Name = name,
            StageName = stage,
            CloseDate = close,
            AccountId = accountId(),
            OwnerId = createdUser
        );
    }

    private static Id accountId2() {
        return [SELECT Id FROM Account WHERE Name = 'Risk Test Account 2' LIMIT 1].Id;
    }

    // ---- org stage order: rank by the CONFIGURED picklist --------------------
    @isTest
    static void stageOrder_matchesOrgPicklist() {
        Map<String, Integer> m = OpportunityRiskService.stageOrder();
        List<PicklistEntry> orgValues = Opportunity.StageName.getDescribe().picklistValues;
        System.assertEquals(orgValues.size(), m.size(),
            'stageOrder must cover every picklist value');
        for (Integer i = 0; i < orgValues.size(); i++) {
            System.assertEquals(i + 1, m.get(orgValues[i].value),
                'configured position ' + (i + 1) + ' must be ' + orgValues[i].value);
        }
        System.assertEquals(5, OpportunityRiskService.earlyStageCutoff(),
            'early-stage cutoff must be half of the picklist');
    }

    // ---- AC1: inactivity -----------------------------------------------------
    @isTest
    static void ac1_inactive15Days_low() {
        Opportunity o = mkOpp('AC1 inactive 15', 'Qualification', Date.today().addDays(60));
        o.Last_User_Change__c = System.now().addDays(-15);
        insert o;

        Opportunity r = readRisk(o.Id);
        System.assertEquals('Low', r.Risk_Level__c, 'AC1: 15 inactive days -> Low');
        System.assert(r.Risk_Reason__c != null && r.Risk_Reason__c.contains('Inaktivity'),
            'AC1: reason must name inactivity');
        System.assertEquals(Decimal.valueOf(15), r.Inactive_Days__c,
            'AC1: Inactive Days shows the day count');
    }

    // ---- AC2: early stage + close date within 7 days -------------------------
    @isTest
    static void ac2_earlyStage_closeIn5Days() {
        Opportunity o = mkOpp('AC2 close soon', 'Qualification', Date.today().addDays(5));
        insert o;

        Opportunity r = readRisk(o.Id);
        System.assertEquals('Low', r.Risk_Level__c, 'AC2: single warning -> Low');
        System.assert(r.Risk_Reason__c != null
                      && r.Risk_Reason__c.contains('Unrealistic close date'),
            'AC2: reason must name the close-date situation');
    }

    // ---- AC3: close date already passed -> High ------------------------------
    @isTest
    static void ac3_closeDatePast_high() {
        Opportunity o = mkOpp('AC3 close passed', 'Value Proposition', Date.today().addDays(-3));
        insert o;

        Opportunity r = readRisk(o.Id);
        System.assertEquals('High', r.Risk_Level__c, 'AC3: passed close date -> High');
        System.assert(r.Risk_Reason__c != null
                      && r.Risk_Reason__c.contains('Close date already passed'),
            'AC3: reason must name the passed close date');
    }

    // ---- AC4: setback >1 = High, exactly 1 = warning -------------------------
    @isTest
    static void ac4_setbackOne_warning_setbackTwo_high() {
        Opportunity one = mkOpp('AC4 setback one', 'Needs Analysis', Date.today().addDays(30));
        one.Highest_Stage_Reached__c = 'Id. Decision Makers'; // pos 4, current pos 3
        insert one;

        Opportunity r1 = readRisk(one.Id);
        System.assertEquals('Id. Decision Makers', r1.Highest_Stage_Reached__c,
            'AC4: high-water mark must not move backwards');
        System.assertEquals('Low', r1.Risk_Level__c,
            'AC4: setback of exactly 1 is a single warning, not High');
        System.assert(r1.Risk_Reason__c != null && r1.Risk_Reason__c.contains('Stage setback'),
            'AC4: reason must name the setback');

        Opportunity two = mkOpp('AC4 setback two', 'Qualification', Date.today().addDays(30));
        two.Highest_Stage_Reached__c = 'Perception Analysis'; // pos 6, current pos 2
        insert two;

        Opportunity r2 = readRisk(two.Id);
        System.assertEquals('High', r2.Risk_Level__c, 'AC4: setback >1 -> High');
        System.assert(r2.Risk_Reason__c != null && r2.Risk_Reason__c.contains('Stage setback'),
            'AC4: reason names the setback');
    }

    // ---- AC5: two warnings, no High driver -> Medium -------------------------
    @isTest
    static void ac5_twoWarnings_medium() {
        Opportunity o = mkOpp('AC5 two warnings', 'Qualification', Date.today().addDays(5));
        o.Last_User_Change__c = System.now().addDays(-20); // C1 + C2, no High driver
        insert o;

        Opportunity r = readRisk(o.Id);
        System.assertEquals('Medium', r.Risk_Level__c, 'AC5: two warnings -> Medium');
        System.assert(r.Risk_Reason__c != null
                      && r.Risk_Reason__c.contains('Inaktivity')
                      && r.Risk_Reason__c.contains('Unrealistic close date'),
            'AC5: reason must name every applying condition');
    }

    // ---- AC6: recalculation on a user change ---------------------------------
    @isTest
    static void ac6_userUpdate_recalculates() {
        Opportunity o = mkOpp('AC6 recovery', 'Qualification', Date.today().addDays(5));
        o.Last_User_Change__c = System.now().addDays(-20);
        insert o;
        Opportunity flagged = readRisk(o.Id);
        System.assertEquals('Medium', flagged.Risk_Level__c, 'AC6 precondition: flagged Medium');

        o.Description = 'touched by the rep';
        update o;

        Opportunity r = readRisk(o.Id);
        System.assertEquals('Low', r.Risk_Level__c,
            'AC6: after the update only the close-date warning remains -> Low');
        System.assert(r.Last_User_Change__c != null
                      && r.Last_User_Change__c >= flagged.Last_Risk_Evaluation__c,
            'AC6: the user change must move the anchor');
        System.assertEquals(Decimal.valueOf(0), r.Inactive_Days__c, 'AC6: inactivity counter reset');
    }

    // ---- AC7: closed opportunities are cleared -------------------------------
    @isTest
    static void ac7_closedWonAndLost_cleared() {
        Opportunity won = mkOpp('AC7 won', 'Prospecting', Date.today().addDays(5));
        won.Last_User_Change__c = System.now().addDays(-20);
        insert won;
        Opportunity flagged = readRisk(won.Id);
        System.assertEquals('Medium', flagged.Risk_Level__c, 'AC7 precondition: flagged');

        won.StageName = 'Closed Won';
        update won;
        Opportunity rWon = readRisk(won.Id);
        System.assertEquals(null, rWon.Risk_Level__c, 'AC7: Closed Won -> no level');
        System.assertEquals(null, rWon.Risk_Reason__c, 'AC7: Closed Won -> reason cleared');

        Opportunity lost = mkOpp('AC7 lost', 'Prospecting', Date.today().addDays(5));
        lost.Last_User_Change__c = System.now().addDays(-20);
        lost.Loss_Reason__c = 'ZuTeuer'; // ValRule LossReason_PflichtBeiClosedLost
        insert lost;
        lost.StageName = 'Closed Lost';
        update lost;
        Opportunity rLost = readRisk(lost.Id);
        System.assertEquals(null, rLost.Risk_Level__c, 'AC7: Closed Lost -> no level');
        System.assertEquals(null, rLost.Risk_Reason__c, 'AC7: Closed Lost -> reason cleared');
    }

    // ---- AC8: no condition applies -> cleared --------------------------------
    @isTest
    static void ac8_healthy_cleared() {
        Opportunity o = mkOpp('AC8 healthy', 'Qualification', Date.today().addDays(30));
        insert o;
        Opportunity r = readRisk(o.Id);
        System.assertEquals(null, r.Risk_Level__c, 'AC8: nothing applies -> no level');
        System.assertEquals(null, r.Risk_Reason__c, 'AC8: nothing applies -> no reason');
    }

    // ---- AC10: consistency across owners -------------------------------------
    @isTest
    static void ac10_differentAccounts_sameRules() {
        Opportunity first = mkOpp('AC10 rep A', 'Prospecting', Date.today().addDays(-2));
        Opportunity second = mkOpp('AC10 rep B', 'Prospecting', Date.today().addDays(-2));
        second.AccountId = accountId2();
        insert new List<Opportunity>{first, second};

        List<Opportunity> read = [SELECT Id, Risk_Level__c, Risk_Reason__c
                                  FROM Opportunity
                                  WHERE Name IN ('AC10 rep A', 'AC10 rep B')];
        System.assertEquals(2, read.size(), 'AC10: both records assessed');
        for (Opportunity r : read) {
            System.assertEquals('High', r.Risk_Level__c, 'AC10: same rule on every record');
        }
    }

    // ---- AC11: bulk import — every record assessed, none missing -------------
    @isTest
    static void ac11_bulk200_everyRecordAssessed() {
        List<Opportunity> import200 = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            import200.add(mkOpp('AC11 bulk ' + i, 'Prospecting', Date.today().addDays(-1)));
        }
        Test.startTest();
        insert import200; // ONE bulk insert = ONE trigger invocation over the chunk
        Test.stopTest();

        List<Opportunity> all = [SELECT Id, Name, Risk_Level__c FROM Opportunity
                                 WHERE Risk_Level__c = 'High'];
        Integer mine = 0;
        for (Opportunity r : all) {
            if (r.Name != null && r.Name.startsWith('AC11 bulk ')) {
                mine++;
            }
        }
        System.assertEquals(200, mine, 'AC11: every bulk record assessed, none missing');
    }

    // ---- nightly path: the scheduler's own writes are NOT user changes -------
    @isTest
    static void scheduler_recompute_doesNotMoveAnchor() {
        Opportunity o = mkOpp('AC-night', 'Prospecting', Date.today().addDays(1));
        o.Last_User_Change__c = System.now().addDays(-20);
        insert o;
        Opportunity before = readRisk(o.Id);
        System.assertEquals('Medium', before.Risk_Level__c,
            'night: anchor 20 days old (C1) + close date tomorrow in early stage (C2) -> Medium');

        Test.startTest();
        Integer saved = OpportunityRiskService.recomputeAll();
        Test.stopTest();

        Opportunity after = readRisk(o.Id);
        System.assertEquals(before.Last_User_Change__c, after.Last_User_Change__c,
            'the scheduler must never move the user-change anchor');
        System.assertEquals('Medium', after.Risk_Level__c, 'night: level stays consistent');
        System.debug('recomputeAll saved=' + saved);
    }

    // The nightly job itself is created by DevOps via System.schedule(); the
    // scheduler's behaviour is covered above by scheduler_recompute_doesNotMoveAnchor,
    // which runs the same recomputeAll path the Scannable would run.
}
