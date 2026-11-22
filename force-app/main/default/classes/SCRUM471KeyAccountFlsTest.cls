/**
 * [SCRUM-471] FLS positive + negative probes for Account.Is_Key_Account__c
 * (AC5 read-but-cannot-change, AC6 no record access -> nothing visible,
 * AC7 change rejected).
 *
 * House pattern SCRUM470PreferredContactMethodFlsTest / SCRUM442_Satisfaction /
 * SCRUM453_ContactLeft: a temp User on the "Standard User" profile, PS assigned
 * inside the test, getDescribe() READ inside System.runAs and ASSERTED outside any
 * try (falsifiability: an assert inside the try of a SELECT can never fail).
 *
 * Three user states — the split that makes the negatives mean anything:
 *   1. no PS at all          -> neither readable nor writable   (AC6 / AC7 baseline)
 *   2. Read PS only          -> readable, NOT writable          (AC5, AC7)
 *   3. Read PS + Set PS      -> readable AND writable           (AC2, AC3)
 *
 * The negatives are a PROBE, not an assumption (ADR-5 / SCRUM-421 vs SCRUM-430
 * contradiction): measured for THIS field in Test-Org on 2026-11-22,
 *   SELECT Parent.Label, Parent.IsOwnedByProfile, PermissionsRead, PermissionsEdit
 *   FROM FieldPermissions WHERE SobjectType='Account' AND Field='Account.Is_Key_Account__c'
 * -> 3 rows, ALL IsOwnedByProfile=false (the two PSs of this ticket plus the org PS
 * "Agentic Near Core CRM", which is assigned to nobody). NO Profile row: the
 * Standard User profile grants nothing on the new field, so a PS-less user is
 * genuinely blocked and these asserts test the FLS wall, not a lucky default.
 *
 * Test-Org holds 2/2 System-Administrator licences, so a second low-privilege
 * browser session for the negative proof is impossible (house finding SCRUM-405)
 * -> the AC5/AC6/AC7 negatives belong to THIS class; System.runAs() does NOT
 * bypass FLS.
 */
@isTest
private class SCRUM471KeyAccountFlsTest {

    private static final String PS_READ = 'SCRUM471_KeyAccount_Read';
    private static final String PS_SET = 'SCRUM471_KeyAccount_Set';

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Fls471',
            Alias                = 'f471' + tag,
            Email                = 'f471' + tag + sfx + '@x.invalid',
            Username             = 'f471' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static Boolean accountReadableBy(final User u) {
        Boolean readable = false;
        System.runAs(u) {
            readable = Account.SObjectType.getDescribe().isAccessible();
        }
        return readable;
    }

    private static Boolean markReadableBy(final User u) {
        Boolean readable = false;
        System.runAs(u) {
            readable = Account.Is_Key_Account__c.getDescribe().isAccessible();
        }
        return readable;
    }

    private static Boolean markWritableBy(final User u) {
        Boolean writable = false;
        System.runAs(u) {
            writable = Account.Is_Key_Account__c.getDescribe().isUpdateable();
        }
        return writable;
    }

