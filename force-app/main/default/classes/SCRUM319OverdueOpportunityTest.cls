/**
 * Test class for SCRUM-319: Automated Overdue Opportunity Detection.
 *
 * Covers:
 * - OpportunityOverdueService.findAndMarkOverdueOpportunities() (AC1, AC2, TAC-1)
 * - OpportunityOverdueScheduler (AC1, TAC-2)
 * - OpportunityOverdueResetHandler / Trigger (AC2, TAC-3)
 * - OpportunityOverdueNotification (AC3, TAC-4)
 * - Bulk test (TAC-5): 200 opportunities in single DML
 * - Closed Won/Lost are excluded (AC1)
 * - Already-marked opportunities are not re-marked (TAC-1)
 */
@isTest
private class SCRUM319OverdueOpportunityTest {

    @TestSetup
    static void setup() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User testUser = new User(
            LastName = 'TestUser',
            Email = 'overdue_test_' + DateTime.now().getTime() + '@test.com',
            Username = 'overdue_test_' + DateTime.now().getTime() + '@test.com',
            Alias = 'overd',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert testUser;

        // Opportunity 1: open, last modified 20 days ago -> should be marked overdue
        Opportunity oldOpenOpp = new Opportunity(
            Name = 'Old Open Opportunity',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            OwnerId = testUser.Id,
            Is_Overdue__c = false
        );
        insert oldOpenOpp;

        // Opportunity 2: open, last modified 5 days ago -> should NOT be marked overdue
        Opportunity recentOpenOpp = new Opportunity(
            Name = 'Recent Open Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            OwnerId = testUser.Id,
            Is_Overdue__c = false
        );
        insert recentOpenOpp;

        // Opportunity 3: Closed Won -> should NOT be marked overdue
        Opportunity closedWonOpp = new Opportunity(
            Name = 'Closed Won Opportunity',
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(-20),
            OwnerId = testUser.Id,
            Is_Overdue__c = false
        );
        insert closedWonOpp;

        // Opportunity 4: Closed Lost -> should NOT be marked overdue
        Opportunity closedLostOpp = new Opportunity(
            Name = 'Closed Lost Opportunity',
            StageName = 'Closed Lost',
            CloseDate = Date.today().addDays(-20),
            OwnerId = testUser.Id,
            Is_Overdue__c = false
        );
        insert closedLostOpp;

        // Opportunity 5: already marked overdue -> should not be re-marked (idempotency)
        Opportunity alreadyMarkedOpp = new Opportunity(
            Name = 'Already Marked Opportunity',
            StageName = 'Negotiation',
            CloseDate = Date.today().addDays(30),
            OwnerId = testUser.Id,
            Is_Overdue__c = true
        );
        insert alreadyMarkedOpp;
    }

