/**
 * [SCRUM-432] FLS negative + positive proof for the four Wiedervorlage fields
 * on Case (docs/SCRUM-432-design.md AC8).
 *
 * Without Permission Set SCRUM432_Wiedervorlage_ServiceTeam a user must NOT
 * read or write Wiedervorlage_Datum__c / _Notiz__c / _Von__c, and must NOT
 * even see Wiedervorlage_Heute_Offen__c (formel). With the Permission Set the
 * three storage fields must be readable AND writable, and the formula checkbox
 * must be readable but stay non-updatable (formula + editable=false).
 *
 * The Test-Org holds essentially two licences (both System Administrators), so
 * a second browser session for the negative proof is impossible. System.runAs()
 * creates a licence-free test-context user and exercises REAL field-level
 * security (runAs does not bypass FLS; it does bypass some sharing — sharing
 * is not asserted here).
 *
 * Design: 1:1 from the verified SCRUM-378 / SCRUM-390 / SCRUM-414
 * House-Pattern. Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM432WiedervorlageFlsTest {

    @isTest
    static void wiedervorlageFields_invisibleWithoutPS_visibleWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls432Neg',
            Alias = 'fls432',
            Email = 'fls432neg@example.invalid',
            Username = 'fls432neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // 1. PRECONDITION: object-level Case access exists, otherwise the FLS
        //    assertions below would pass for the wrong reason.
        System.runAs(u) {
            System.assert(
                Case.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Case object access - ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 2. NEGATIVE: no Permission Set -> none of the four fields visible.
        System.runAs(u) {
            System.assertEquals(
                false, Case.Wiedervorlage_Datum__c.getDescribe().isAccessible(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Datum__c must NOT be readable');
            System.assertEquals(
                false, Case.Wiedervorlage_Datum__c.getDescribe().isUpdateable(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Datum__c must NOT be writable');
            System.assertEquals(
                false, Case.Wiedervorlage_Notiz__c.getDescribe().isAccessible(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Notiz__c must NOT be readable');
            System.assertEquals(
                false, Case.Wiedervorlage_Notiz__c.getDescribe().isUpdateable(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Notiz__c must NOT be writable');
            System.assertEquals(
                false, Case.Wiedervorlage_Von__c.getDescribe().isAccessible(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Von__c must NOT be readable');
            System.assertEquals(
                false, Case.Wiedervorlage_Von__c.getDescribe().isUpdateable(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Von__c must NOT be writable');
            System.assertEquals(
                false, Case.Wiedervorlage_Heute_Offen__c.getDescribe().isAccessible(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Heute_Offen__c must NOT be readable');
            System.assertEquals(
                false, Case.Wiedervorlage_Heute_Offen__c.getDescribe().isUpdateable(),
                'Without PS SCRUM432_Wiedervorlage_ServiceTeam Wiedervorlage_Heute_Offen__c must NOT be writable');
        }

        // 3. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet
            WHERE Name = 'SCRUM432_Wiedervorlage_ServiceTeam' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 4. POSITIVE: with Permission Set -> storage fields readable + writable;
        //    formula readable but read-only (formula + editable=false).
        System.runAs(u) {
            System.assertEquals(
                true, Case.Wiedervorlage_Datum__c.getDescribe().isAccessible(),
                'With PS Wiedervorlage_Datum__c must be readable');
            System.assertEquals(
                true, Case.Wiedervorlage_Datum__c.getDescribe().isUpdateable(),
                'With PS Wiedervorlage_Datum__c must be writable');
            System.assertEquals(
                true, Case.Wiedervorlage_Notiz__c.getDescribe().isAccessible(),
                'With PS Wiedervorlage_Notiz__c must be readable');
            System.assertEquals(
                true, Case.Wiedervorlage_Notiz__c.getDescribe().isUpdateable(),
                'With PS Wiedervorlage_Notiz__c must be writable');
            System.assertEquals(
                true, Case.Wiedervorlage_Von__c.getDescribe().isAccessible(),
                'With PS Wiedervorlage_Von__c must be readable');
            System.assertEquals(
                true, Case.Wiedervorlage_Von__c.getDescribe().isUpdateable(),
                'With PS Wiedervorlage_Von__c must be writable');
            System.assertEquals(
                true, Case.Wiedervorlage_Heute_Offen__c.getDescribe().isAccessible(),
                'With PS Wiedervorlage_Heute_Offen__c must be readable');
            System.assertEquals(
                false, Case.Wiedervorlage_Heute_Offen__c.getDescribe().isUpdateable(),
                'With PS Wiedervorlage_Heute_Offen__c must remain read-only (formula + editable=false)');
        }
    }
}