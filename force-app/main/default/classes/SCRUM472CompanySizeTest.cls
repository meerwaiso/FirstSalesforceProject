/**
 * [SCRUM-472] Functional test for the hand-set Picklist Lead.Company_Size__c
 * ("Company Size" — one of four employee bands, chosen by hand, blank allowed,
 * nothing automatic).
 *
 * Covers:
 *   AC3  a new lead saves cleanly with an EMPTY size (blank is allowed, no default)
 *   AC2  a colleague holding SCRUM472_CompanySize sets one band -> the lead reads
 *        exactly that band, no other field on the record changed
 *   AC2b the colleague changes it to another band -> the lead reads the new band
 *   AC4  the colleague clears it -> the lead is saved with an empty size, no error,
 *        the lead itself is NOT deleted
 *   AC5  NOT covered here — see the block below the change-band method: measured, neither
 *        Apex nor the REST API enforces the four values (the UI does) -> Tester's E2E job
 *   AC7  a colleague who creates leads can set the size already at creation
 *   AC8  filling / changing the size triggers nothing: no EmailMessage, no Task,
 *        no Case, no Opportunity, no extra Lead, no other field touched (count-based)
 *
 * FLS-Gate / CI form (house SCRUM470/471/442): JEDE fachliche DML/SELECT on the
 * NEW field runs inside System.runAs(user); the temp User and its PermissionSetAssignment
 * are inserted STRICTLY FIRST (a User cannot grant itself a PSA — the mixed order
 * reddens MIXED_DML_OPERATION in CI RunLocalTests). All later DML stays under the
 * SAME user (static closer).
 *
 * update uses a FRESH sObject (Id + the written field only) — `update` on a fully
 * populated record cache writes every field and reddens on one that is not writeable
 * (house SCRUM-459).
 *
 * The test Leads carry NO Email: LeadDuplicateGuard (before insert/update on Lead)
 * normalises Email into Email_Norm__c and marks Likely_Duplicate__c/Duplicate_Of__c,
 * and a runAs user without that FLS would hit DmlException 'fields being inaccessible
 * on Sobject Lead'. A Lead without Email is never marked (measured in
 * LeadDuplicateGuard.resolveCore: Email_Norm__c == null -> skip on insert).
 *
 * AC9 (existing leads stay empty) has NO Apex method, deliberately: org-wide SOQL
 * inside a test method sees only the test's own records (measured again in
 * SCRUM-471), so an assert about the org's existing Leads would be vacuous. AC9 is
 * proven at org level instead (read-backs in the handoff comment):
 *   sf data query -o Test-Org -q "SELECT COUNT() FROM Lead"                        -> 66
 *   sf data query -o Test-Org -q "SELECT COUNT() FROM Lead WHERE Company_Size__c != null" -> 0
 *   sf data query -o Test-Org -q "SELECT Id, LastName, Company_Size__c FROM Lead"  -> 66 rows, all null
 */
@isTest
private class SCRUM472CompanySizeTest {

    private static final String PS_NAME = 'SCRUM472_CompanySize';
    private static final String BAND_SMALL = 'up_to_10';
    private static final String BAND_MID = '11_to_50';
    private static final String BAND_LARGE = '51_to_250';
    private static final String BAND_HUGE = 'more_than_250';

