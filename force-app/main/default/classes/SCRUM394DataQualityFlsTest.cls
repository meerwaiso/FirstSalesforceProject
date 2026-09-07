/**
 * [SCRUM-394] FLS negative + positive proof for Lead.Data_Quality__c
 * ("Datenqualität", read-only Text formula).
 *
 * The field ships with a read-only FLS Permission Set
 * SCRUM394_LeadDataQuality. A brand-new custom field is FLS-gated by default:
 * a user WITHOUT the Permission Set cannot read it. This test proves both
 * sides against REAL org behaviour:
 *   1. temp user on the "Standard User" profile (no FLS on the new field)
 *   2. PRECONDITION: Lead object-level access is present, otherwise the FLS
 *      assertions below would pass for the wrong reason
 *   3. NEGATIVE: without PS -> field not readable, not writable
 *   4. assign PS SCRUM394_LeadDataQuality
 *   5. POSITIVE: with PS -> field readable; still NOT writable (read-only
 *      Formula + PS editable=false)
 *
 * 1:1 house shape: SCRUM382CustomerSinceDaysFlsTest.cls (SCRUM-378/359 pattern).
 * Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM394DataQualityFlsTest {

    @isTest
    static void dataQuality_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls394Neg',
            Alias = 'fls394',
            Email = 'fls394neg@example.invalid',
            Username = 'fls394neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified, SCRUM-382)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified, SCRUM-382)
        );
        insert u;

        // 2. Precondition: Standard User has Lead object access.
        System.runAs(u) {
            System.assert(
                Lead.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Lead object access — ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 3. NEGATIVE: no Permission Set -> field is invisible.
        System.runAs(u) {
            System.assertEquals(
                false, Lead.Data_Quality__c.getDescribe().isAccessible(),
                'Without PS SCRUM394_LeadDataQuality Data_Quality__c must NOT be readable'
            );
            System.assertEquals(
                false, Lead.Data_Quality__c.getDescribe().isUpdateable(),
                'Without PS SCRUM394_LeadDataQuality Data_Quality__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM394_LeadDataQuality' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set -> readable; stays read-only.
        System.runAs(u) {
            System.assertEquals(
                true, Lead.Data_Quality__c.getDescribe().isAccessible(),
                'With PS SCRUM394_LeadDataQuality Data_Quality__c must be readable'
            );
            // Read-only Formula + PS editable=false: even with the PS it is never writable.
            System.assertEquals(
                false, Lead.Data_Quality__c.getDescribe().isUpdateable(),
                'With PS SCRUM394_LeadDataQuality Data_Quality__c must remain read-only (formula + editable=false)'
            );
        }
    }
}
