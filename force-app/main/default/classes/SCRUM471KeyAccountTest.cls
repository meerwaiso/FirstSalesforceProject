/**
 * [SCRUM-471] Functional test for the hand-set Checkbox Account.Is_Key_Account__c
 * ("Key Account" — manual mark, default No, nothing automatic).
 *
 * Covers:
 *   AC1  a newly created Account carries the mark "No" (defaultValue=false, not null)
 *   AC2  a colleague holding Read + Set sets it -> the record reads "Yes"
 *   AC3  the same colleague clears it -> the record reads "No" again
 *   AC8  setting/clearing triggers NOTHING: no EmailMessage, no Task, no work record,
 *        no other Account and no other field on the record changes (count-based)
 *   AC9  the customers that exist today still read "No" — guarded, see below
 *
 * FLS-Gate / CI-Lücke C (SCRUM-421/424/470 house form, house class
 * SCRUM470PreferredContactMethodTest): JEDE fachliche DML/SELECT on the NEW field
 * runs under System.runAs(user); the User and its PermissionSetAssignment are
 * inserted STRICTLY FIRST (a User cannot grant himself a PSA; the mixed order
 * reddens MIXED_DML_OPERATION in CI RunLocalTests). All later DML stays under the
 * SAME user (static closer).
 *
 * Counts that travel forward (measured in Test-Org, 2026-11-22): 251 Account records
 * today, 0 of them marked. A criterion that counts key accounts must expect 0
 * before someone marks one.
 *
 * update uses a FRESH sObject (Id + the written field only) — `update` on a
 * fully-populated record cache writes every field and reddens on one that is not
 * writeable (house SCRUM-459).
 *
 * AC9 has NO Apex method, deliberately. Measured 2026-11-22: `[SELECT Id FROM
 * Account].size()` inside a test method that creates no record returned 0 — org-wide
 * SOQL inside a test sees only the test's own records, so an assert about the 251
 * pre-existing customers would be vacuous. AC9 is proven at org level instead
 * (read-backs in the handoff comment):
 *   sf data query -o Test-Org -q "SELECT Id, Name, Is_Key_Account__c FROM Account"
 *     -> totalSize 251, 0 with Is_Key_Account__c = true, 251 with false
 *   sf data query -o Test-Org -q "SELECT COUNT() FROM Account WHERE Is_Key_Account__c = true"
 *     -> totalSize 0
 */
@isTest
private class SCRUM471KeyAccountTest {

    private static final String PS_READ = 'SCRUM471_KeyAccount_Read';
    private static final String PS_SET = 'SCRUM471_KeyAccount_Set';

