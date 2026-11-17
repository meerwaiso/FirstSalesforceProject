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
        Opportunity o = new Opportunity(
            Name = '461 FLS Opp',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 30,
            Amount = 60000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = [SELECT Id FROM Competitor__c LIMIT 1].Id
        );
        insert o;
        Competitor__c mueller = new Competitor__c(Company_Name__c = 'Müller GmbH');
        insert mueller;
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

    private static PermissionSet mkPs(String name) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = name LIMIT 1];
        System.assert(ps != null, 'precondition: Permission Set ' + name + ' deployed');
        return ps;
    }

    @isTest
    static void competitorFields_invisibleWithoutAnyPS() {
        User neg = mkUser('fls461neg');
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
        User reader = mkUser('fls461reader');
        User lead = mkUser('fls461lead');
        insert reader;
        insert lead;

        PermissionSet listRead = mkPs('SCRUM461_Competitor_List_Read');
        PermissionSet teamlead = mkPs('SCRUM461_Competitor_List_Teamleitung');
        insert new PermissionSetAssignment(AssigneeId = reader.Id, PermissionSetId = listRead.Id);
        insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = listRead.Id);
        insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = teamlead.Id);

        System.runAs(lead) {
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isAccessible(),
                'AC4: a team lead reads the list');
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isCreateable(),
                'AC4: only the team lead PS grants create');
            Competitor__c added = new Competitor__c(Company_Name__c = '461 Teamlead Competitor');
            Id addedId = insert added;
            System.assert(addedId != null, 'AC4: the team lead added a competitor');
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
            Competitor__c[] both = [SELECT Id, Company_Name__c FROM Competitor__c];
            System.assertEquals(2, both.size(),
                'AC4: both entries are selectable by a plain reader');

            boolean refused = false;
            try {
                insert new Competitor__c(Company_Name__c = '461 Reader Attempt');
            } catch (Exception e) {
                refused = true;
                System.debug('AC4 expected refusal: ' + e.getMessage());
            }
            System.assertEquals(true, refused,
                'AC4: the add attempt of a non-team-lead must be refused');
        }
    }
}
