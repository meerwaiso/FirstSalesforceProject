/**
 * [SCRUM-459] SCRUM459FollowupFlsTest - AC6 (typing refused) + AC12 (negative access).
 *
 * AC12: a user WITHOUT any follow-up Permission Set cannot see the obligation
 * object, its fields or the six monitoring values, and a save attempt on an
 * obligation fails. A brand-new Custom Object is FLS-gated by default (house
 * SCRUM417OpenOpportunityHistoryFlsTest, verified pattern).
 *
 * AC6: even WITH both Permission Sets the six monitoring fields stay
 * editable=false - a Permission Set can grant, never revoke, so the negative
 * proof is only meaningful while the test user holds the READ-PS (house lesson
 * SCRUM-442/449).
 *
 * Mixed-DML house rule (SCRUM-442): all setup inserts (User, PermissionSet)
 * first in System context - a user cannot grant himself a PermissionSet
 * assignment - then the business DML/SOQL inside System.runAs.
 *
 * @author developer-agent
 * @date 2026-10-31
 */
@isTest
private class SCRUM459FollowupFlsTest {

    @TestSetup
    static void setup_parentForObligationDml() {
        Account a = new Account(Name = '459 FLS Account');
        insert a;
        Opportunity o = new Opportunity(
            Name = '459 FLS Opp',
            AccountId = a.Id,
            StageName = 'Prospecting',
            Amount = 60000,
            CloseDate = Date.today() + 90
        );
        insert o;
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Fls459',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    @isTest
    static void obligationAndMonitoringFields_invisibleWithoutPS() {
        User neg = mkUser('fls459n');
        insert neg;

        System.runAs(neg) {
            // Precondition: the OBJECT is visible to a Standard User, otherwise
            // the field asserts below would pass for the wrong reason (house).
            Opportunity o = [SELECT Id FROM Opportunity WHERE Name = '459 FLS Opp' LIMIT 1];
            System.assert(o != null, 'precondition: fixture Opportunity readable');

            System.assertEquals(false,
                Followup_Obligation__c.SObjectType.getDescribe().isAccessible(),
                'AC12: obligation object must NOT be visible without the PS');
            System.assertEquals(false,
                Followup_Obligation__c.Opportunity__c.getDescribe().isAccessible(),
                'AC12: Opportunity__c not readable');
            System.assertEquals(false,
                Followup_Obligation__c.Status__c.getDescribe().isAccessible(),
                'AC12: Status__c not readable');
            System.assertEquals(false,
                Followup_Obligation__c.Due_Date__c.getDescribe().isAccessible(),
                'AC12: Due_Date__c not readable');
            System.assertEquals(false,
                Followup_Obligation__c.Completed_Date__c.getDescribe().isAccessible(),
                'AC12: Completed_Date__c not readable');
            System.assertEquals(false,
                Followup_Obligation__c.Next_Action__c.getDescribe().isAccessible(),
                'AC12: sensitive Next_Action__c not readable');
            System.assertEquals(false,
                Opportunity.Followup_Required__c.getDescribe().isAccessible(),
                'AC12: monitoring value not readable');
            System.assertEquals(false,
                Opportunity.Next_Followup_Date__c.getDescribe().isAccessible(),
                'AC12: Next_Followup_Date__c not readable');
            System.assertEquals(false,
                Opportunity.Overdue_Followup_Count__c.getDescribe().isAccessible(),
                'AC12: Overdue_Followup_Count__c not readable');
            System.assertEquals(false,
                Opportunity.Last_Customer_Interaction__c.getDescribe().isAccessible(),
                'AC12: Last_Customer_Interaction__c not readable');
            System.assertEquals(false,
                Opportunity.Followup_Status__c.getDescribe().isAccessible(),
                'AC12: Followup_Status__c not readable');
            System.assertEquals(false,
                Opportunity.Needs_Manager_Attention__c.getDescribe().isAccessible(),
                'AC12: Needs_Manager_Attention__c not readable');

            // AC12: a save attempt on an obligation fails.
            boolean saved = false;
            try {
                insert new Followup_Obligation__c(
                    Opportunity__c = o.Id,
                    Status__c = 'Outstanding',
                    Due_Date__c = Date.today() - 1,
                    Next_Action__c = 'must be refused'
                );
                saved = true;
            } catch (Exception e) {
                System.debug('AC12 expected refusal: ' + e.getMessage());
            }
            System.assertEquals(false, saved, 'AC12: save attempt on an obligation must fail without the PS');
        }
    }

    @isTest
    static void withBothPS_readableButNeverEditable() {
        User pos = mkUser('fls459p');
        insert pos;
        PermissionSet repPs = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM459_FollowupObligation_Rep' LIMIT 1];
        PermissionSet readPs = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM459_FollowupMonitoring_Read' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = pos.Id, PermissionSetId = repPs.Id);
        insert new PermissionSetAssignment(AssigneeId = pos.Id, PermissionSetId = readPs.Id);

        System.runAs(pos) {
            System.assertEquals(true,
                Followup_Obligation__c.SObjectType.getDescribe().isAccessible(),
                'With PS: obligation object readable (Sales Rep / Sales Manager)');
            System.assertEquals(true,
                Followup_Obligation__c.SObjectType.getDescribe().isCreateable(),
                'With PS: the rep may create an obligation');
            System.assertEquals(false,
                Followup_Obligation__c.SObjectType.getDescribe().isDeletable(),
                'AC: no sales role deletes an obligation (System Administrator only)');
            System.assertEquals(true,
                Followup_Obligation__c.Next_Action__c.getDescribe().isAccessible(),
                'With PS: sensitive Next_Action__c readable');

            // AC6: typing into the monitoring values is refused - not editable.
            System.assertEquals(true,
                Opportunity.Followup_Required__c.getDescribe().isAccessible(),
                'AC6: readable');
            System.assertEquals(false,
                Opportunity.Followup_Required__c.getDescribe().isUpdateable(),
                'AC6: not editable');
            System.assertEquals(false,
                Opportunity.Next_Followup_Date__c.getDescribe().isUpdateable(),
                'AC6: not editable');
            System.assertEquals(false,
                Opportunity.Overdue_Followup_Count__c.getDescribe().isUpdateable(),
                'AC6: typing into the overdue count is refused');
            System.assertEquals(false,
                Opportunity.Last_Customer_Interaction__c.getDescribe().isUpdateable(),
                'AC6: not editable');
            System.assertEquals(false,
                Opportunity.Followup_Status__c.getDescribe().isUpdateable(),
                'AC6: typing into the follow-up status is refused');
            System.assertEquals(false,
                Opportunity.Needs_Manager_Attention__c.getDescribe().isUpdateable(),
                'AC6: not editable');
        }
    }
}