    private static void assignNamedPs(final User u, final List<String> names) {
        List<PermissionSet> psList =
            [SELECT Id, Name FROM PermissionSet WHERE Name IN :names];
        System.assertEquals(names.size(), psList.size(),
            'Precondition: every named PS must exist in the org, otherwise the asserts below test nothing.');
        for (PermissionSet ps : psList) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    // ---- PRECONDITION first: Standard User has object-level Account access ---
    @isTest
    static void precondition_standard_user_reads_account() {
        User u = mkTestUser('pre');
        System.assert(
            accountReadableBy(u),
            'Precondition failed: the Standard User has no object-level Account access — '
                + 'every FLS assert below would then be green for the WRONG reason '
                + '(missing Account CRUD, not missing FLS). A test-local *_TestObjectAccess PS is needed then (house SCRUM442/451/464/467).'
        );
    }

    // ---- AC6/AC7 NEGATIVE: no PS at all --------------------------------------
    @isTest
    static void withoutPS_mark_invisible_and_unwritable() {
        User u = mkTestUser('none');
        System.assert(
            accountReadableBy(u),
            'Precondition: Standard User must read Account, otherwise the wall below is missing CRUD, not FLS.'
        );

        // FALSIFIABLE half 1: asserted OUTSIDE any try — readable=true reddens this.
        Boolean readable = markReadableBy(u);
        System.assertEquals(false, readable,
            'AC6: without any PS the mark must NOT be readable (nothing visible).');

        // FALSIFIABLE half 2: the SOQL probe — ONLY the SELECT sits in the try.
        Boolean threw = false;
        System.runAs(u) {
            try {
                List<Account> rows = [SELECT Is_Key_Account__c FROM Account WITH USER_MODE LIMIT 1];
            } catch (Exception e) {
                threw = true; // 'No such column' / SecurityException — both are the FLS wall
            }
        }
        System.assert(threw,
            'AC6: reading the mark without a PS must hit the FLS wall.');

        Boolean writable = markWritableBy(u);
        System.assertEquals(false, writable,
            'AC7: without the Set PS the mark must not be updateable.');
    }

    // ---- AC5: read-but-cannot-change (Read PS, no Set PS) -------------------
    @isTest
    static void readPS_only_readable_not_writable() {
        User u = mkTestUser('read');
        assignNamedPs(u, new List<String>{ PS_READ });
        System.assert(
            accountReadableBy(u),
            'Precondition: Standard User must read Account, otherwise the split below proves nothing.'
        );

        Boolean readable = markReadableBy(u);
        System.assertEquals(true, readable,
            'AC4/AC5: with SCRUM471_KeyAccount_Read the mark IS visible.');

        Boolean writable = markWritableBy(u);
        System.assertEquals(false, writable,
            'AC5/AC7: with the Read PS only the mark is NOT updateable.');

        // The runtime refusal, falsifiable: an update that SUCCEEDS leaves threw=false
        // and reddens the assert below.
        Boolean threw = false;
        System.runAs(u) {
            try {
                Account a = new Account(Name = 'TEST-SCRUM-471-AC7', Is_Key_Account__c = true);
                insert a;
            } catch (Exception e) {
                threw = true;
            }
        }
        System.assert(threw,
            'AC7: a colleague who may read but not edit customers must be REFUSED when writing the mark.');
    }

    // ---- AC2/AC3 POSITIVE: Read + Set -> set AND clear by hand --------------
    @isTest
    static void readAndSetPS_writable_both_ways() {
        User u = mkTestUser('both');
        assignNamedPs(u, new List<String>{ PS_READ, PS_SET });
        System.assert(
            accountReadableBy(u),
            'Precondition: the PS holder must read Account.'
        );

        System.assert(markReadableBy(u), 'AC4: with the Read PS the mark is visible.');
        System.assert(markWritableBy(u), 'AC2/AC3: with the Set PS the mark is writable.');

        Id accountId;
        Boolean setTo;
        System.runAs(u) {
            Account a = new Account(Name = 'TEST-SCRUM-471-FLS-POS');
            insert a;
            accountId = a.Id;
        }

        System.runAs(u) {
            Account setFresh = new Account();
            setFresh.Id = accountId;
            setFresh.Is_Key_Account__c = true;
            update setFresh; // AC2: setting by hand saves
        }
        System.runAs(u) {
            setTo = [SELECT Is_Key_Account__c FROM Account WHERE Id = :accountId LIMIT 1].Is_Key_Account__c;
        }
        System.assertEquals(true, setTo, 'AC2: after the save the customer reads "Yes".');

        System.runAs(u) {
            Account clearFresh = new Account();
            clearFresh.Id = accountId;
            clearFresh.Is_Key_Account__c = false;
            update clearFresh; // AC3: clearing by hand saves
        }
        System.runAs(u) {
            setTo = [SELECT Is_Key_Account__c FROM Account WHERE Id = :accountId LIMIT 1].Is_Key_Account__c;
        }
        System.assertEquals(false, setTo, 'AC3: after the clear the customer reads "No" again.');
    }
}
