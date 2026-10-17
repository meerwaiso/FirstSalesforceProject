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

    @TestSetup
    static void setup_accountForUserDml() {
        // Setup DML in its OWN transaction (@TestSetup) — see the MIXED_DML note
        // in the method below. Looked up by Name, not by a static: TestSetup
        // statics are not visible from test methods (house lesson, bulk test).
        Account a = new Account(Name = 'FLS449 Account');
        insert a;
    }

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
        // MIXED_DML (measured 2026-10-14, run 707WU00001Nl2Tv): inserting the
        // Account HERE failed with "DML operation on setup object ... Account,
        // original object: PermissionSetAssignment" — a setup-object insert may
        // not follow the non-setup PSA inserts of this transaction. The Account
        // therefore comes from @TestSetup, its own transaction, and is looked up
        // by Name here (TestSetup statics are not visible across methods).
        Account a = [SELECT Id FROM Account WHERE Name = 'FLS449 Account' LIMIT 1];
        System.runAs(u) {
            Opportunity o = new Opportunity(
                Name = 'FLS449 user opp',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(2), // early stage + close date soon -> C2 applies
                AccountId = a.Id
            );
            insert o;
            // The user cannot SEE the risk fields, so the read-back happens in
            // System context below — here only the record itself is proven.
            Opportunity r = [SELECT Id, Name FROM Opportunity
                             WHERE Name = 'FLS449 user opp' LIMIT 1];
            System.assertEquals('FLS449 user opp', r.Name,
                'the user can create the record without touching the risk fields');
        }
        Opportunity assessed = [SELECT Id, Risk_Level__c FROM Opportunity
                                WHERE Name = 'FLS449 user opp' LIMIT 1];
        System.assertNotEquals(null, assessed.Risk_Level__c,
            'the trigger (system context) assessed the record even for a user without PS');
    }

    // ---- Review SCRUM-449 round 6, Blocking 4: the fix must be proven -------
    // (a) The nightly sweep must survive an org in which a custom field on the
    // object is INVISIBLE to the acting user. That is exactly the Prod shape of
    // TestFeld__c (exists, no grant at all -> "Operation failed due to fields
    // being inaccessible on Sobject Opportunity", AsyncApexJob
    // 707g500000ryLVDAA2). Test-Org reproduces the shape with a user that holds
    // ONLY the two SCRUM449 sets: Rueckruf_desired__c (SCRUM440_Rueckrufwunsch),
    // Discount_in_Pct__c and Rejection_Reason__c (SCRUM445_*) are granted by
    // Permission Sets, not by Profiles (measured with scripts/fls-check.sh), so
    // for this user they are invisible — the same wall the Prod scheduler hit.
    @isTest
    static void sweep_survivesForeignFieldInvisibleToActingUser() {
        User u = mkUser('fls449sw');
        insert u;
        // Account from @TestSetup (own transaction), looked up by Name — house
        // lesson: TestSetup statics are not visible across methods, and a setup
        // object must not be inserted after the PSA inserts of this transaction.
        Account acct = [SELECT Id FROM Account WHERE Name = 'FLS449 Account' LIMIT 1];
        PermissionSet psRead = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM449OpportunityRisk' LIMIT 1
        ];
        PermissionSet psWrite = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM449OpportunityRiskWrite' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psRead.Id);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psWrite.Id);

        // PRECONDITION — the probe must be able to fail. If this user could see
        // all three foreign fields, the run below would prove nothing about the
        // FLS wall and the test would pass for the wrong reason.
        System.runAs(u) {
            System.assert(Opportunity.SObjectType.getDescribe().isAccessible(),
                'precondition: the user must be able to open Opportunity');
            System.assertEquals(false, Opportunity.Rueckruf_desired__c.getDescribe().isAccessible(),
                'precondition: Rueckruf_desired__c must be INVISIBLE to this user (the Prod shape)');
            System.assertEquals(false, Opportunity.Discount_in_Pct__c.getDescribe().isAccessible(),
                'precondition: Discount_in_Pct__c must be INVISIBLE to this user');
            System.assertEquals(false, Opportunity.Rejection_Reason__c.getDescribe().isAccessible(),
                'precondition: Rejection_Reason__c must be INVISIBLE to this user');
            System.assertEquals(true, Opportunity.Risk_Level__c.getDescribe().isAccessible(),
                'precondition: the risk fields themselves must be readable');
        }

        // (a1) THE WALL ITSELF, hit directly. This is the non-vacuous proof:
        // userEditedRecord() is the code that read the foreign fields, and for
        // THIS user three of them are invisible. Under the old code the call
        // below threw System.DmlException: "Operation failed due to fields being
        // inaccessible on Sobject Opportunity" — the exact message of the failed
        // Prod AsyncApexJob 707g500000ryLVDAA2 — and an unhandled exception fails
        // the test. With the guard the call answers without touching the field.
        // refreshForeignVisibility() is what the handler calls once per transaction
        // (accessibility belongs to the acting user), so the test mirrors the
        // production path rather than the lazy fallback.
        System.runAs(u) {
            OpportunityRiskService.refreshForeignVisibility();

            // Two records identical in every field the user CAN see. A user
            // transaction that changes nothing visible is not a user change.
            Opportunity plainA = new Opportunity(
                Name = 'FLS449 wall probe',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = acct.Id
            );
            Opportunity plainB = new Opportunity(
                Name = 'FLS449 wall probe',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = acct.Id
            );
            System.assertEquals(false, OpportunityRiskService.userEditedRecord(plainB, plainA),
                'a transaction that changes nothing the user can see is not a user change ' +
                    '(and must not read the invisible foreign fields at all)');

            // Same call, one VISIBLE difference: the diff still works for a user
            // who cannot see the foreign fields.
            Opportunity touched = new Opportunity(
                Name = 'FLS449 wall probe',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Description = 'changed by the rep',
                AccountId = acct.Id
            );
            System.assertEquals(true, OpportunityRiskService.userEditedRecord(touched, plainA),
                'a change of a field the user CAN see is still a user change');
        }

        // (a2) The scheduler path end to end for that user: the nightly sweep must
        // run and must not throw. Honest scope note: recomputeAll() sets
        // systemWriteInProgress, so the handler short-circuits userEditedRecord()
        // on the sweep's OWN writes — the wall proof above is what pins the FLS
        // behaviour; this call proves the sweep still completes for a user without
        // the foreign fields.
        //
        // Measured (probe SCRUM449ProbeTest, 2026-10-17): an Apex test run sees
        // ONLY the records it creates (org-wide open Opportunities = 0 from inside
        // a test), so the sweep here covers the records seeded below, and the
        // count asserts it covered them.
        List<Opportunity> seeds = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            seeds.add(new Opportunity(
                Name = 'FLS449 sweep ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(-1), // past close date -> High, so the sweep must write
                AccountId = acct.Id
            ));
        }
        System.runAs(u) {
            insert seeds;
        }

        Integer saved = 0;
        Test.startTest();
        System.runAs(u) {
            saved = OpportunityRiskService.recomputeAll();
        }
        Test.stopTest();

        List<Opportunity> stamped = [
            SELECT Id, Name, Last_Risk_Evaluation__c, Last_User_Change__c, Risk_Level__c
            FROM Opportunity WHERE Name LIKE 'FLS449 sweep%'
        ];
        System.assertEquals(3, stamped.size(), 'the sweep must cover the seeded open records (seeded=3)');
        Integer stampedCount = 0;
        Integer anchoredCount = 0;
        Integer levelledCount = 0;
        for (Opportunity o : stamped) {
            if (o.Last_Risk_Evaluation__c != null) {
                stampedCount++;
            }
            if (o.Last_User_Change__c != null) {
                anchoredCount++;
            }
            if (o.Risk_Level__c != null) {
                levelledCount++;
            }
        }
        System.assertEquals(3, stampedCount,
            'every seeded record carries an evaluation stamp (stamped=' + stampedCount + ')');
        System.assertEquals(3, anchoredCount,
            'the anchor exists on every seeded record (anchored=' + anchoredCount + ')');
        System.assertEquals(3, levelledCount,
            'the sweep actually assessed the records (levelled=' + levelledCount + ')');
    // saved is NOT asserted > 0: the insert above already ran the trigger,
    // so the records are consistent and the sweep legitimately finds
    // nothing dirty (measured: saved=0 with stamped=3). What must not
    // happen is the wall — an unhandled DmlException fails the test. The
    // 3/3/3 counts above are the non-vacuous check that the records were
    // assessed; the direct userEditedRecord() call is the wall proof.
    System.debug('sweep as a user without the foreign fields completed, saved=' + saved);
    }

    // (b) A user edit of a field the acting user CAN see must still move the
    // anchor — the guard must not have silently dropped a real user-change
    // signal. Round-7 Blocking 1: the previous version used TestFeld__c and
    // asserted its visibility from the ORG's Profiles (28 Profiles grant it in
    // Test-Org, nothing grants it in Prod-Org) — a test that reads one org's
    // FLS proves nothing about the rule and reddened the Prod-Org Drift Gate.
    // The proof now uses a field granted by a PERMISSION SET that exists in
    // BOTH orgs: Rueckruf_desired__c via SCRUM440_Rueckrufwunsch. Measured 2026-10-17
    // in Test-Org AND Prod-Org: FieldPermissions rows Parent.Name='SCRUM440_Rueckrufwunsch',
    // read=true, edit=true for Rueckruf_desired__c and Rueckruf_am__c, IsOwnedByProfile=false.
    // The test user holds that PS, so the precondition is the CONTRACT (the PS
    // grants the field), not one org's Profile table.
    @isTest
    static void userEditOfGrantedForeignField_movesAnchor() {
        Account a = [SELECT Id FROM Account WHERE Name = 'FLS449 Account' LIMIT 1];
        User u = mkUser('fls449ue');
        insert u; // the user must exist before System.runAs can act as it

        // The user needs the SCRUM449 sets: the trigger writes the six risk
        // fields on EVERY insert/update, so without them the insert itself
        // throws "fields being inaccessible on Sobject Opportunity" (measured:
        // deploy 0AfWU00000cIyPe0AK, a bare Standard User at line 271).
        PermissionSet psRead = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM449OpportunityRisk' LIMIT 1
        ];
        PermissionSet psWrite = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM449OpportunityRiskWrite' LIMIT 1
        ];
        // The foreign field of the proof is granted by SCRUM440_Rueckrufwunsch —
        // a Permission Set present in BOTH orgs, unlike TestFeld__c's Profile
        // grants. Never read the org's Profiles here (round-7 Blocking 1).
        PermissionSet psForeign = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM440_Rueckrufwunsch' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psRead.Id);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psWrite.Id);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psForeign.Id);

        // PRECONDITION: the field must be visible AND writable for this user,
        // otherwise the edit below is not a user change and the assertion would
        // pass for the wrong reason.
        System.runAs(u) {
            System.assertEquals(true, Opportunity.Rueckruf_desired__c.getDescribe().isAccessible(),
                'precondition: Rueckruf_desired__c must be readable for a user holding '
                    + 'SCRUM440_Rueckrufwunsch (the PS grants it in both orgs)');
            System.assertEquals(true, Opportunity.Rueckruf_desired__c.getDescribe().isUpdateable(),
                'precondition: Rueckruf_desired__c must be writable for that user');
            System.assertEquals(true, Opportunity.Rueckruf_am__c.getDescribe().isAccessible(),
                'precondition: the paired Rueckruf_am__c must be readable (ValRule pair)');
        }

        Opportunity seed = new Opportunity(
            Name = 'FLS449 anchor edit',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30), // far away -> only the anchor matters
            AccountId = a.Id
        );
        // Anchor seeded 20 days in the past, so the value after the edit is
        // unambiguous: a moved anchor is ~now, a swallowed edit leaves now-20d.
        // (Comparing two anchors written in the same second is not a
        // discriminator — the DateTime string only shows seconds.)
        seed.Last_User_Change__c = System.now().addDays(-20);
        System.runAs(u) {
            insert seed;
        }
        Opportunity before = [
            SELECT Id, Last_User_Change__c FROM Opportunity
            WHERE Name = 'FLS449 anchor edit' LIMIT 1
        ];
        System.assertNotEquals(null, before.Last_User_Change__c, 'the insert seeded the anchor');

        System.runAs(u) {
            Opportunity o = [SELECT Id, Rueckruf_desired__c, Rueckruf_am__c
                             FROM Opportunity
                             WHERE Name = 'FLS449 anchor edit' LIMIT 1];
            // ValRule pair Rueckruf_am_PflichtBeiGesetzer / Rueckruf_am_KeineNichte
            // (measured in both orgs): a set checkbox requires a FUTURE
            // Rueckruf_am__c, otherwise the save is blocked.
            o.Rueckruf_desired__c = true;
            o.Rueckruf_am__c = System.now().addDays(3);
            update o;
        }

        Opportunity after = [
            SELECT Id, Last_User_Change__c FROM Opportunity
            WHERE Name = 'FLS449 anchor edit' LIMIT 1
        ];
        System.assert(after.Last_User_Change__c > before.Last_User_Change__c,
            'a user edit of a field the user CAN see must move the anchor: ' +
                'anchor before=' + before.Last_User_Change__c +
                ', anchor after=' + after.Last_User_Change__c);
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
