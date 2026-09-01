/**
 * [SCRUM-378] FLS negative + positive proof for Last_Attempt_Date__c +
 * Is_Due__c on Lead (Nachfassliste für Leads).
 *
 * SCRUM-378 AC8 ("Zugriff nur für Leads-Verantwortliche"): a user WITHOUT the
 * Permission Set SCRUM378_LeadNachfassung must NOT read or write either of
 * the two new Lead fields; a user WITH the Permission Set must read both and
 * write only Last_Attempt_Date__c (Is_Due__c is a read-only Formula — the PS
 * grants editable=false by design; even with the PS it must stay
 * non-updatable).
 *
 * The Test-Org holds exactly two licences (both System Administrators), so a
 * second browser session for the negative proof is impossible.
 * System.runAs() creates a licence-free test-context user and exercises REAL
 * field-level security (runAs does not bypass FLS; it does bypass some
 * sharing — sharing is not asserted here).
 *
 * Design: 1:1 from the verified SCRUM-359 / SCRUM-353 pattern.
 *   1. temp user on the "Standard User" profile (no FLS on the new fields)
 *   2. PRECONDITION: object-level Lead access is present, otherwise the
 *      FLS assertions below would pass for the wrong reason
 *   3. NEGATIVE: without PS → BOTH fields not readable, not writable
 *   4. assign PS SCRUM378_LeadNachfassung
 *   5. POSITIVE: with PS → BOTH readable; Last_Attempt_Date__c writable
 *
 * Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM378LeadNachfassungFlsTest {

    @isTest
    static void nachfassungFields_invisibleWithoutPS_visibleWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls378Neg',
            Alias = 'fls378',
            Email = 'fls378neg@example.invalid',
            Username = 'fls378neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
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

        // 3. NEGATIVE: no Permission Set → both fields invisible.
        System.runAs(u) {
            System.assertEquals(
                false, Lead.Last_Attempt_Date__c.getDescribe().isAccessible(),
                'Without PS SCRUM378_LeadNachfassung Last_Attempt_Date__c must NOT be readable'
            );
            System.assertEquals(
                false, Lead.Last_Attempt_Date__c.getDescribe().isUpdateable(),
                'Without PS SCRUM378_LeadNachfassung Last_Attempt_Date__c must NOT be writable'
            );
            System.assertEquals(
                false, Lead.Is_Due__c.getDescribe().isAccessible(),
                'Without PS SCRUM378_LeadNachfassung Is_Due__c must NOT be readable'
            );
            System.assertEquals(
                false, Lead.Is_Due__c.getDescribe().isUpdateable(),
                'Without PS SCRUM378_LeadNachfassung Is_Due__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM378_LeadNachfassung' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set → both readable; date writable.
        System.runAs(u) {
            System.assertEquals(
                true, Lead.Last_Attempt_Date__c.getDescribe().isAccessible(),
                'With PS SCRUM378_LeadNachfassung Last_Attempt_Date__c must be readable'
            );
            System.assertEquals(
                true, Lead.Last_Attempt_Date__c.getDescribe().isUpdateable(),
                'With PS SCRUM378_LeadNachfassung Last_Attempt_Date__c must be writable'
            );
            System.assertEquals(
                true, Lead.Is_Due__c.getDescribe().isAccessible(),
                'With PS SCRUM378_LeadNachfassung Is_Due__c must be readable'
            );
            // Is_Due__c is a Formula Checkbox: even WITH the PS it must stay
            // non-updatable (PS grants editable=false; formula nature reinforces).
            System.assertEquals(
                false, Lead.Is_Due__c.getDescribe().isUpdateable(),
                'With PS SCRUM378_LeadNachfassung Is_Due__c must remain read-only (formula + editable=false)'
            );
        }
    }
}
