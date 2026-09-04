/**
 * [SCRUM-386] FLS negative + positive proof for Likely_Duplicate__c,
 * Duplicate_Of__c and Email_Norm__c (Dubletten-Markierung auf Lead).
 *
 * Pattern 1:1 from SCRUM-378 / SCRUM-359: temp user on "Standard User" profile
 * (no FLS on the new custom fields by default), precondition Lead object access,
 * NEGATIVE without PS (all 3 fields not readable, not writable), then grant PS
 * SCRUM-386_LeadDuplicate, POSITIVE with PS (all 3 fields readable AND writable).
 *
 * System Administrators inherit FLS on custom fields — that is why the Standard
 * User profile is used (verified SCRUM-329). Everything rolls back with the test
 * transaction.
 */
@isTest
private class SCRUM386LeadDuplicateFlsTest {

    private static void assertInvisible(Schema.SObjectField f, String label) {
        System.assertEquals(false, f.getDescribe().isAccessible(), label + ' must NOT be readable without PS');
        System.assertEquals(false, f.getDescribe().isUpdateable(), label + ' must NOT be writable without PS');
    }

    private static void assertVisible(Schema.SObjectField f, String label) {
        System.assertEquals(true, f.getDescribe().isAccessible(), label + ' must be readable with PS');
        System.assertEquals(true, f.getDescribe().isUpdateable(), label + ' must be writable with PS');
    }

    @isTest
    static void dupFields_invisibleWithoutPS_visibleWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'FlS386Neg',
            Alias = 'fls386',
            Email = 'fls386neg@example.invalid',
            Username = 'fls386neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        System.runAs(u) {
            System.assert(
                Lead.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Lead object access'
            );
        }

        System.runAs(u) {
            assertInvisible(Lead.Likely_Duplicate__c, 'Likely_Duplicate__c');
            assertInvisible(Lead.Duplicate_Of__c, 'Duplicate_Of__c');
            assertInvisible(Lead.Email_Norm__c, 'Email_Norm__c');
        }

        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM386_LeadDuplicate' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        System.runAs(u) {
            assertVisible(Lead.Likely_Duplicate__c, 'Likely_Duplicate__c');
            assertVisible(Lead.Duplicate_Of__c, 'Duplicate_Of__c');
            assertVisible(Lead.Email_Norm__c, 'Email_Norm__c');
        }
    }
}