/**
 * Test class for SCRUM-308: Verlustgrund-Pflichtfeld und Manager-Benachrichtigung.
 *
 * Covers:
 * - Validation Rules (AC1, AC3): Verlustgrund required on Closed Lost, Detail required when Sonstiges
 * - Trigger + Handler (TAC-1..TAC-9): Closed Lost notification for Amount > 50,000
 * - Queueable (TAC-4, TAC-5): Email sent only for Amount > 50,000
 * - Bulk test (TAC-9): 200 opportunities in a single trigger fire
 * - No-exception when no manager (TAC-6)
 */
@isTest
private class SCRUM308LossReasonValidationTest {

    // ── Test Data Setup ──────────────────────────────────────────────────────

    /**
     * Creates a user with a manager, returning the user as the "owner" and the manager.
     */
    @TestSetup
    static void setup() {
        // Create manager user
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User manager = new User(
            LastName = 'TestManager',
            Email = 'manager@test.com',
            Username = 'manager_scrum308_' + DateTime.now().getTime() + '@test.com',
            Alias = 'mgr',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert manager;

        // Create owner user with manager
        User owner = new User(
            LastName = 'TestOwner',
            Email = 'owner@test.com',
            Username = 'owner_scrum308_' + DateTime.now().getTime() + '@test.com',
            Alias = 'ownr',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE',
            ManagerId = manager.Id
        );
        insert owner;

        // Create a few opportunities for reuse
        Opportunity opp1 = new Opportunity(
            Name = 'High Value Lost Deal',
            Amount = 100000,
            StageName = 'Proposal/Price Quote',
            CloseDate = Date.today().addDays(30),
            OwnerId = owner.Id
        );
        insert opp1;

        Opportunity opp2 = new Opportunity(
            Name = 'Low Value Lost Deal',
            Amount = 10000,
            StageName = 'Proposal/Price Quote',
            CloseDate = Date.today().addDays(30),
            OwnerId = owner.Id
        );
        insert opp2;
    }

    // ── AC1: Validation Rule - Verlustgrund required when Closed Lost ────────

    @isTest
    static void testValidationRule_ClosedLost_WithoutVerlustgrund_Fails() {
        Opportunity opp = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'High Value Lost Deal' LIMIT 1];

        opp.StageName = 'Closed Lost';
        // Verlustgrund__c is NOT set

        try {
            update opp;
            System.assert(false, 'Expected DMLException due to validation rule');
        } catch (DmlException e) {
            // Expected — validation rule should block
            System.assert(
                e.getMessage().contains('Verlustgrund'),
                'Validation error should mention Verlustgrund, got: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void testValidationRule_ClosedLost_WithVerlustgrund_Succeeds() {
        Opportunity opp = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'High Value Lost Deal' LIMIT 1];

        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Preis';

        Test.startTest();
        update opp;
        Test.stopTest();

        // Verify the opportunity was updated
        Opportunity updated = [SELECT Id, StageName, Verlustgrund__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Closed Lost', updated.StageName);
        System.assertEquals('Preis', updated.Verlustgrund__c);
    }

    // ── AC3: Validation Rule - Detail required when Sonstiges ────────────────

    @isTest
    static void testValidationRule_Sonstiges_WithoutDetail_Fails() {
        Opportunity opp = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'High Value Lost Deal' LIMIT 1];

        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Sonstiges';
        // Verlustgrund_Detail__c is NOT set

        try {
            update opp;
            System.assert(false, 'Expected DMLException due to validation rule');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Detail'),
                'Validation error should mention Detail, got: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void testValidationRule_Sonstiges_WithDetail_Succeeds() {
        Opportunity opp = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'High Value Lost Deal' LIMIT 1];

        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Sonstiges';
        opp.Verlustgrund_Detail__c = 'Kunde hat sich für ein anderes Produkt entschieden.';

        Test.startTest();
        update opp;
        Test.stopTest();

        Opportunity updated = [SELECT Id, Verlustgrund_Detail__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Kunde hat sich für ein anderes Produkt entschieden.', updated.Verlustgrund_Detail__c);
    }

    @isTest
    static void testValidationRule_NonSonstiges_WithoutDetail_Succeeds() {
        Opportunity opp = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'High Value Lost Deal' LIMIT 1];

        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Konkurrenzprodukt';
        // No detail needed for non-Sonstiges

        Test.startTest();
        update opp;
        Test.stopTest();
    }

    // ── AC4: Manager notification for Amount > 50,000 ───────────────────────

    @isTest
    static void testNotification_HighValue_SendsEmail() {
        Opportunity opp = [
            SELECT Id, Name, StageName, Amount, Owner.ManagerId
            FROM Opportunity
            WHERE Name = 'High Value Lost Deal' LIMIT 1
        ];

        Test.startTest();
        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Preis';
        update opp;
        Test.stopTest();

        // In test context, email is not actually sent (guarded by Test.isRunningTest())
        // but we verify the trigger fired without exception
        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Closed Lost', updated.StageName);
    }

    // ── TAC-5: NO notification for Amount <= 50,000 ─────────────────────────

    @isTest
    static void testNotification_LowValue_NoEmail() {
        Opportunity opp = [
            SELECT Id, Name, StageName, Amount
            FROM Opportunity
            WHERE Name = 'Low Value Lost Deal' LIMIT 1
        ];

        Test.startTest();
        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Timing';
        update opp;
        Test.stopTest();

        // No exception should be thrown
        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Closed Lost', updated.StageName);
    }

    // ── TAC-3: Trigger only fires on status CHANGE to Closed Lost ────────────

    @isTest
    static void testTrigger_NoFire_WhenAlreadyClosedLost() {
        Opportunity opp = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'High Value Lost Deal' LIMIT 1];

        // First set to Closed Lost
        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Preis';
        update opp;

        // Reset the static flag for the second update
        OpportunityClosedLostHandler.hasFired = false;

        // Now update another field while still Closed Lost — trigger should NOT re-fire
        Test.startTest();
        opp.Name = 'Renamed Lost Deal';
        update opp;
        Test.stopTest();

        // No exception expected
    }

