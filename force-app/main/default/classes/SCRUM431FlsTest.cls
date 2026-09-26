/**
 * [SCRUM-431] FLS negative + positive proof for the two new fields.
 *
 * A user WITHOUT the Permission Sets must NOT see either field (the
 * Standard-User profile carries no FLS on custom fields — asserted as a
 * precondition, house pattern SCRUM359/344/353). The ServiceTeam PS grants
 * read-only on both; the Teamleitung PS grants read+edit on the Account
 * field, read-only on the Case formula field (a formula field is never
 * updatable — asserted, not assumed).
 *
 * Everything created rolls back with the test transaction.
 */
@isTest
private class SCRUM431FlsTest {

    private static User newStandardUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls431',
            Alias = 'fls431',
            Email = 'fls431-' + tag + '@example.invalid',
            Username = 'fls431-' + tag + '-' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE fails in this org (house note 359)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static void assignPS(String name, Id assigneeId) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = assigneeId, PermissionSetId = ps.Id);
    }

    @isTest
    static void fieldsInvisibleWithoutPS() {
        User u = newStandardUser('neg');
        System.runAs(u) {
            // Preconditions: object CRUD present — a negative FLS result
            // proves FLS, not a missing object.
            System.assertTrue(
                Account.SObjectType.getDescribe().isAccessible(),
                'Precondition: Standard User needs Account object access');
            System.assertTrue(
                Case.SObjectType.getDescribe().isAccessible(),
                'Precondition: Standard User needs Case object access');
            // Negative: neither field is readable without the SCRUM431 PS.
            System.assertEquals(
                false, Wartungsvertrag__c.getDescribe().isAccessible(),
                'Account field must NOT be readable without the SCRUM431 PS');
            System.assertEquals(
                false, Wartungsvertrag_Anzeige__c.getDescribe().isAccessible(),
                'Case field must NOT be readable without the SCRUM431 PS');
        }
    }

    @isTest
    static void serviceTeamReadsBothCannotEdit() {
        User u = newStandardUser('svc');
        assignPS('SCRUM431_Wartungsvertrag_ServiceTeam', u.Id);
        System.runAs(u) {
            System.assertEquals(true, Wartungsvertrag__c.getDescribe().isAccessible(),
                'ServiceTeam must READ the Account field');
            System.assertEquals(false, Wartungsvertrag__c.getDescribe().isUpdateable(),
                'ServiceTeam must NOT EDIT the Account field');
            System.assertEquals(true, Wartungsvertrag_Anzeige__c.getDescribe().isAccessible(),
                'ServiceTeam must READ the Case field');
            System.assertEquals(false, Wartungsvertrag_Anzeige__c.getDescribe().isUpdateable(),
                'The Case field is a formula field — never updatable');
        }
    }

    @isTest
    static void teamleitungReadsAndEditsAccountField() {
        User u = newStandardUser('team');
        assignPS('SCRUM431_Wartungsvertrag_Teamleitung', u.Id);
        System.runAs(u) {
            System.assertEquals(true, Wartungsvertrag__c.getDescribe().isAccessible(),
                'Teamleitung must READ the Account field');
            System.assertEquals(true, Wartungsvertrag__c.getDescribe().isUpdateable(),
                'Teamleitung must EDIT the Account field');
            System.assertEquals(true, Wartungsvertrag_Anzeige__c.getDescribe().isAccessible(),
                'Teamleitung must READ the Case field');
            System.assertEquals(false, Wartungsvertrag_Anzeige__c.getDescribe().isUpdateable(),
                'The Case field is a formula field — never updatable');
        }
    }
}