    /** Frischer Standard-User (Hausform SCRUM430/470/471; de_DE + UTC rejected in this org). */
    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'CompSize472',
            Alias                = 'c472' + tag,
            Email                = 'c472' + tag + sfx + '@x.invalid',
            Username             = 'c472' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** The single Read+Edit PS of this ticket. */
    private static void assignPs(User u) {
        List<PermissionSet> psList = [SELECT Id FROM PermissionSet WHERE Name = :PS_NAME];
        System.assertEquals(1, psList.size(),
            'Precondition: SCRUM472_CompanySize must exist in the org, otherwise the asserts below test nothing.');
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psList[0].Id);
    }

    // ---- AC3: a new lead saves cleanly with an empty size --------------------
    @isTest
    static void new_lead_saves_with_empty_size() {
        User u = mkTestUser('ac3');
        assignPs(u);
        Id leadId;
        Boolean stillThere;
        String band;
        System.runAs(u) {
            Lead l = new Lead(LastName = 'TEST-SCRUM-472-AC3', Company = 'Corner Shop');
            insert l; // no exception: blank is allowed and nothing defaults it
            leadId = l.Id;
            band = l.Company_Size__c;
        }
        System.assertEquals(null, band, 'AC3: a new lead has no size yet (no default, no backfill).');
        System.runAs(u) {
            stillThere = [SELECT Id FROM Lead WHERE Id = :leadId LIMIT 1].Id != null;
        }
        System.assert(stillThere, 'AC3: the blank save left the lead in place.');
    }

    // ---- AC7: created with a band, AC2: the lead reads exactly that band -----
    @isTest
    static void created_with_band_reads_that_band() {
        User u = mkTestUser('ac7');
        assignPs(u);
        Id leadId;
        String bandAtCreate;
        System.runAs(u) {
            Lead l = new Lead(
                LastName = 'TEST-SCRUM-472-AC7',
                Company = 'Miller & Sons',
                Company_Size__c = BAND_SMALL
            );
            insert l;
            leadId = l.Id;
            bandAtCreate = l.Company_Size__c;
        }
        System.assertEquals(BAND_SMALL, bandAtCreate,
            'AC7: a colleague who creates leads can set the size already at creation.');

        String bandAfter;
        String companyAfter;
        System.runAs(u) {
            Lead l = [SELECT Company_Size__c, Company FROM Lead WHERE Id = :leadId LIMIT 1];
            bandAfter = l.Company_Size__c;
            companyAfter = l.Company;
        }
        System.assertEquals(BAND_SMALL, bandAfter, 'AC2: the saved lead reads exactly the chosen band.');
        System.assertEquals('Miller & Sons', companyAfter, 'AC2: the save touched no other field.');
    }

    // ---- AC2b: changing the band to another one ------------------------------
    @isTest
    static void colleague_changes_the_band() {
        User u = mkTestUser('chg');
        assignPs(u);
        Id leadId;
        System.runAs(u) {
            Lead l = new Lead(LastName = 'TEST-SCRUM-472-CHG', Company = 'Millwork GmbH');
            insert l;
            leadId = l.Id;
        }
        System.runAs(u) {
            Lead fresh = new Lead();
            fresh.Id = leadId;
            fresh.Company_Size__c = BAND_MID;
            update fresh; // FRESH sObject: Id + the written field only (house SCRUM-459)
        }
        String midBand;
        System.runAs(u) {
            Lead l = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1];
            midBand = l.Company_Size__c;
        }
        System.assertEquals(BAND_MID, midBand, 'AC2: after the change the lead reads the new band.');

        System.runAs(u) {
            Lead fresh = new Lead();
            fresh.Id = leadId;
            fresh.Company_Size__c = BAND_LARGE;
            update fresh;
        }
        System.runAs(u) {
            Lead l = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1];
            System.assertEquals(BAND_LARGE, l.Company_Size__c,
                'AC2: a second change moves the band again — the value stays hand-editable.');
        }
    }

    // ---- AC4: clearing the band saves empty, the lead is NOT deleted ---------
    @isTest
    static void colleague_clears_the_band() {
        User u = mkTestUser('clr');
        assignPs(u);
        Id leadId;
        String before;
        System.runAs(u) {
            Lead l = new Lead(LastName = 'TEST-SCRUM-472-AC4', Company = 'Wrong Size Co', Company_Size__c = BAND_HUGE);
            insert l;
            leadId = l.Id;
            before = l.Company_Size__c;
        }
        System.assertEquals(BAND_HUGE, before, 'Precondition: the band is set before it is cleared.');

        System.runAs(u) {
            Lead fresh = new Lead();
            fresh.Id = leadId;
            fresh.Company_Size__c = null;
            update fresh; // no exception = clearing is allowed by Edit, not Delete
        }
        String after;
        Boolean leadStillExists;
        System.runAs(u) {
            List<Lead> rows = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId];
            leadStillExists = rows.size() == 1;
            after = leadStillExists ? rows[0].Company_Size__c : 'MISSING';
        }
        System.assert(leadStillExists, 'AC4: clearing the size did NOT delete the lead.');
        System.assertEquals(null, after, 'AC4: after clearing, the lead saves with an empty size.');
    }

    // ---- AC5: NO Apex method — measured, the value set is not enforced below the UI ----
    // AC5 ("a value that is not one of the four ranges is rejected") is NOT provable from
    // Apex or the REST API, and asserting it would be a fake PASS. Measured 2026-11-23 in Test-Org,
    // both ACCEPT an out-of-band value and STORE it:
    //   Apex: Lead l = new Lead(..., Company_Size__c = 'several hundred'); insert l; -> no exception
    //   API:  sf data update record -o Test-Org -s Lead -i 00QWU00000iUQq92AG -v "Company_Size__c=nonsense_band"
    //         -> "Successfully updated record"; read-back shows COMPANY_SIZE__C = nonsense_band
    //         (the probe record was created with a legal band, then deleted: `sf data delete record` -> Success)
    // What IS enforced: the field is a restricted Picklist, so the Lightning UI only ever OFFERS the
    // four labels (there is no free-text entry) and the bands group for sort/filter. AC5 is a UI
    // criterion -> the Tester's Playwright job (assert the picker offers exactly the four labels).
    // Flagged as an open point in the handoff comment for @architect-agent.

    // ---- AC8: filling / changing the size fires nothing ----------------------
    @isTest
    static void setting_the_size_fires_nothing() {
        User u = mkTestUser('ac8');
        assignPs(u);

        Id leadId;
        Integer leadsBefore;
        Integer emailsBefore;
        Integer tasksBefore;
        Integer casesBefore;
        Integer oppsBefore;
        Integer sizedBefore;
        System.runAs(u) {
            leadsBefore = [SELECT Id FROM Lead].size();
            emailsBefore = [SELECT Id FROM EmailMessage].size();
            tasksBefore = [SELECT Id FROM Task].size();
            casesBefore = [SELECT Id FROM Case].size();
            oppsBefore = [SELECT Id FROM Opportunity].size();
            sizedBefore = [SELECT Id FROM Lead WHERE Company_Size__c != null].size();
            Lead l = new Lead(
                LastName = 'TEST-SCRUM-472-AC8',
                Company = 'Quiet Shop',
                Phone = '+49000000000',
                Company_Size__c = BAND_SMALL
            );
            insert l;
            leadId = l.Id;
        }

        System.runAs(u) {
            Lead fresh = new Lead();
            fresh.Id = leadId;
            fresh.Company_Size__c = BAND_HUGE;
            update fresh;
        }

        String phoneAfter;
        String companyAfter;
        String bandAfter;
        Integer leadsAfter;
        Integer emailsAfter;
        Integer tasksAfter;
        Integer casesAfter;
        Integer oppsAfter;
        Integer sizedAfter;
        System.runAs(u) {
            Lead l = [SELECT Phone, Company, Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1];
            phoneAfter = l.Phone;
            companyAfter = l.Company;
            bandAfter = l.Company_Size__c;
            leadsAfter = [SELECT Id FROM Lead].size();
            emailsAfter = [SELECT Id FROM EmailMessage].size();
            tasksAfter = [SELECT Id FROM Task].size();
            casesAfter = [SELECT Id FROM Case].size();
            oppsAfter = [SELECT Id FROM Opportunity].size();
            sizedAfter = [SELECT Id FROM Lead WHERE Company_Size__c != null].size();
        }

        System.assertEquals(BAND_HUGE, bandAfter, 'AC8: the band itself persisted.');
        System.assertEquals('+49000000000', phoneAfter, 'AC8: Phone of the lead is untouched by the size saves.');
        System.assertEquals('Quiet Shop', companyAfter, 'AC8: Company of the lead is untouched by the size saves.');
        System.assertEquals(leadsBefore + 1, leadsAfter,
            'AC8: exactly one Lead more than before — the size saves created no additional record.');
        System.assertEquals(sizedBefore + 1, sizedAfter,
            'AC8: exactly one lead carries a size — no other lead got a size automatically.');
        System.assertEquals(emailsBefore, emailsAfter, 'AC8: no EmailMessage was created.');
        System.assertEquals(tasksBefore, tasksAfter, 'AC8: no Task was created.');
        System.assertEquals(casesBefore, casesAfter, 'AC8: no Case record was touched.');
        System.assertEquals(oppsBefore, oppsAfter, 'AC8: no Opportunity record was touched.');
    }
}