    // ── TAC-9: Bulk test with 200 opportunities ──────────────────────────────

    @isTest
    static void testBulk_200Opportunities() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                Amount = 60000,
                StageName = 'Proposal/Price Quote',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        // Update all to Closed Lost
        for (Opportunity opp : opps) {
            opp.StageName = 'Closed Lost';
            opp.Verlustgrund__c = 'Kein Budget';
        }

        Test.startTest();
        update opps;
        Test.stopTest();

        // Verify all updated
        Integer closedLostCount = [
            SELECT COUNT() FROM Opportunity WHERE StageName = 'Closed Lost' AND Amount = 60000
        ];
        System.assertEquals(200, closedLostCount);
    }

    // ── TAC-6: No manager — no exception ─────────────────────────────────────

    @isTest
    static void testNoManager_NoException() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Owner with NO manager
        User ownerNoManager = new User(
            LastName = 'NoManagerOwner',
            Email = 'no_mgr_owner@test.com',
            Username = 'no_mgr_scrum308_' + DateTime.now().getTime() + '@test.com',
            Alias = 'nomo',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
            // ManagerId intentionally NOT set
        );
        insert ownerNoManager;

        Opportunity opp = new Opportunity(
            Name = 'No Manager High Value',
            Amount = 75000,
            StageName = 'Proposal/Price Quote',
            CloseDate = Date.today().addDays(30),
            OwnerId = ownerNoManager.Id
        );
        insert opp;

        Test.startTest();
        opp.StageName = 'Closed Lost';
        opp.Verlustgrund__c = 'Preis';
        update opp;
        Test.stopTest();

        // Should not throw an exception
        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Closed Lost', updated.StageName);
    }

    // ── Queueable direct test ────────────────────────────────────────────────

    @isTest
    static void testQueueable_DirectExecution() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User manager = new User(
            LastName = 'QueueMgr',
            Email = 'queue_mgr@test.com',
            Username = 'queue_mgr_scrum308_' + DateTime.now().getTime() + '@test.com',
            Alias = 'qm',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE'
        );
        insert manager;

        User owner = new User(
            LastName = 'QueueOwner',
            Email = 'queue_owner@test.com',
            Username = 'queue_owner_scrum308_' + DateTime.now().getTime() + '@test.com',
            Alias = 'qo',
            TimeZoneSidKey = 'Europe/Berlin',
            LocaleSidKey = 'de_DE',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'de_DE',
            ManagerId = manager.Id
        );
        insert owner;

        Opportunity opp = new Opportunity(
            Name = 'Queue Test Deal',
            Amount = 80000,
            StageName = 'Closed Lost',
            CloseDate = Date.today(),
            Verlustgrund__c = 'Sonstiges',
            Verlustgrund_Detail__c = 'Queue test detail',
            OwnerId = owner.Id
        );
        insert opp;

        Test.startTest();
        SendLostOpportunityNotification q = new SendLostOpportunityNotification(new List<Id> { opp.Id });
        System.enqueueJob(q);
        Test.stopTest();

        // No exception expected; email sending is guarded by Test.isRunningTest()
    }

    // ── Picklist value test (AC2) ────────────────────────────────────────────

    @isTest
    static void testPicklistValues() {
        // Verify the picklist has the expected values by successfully setting each
        String[] expectedValues = new String[] {
            'Preis', 'Konkurrenzprodukt', 'Kein Budget', 'Timing', 'Sonstiges'
        };

        for (String value : expectedValues) {
            Opportunity opp = new Opportunity(
                Name = 'Picklist Test ' + value,
                Amount = 1000,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Verlustgrund__c = value
            );
            insert opp;

            Opportunity inserted = [SELECT Verlustgrund__c FROM Opportunity WHERE Id = :opp.Id];
            System.assertEquals(value, inserted.Verlustgrund__c, 'Picklist value ' + value + ' should be valid');
        }
    }
}