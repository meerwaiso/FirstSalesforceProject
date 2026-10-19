/**
 * [SCRUM-451] Tester artefact — AC2 negative proof against REAL org behaviour.
 *
 * SCRUM451WartungsvertragFlsTest proves the negative by reflection
 * (`isUpdateable() == false`). That answers "the platform says the field is
 * locked" — it does not answer the second half of AC2:
 *
 *   "Given a user who is not a team lead, When they try to change the contract
 *      flag or either date, Then the change is refused AND THE STORED VALUE
 *      STAYS UNCHANGED."
 *
 * This class therefore attempts the DML itself and reads the record back
 * afterwards. Two licences exist in this org and both are held by System
 * Administrators, so a second browser session is impossible — System.runAs is
 * the default route here (skill salesforce-playwright-session §4c).
 *
 * Measured facts this class stands on (Test-Org, 2026-10-18):
 *   - FieldPermissions WHERE Field='Account.Wartungsvertrag_End__c' → read is
 *     granted by the permission GROUP "Agentic Near Core CRM", edit by nobody
 *     but SCRUM451_Wartungsvertrag_Dates_Teamleitung. A Permission Set can only
 *     grant, never revoke, so the negative is on the EDIT side.
 *   - The seeded end date (today-30) is AFTER the seeded start date (today-9
 *     months), so a refusal here cannot come from the ValidationRule
 *     Wartungsvertrag_End_Before_Start — it can only come from FLS.
 *   - House shape SCRUM451WartungsvertragTest: User + PermissionSetAssignment
 *     are setup DML before any business DML (MIXED_DML_OPERATION otherwise).
 */
@isTest
private class SCRUM451TesterFlsNegativeTest {

    private static Profile standardProfile() {
        return [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    }

    private static User newUser(String tag) {
        Profile p = standardProfile();
        String uName = 'scr451neg-' + tag + '-' + DateTime.now().getTime() + '@example.invalid';
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr451Neg-' + tag,
            Alias = ('45n' + tag).left(8),
            Email = uName,
            Username = uName,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static void assignPS(String psName, Id userId) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    }

    // ---- setup DML first: the two users, and the PS only on the team lead ---
    @isTest
    static void nonTeamleadChangeRefused_storedValueUnchanged() {
        User lead = newUser('lead');
        for (String psName : new String[] {
                'SCRUM431_Wartungsvertrag_Teamleitung',
                'SCRUM451_Wartungsvertrag_Dates_Teamleitung',
                'SCRUM451_Wartungsvertrag_Dates_Read',
                'SCRUM451_TestObjectAccess' }) {
            assignPS(psName, lead.Id);
        }
        User outsider = newUser('out');

        Date startSeeded = Date.today().addMonths(-9);
        Date endSeeded = Date.today().addDays(-30);   // AFTER start → the ValidationRule cannot be the cause

        // A team lead records both dates (the positive round trip).
        Id accId = null;
        System.runAs(lead) {
            Account a = new Account(
                Name = 'TEST-SCRUM-451-NEG-SAVE',
                Wartungsvertrag__c = true,
                Wartungsvertrag_Start__c = startSeeded,
                Wartungsvertrag_End__c = endSeeded
            );
            insert a;
            accId = a.Id;
        }
        System.assertNotEquals(null, accId, 'setup: the team lead stored the customer');

        Account seeded = [SELECT Id, Name, Wartungsvertrag__c, Wartungsvertrag_Start__c,
                          Wartungsvertrag_End__c FROM Account WHERE Id = :accId];
        System.assertEquals(endSeeded, seeded.Wartungsvertrag_End__c,
            'setup: the recorded end date is stored as typed');
        System.assertEquals(true, seeded.Wartungsvertrag__c, 'setup: the flag is stored as typed');

        // ---- the user WITHOUT the team-lead PS attempts the change ----------
        Boolean endRefused = false;
        Boolean flagRefused = false;
        String endMsg = '';
        System.runAs(outsider) {
            Account attemptEnd = seeded;
            attemptEnd.Wartungsvertrag_End__c = Date.today().addDays(60);
            try {
                update attemptEnd;
            } catch (DmlException e) {
                endRefused = true;
                endMsg = e.getMessage();
            }
            Account attemptFlag = seeded;
            attemptFlag.Wartungsvertrag__c = false;
            try {
                update attemptFlag;
            } catch (DmlException e) {
                flagRefused = true;
            }
        }
        System.assert(endRefused,
            'AC2: a user without the team-lead Permission Set MUST NOT be able to move the end date. '
            + 'Actually the save went through — the FLS entry is missing or unassigned.');
        System.assert(endMsg.length() > 0, 'AC2: the refusal names a reason: ' + endMsg);
        System.assert(flagRefused,
            'AC2: the same user MUST NOT be able to clear the contract flag either');

        // ---- the stored value must be untouched ----------------------------
        Account after = [SELECT Wartungsvertrag__c, Wartungsvertrag_Start__c,
                         Wartungsvertrag_End__c FROM Account WHERE Id = :accId];
        System.assertEquals(endSeeded, after.Wartungsvertrag_End__c,
            'AC2: the stored end date is unchanged after the refused save');
        System.assertEquals(startSeeded, after.Wartungsvertrag_Start__c,
            'AC2: the stored start date is unchanged after the refused save');
        System.assertEquals(true, after.Wartungsvertrag__c,
            'AC2: the stored flag is unchanged after the refused save');

        // and the derived decision still follows the STORED dates, not the attempt
        Account derived = [SELECT Wartungsvertrag_Ende_Tage__c, Wartungsvertrag_Status__c,
                           Wartungsvertrag_Active__c FROM Account WHERE Id = :accId];
        System.assert(derived.Wartungsvertrag_Ende_Tage__c == null,
            'AC2: the stored end date is in the past -> no day count, never a negative one');
        System.assertEquals('expired', derived.Wartungsvertrag_Status__c,
            'AC2: the glance value still follows the STORED dates, not the refused attempt');
        System.assertEquals(false, derived.Wartungsvertrag_Active__c,
            'AC2: the stored end date is in the past -> the customer no longer counts');
    }
}
