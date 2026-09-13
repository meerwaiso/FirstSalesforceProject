/**
 * [SCRUM-413] FLS: negative + positive proof.
 */
@isTest
private class SCRUM413LastRealContactDateFlsTest {
    @isTest static void field_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id, LastName = 'Fls413', Alias = 'f413',
            Email = 'fls413_' + DateTime.now().getTime() + '@example.invalid',
            Username = 'fls413_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        System.runAs(u) {
            System.assert(Contact.SObjectType.getDescribe().isAccessible());
        }
        System.runAs(u) {
            System.assertEquals(false, Contact.Last_Real_Contact_Date__c.getDescribe().isAccessible(), 'Ohne PS: nicht lesbar');
            System.assertEquals(false, Contact.Last_Real_Contact_Date__c.getDescribe().isUpdateable(), 'Ohne PS: nicht updater');
        }
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM413_LastRealContactDate' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        System.runAs(u) {
            System.assertEquals(true, Contact.Last_Real_Contact_Date__c.getDescribe().isAccessible(), 'Mit PS: lesbar');
            System.assertEquals(false, Contact.Last_Real_Contact_Date__c.getDescribe().isUpdateable(), 'Mit PS: NICHT updater');
        }
    }
}
