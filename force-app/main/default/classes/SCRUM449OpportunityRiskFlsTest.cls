/**
 * [SCRUM-449] SCRUM449OpportunityRiskFlsTest — FLS negative + positive proof.
 *
 * AC9 (nobody sets the risk by hand) and the read-gate for the six new fields:
 *   - a Standard-User WITHOUT any PS: the six fields are neither readable
 *     nor writable (new custom fields are FLS-gated by default — house
 *     SCRUM416OpenOpportunityFlsTest, verified pattern).
 *   - the same user WITH SCRUM449OpportunityRisk: readable, still NOT writable
 *     (editable=false on every field permission).
 *   - even WITH the Write-PS the fields stay non-editable for a human:
 *     SCRUM449OpportunityRiskWrite is assigned to the scheduler user only,
 *     never to a human profile — and a Permission Set can only grant, never
 *     revoke, so the negative proof below is only meaningful while the test
 *     user holds the READ-PS (house lesson: PS grants, never revokes).
 *
 * Mixed-DML house lesson (SCRUM-442): the PermissionSetAssignment inserts are
 * System-context setup DML; the business SOQL/DML runs under System.runAs(user)
 * in the SAME transaction — a user cannot grant himself a PSA, so the PSA
 * insert stays outside the runAs block.
 *
 * @author developer-agent
 * @date 2026-10-14
 */
@isTest
private class SCRUM449OpportunityRiskFlsTest {

    private static List<String> fieldApiNames() {
        return new List<String>{
            'Opportunity.Risk_Level__c',
            'Opportunity.Risk_Reason__c',
            'Opportunity.Inactive_Days__c',
            'Opportunity.Last_Risk_Evaluation__c',
            'Opportunity.Last_User_Change__c',
            'Opportunity.Highest_Stage_Reached__c'
        };
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Fls449',
            Alias = alias, // max 8 chars (org limit, verified by the error)
            Email = alias + '449@example.invalid',
            Username = alias + '449_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
        );
    }

    @isTest
    static void riskFields_invisibleWithoutPS_readableNotWritableWithPS() {
        User u = mkUser('fls449n');
        insert u;

        // Precondition: the user can see the OBJECT — otherwise the negative
        // asserts below would pass for the wrong reason (house SCRUM416).
        System.runAs(u) {
            System.assert(
                Opportunity.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Opportunity object access — ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // NEGATIVE: no PS at all -> every risk field invisible AND unwritable.
        System.runAs(u) {
            System.assertEquals(false, Opportunity.Risk_Level__c.getDescribe().isAccessible(),
                'Without PS Risk_Level__c must NOT be readable');
            System.assertEquals(false, Opportunity.Risk_Reason__c.getDescribe().isAccessible(),
                'Without PS Risk_Reason__c must NOT be readable');
            System.assertEquals(false, Opportunity.Inactive_Days__c.getDescribe().isAccessible(),
                'Without PS Inactive_Days__c must NOT be readable');
            System.assertEquals(false, Opportunity.Last_Risk_Evaluation__c.getDescribe().isAccessible(),
                'Without PS Last_Risk_Evaluation__c must NOT be readable');
            System.assertEquals(false, Opportunity.Last_User_Change__c.getDescribe().isAccessible(),
                'Without PS Last_User_Change__c must NOT be readable');
            System.assertEquals(false, Opportunity.Highest_Stage_Reached__c.getDescribe().isAccessible(),
                'Without PS Highest_Stage_Reached__c must NOT be readable');
            System.assertEquals(false, Opportunity.Risk_Level__c.getDescribe().isUpdateable(),
                'Without PS Risk_Level__c must NOT be writable');
        }

        // Grant the READ-PS only.
        PermissionSet psRead = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM449OpportunityRisk' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psRead.Id);

        // POSITIVE: readable with the PS; AC9: still NOT writable for a human.
        System.runAs(u) {
            System.assertEquals(true, Opportunity.Risk_Level__c.getDescribe().isAccessible(),
                'With PS Risk_Level__c must be readable');
            System.assertEquals(true, Opportunity.Risk_Reason__c.getDescribe().isAccessible(),
                'With PS Risk_Reason__c must be readable');
            System.assertEquals(true, Opportunity.Inactive_Days__c.getDescribe().isAccessible(),
                'With PS Inactive_Days__c must be readable');
            System.assertEquals(true, Opportunity.Last_Risk_Evaluation__c.getDescribe().isAccessible(),
                'With PS Last_Risk_Evaluation__c must be readable');
            System.assertEquals(true, Opportunity.Last_User_Change__c.getDescribe().isAccessible(),
                'With PS Last_User_Change__c must be readable');
            System.assertEquals(true, Opportunity.Highest_Stage_Reached__c.getDescribe().isAccessible(),
                'With PS Highest_Stage_Reached__c must be readable');
            // AC9: editable=false on every field permission of the read-PS.
            System.assertEquals(false, Opportunity.Risk_Level__c.getDescribe().isUpdateable(),
                'AC9: with the READ-PS Risk_Level__c must stay read-only');
            System.assertEquals(false, Opportunity.Risk_Reason__c.getDescribe().isUpdateable(),
                'AC9: Risk_Reason__c must stay read-only');
            System.assertEquals(false, Opportunity.Last_Risk_Evaluation__c.getDescribe().isUpdateable(),
                'AC9: Last_Risk_Evaluation__c must stay read-only');
            System.assertEquals(false, Opportunity.Last_User_Change__c.getDescribe().isUpdateable(),
                'AC9: Last_User_Change__c must stay read-only');
            System.assertEquals(false, Opportunity.Highest_Stage_Reached__c.getDescribe().isUpdateable(),
                'AC9: Highest_Stage_Reached__c must stay read-only');
        }

        // Business DML under the user: the user can still work with the record
        // itself (the risk fields are simply not theirs to set).
        System.runAs(u) {
            Account a = [SELECT Id FROM Account WHERE Name = 'Risk Test Account' LIMIT 1];
            Opportunity o = new Opportunity(
                Name = 'FLS449 user opp',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = a.Id
            );
            insert o;
            Opportunity r = [SELECT Id, Risk_Level__c FROM Opportunity
                             WHERE Name = 'FLS449 user opp' LIMIT 1];
            System.assertNotEquals(null, r.Risk_Level__c,
                'the trigger (system context) assesses the record even for a user without PS');
        }
    }

    @isTest
    static void writePS_neverAssignedToHumanProfiles() {
        // AC9 second half: SCRUM449OpportunityRiskWrite exists for the scheduler
        // user only. Assert it sits on no Standard-User profile (the org-verifiable
        // half: PSA rows, columns AssigneeId/PermissionSetId — house lesson:
        // there is no `Assignee` column and no join on PermissionSet.Name).
        Id standardProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        PermissionSet psWrite = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM449OpportunityRiskWrite' LIMIT 1
        ];
        List<PermissionSetAssignment> rows = [SELECT AssigneeId, PermissionSetId
                                              FROM PermissionSetAssignment
                                              WHERE PermissionSetId = :psWrite.Id];
        for (PermissionSetAssignment row : rows) {
            User u = [SELECT Id, ProfileId FROM User WHERE Id = :row.AssigneeId LIMIT 1];
            System.assertNotEquals(standardProfileId, u.ProfileId,
                'the Write-PS must never sit on a Standard User profile');
        }
    }
}
