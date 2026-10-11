/**
 * [SCRUM-442] Shared test helper: Standard User holding the SCRUM-442
 * satisfaction Permission Sets (Read + Edit FLS on Case.Customer_Satisfaction__c,
 * plus the Account rollup fields for the Rebuilder DML).
 *
 * Why this class: the fresh field Case.Customer_Satisfaction__c is not yet
 * released in Prod-Org. The FLS-Gate (Lücke C) demands that the business DML/
 * SOQL on a new field runs under System.runAs(a user carrying the granting PS) —
 * otherwise the Prod check-only validation reports the fields as inaccessible on
 * the Sobject. Same idiom as SCRUM434TestFixtures (house pattern SCRUM370 /
 * SCRUM432 / SCRUM434): the User AND the PermissionSetAssignments are created in
 * System context (a User cannot grant himself a PSA; Setup-DML outside the runAs
 * avoids MIXED_DML), the field-bearing DML runs inside System.runAs(u).
 *
 * The user carries THREE sets: SCRUM442_Satisfaction_Write (Edit on the Case
 * score), SCRUM442_Satisfaction_Read (Read on all six SCRUM-442 fields) and
 * SCRUM442_Satisfaction_System (Edit on the four Account rollup fields, needed
 * by AccountSatisfactionRebuilder DML). It also carries SCRUM434_Ursache, so one
 * single user can close a Case completely under the rules of both tickets —
 * closing a Case now requires Ursache__c (SCRUM-434) AND the score (SCRUM-442).
 *
 * REMARK (house finding from SCRUM434TestFixtures, Prod-Org Drift Gate run
 * 36585422149): this class is deliberately NOT @isTest. @isTest made the class
 * test-visible but withheld it from the referencing test classes during a
 * Prod-Org check-only validation, producing "Type is not visible" component
 * errors and a red drift gate. As a plain public class it sits in the always-
 * visible layer and is referenceable from every test class. It is only ever
 * called from @isTest methods, so it stays production-neutral. It must be
 * DEPLOYED (Test-Org now, Prod at Release) so the drift gate can compile it.
 *
 * @author developer-agent
 * @date 2026-10-10
 */
public without sharing class SCRUM442TestFixtures {

    // Unique username within one test class run (several methods, one tx each).
    private static Integer n = 0;

    private static final String[] PS_NAMES = new String[] {
        'SCRUM442_Satisfaction_Write',
        'SCRUM442_Satisfaction_Read',
        'SCRUM442_Satisfaction_System',
        'SCRUM434_Ursache',
        // SCRUM-442 Cause E (review 3): object-level access for the fixture
        // user — the Rebuilder's per-chunk query reaches Case FROM Account
        // under runAs; a Standard User without Case/Account object access
        // gets "fields being inaccessible on Sobject Case". This is a TEST-
        // LOCAL set: SCRUM442_Satisfaction_Read serves Sales users and must
        // NOT be widened for a test's benefit (released scope).
        'SCRUM442_TestObjectAccess',
        // Closing a Case in THIS org fires the rules of SCRUM-436 (Reminder
        // fields) and SCRUM-437 (ProblemSerie fields) as well: measured 2026-10-11,
        // a seed insert carrying Customer_Satisfaction__c under a user holding
        // only the 442/434 sets fails "fields being inaccessible on Sobject Case"
        // — missing field FLS, not missing CRUD (house finding). The triggers
        // WRITE those Case fields at the save, so the fixture user needs the
        // EDITABLE variants (SCRUM436_CaseReminder / SCRUM437_ProblemSerie_Read
        // are editable=false and do not cover a trigger write). Test-local
        // grants; released scopes untouched.
        'SCRUM436_CaseReminderSystem',
        'SCRUM437_ProblemSerie_System'
    };

    /**
     * Creates a Standard User, assigns the four PS above and returns it. Use it
     * as the System.runAs target for the score-bearing DML/SOQL on
     * Case.Customer_Satisfaction__c and for the Account rollup fields.
     */
    public static User satisfactionUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(System.now().getTime());
        String t = (tag == null || tag == '') ? 'x' : tag.replace(' ', '').replace('-', '');
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr442F',
            Alias = 'scr442',
            Email = 'scr442fix_' + t + '_' + stamp + '_' + (n++) + '@example.invalid',
            Username = 'scr442fix_' + t + '_' + stamp + '_' + (n++) + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        grantPsToUser(u);
        return u;
    }

    /**
     * Assigns the four PS above to an ALREADY existing User (e.g. a seeded
     * fromUser that must stay the Case owner). Idempotent: a second PSA for the
     * same User+PS would be a duplicate error.
     */
    public static void grantPsToUser(User u) {
        for (String name : PS_NAMES) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1];
            if (ps == null || ps.Id == null) {
                continue; // set not deployed yet (Prod before Release) — skip, never fail
            }
            Integer cnt = (Integer)[SELECT COUNT(Id) cnt FROM PermissionSetAssignment
                                   WHERE AssigneeId = :u.Id AND PermissionSetId = :ps.Id][0].get('cnt');
            if (cnt == 0) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
    }
}