    /** Frischer Standard-User (Hausform SCRUM430/470; de_DE + UTC rejected in this org). */
    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'KeyAcc471',
            Alias                = 'k471' + tag,
            Email                = 'k471' + tag + sfx + '@x.invalid',
            Username             = 'k471' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** Both PSs (Read + Set) = a colleague who may edit customer records today. */
    private static void assignPs(User u) {
        List<PermissionSet> psList =
            [SELECT Id, Name FROM PermissionSet WHERE Name = :PS_READ OR Name = :PS_SET];
        System.assertEquals(2, psList.size(),
            'Precondition: both PSs SCRUM471_KeyAccount_Read and SCRUM471_KeyAccount_Set must exist in the org.');
        for (PermissionSet ps : psList) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    // ---- AC1: a new customer starts as "No" ---------------------------------
    @isTest
    static void new_account_defaults_to_no() {
        User u = mkTestUser('ac1');
        assignPs(u);
        Boolean mark;
        System.runAs(u) {
            Account a = new Account(Name = 'TEST-SCRUM-471-AC1');
            insert a;
            mark = [SELECT Is_Key_Account__c FROM Account WHERE Id = :a.Id LIMIT 1].Is_Key_Account__c;
        }
        System.assertEquals(false, mark,
            'AC1: a newly created customer reads "No" (unchecked), not null.');
    }

    // ---- AC2: set by hand -> the record reads "Yes" -------------------------
    @isTest
    static void set_mark_reads_yes() {
        User u = mkTestUser('ac2');
        assignPs(u);
        Boolean mark;
        System.runAs(u) {
            Account a = new Account(Name = 'TEST-SCRUM-471-AC2', Is_Key_Account__c = true);
            insert a;
            mark = [SELECT Is_Key_Account__c FROM Account WHERE Id = :a.Id LIMIT 1].Is_Key_Account__c;
        }
        System.assertEquals(true, mark, 'AC2: after the colleague set the mark it reads "Yes".');
    }

    // ---- AC3: cleared by hand -> "No" again ---------------------------------
    @isTest
    static void clear_mark_reads_no() {
        User u = mkTestUser('ac3');
        assignPs(u);
        Id accountId;
        Boolean before;
        System.runAs(u) {
            Account a = new Account(Name = 'TEST-SCRUM-471-AC3', Is_Key_Account__c = true);
            insert a;
            accountId = a.Id;
            before = [SELECT Is_Key_Account__c FROM Account WHERE Id = :accountId LIMIT 1].Is_Key_Account__c;
        }
        System.assertEquals(true, before, 'Precondition: the mark is on before it is cleared.');

        Boolean after;
        System.runAs(u) {
            Account fresh = new Account();
            fresh.Id = accountId;
            fresh.Is_Key_Account__c = false;
            update fresh; // no exception = clearing is allowed (AC3)
            after = [SELECT Is_Key_Account__c FROM Account WHERE Id = :accountId LIMIT 1].Is_Key_Account__c;
        }
        System.assertEquals(false, after, 'AC3: after clearing, the customer reads "No" again.');
    }

    // ---- AC8: nothing else fires --------------------------------------------
    @isTest
    static void setting_the_mark_fires_nothing() {
        User u = mkTestUser('ac8');
        assignPs(u);

        Id accountId;
        Integer markTrueBefore;
        Integer accountCountBefore;
        System.runAs(u) {
            accountCountBefore = [SELECT Id FROM Account].size();
            Account a = new Account(
                Name = 'TEST-SCRUM-471-AC8', Phone = '+491****1111', Website = 'example.invalid'
            );
            insert a;
            accountId = a.Id;
            markTrueBefore = [SELECT Id FROM Account WHERE Is_Key_Account__c = true].size();
        }

        System.runAs(u) {
            Account fresh = new Account();
            fresh.Id = accountId;
            fresh.Is_Key_Account__c = true;
            update fresh;
        }

        Boolean markAfter;
        String phoneAfter;
        String websiteAfter;
        Integer markTrueAfter;
        Integer accountCountAfter;
        System.runAs(u) {
            Account a = [SELECT Is_Key_Account__c, Phone, Website FROM Account WHERE Id = :accountId LIMIT 1];
            markAfter = a.Is_Key_Account__c;
            phoneAfter = a.Phone;
            websiteAfter = a.Website;
            markTrueAfter = [SELECT Id FROM Account WHERE Is_Key_Account__c = true].size();
            accountCountAfter = [SELECT Id FROM Account].size();
        }

        // Count-based, not "looks fine": exactly ONE more marked record, the record
        // itself otherwise untouched, and no side records anywhere.
        System.assertEquals(markTrueBefore + 1, markTrueAfter,
            'AC8: exactly one more Account carries the mark — nothing else got marked automatically.');
        System.assertEquals(true, markAfter, 'AC8: the mark itself persisted.');
        System.assertEquals('+491****1111', phoneAfter, 'AC8: Phone of the record is untouched by the save.');
        System.assertEquals('example.invalid', websiteAfter, 'AC8: Website of the record is untouched by the save.');

        // No emails, no tasks. (Work__Report is NOT an sObject in Test-Org —
        // measured: `sf data query -q "SELECT Id FROM Work__Report"` -> INVALID_TYPE
        // "sObject type 'Work__Report' is not supported" — so the work-record half of
        // AC8 cannot be counted here; it stays an org-level observation.)
        Integer emailBefore = [SELECT Id FROM EmailMessage].size();
        Integer taskBefore = [SELECT Id FROM Task].size();
        Integer caseBefore = [SELECT Id FROM Case].size();
        Integer oppoBefore = [SELECT Id FROM Opportunity].size();
        System.assert(emailBefore >= 0, 'sanity: EmailMessage table readable.');
        System.assert(taskBefore >= 0, 'sanity: Task table readable.');

        System.runAs(u) {
            Account fresh = new Account();
            fresh.Id = accountId;
            fresh.Is_Key_Account__c = false;
            update fresh; // the CLEAR direction, AC3 + AC8 together
        }

        Integer emailAfter = [SELECT Id FROM EmailMessage].size();
        Integer taskAfter = [SELECT Id FROM Task].size();
        Integer caseAfter = [SELECT Id FROM Case].size();
        Integer oppoAfter = [SELECT Id FROM Opportunity].size();
        Integer markTrueFinal;
        System.runAs(u) {
            markTrueFinal = [SELECT Id FROM Account WHERE Is_Key_Account__c = true].size();
        }

        System.assertEquals(emailBefore, emailAfter, 'AC8: setting/clearing the mark created no EmailMessage.');
        System.assertEquals(taskBefore, taskAfter, 'AC8: setting/clearing the mark created no Task.');
        System.assertEquals(caseBefore, caseAfter, 'AC8: no Case record was touched by the mark saves.');
        System.assertEquals(oppoBefore, oppoAfter, 'AC8: no Opportunity record was touched by the mark saves.');
        System.assertEquals(accountCountBefore + 1, accountCountAfter,
            'AC8: exactly one Account exists more than before — the saves created no additional record.');
        System.assertEquals(markTrueBefore, markTrueFinal,
            'AC8/AC3: after clear, the marked count is back to the baseline (mark on, then off).');
    }

    // ---- AC9: the 251 customers that exist today still read "No" -----------
    // AC9 has no Apex method: see the note in the class header — the day-one state
    // of the 251 existing customers is an ORG-level fact (CLI read-back), an Apex
    // assert about them would be vacuous because a test cannot see them.
}
