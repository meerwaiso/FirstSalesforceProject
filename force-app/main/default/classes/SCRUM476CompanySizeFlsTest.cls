/**
 * [SCRUM-476] FLS positive + negative proof for Account.Company_Size__c.
 * (AC1 visible to everyone who may open a customer, AC2/AC4 set AND cleared by hand,
 *  AC6 without the PS nothing is visible, AC9 the Read half grants no edit,
 *  AC11 clearing is an Edit -> no Delete rights involved.)
 *
 * House pattern SCRUM472CompanySizeFlsTest / SCRUM471KeyAccountFlsTest / SCRUM386LeadDuplicateFlsTest:
 * a temp User on the "Standard User" profile, the PS assigned OUTSIDE System.runAs
 * (a User cannot grant himself a Permission Set), getDescribe() READ inside runAs and
 * asserted OUTSIDE any try — an assert inside the try of a SELECT can never fail, so
 * the SOQL half keeps only the SELECT in the try.
 *
 * Three user states — the pair is what makes the third state mean anything:
 *   1. no PS                        -> neither readable nor writable  (AC6)
 *   2. SCRUM476_CompanySize_READ    -> readable, NOT writable         (AC9)
 *   3. READ + SET                   -> readable AND writable/clearable (AC1, AC2, AC4)
 *
 * The negatives are a probe, not an assumption. Measured for THIS field in Test-Org
 * on 2026-11-24 with a FieldPermissions query: THREE rows, ALL with
 * Parent.IsOwnedByProfile=false — SCRUM476_CompanySize_Read (read), SCRUM476_CompanySize_Set
 * (read+edit) and a pre-existing org PS 'Agentic Near Core CRM' (read only). NO Profile row:
 * the Standard User profile grants nothing on the new field, so a PS-less user is genuinely
 * blocked and these asserts test the FLS wall, not a lucky profile default.
 * System Administrators inherit FLS on custom fields — the fixture user is a Standard User
 * (verified in SCRUM-329/386).
 *
 * The customer fixture is created in System mode BEFORE any runAs work of the same method:
 * an Account insert under a synthetic user would first trip the org's Validation Rules
 * (AccountStreetZipRequired / AccountStateRequired / AccountWebsiteAndPhoneRequired /
 * AccountEmailAndCityRequired — house SCRUM-449) and the missing CRUD of the other Account
 * PSs, which is the Tester's finding, not an FLS fact about THIS field. The values asserted
 * below are about Company_Size__c only; the record itself is written before runAs begins.
 */
@isTest
private class SCRUM476CompanySizeFlsTest {

    private static final String PS_READ = 'SCRUM476_CompanySize_Read';
    private static final String PS_SET = 'SCRUM476_CompanySize_Set';

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Fls476',
            Alias                = 'f476' + tag,
            Email                = 'f476' + tag + sfx + '@x.invalid',
            Username             = 'f476' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static Id psId(String name) {
        List<PermissionSet> found = [SELECT Id FROM PermissionSet WHERE Name = :name];
        System.assertEquals(1, found.size(),
            'Precondition: ' + name + ' must exist in the org, otherwise the asserts below test nothing.');
        return found[0].Id;
    }

