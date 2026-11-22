/**
 * [SCRUM-470] FLS positiv + negativ for Contact.Preferred_Contact_Method__c (AC6).
 *
 * House pattern SCRUM430RueckrufZeitfensterFlsTest (same object, same Read+Edit PS)
 * and SCRUM382CustomerSinceDaysFlsTest:
 *   1. temp User on the "Standard User" profile (no FLS on the new field)
 *   2. PRECONDITION first: object-level Contact access, otherwise every FLS assert
 *      below would be green for the WRONG reason (missing Contact CRUD, not FLS)
 *   3. NEGATIVE: without the PS the field is not readable (SELECT throws)
 *   4. assign PS SCRUM470_ContactContactWay
 *   5. POSITIVE: with the PS the field is readable AND writable
 *
 * The negative is a PROBE, not an assumption (ADR-5): the Standard-User profile must
 * block the field for the negative to mean anything. Measured for THIS field in the
 * handoff comment (FieldPermissions read-back) — the SCRUM-430 conclusion is NOT
 * inherited: `SELECT … FieldPermissions WHERE Field='Contact.Preferred_Contact_Method__c'`
 * must show only the PermissionSet row (IsOwnedByProfile=false). If a Profile row
 * granted it, the negative could pass only by luck and this class is the wrong oracle.
 *
 * Test-Org holds 2/2 System-Administrator licences, so a second low-privilege browser
 * session for the negative proof is impossible (house finding SCRUM-405) → AC6 belongs
 * to this class, System.runAs() does NOT bypass FLS.
 */
@isTest
private class SCRUM470PreferredContactMethodFlsTest {

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Fls470',
            Alias                = 'f470' + tag,
            Email                = 'f470' + tag + '@example.invalid',
            Username             = 'f470' + tag + System.now().getTime() + '@example.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static Boolean contactReadableBy(final User u) {
        Boolean readable = false;
        System.runAs(u) {
            readable = Contact.SObjectType.getDescribe().isAccessible();
        }
        return readable;
    }

    // ---- Precondition: Standard User has object-level Contact access -------
    @isTest
    static void precondition_contact_object_access() {
        User u = mkTestUser('pre');
        System.assert(
            contactReadableBy(u),
            'Precondition failed: the Standard User has no object-level Contact access — '
                + 'every FLS assert below would be green for the wrong reason.'
                + ' A test-local object-access PS is needed then (house SCRUM442/451/464/467_TestObjectAccess).'
        );
    }

    // ---- AC6 NEGATIVE: without the PS the field is not readable ------------
    @isTest
    static void withoutPS_field_not_readable() {
        User u = mkTestUser('neg');
        System.assert(
            contactReadableBy(u),
            'Precondition failed: Standard User has no Contact access — the exception below '
                + 'would come from the missing CRUD, not from the missing FLS.'
        );

        Boolean threw = false;
        System.runAs(u) {
            try {
                List<Contact> rows = [SELECT Preferred_Contact_Method__c FROM Contact WITH USER_MODE LIMIT 1];
                // Even an empty result list means the column RESOLVED → FLS present → the AC fails.
                System.assert(
                    false,
                    'Without PS SCRUM470_ContactContactWay: SELECT on Preferred_Contact_Method__c must NOT resolve (AC6).'
                );
            } catch (Exception e) {
                threw = true; // 'No such column' / SecurityException — wording differs, both are the wall.
            }
        }
        System.assert(
            threw,
            'Without PS SCRUM470_ContactContactWay: reading Preferred_Contact_Method__c must hit the FLS wall (AC6).'
        );

        // Not writable either (AC6: users without the PS may neither see nor set it).
        Boolean schemaWritable = false;
        System.runAs(u) {
            schemaWritable = Contact.Preferred_Contact_Method__c.getDescribe().isUpdateable();
        }
        System.assertEquals(
            false, schemaWritable,
            'Without PS: Preferred_Contact_Method__c must not be updateable (AC6).'
        );
    }

    // ---- AC3 POSITIVE: with the PS the field is readable and writable ------
    @isTest
    static void withPS_readable_and_writable() {
        User u = mkTestUser('pos');
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM470_ContactContactWay' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        Boolean readable;
        System.runAs(u) {
            readable = Contact.Preferred_Contact_Method__c.getDescribe().isAccessible();
        }
        System.assert(readable, 'With PS: Preferred_Contact_Method__c must be readable (AC3).');

        Id contactId;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-FLS-POS', Preferred_Contact_Method__c = 'Letter');
            insert c;
            contactId = c.Id;
        }

        String read1;
        System.runAs(u) {
            read1 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :contactId LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Letter', read1, 'With PS: SELECT returns the value that was entered (AC3).');

        System.runAs(u) {
            Contact c2 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :contactId LIMIT 1];
            c2.Preferred_Contact_Method__c = 'Email';
            update c2; // no exception = writable by a PS holder (AC3)
        }

        String read2;
        System.runAs(u) {
            read2 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :contactId LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Email', read2, 'With PS: the PS holder changed the value (AC3).');
    }
}
