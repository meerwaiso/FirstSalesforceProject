/**
 * [SCRUM-382] FLS negative + positive proof for Account.Customer_Since_Days__c
 * (Kunde seit (Tage), read-only Number formula).
 *
 * PO-AC "keine Berechtigungssteuerung, das Feld ist für alle sichtbar" is
 * reached in the org by assigning the Permission Set to the users (a
 * Deployment follow-up for @devops-agent). But a brand-new custom field is
 * FLS-gated by default: a user WITHOUT the Permission Set cannot read it.
 * This test proves both sides against REAL org behaviour:
 *   1. temp user on the "Standard User" profile (no FLS on the new field)
 *   2. PRECONDITION: Account object-level access is present, otherwise the
 *      FLS assertions below would pass for the wrong reason
 *   3. NEGATIVE: without PS → field not readable, not writable
 *   4. assign PS SCRUM382_CustomerSinceDays
 *   5. POSITIVE: with PS → field readable; still NOT writable (read-only
 *      Formula + PS editable=false)
 *
 * The Test-Org holds exactly two licences (both System Administrators), so a
 * second browser session for the negative proof is impossible. System.runAs()
 * creates a licence-free test-context user and exercises real FLS (runAs does
 * not bypass FLS). Everything created here rolls back with the test txn.
 *
 * 1:1 from the verified SCRUM-378 / SCRUM-359 pattern.
 */
@isTest
private class SCRUM382CustomerSinceDaysFlsTest {

    @isTest
    static void customerSinceDays_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls382Neg',
            Alias = 'fls382',
            Email = 'fls382neg@example.invalid',
            Username = 'fls382neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
        );
        insert u;

        // 2. Precondition: Standard User has Account object access.
        System.runAs(u) {
            System.assert(
                Account.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Account object access — ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 3. NEGATIVE: no Permission Set → field is invisible.
        System.runAs(u) {
            System.assertEquals(
                false, Account.Customer_Since_Days__c.getDescribe().isAccessible(),
                'Without PS SCRUM382_CustomerSinceDays Customer_Since_Days__c must NOT be readable'
            );
            System.assertEquals(
                false, Account.Customer_Since_Days__c.getDescribe().isUpdateable(),
                'Without PS SCRUM382_CustomerSinceDays Customer_Since_Days__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM382_CustomerSinceDays' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set → readable; stays read-only.
        System.runAs(u) {
            System.assertEquals(
                true, Account.Customer_Since_Days__c.getDescribe().isAccessible(),
                'With PS SCRUM382_CustomerSinceDays Customer_Since_Days__c must be readable'
            );
            // Read-only Formula + PS editable=false: even with the PS it is never writable.
            System.assertEquals(
                false, Account.Customer_Since_Days__c.getDescribe().isUpdateable(),
                'With PS SCRUM382_CustomerSinceDays Customer_Since_Days__c must remain read-only (formula + editable=false)'
            );
        }
    }
}
