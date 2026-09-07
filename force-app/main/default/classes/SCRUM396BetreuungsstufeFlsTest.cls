/**
 * [SCRUM-396] FLS negative + positive proof for Contact.Betreuungsstufe__c
 * („Betreuungsstufe“, read-only Text formula).
 *
 * The field ships with a read-only FLS Permission Set
 * SCRUM396_Betreuungsstufe. A brand-new custom field is FLS-gated by default:
 * a user WITHOUT the Permission Set cannot read it. This test proves both
 * sides against REAL org behaviour:
 *   1. temp user on the „Standard User" profile (no FLS on the new field)
 *   2. PRECONDITION: Contact object-level access is present, otherwise the
 *      FLS assertions below would pass for the wrong reason
 *   3. NEGATIVE: without PS -> field not readable, not writable
 *   4. assign PS SCRUM396_Betreuungsstufe
 *   5. POSITIVE: with PS -> field readable; still NOT writable (read-only
 *      Formula + PS editable=false)
 *
 * 1:1 house shape: SCRUM382CustomerSinceDaysFlsTest.cls (SCRUM-378/359
 * pattern), Contact version (SCRUM-394 shape for the Lead equivalent).
 * Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM396BetreuungsstufeFlsTest {

    @isTest
    static void betreuungsstufe_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls396Neg',
            Alias = 'fls396',
            Email = 'fls396neg@example.invalid',
            Username = 'fls396neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified, SCRUM-382)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified, SCRUM-382)
        );
        insert u;

        // 2. Precondition: Standard User has Contact object access.
        System.runAs(u) {
            System.assert(
                Contact.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Contact object access — ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 3. NEGATIVE: no Permission Set -> field is invisible.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.Betreuungsstufe__c.getDescribe().isAccessible(),
                'Without PS SCRUM396_Betreuungsstufe Betreuungsstufe__c must NOT be readable'
            );
            System.assertEquals(
                false, Contact.Betreuungsstufe__c.getDescribe().isUpdateable(),
                'Without PS SCRUM396_Betreuungsstufe Betreuungsstufe__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM396_Betreuungsstufe' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set -> readable; stays read-only.
        System.runAs(u) {
            System.assertEquals(
                true, Contact.Betreuungsstufe__c.getDescribe().isAccessible(),
                'With PS SCRUM396_Betreuungsstufe Betreuungsstufe__c must be readable'
            );
            // Read-only Formula + PS editable=false: even with the PS it is never writable.
            System.assertEquals(
                false, Contact.Betreuungsstufe__c.getDescribe().isUpdateable(),
                'With PS SCRUM396_Betreuungsstufe Betreuungsstufe__c must remain read-only (formula + editable=false)'
            );
        }
    }
}
