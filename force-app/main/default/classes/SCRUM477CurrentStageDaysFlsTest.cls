/**
 * [SCRUM-477][Tester] Tage jetzige Stage — the permission boundary, on its own two users.
 * [SCRUM-482] Rebuilt: the class used to run @isTest(SeeAllData=true), ask every active User
 * of the org and read the whole stuck list. That made the verdict depend on who happens to
 * exist in the org (a Test-Org username the Prod-Org Drift Gate never had) and on how many
 * deals were stuck that day. Whether real people hold a Permission Set is a release read-back
 * (scripts/fls-check.sh), not an automated test.
 *
 * What is asserted now (SCRUM-482 ADR-4/ADR-5):
 *   the boundary — a colleague who holds the deployed read-only Permission Set reads the
 *   number, nobody writes it, and a colleague who differs only in that grant cannot read it.
 *   Two users are created by the test; the only Permission Set named is the one of SCRUM-477,
 *   and it is assigned only to a user the test created. No new Permission Set, no new grant,
 *   no Profile edit.
 *
 * Mixed DML house rule (SCRUM-442 / SCRUM-467): User and PermissionSetAssignment are System
 * context setup DML first, every business DML/SOQL runs inside System.runAs. The negative is
 * getDescribe().isAccessible() plus a rejected SOQL read of the test's own record — never a
 * refused Apex update (Apex runs "on the inside", and the counter is createable:false, so a
 * write-refusal test would pass even with a useless Permission Set).
 *
 * @author developer-agent
 * @date 2026-11-26
 */
@isTest
public class SCRUM477CurrentStageDaysFlsTest {

    private static User mkUser(String tag, List<String> psNames) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr482Fls-' + tag,
            Alias = ('f482' + tag).left(8),
            Email = 'scr482fls-' + tag + '@example.invalid',
            Username = 'scr482fls-' + tag + '-' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        for (String psName : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    // T5 — the holder reads the number of its own fixture; nobody may write it.
    @isTest
    static void holderReadsTheCounter_nobodyWritesIt() {
        User holder = mkUser('holder', new List<String>{ 'SCRUM477_CurrentStageDays_Read' });
        // The second colleague differs from the first ONLY in that grant.
        User blind = mkUser('blind', new List<String>());

        boolean objectVisible = false;
        System.runAs(blind) {
            objectVisible = Opportunity.SObjectType.getDescribe().isAccessible();
        }
        System.assert(
            objectVisible,
            'precondition: the colleague must be able to open the Opportunity — otherwise the ' +
                'asserts below would pass for the wrong reason'
        );

        Integer rows = 0;
        Double counterSeen = null;
        boolean readable = false;
        boolean writable = false;
        System.runAs(holder) {
            Opportunity fresh = new Opportunity(
                Name = 'TEST-SCRUM-482-T5',
                StageName = 'Prospecting',
                Amount = 1200.00,
                CloseDate = Date.today().addDays(25)
            );
            insert fresh;
            List<Opportunity> found = [
                SELECT Id, Stage_Days_In_Current_Stage__c
                FROM Opportunity
                WHERE Id = :fresh.Id
            ];
            rows = found.size();
            if (rows == 1) {
                counterSeen = found[0].Stage_Days_In_Current_Stage__c;
            }
            readable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isAccessible();
            writable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isUpdateable();
        }

        System.assertEquals(1, rows, 'T5: the holder reads exactly its own fixture row');
        System.assertEquals(0.0, counterSeen,
            'T5: the holder sees the number itself — a new open deal is 0 days');
        System.assertEquals(true, readable,
            'T5: the read-only Permission Set makes the counter readable for its holder');
        System.assertEquals(false, writable,
            'AC8: the counter is writable by nobody, not even by a holder of the read-only set');
    }

    // T6 — the mandatory negative: without the Permission Set the number is not readable.
    @isTest
    static void withoutPermissionSet_theNumberIsNotReadable() {
        User holder = mkUser('holder', new List<String>{ 'SCRUM477_CurrentStageDays_Read' });
        User blind = mkUser('blind', new List<String>());

        Id fixtureId = null;
        System.runAs(holder) {
            Opportunity fresh = new Opportunity(
                Name = 'TEST-SCRUM-482-T6',
                StageName = 'Prospecting',
                Amount = 1100.00,
                CloseDate = Date.today().addDays(25)
            );
            insert fresh;
            fixtureId = fresh.Id;
        }
        System.assertNotEquals(null, fixtureId, 'setup: the fixture exists, so a rejected read is about the field');

        boolean fieldVisibleToBlind = false;
        System.runAs(blind) {
            fieldVisibleToBlind = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isAccessible();
        }
        System.assertEquals(
            false,
            fieldVisibleToBlind,
            'T6: a colleague without the Permission Set does not even see the field on the record'
        );

        boolean queryRejected = false;
        Integer blindRows = -1;
        System.runAs(blind) {
            try {
                List<Opportunity> found = [
                    SELECT Id, Stage_Days_In_Current_Stage__c
                    FROM Opportunity
                    WHERE Id = :fixtureId
                ];
                blindRows = found.size();
            } catch (Exception e) {
                queryRejected = true;
            }
        }
        System.assertEquals(
            true,
            queryRejected,
            'T6: SOQL served the day counter to a colleague without the Permission Set (' +
                    blindRows +
                    ' rows)'
        );
    }
}
