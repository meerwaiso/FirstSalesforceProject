/**
 * [SCRUM-353] FLS negative + positive proof for FeldFinoIlsede__c.
 *
 * AC4 of SCRUM-353: a user WITHOUT the Permission Set SCRUM353_FeldFinoIlsede
 * must NOT see / read / write the field (FLS applies). This is the mandatory
 * negative test — no Done without it.
 *
 * AGENTS.md DoD requires every permission change to be proven against real
 * org behaviour with a user that does NOT have the new Permission Set. The
 * Test-Org holds exactly two licences (both System Administrators), so a
 * second browser session is impossible — System.runAs() creates a
 * licence-free test-context user and exercises REAL field-level security
 * (runAs does not bypass FLS; it does bypass some sharing, but that is not
 * asserted here).
 *
 * Design (1:1 from the verified SCRUM-344 pattern):
 *   1. temp user on the "Standard User" profile (Contact object CRUD by
 *      default, no FLS on the custom field — custom fields are invisible to
 *      standard profiles unless granted via a Permission Set)
 *   2. PRECONDITION: object-level Contact access is present, otherwise the
 *      FLS assertion below would pass for the wrong reason (missing object
 *      CRUD, not missing FLS)
 *   3. NEGATIVE (AC4): without PS → field not readable, not writable
 *   4. assign PS SCRUM353_FeldFinoIlsede to the temp user
 *   5. POSITIVE: with PS → field readable AND writable
 *
 * Everything created here (user, PermissionSetAssignment) rolls back with
 * the test transaction — the org is left untouched.
 *
 * Note (verified SCRUM-329 negative run, 2026-08-23): System Administrators
 * inherit FLS on custom fields even without a Permission Set — that is why
 * this test explicitly uses the Standard User profile and NOT a sys-admin.
 */
@isTest
private class SCRUM353FeldFinoIlsedeFlsTest {

    private static Schema.DescribeFieldResult field() {
        return Contact.FeldFinoIlsede__c.getDescribe();
    }

    @isTest
    static void feldFinoIlsede_notAccessibleWithoutPS_accessibleWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls353Neg',
            Alias = 'fls35',
            Email = 'fls353neg@example.invalid',
            Username = 'fls353neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE fails in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here: restricted picklist (verified)
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

        // 3. NEGATIVE (AC4): no Permission Set → field invisible.
        System.runAs(u) {
            System.assertEquals(
                false, field().isAccessible(),
                'Without PS SCRUM353_FeldFinoIlsede the field must NOT be readable (AC4)'
            );
            System.assertEquals(
                false, field().isUpdateable(),
                'Without PS SCRUM353_FeldFinoIlsede the field must NOT be writable (AC4)'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM353_FeldFinoIlsede' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set → field readable and writable.
        System.runAs(u) {
            System.assertEquals(
                true, field().isAccessible(),
                'With PS SCRUM353_FeldFinoIlsede the field must be readable'
            );
            System.assertEquals(
                true, field().isUpdateable(),
                'With PS SCRUM353_FeldFinoIlsede the field must be writable'
            );
        }
    }
}
