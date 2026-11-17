/**
 * [SCRUM-461] SCRUM461CompetitorFlsTest - the role gate on the competitor list.
 *
 * TAC7 / AC4: a user holding NONE of the three Permission Sets sees neither the
 *             Competitor__c object nor any of the four Opportunity fields - the
 *             commercially sensitive Competitor_Price__c included.
 * TAC6  / AC4: a user holding only SCRUM461_Competitor_List_Read can read the
 *             list but cannot add to it; a user holding SCRUM461_Competitor_List_Teamleitung
 *             can, and the record just added is immediately selectable by the reader.
 *
 * Mixed-DML house rule (SCRUM-442): the User and its PermissionSetAssignment are
 * created in System context - a user cannot grant himself a Permission Set -
 * the business DML/SOQL runs inside System.runAs.
 *
 * @author developer-agent
 * @date 2026-11-17
 */
@isTest
private class SCRUM461CompetitorFlsTest {

    @TestSetup
    static void setup_fixtures() {
        Account a = new Account(Name = '461 FLS Account');
        insert a;
        Competitor__c mueller = new Competitor__c(Name = 'Müller GmbH');
        insert mueller;
        Opportunity o = new Opportunity(
            Name = '461 FLS Opp',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 30,
            Amount = 60000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = mueller.Id
        );
        insert o;
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Fls461',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    private static PermissionSet mkPs(String psName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        System.assert(ps != null, 'precondition: Permission Set ' + psName + ' deployed');
        return ps;
    }

    @isTest
    static void competitorFields_invisibleWithoutAnyPS() {
        User neg = mkUser('fls461n');
        insert neg;

        System.runAs(neg) {
            // Precondition: the Opportunity itself is visible, otherwise the asserts
            // below would pass for the wrong reason (house SCRUM-459 pattern).
            Opportunity o = [SELECT Id, Name FROM Opportunity WHERE Name = '461 FLS Opp' LIMIT 1];
            System.assert(o != null, 'precondition: fixture Opportunity readable');

            System.assertEquals(
                false,
                Competitor__c.SObjectType.getDescribe().isAccessible(),
                'AC4/TAC7: the competitor list is not readable without a PS'
            );
            System.assertEquals(
                false,
                Opportunity.Competitor_Lost_To__c.getDescribe().isAccessible(),
                'TAC7: Competitor_Lost_To__c not readable'
            );
            System.assertEquals(
                false,
                Opportunity.Competitor_Price__c.getDescribe().isAccessible(),
                'TAC7: the sensitive Competitor_Price__c is not readable'
            );
            System.assertEquals(
                false,
                Opportunity.Competitor_Gap__c.getDescribe().isAccessible(),
                'TAC7: Competitor_Gap__c not readable'
            );
            System.assertEquals(
                false,
                Opportunity.Lost_Last_12M__c.getDescribe().isAccessible(),
                'TAC7: Lost_Last_12M__c not readable'
            );
        }
    }

    @isTest
    static void teamLead_mayAdd_readOnlyUserMayNot() {
        User reader = mkUser('fls461r');
        User lead = mkUser('fls461l');
        insert reader;
        insert lead;

        PermissionSet listRead = mkPs('SCRUM461_Competitor_List_Read');
        PermissionSet teamlead = mkPs('SCRUM461_Competitor_List_Teamleitung');
        insert new PermissionSetAssignment(AssigneeId = reader.Id, PermissionSetId = listRead.Id);
        insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = listRead.Id);
        insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = teamlead.Id);

        // A name that is fresh per run: a previous test run may still hold a record
        // of this name, and the duplicate guard would refuse it (TAC10).
        String freshName = '461 Teamlead Competitor ' + DateTime.now().getTime();

        System.runAs(lead) {
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isAccessible(),
                'AC4: a team lead reads the list');
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isCreateable(),
                'AC4: only the team lead PS grants create');
            Competitor__c added = new Competitor__c(Name = freshName);
            insert added;
            System.assert(added.Id != null, 'AC4: the team lead added a competitor');
        }

        System.runAs(reader) {
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isAccessible(),
                'AC4: the reader sees the list, which is what makes the picker work');
            System.assertEquals(false, Competitor__c.SObjectType.getDescribe().isCreateable(),
                'AC4: a user without the team-lead PS cannot add a competitor');
            System.assertEquals(
                false,
                Competitor__c.SObjectType.getDescribe().isDeletable(),
                'AC4: the read-only user cannot clear an entry'
            );

            // The record the team lead just added is immediately selectable.
            Set<String> selectable = new Set<String>();
            for (Competitor__c c : [SELECT Id, Name FROM Competitor__c]) {
                selectable.add(c.Name);
            }
            System.assert(selectable.contains('Müller GmbH'),
                'AC4: an existing entry is selectable by a plain reader');
            System.assert(selectable.contains(freshName),
                'AC4: the entry the team lead just added is immediately selectable');

            // Measured 2026-11-17 in Test-Org: Apex `insert` of a typed custom object is
            // NOT blocked by the object-level create permission - isCreateable() reports
            // false for this user, yet the insert saves. The gate the users actually
            // meet (the Setup picker, an API call) reads that same flag, so the
            // isCreateable assertion above is the enforceable one; the UI half of AC4
            // is the Tester's Playwright test. Asserting a refused Apex insert would
            // assert a guarantee the platform does not give.
        }
    }
}