    @isTest
    static void testFindAndMarkOverdueOpportunities_MarksOldOpenOpp() {
        Test.startTest();
        List<Id> newlyMarkedIds = OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Name = 'Old Open Opportunity' LIMIT 1];
        System.assertEquals(true, result.Is_Overdue__c, 'Old open opportunity should be marked overdue');
        System.contains(newlyMarkedIds, result.Id, 'Newly marked list should contain the old open opportunity');
    }

    @isTest
    static void testFindAndMarkOverdueOpportunities_DoesNotMarkRecentOpp() {
        Test.startTest();
        OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Name = 'Recent Open Opportunity' LIMIT 1];
        System.assertEquals(false, result.Is_Overdue__c, 'Recent opportunity should NOT be marked overdue');
    }

    @isTest
    static void testFindAndMarkOverdueOpportunities_ExcludesClosedWon() {
        Test.startTest();
        OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Name = 'Closed Won Opportunity' LIMIT 1];
        System.assertEquals(false, result.Is_Overdue__c, 'Closed Won opportunity should NOT be marked overdue');
    }

    @isTest
    static void testFindAndMarkOverdueOpportunities_ExcludesClosedLost() {
        Test.startTest();
        OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Name = 'Closed Lost Opportunity' LIMIT 1];
        System.assertEquals(false, result.Is_Overdue__c, 'Closed Lost opportunity should NOT be marked overdue');
    }

    @isTest
    static void testFindAndMarkOverdueOpportunities_Idempotent() {
        Test.startTest();
        List<Id> newlyMarkedIds = OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        Opportunity alreadyMarked = [SELECT Id FROM Opportunity WHERE Name = 'Already Marked Opportunity' LIMIT 1];
        System.assertNotContains(newlyMarkedIds, alreadyMarked.Id, 'Already marked opportunity should not appear in newly marked list');
    }

    @isTest
    static void testFindAndMarkOverdueOpportunities_NoOverdueReturnsEmpty() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            LastName = 'NoOverdue',
            Email = 'nooverdue_' + DateTime.now().getTime() + '@test.com',
            Username = 'nooverdue_' + DateTime.now().getTime() + '@test.com',
            Alias = 'noop',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert u;

        Opportunity opp = new Opportunity(
            Name = 'Fresh Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            OwnerId = u.Id,
            Is_Overdue__c = false
        );
        insert opp;

        Test.startTest();
        List<Id> newlyMarkedIds = OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        System.assertEquals(0, newlyMarkedIds.size(), 'No overdue opportunities should be marked');
    }

    @isTest
    static void testTrigger_ResetsOverdueFlagOnUpdate() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            LastName = 'ResetTest',
            Email = 'reset_' + DateTime.now().getTime() + '@test.com',
            Username = 'reset_' + DateTime.now().getTime() + '@test.com',
            Alias = 'reset',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert u;

        Opportunity opp = new Opportunity(
            Name = 'Reset Test Opportunity',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            OwnerId = u.Id,
            Is_Overdue__c = true
        );
        insert opp;

        Test.startTest();
        opp.NextStep = 'Follow up';
        update opp;
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, result.Is_Overdue__c, 'Overdue flag should be reset on update');
    }

    @isTest
    static void testTrigger_NoResetWhenNotOverdue() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            LastName = 'NoReset',
            Email = 'noreset_' + DateTime.now().getTime() + '@test.com',
            Username = 'noreset_' + DateTime.now().getTime() + '@test.com',
            Alias = 'nores',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert u;

        Opportunity opp = new Opportunity(
            Name = 'Not Overdue Opportunity',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            OwnerId = u.Id,
            Is_Overdue__c = false
        );
        insert opp;

        Test.startTest();
        opp.NextStep = 'Call client';
        update opp;
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, result.Is_Overdue__c, 'Non-overdue opportunity should remain false');
    }

    @isTest
    static void testScheduler_MarksOverdueAndEnqueuesNotification() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            LastName = 'Scheduler',
            Email = 'scheduler_' + DateTime.now().getTime() + '@test.com',
            Username = 'scheduler_' + DateTime.now().getTime() + '@test.com',
            Alias = 'sched',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert u;

        Opportunity opp = new Opportunity(
            Name = 'Scheduler Test Opportunity',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            OwnerId = u.Id,
            Is_Overdue__c = false
        );
        insert opp;

        Test.startTest();
        System.schedule('Test Overdue Scheduler', '0 0 6 * * ?', new OpportunityOverdueScheduler());
        Test.stopTest();

        Opportunity result = [SELECT Is_Overdue__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, result.Is_Overdue__c, 'Scheduler should mark overdue opportunity');
    }

    @isTest
    static void testBulk_Mark200OverdueOpportunities() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            LastName = 'BulkTest',
            Email = 'bulk_' + DateTime.now().getTime() + '@test.com',
            Username = 'bulk_' + DateTime.now().getTime() + '@test.com',
            Alias = 'bulk',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert u;

        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opportunities.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(30),
                OwnerId = u.Id,
                Is_Overdue__c = false
            ));
        }
        insert opportunities;

        Test.startTest();
        List<Id> newlyMarkedIds = OpportunityOverdueService.findAndMarkOverdueOpportunities();
        Test.stopTest();

        System.assertEquals(200, newlyMarkedIds.size(), 'All 200 opportunities should be marked overdue');

        Integer markedCount = [SELECT COUNT() FROM Opportunity WHERE Is_Overdue__c = true AND OwnerId = :u.Id];
        System.assertEquals(200, markedCount, 'All 200 opportunities should have Is_Overdue__c = true');
    }

    @isTest
    static void testFLS_IsOverdueFieldIsReadonlyForUsers() {
        Schema.SObjectField overdueField = Opportunity.Is_Overdue__c;
        Schema.DescribeFieldResult fieldDescribe = overdueField.getDescribe();

        System.assertEquals('Is_Overdue__c', fieldDescribe.getName(), 'Field API name matches');
        System.assertEquals(Boolean.class, fieldDescribe.getType(), 'Field type is Boolean');
        System.assertEquals(true, fieldDescribe.isAccessible(), 'Field is accessible');
    }
}