    private static void assignPs(User u, String psName) {
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId(psName));
    }

    private static Account mkCustomer(String name) {
        Account a = new Account(
            Name = name, Street = 'Test-Street 1', PostalCode = '12345', State = 'NY',
            PhoneNumber = '03012345678', Website = 'https://test.invalid',
            Email = 'test-476-fls@x.invalid', AddressCity = 'TestCity'
        );
        insert a;
        return a;
    }

    private static Boolean customerReadableBy(User u) {
        Boolean ok = false;
        System.runAs(u) {
            ok = Account.SObjectType.getDescribe().isAccessible();
        }
        return ok;
    }

    private static Boolean sizeReadableBy(User u) {
        Boolean ok = false;
        System.runAs(u) {
            ok = Account.Company_Size__c.getDescribe().isAccessible();
        }
        return ok;
    }

    private static Boolean sizeWritableBy(User u) {
        Boolean ok = false;
        System.runAs(u) {
            ok = Account.Company_Size__c.getDescribe().isUpdateable();
        }
        return ok;
    }

    // ---- AC 6 NEGATIVE: no PS at all -> nothing visible, nothing writable ----
    @isTest
    static void withoutPS_size_invisible_and_unwritable() {
        User u = mkTestUser('none');
        Account a = mkCustomer('TEST-476-FLS-NONE');
        Id acctId = a.Id;
        System.assert(customerReadableBy(u),
            'Precondition: the Standard User must read the Account OBJECT, otherwise the wall below '
                + 'is missing CRUD, not FLS (a test-local *_TestObjectAccess PS is needed then, house SCRUM-442/451/464/467).');

        // FALSIFIABLE half 1: asserted outside any try — readable=true reddens this.
        Boolean readable = sizeReadableBy(u);
        System.assertEquals(false, readable,
            'AC6: without any PS the size must NOT be readable (nothing visible).');

        // FALSIFIABLE half 2: the SOQL probe — ONLY the SELECT sits in the try.
        boolean threw = false;
        System.runAs(u) {
            try {
                List<Account> rows = [SELECT Company_Size__c FROM Account WHERE Id = :acctId WITH USER_MODE LIMIT 1];
            } catch (Exception e) {
                threw = true; // 'No such column' / SecurityException — both are the FLS wall
            }
        }
        System.assert(threw, 'AC6: reading the size without a PS must hit the FLS wall.');

        Boolean writable = sizeWritableBy(u);
        System.assertEquals(false, writable,
            'AC6: without the PS the size must not be writeable, either.');

        // FALSIFIABLE half 3: an update that SUCCEEDS leaves threwUpdate=false -> red below.
        boolean threwUpdate = false;
        System.runAs(u) {
            try {
                Account fresh = new Account();
                fresh.Id = acctId;
                fresh.Company_Size__c = 'up_to_10';
                update fresh;
            } catch (Exception e) {
                threwUpdate = true;
            }
        }
        System.assert(threwUpdate, 'AC6: a colleague without the PS must be REFUSED when writing the size.');
    }

    // ---- AC 9: the READ half alone grants visibility but NO edit ----
    @isTest
    static void readPS_only_visible_but_not_writable() {
        User u = mkTestUser('read');
        assignPs(u, PS_READ);
        Account a = mkCustomer('TEST-476-FLS-READ');
        Id acctId = a.Id;
        System.assert(customerReadableBy(u), 'Precondition: the PS holder must read the Account object.');

        System.assert(sizeReadableBy(u),
            'AC1: with the READ PS alone the size IS visible (visibility, not ownership).');

        Boolean writable = sizeWritableBy(u);
        System.assertEquals(false, writable,
            'AC9: the READ PS must not carry an edit — a viewer may not change the band.');

        boolean threwUpdate = false;
        System.runAs(u) {
            try {
                Account fresh = new Account();
                fresh.Id = acctId;
                fresh.Company_Size__c = 'up_to_10';
                update fresh;
            } catch (Exception e) {
                threwUpdate = true;
            }
        }
        System.assert(threwUpdate, 'AC9: writing the size with only the READ PS must be refused.');
    }

    // ---- AC 1/AC 2/AC 4 POSITIVE: READ + SET -> visible, settable, clearable ----
    @isTest
    static void withBothPS_readable_editable_clearable() {
        User u = mkTestUser('both');
        assignPs(u, PS_READ);
        assignPs(u, PS_SET);
        Account a = mkCustomer('TEST-476-FLS-BOTH');
        Id acctId = a.Id;
        System.assert(customerReadableBy(u), 'Precondition: the PS holder must read the Account object.');

        System.assert(sizeReadableBy(u), 'AC1: with the pair the size IS visible.');
        System.assert(sizeWritableBy(u), 'AC2/AC4: with the pair the size is editable (set AND clear).');

        System.runAs(u) {
            Account fresh = new Account();
            fresh.Id = acctId;
            fresh.Company_Size__c = '11_to_50';
            update fresh; // AC2: setting by hand saves
        }
        String afterSet;
        System.runAs(u) {
            afterSet = [SELECT Company_Size__c FROM Account WHERE Id = :acctId WITH USER_MODE LIMIT 1].Company_Size__c;
        }
        System.assertEquals('11_to_50', afterSet, 'AC2: after the save the customer reads the chosen band.');

        System.runAs(u) {
            Account fresh = new Account();
            fresh.Id = acctId;
            fresh.Company_Size__c = null;
            update fresh; // AC4: clearing is an Edit
        }
        List<Account> rows;
        System.runAs(u) {
            rows = [SELECT Company_Size__c FROM Account WHERE Id = :acctId WITH USER_MODE];
        }
        System.assertEquals(1, rows.size(),
            'AC11: clearing the size did NOT delete the customer (no Delete rights involved).');
        System.assertEquals(null, rows[0].Company_Size__c,
            'AC4: after clearing, the customer saves with an empty size.');
    }
}
