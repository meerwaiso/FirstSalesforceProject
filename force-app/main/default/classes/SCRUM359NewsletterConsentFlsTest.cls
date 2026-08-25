/**
 * [SCRUM-359] FLS negative + positive proof for NewsletterConsent__c +
 * ConsentDate__c.
 *
 * SCRUM-359 acceptance criteria (newsletter consent on Contact): a user
 * WITHOUT the Permission Set SCRUM359_NewsletterConsent must NOT see /
 * read / write either of the two new custom fields; a user WITH the
 * Permission Set must read AND write both. Custom fields are invisible to
 * the Standard User profile by default, which is what makes the negative
 * assertion meaningful.
 *
 * The Test-Org holds exactly two licences (both System Administrators), so
 * a second browser session is impossible — System.runAs() creates a
 * licence-free test-context user and exercises REAL field-level security
 * (runAs does not bypass FLS; it does bypass some sharing, but that is not
 * asserted here).
 *
 * Design (1:1 from the verified SCRUM-353 / SCRUM-344 pattern):
 *   1. temp user on the "Standard User" profile (Contact object CRUD by
 *      default, no FLS on the new custom fields)
 *   2. PRECONDITION: object-level Contact access is present, otherwise the
 *      FLS assertions below would pass for the wrong reason (missing
 *      object CRUD, not missing FLS)
 *   3. NEGATIVE: without PS → BOTH fields not readable, not writable
 *   4. assign PS SCRUM359_NewsletterConsent to the temp user
 *   5. POSITIVE: with PS → BOTH fields readable AND writable
 *
 * Everything created here (user, PermissionSetAssignment) rolls back with
 * the test transaction — the org is left untouched.
 *
 * Note (verified SCRUM-329 negative run, 2026-08-23): System Administrators
 * inherit FLS on custom fields even without a Permission Set — that is why
 * this test explicitly uses the Standard User profile and NOT a sys-admin.
 */
@isTest
private class SCRUM359NewsletterConsentFlsTest {

    @isTest
    static void newsletterConsent_fieldsInvisibleWithoutPS_visibleWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls359Neg',
            Alias = 'fls39',
            Email = 'fls359neg@example.invalid',
            Username = 'fls359neg_' + DateTime.now().getTime() + '@example.invalid',
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

        // 3. NEGATIVE: no Permission Set → both fields invisible.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.NewsletterConsent__c.getDescribe().isAccessible(),
                'Without PS SCRUM359_NewsletterConsent NewsletterConsent__c must NOT be readable'
            );
            System.assertEquals(
                false, Contact.NewsletterConsent__c.getDescribe().isUpdateable(),
                'Without PS SCRUM359_NewsletterConsent NewsletterConsent__c must NOT be writable'
            );
            System.assertEquals(
                false, Contact.ConsentDate__c.getDescribe().isAccessible(),
                'Without PS SCRUM359_NewsletterConsent ConsentDate__c must NOT be readable'
            );
            System.assertEquals(
                false, Contact.ConsentDate__c.getDescribe().isUpdateable(),
                'Without PS SCRUM359_NewsletterConsent ConsentDate__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM359_NewsletterConsent' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set → both fields readable and writable.
        System.runAs(u) {
            System.assertEquals(
                true, Contact.NewsletterConsent__c.getDescribe().isAccessible(),
                'With PS SCRUM359_NewsletterConsent NewsletterConsent__c must be readable'
            );
            System.assertEquals(
                true, Contact.NewsletterConsent__c.getDescribe().isUpdateable(),
                'With PS SCRUM359_NewsletterConsent NewsletterConsent__c must be writable'
            );
            System.assertEquals(
                true, Contact.ConsentDate__c.getDescribe().isAccessible(),
                'With PS SCRUM359_NewsletterConsent ConsentDate__c must be readable'
            );
            System.assertEquals(
                true, Contact.ConsentDate__c.getDescribe().isUpdateable(),
                'With PS SCRUM359_NewsletterConsent ConsentDate__c must be writable'
            );
        }
    }
}
