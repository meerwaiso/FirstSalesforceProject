/**
 * [SCRUM-472] FLS positive + negative proof for Lead.Company_Size__c
 * (AC1 visible to everyone who may open the lead, AC2/AC4 set AND clear by hand,
 * AC6 without the PS nothing is visible, AC-not-applicable: no Delete rights).
 *
 * House pattern SCRUM471KeyAccountFlsTest / SCRUM386LeadDuplicateFlsTest /
 * SCRUM470PreferredContactMethodFlsTest: a temp User on the "Standard User"
 * profile, the PS assigned INSIDE the test, getDescribe() READ inside
 * System.runAs and asserted OUTSIDE any try — an assert inside the try of a SELECT
 * can never fail (falsifiability), so the SOQL half keeps only the SELECT in the try.
 *
 * Two user states — the split that makes the negatives mean anything:
 *   1. no PS at all                -> neither readable nor writable  (AC6)
 *   2. SCRUM472_CompanySize        -> readable AND writable/clearable (AC1, AC2, AC4)
 * There is no "read but not write" state in this ticket: the PO pinned Read + Edit
 * for the SAME user set, so one PS carries both (ADR-3).
 *
 * The negatives are a probe, not an assumption. Measured for THIS field in Test-Org
 * on 2026-11-23 with scripts/fls-check.sh Lead Company_Size__c Test-Org:
 *   1. Existenz  ja (Picklist)
 *   2. Rechte    exactly ONE row: SCRUM472_CompanySize read=true edit=true
 *                -> NO Parent.IsOwnedByProfile row: the Standard User profile grants
 *                   nothing on the new field, so a PS-less user is genuinely blocked
 *                   and these asserts test the FLS wall, not a lucky profile default.
 * System Administrators inherit FLS on custom fields — that is why the fixture user
 * is a Standard User (verified in SCRUM-329/386).
 */
@isTest
private class SCRUM472CompanySizeFlsTest {

    private static final String PS_NAME = 'SCRUM472_CompanySize';

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Fls472',
            Alias                = 'f472' + tag,
            Email                = 'f472' + tag + sfx + '@x.invalid',
            Username             = 'f472' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static void assignPs(User u) {
        List<PermissionSet> psList = [SELECT Id FROM PermissionSet WHERE Name = :PS_NAME];
        System.assertEquals(1, psList.size(),
            'Precondition: SCRUM472_CompanySize must exist in the org, otherwise the asserts below test nothing.');
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psList[0].Id);
    }

    // ---- PRECONDITION: the Standard User reads the Lead OBJECT ---------------
    @isTest
    static void precondition_standard_user_reads_lead() {
        User u = mkTestUser('pre');
        System.assert(
            leadReadableBy(u),
            'Precondition failed: the Standard User has no object-level Lead access — '
                + 'every FLS assert below would then be green for the WRONG reason '
                + '(missing Lead CRUD, not missing FLS). A test-local *_TestObjectAccess PS is needed then (house SCRUM442/451/464/467).'
        );
    }

    private static Boolean leadReadableBy(User u) {
        Boolean readable = false;
        System.runAs(u) {
            readable = Lead.SObjectType.getDescribe().isAccessible();
        }
        return readable;
    }

    private static Boolean sizeReadableBy(User u) {
        Boolean readable = false;
        System.runAs(u) {
            readable = Lead.Company_Size__c.getDescribe().isAccessible();
        }
        return readable;
    }

    private static Boolean sizeWritableBy(User u) {
        Boolean writable = false;
        System.runAs(u) {
            writable = Lead.Company_Size__c.getDescribe().isUpdateable();
        }
        return writable;
    }

    // ---- AC6 NEGATIVE: no PS -> nothing visible, nothing writable ------------
    @isTest
    static void withoutPS_size_invisible_and_unwritable() {
        User u = mkTestUser('none');
        System.assert(
            leadReadableBy(u),
            'Precondition: Standard User must read Lead, otherwise the wall below is missing CRUD, not FLS.'
        );

        // FALSIFIABLE half 1: asserted OUTSIDE any try — readable=true reddens this.
        Boolean readable = sizeReadableBy(u);
        System.assertEquals(false, readable,
            'AC6: without any PS the size must NOT be readable (nothing visible).');

        // FALSIFIABLE half 2: the SOQL probe — ONLY the SELECT sits in the try.
        boolean threw = false;
        System.runAs(u) {
            try {
                List<Lead> rows = [SELECT Company_Size__c FROM Lead WITH USER_MODE LIMIT 1];
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
            Lead l = new Lead(LastName = 'TEST-SCRUM-472-FLS-NEG', Company = 'No PS Co');
            insert l;
            Id leadId = l.Id;
            try {
                Lead fresh = new Lead();
                fresh.Id = leadId;
                fresh.Company_Size__c = 'up_to_10';
                update fresh;
            } catch (Exception e) {
                threwUpdate = true;
            }
        }
        System.assert(threwUpdate, 'AC6: a colleague without the PS must be REFUSED when writing the size.');
    }

    // ---- AC1/AC2/AC4 POSITIVE: the PS -> readable, writable, clearable -------
    @isTest
    static void withPS_size_readable_editable_clearable() {
        User u = mkTestUser('ps');
        assignPs(u);
        System.assert(leadReadableBy(u), 'Precondition: the PS holder must read Lead.');

        System.assert(sizeReadableBy(u), 'AC1: with SCRUM472_CompanySize the size IS visible.');
        System.assert(sizeWritableBy(u), 'AC2/AC4: with the PS the size is editable (set AND clear).');

        Id leadId;
        String afterSet;
        String afterClear;
        System.runAs(u) {
            Lead l = new Lead(LastName = 'TEST-SCRUM-472-FLS-POS', Company = 'Band Co');
            insert l;
            leadId = l.Id;
        }
        System.runAs(u) {
            Lead fresh = new Lead();
            fresh.Id = leadId;
            fresh.Company_Size__c = '11_to_50';
            update fresh; // AC2: setting by hand saves
        }
        System.runAs(u) {
            afterSet = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1].Company_Size__c;
        }
        System.assertEquals('11_to_50', afterSet, 'AC2: after the save the lead reads the chosen band.');

        System.runAs(u) {
            Lead fresh = new Lead();
            fresh.Id = leadId;
            fresh.Company_Size__c = null;
            update fresh; // AC4: clearing is an Edit — no Delete rights involved
        }
        System.runAs(u) {
            List<Lead> rows = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId];
            System.assertEquals(1, rows.size(), 'AC4: clearing the size did not delete the lead.');
            afterClear = rows[0].Company_Size__c;
        }
        System.assertEquals(null, afterClear, 'AC4: after clearing, the lead saves with an empty size.');
    }
}
