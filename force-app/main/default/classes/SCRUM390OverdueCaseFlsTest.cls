/**
 * [SCRUM-390] FLS negative + positive proof for the two Case formula fields
 *   Case.Processing_Duration__c  (Bearbeitungsdauer (Tage), read-only Number formula)
 *   Case.Is_Overdue__c           (Überfällig, read-only Checkbox formula)
 *
 * PO-AC "read-only FLS, kein Write-PS" is reached in the org by assigning the
 * Permission Set SCRUM390_OverdueCase to the users (a Deployment follow-up for
 * @devops-agent). But a brand-new custom field is FLS-gated by default: a user
 * WITHOUT the Permission Set cannot read it. This test proves both sides against
 * REAL org behaviour for BOTH fields:
 *   1. temp user on the "Standard User" profile (no FLS on either new field)
 *   2. PRECONDITION: Case object-level access is present, otherwise the FLS
 *      assertions below would pass for the wrong reason
 *   3. NEGATIVE: without PS -> neither field readable, neither writable
 *   4. assign PS SCRUM390_OverdueCase
 *   5. POSITIVE: with PS -> both fields readable; both remain NOT writable
 *      (read-only Formula + PS editable=false)
 *
 * The Test-Org holds exactly two licences (both System Administrators), so a
 * second browser session for the negative proof is impossible. System.runAs()
 * creates a licence-free test-context user and exercises real FLS (runAs does
 * not bypass FLS). Everything created here rolls back with the test txn.
 *
 * 1:1 from the verified SCRUM-382 / SCRUM-365 pattern.
 */
@isTest
private class SCRUM390OverdueCaseFlsTest {

    @isTest
    static void overdueCaseFields_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls390Neg',
            Alias = 'fls390',
            Email = 'fls390neg@example.invalid',
            Username = 'fls390neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
        );
        insert u;

        // 2. Precondition: Standard User has Case object access.
        System.runAs(u) {
            System.assert(
                Case.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Case object access - ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 3. NEGATIVE: no Permission Set -> neither field is visible.
        System.runAs(u) {
            System.assertEquals(
                false, Case.Processing_Duration__c.getDescribe().isAccessible(),
                'Without PS SCRUM390_OverdueCase Processing_Duration__c must NOT be readable'
            );
            System.assertEquals(
                false, Case.Processing_Duration__c.getDescribe().isUpdateable(),
                'Without PS SCRUM390_OverdueCase Processing_Duration__c must NOT be writable'
            );
            System.assertEquals(
                false, Case.Is_Overdue__c.getDescribe().isAccessible(),
                'Without PS SCRUM390_OverdueCase Is_Overdue__c must NOT be readable'
            );
            System.assertEquals(
                false, Case.Is_Overdue__c.getDescribe().isUpdateable(),
                'Without PS SCRUM390_OverdueCase Is_Overdue__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM390_OverdueCase' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set -> both readable; both stay read-only.
        System.runAs(u) {
            System.assertEquals(
                true, Case.Processing_Duration__c.getDescribe().isAccessible(),
                'With PS SCRUM390_OverdueCase Processing_Duration__c must be readable'
            );
            System.assertEquals(
                false, Case.Processing_Duration__c.getDescribe().isUpdateable(),
                'With PS SCRUM390_OverdueCase Processing_Duration__c must remain read-only (formula + editable=false)'
            );
            System.assertEquals(
                true, Case.Is_Overdue__c.getDescribe().isAccessible(),
                'With PS SCRUM390_OverdueCase Is_Overdue__c must be readable'
            );
            // Read-only Formula + PS editable=false: even with the PS it is never writable.
            System.assertEquals(
                false, Case.Is_Overdue__c.getDescribe().isUpdateable(),
                'With PS SCRUM390_OverdueCase Is_Overdue__c must remain read-only (formula + editable=false)'
            );
        }
    }
}
