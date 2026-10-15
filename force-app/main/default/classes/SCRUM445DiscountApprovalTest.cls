/**
 * [SCRUM-445] DiscountApprovalTest — business rules of the discount approval (AC2/AC3/AC5/AC7/AC8/AC9/AC10 + Bulk).
 *
 * House-Pattern SCRUM440RueckrufwunschTest / SCRUM442SatisfactionTest:
 *   Standard-User-Profil, setup-DML (Account/User/PSA/mapping) OUTSIDE System.runAs
 *   (a User cannot grant himself a PSA; MIXED_DML rule SCRUM-442), alle business
 *   DML/SOQL that touches the FLS-gated fields INSIDE System.runAs(<user + PS>).
 *   One runAs-User per @isTest method — never two users doing DML in one transaction.
 *
 * AC-mapping (docs/SCRUM-445-design.md):
 *   AC2  discount <= 15 % closes as Won without any approval.
 *   AC3  discount > 15 %: closing as Won refused while the approval is Pending; the
 *        rep is told via the DmlException message (ValRule No_Won_Without_Approval).
 *   AC5  manager/sales-mgmt approves -> closing as Won succeeds.
 *   AC7  raising the discount above the approved value invalidates the approval.
 *   AC8  lowering the discount keeps the approval.
 *   AC9  hard cap: discount > 25 % refused (ValRule Discount_Hard_Cap_25).
 *   AC10 waiting list: every Pending approval listed with its duration (the ListView
 *        filter predicate is asserted record-wise; the view itself is the E2E spec).
 *   Bulk 200 saves -> 1 mapping SOQL + 1 enqueueJob (counters @testVisible).
 */
@isTest
private class SCRUM445DiscountApprovalTest {

    private static Id accountId(String tag) {
        Account a = new Account(Name = 'V445 ' + tag);
        insert a;
        return a.Id;
    }

    private static User mkUser(String tag, String[] psNames) {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'SCRUM445 ' + tag,
            Alias             = tag,
            Email             = tag + '@scr445.example.invalid',
            Username          = 'scr445_' + tag + '_' + String.valueOf(System.now().getTime()) + '@scr445.example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** PSA inserts AFTER the CMOM mapping insert: PSA is non-setup DML and may not
     * precede a non-setup insert (measured MIXED_DML, house SCRUM-442 Cause E). */
    /** House SCRUM442TestFixtures.existingCloser: an org user that ALREADY carries the
     * PS (read of PermissionSetAssignment, no PSA DML). Needed for the CMOM-mapping
     * methods: a CMOM insert is non-setup DML and cannot share a transaction with a
     * PSA insert in EITHER order (measured, house SCRUM-442 Cause E). */
    private static User existingUser(String psName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        Id assignee = null;
        for (PermissionSetAssignment psa : [SELECT AssigneeId FROM PermissionSetAssignment
                                            WHERE PermissionSetId = :ps.Id]) {
            assignee = psa.AssigneeId;
            break;
        }
        System.assertNotEquals(null, assignee,
            'No org user carries ' + psName + ' — the mapping proof is not exercisable (fail, never pass vacuously).');
        return [SELECT Id FROM User WHERE Id = :assignee LIMIT 1][0];
    }

    /** SCRUM-448: the two fixture users come FROM THE ORG, never from a username.
     *  The old orgUser('devops-agent@cline.test') was a SCALAR SELECT on User, so in
     *  Prod-Org — where that username does not exist — it threw
     *  "List has no rows for assignment to SObject" before any assertion ran, and
     *  reddened the Prod-Org Drift Gate on every later PR.
     *  Resolution: the users that ALREADY carry every SCRUM445 PS (read of
     *  PermissionSetAssignment, no PSA DML). In Test-Org that is the same pair the
     *  literals named; in Prod-Org it is Prod's own pair. Ordered by Username so a
     *  run is reproducible. Fails loudly when fewer than two such users exist — the
     *  mapping proof needs a rep AND a DIFFERENT manager, never a vacuous pass. */
    private static User[] orgFixturePair() {
        String[] psNames = new String[] {
            'SCRUM445_Discount_Owner', 'SCRUM445_Discount_Manager', 'SCRUM445_Discount_System'
        };
        Set<Id> common = null;
        for (String psName : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assertNotEquals(null, ps,
                'Permission Set ' + psName + ' missing — the fixture pair is not resolvable (fail, never pass vacuously).');
            Set<Id> holders = new Set<Id>();
            for (PermissionSetAssignment psa : [SELECT AssigneeId FROM PermissionSetAssignment
                                                WHERE PermissionSetId = :ps.Id]) {
                holders.add(psa.AssigneeId);
            }
            System.assert(holders.size() > 0,
                'No user carries ' + psName + ' — the fixture pair is not resolvable (fail, never pass vacuously).');
            if (common == null) {
                common = holders;
            } else {
                Set<Id> both = new Set<Id>();
                for (Id h : holders) {
                    if (common.contains(h)) { both.add(h); }
                }
                common = both;
            }
        }
        System.assert(common != null && common.size() >= 2,
            'Fewer than two org users carry all SCRUM445 PSs — the mapping proof needs a rep and a different manager (fail, never pass vacuously).');
        List<User> users = [SELECT Id, Username FROM User WHERE Id IN :common ORDER BY Username];
        System.assertEquals(2, users.size(),
            'Exactly two org users carry all SCRUM445 PSs; found ' + users.size() + ' — fixture pair ambiguous.');
        return users;
    }

    private static void grantPS(User u, String[] psNames) {
        if (psNames == null) { return; }
        for (String psName : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    private static void mapRep(User rep, User manager) {
        insert new DiscountApprovalManager__c(Rep__c = rep.Id, Manager__c = manager.Id);
    }

    /** Opportunity in Prospecting with a discount; runs under the PS-carrying user. */
    private static Opportunity mkOpp(Id acc, String name, Decimal discount) {
        Opportunity o = new Opportunity(
            Name = name, AccountId = acc, StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(3)
        );
        if (discount != null) {
            o.Discount_in_Pct__c = discount;
        }
        insert o;
        return o;
    }

    // ---------- AC2: at/below the threshold closes without approval ----------
    @isTest
    static void ac2_belowThreshold_closesWithoutApproval() {
        User rep = mkUser('ac2', null);
        grantPS(rep, new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner', 'SCRUM445_DirectManager_Read', 'SCRUM445_Discount_System', 'SCRUM319_OverdueOpportunity', 'SCRUM381_LeadFollowUp', 'SCRUM414_CloseDateOverdue', 'SCRUM416_OpenOpportunities', 'SCRUM440_Rueckrufwunsch', 'SCRUM442_TestObjectAccess' });
        Id oppId = null;
        Boolean closed = false;
        System.runAs(rep) {
            // house SCRUM-440: Account insert INSIDE runAs, immediately before the Opportunity
            Id acc = accountId('ac2');
            Opportunity o = mkOpp(acc, 'AC2 low discount', 10);
            oppId = o.Id;
            o.StageName = 'Closed Won';
            update o;
            closed = true;
        }
        System.assert(closed, 'AC2: a 10 % discount closes as Won without any approval.');
        Opportunity after = [SELECT Id, StageName, Discount_Approval__c, Discount_in_Pct__c
                             FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals('Closed Won', String.valueOf(after.StageName), 'AC2: closed as Won.');
        System.assertEquals(null, after.Discount_Approval__c,
            'AC2: no approval was created for a discount at/below 15 %.');
        System.assertEquals(10, after.Discount_in_Pct__c, 'AC1: the entered discount is stored.');
    }

    // ---------- AC3: above the threshold, closing as Won is blocked ----------
    @isTest
    static void ac3_aboveThreshold_blockedWhilePending() {
        // MIXED_DML measured: PSA insert is setup-class DML, the CMOM insert is not —
        // so setup (User, PSA, Account) strictly first, then CMOM, then business DML.
        User[] pair = orgFixturePair();
        User rep = pair[0];
        User mgr = pair[1];
        Id acc = accountId('ac3');
        mapRep(rep, mgr);
        Id oppId = null;
        DmlException caught = null;
        System.runAs(rep) {
            Opportunity o = mkOpp(acc, 'AC3 big discount', 20);
            oppId = o.Id;
            o.StageName = 'Closed Won';
            try {
                update o;
            } catch (DmlException e) {
                caught = e;
            }
        }
        System.assert(caught != null, 'AC3: closing as Won with a 20 % discount must be refused.');
        Opportunity after = [SELECT Id, StageName, Discount_Approval__c, Approval_Requested_On__c,
                                    Discount_in_Pct__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals('Prospecting', String.valueOf(after.StageName),
            'AC3: the Opportunity is still open after the refused closing.');
        System.assertEquals('Pending', String.valueOf(after.Discount_Approval__c),
            'AC3: the approval request exists (waiting with the manager).');
        System.assert(after.Approval_Requested_On__c != null,
            'AC3: the waiting duration starts at the request creation.');
    }

    // ---------- AC5: the approval makes the Closed Won possible ----------
    @isTest
    static void ac5_approved_then_closeWon() {
        // sales-management shape: may edit the discount AND the approval state.
        User mgmt = mkUser('ac5', null);
        Id oppId = null;
        Boolean closed = false;
        grantPS(mgmt, new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner', 'SCRUM445_Discount_Manager', 'SCRUM445_DirectManager_Read', 'SCRUM445_Discount_System', 'SCRUM319_OverdueOpportunity', 'SCRUM381_LeadFollowUp', 'SCRUM414_CloseDateOverdue', 'SCRUM416_OpenOpportunities', 'SCRUM440_Rueckrufwunsch', 'SCRUM442_TestObjectAccess' });
        System.runAs(mgmt) {
            // house SCRUM-440: Account insert INSIDE runAs, immediately before the Opportunity
            Id acc = accountId('ac5');
            Opportunity o = mkOpp(acc, 'AC5 approved', 20);
            oppId = o.Id;
            o.Discount_Approval__c = 'Approved';
            update o;
            o = [SELECT Id, StageName, Discount_Approval__c, Approved_Discount_Value__c
                 FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.StageName = 'Closed Won';
            update o;
            closed = true;
        }
        System.assert(closed, 'AC5: after the approval the Closed Won save passes.');
        Opportunity after = [SELECT Id, StageName, Discount_Approval__c, Approved_Discount_Value__c
                            FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals('Closed Won', String.valueOf(after.StageName), 'AC5: closed as Won.');
        System.assertEquals('Approved', String.valueOf(after.Discount_Approval__c), 'AC5: approval kept.');
        System.assertEquals(20, after.Approved_Discount_Value__c,
            'AC5: the approval covers the discount value it was given for.');
    }

    // ---------- AC7: raising above the approved value invalidates ----------
    @isTest
    static void ac7_raiseInvalidatesApproval() {
        User mgmt = mkUser('ac7', null);
        Id oppId = null;
        grantPS(mgmt, new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner', 'SCRUM445_Discount_Manager', 'SCRUM445_DirectManager_Read', 'SCRUM445_Discount_System', 'SCRUM319_OverdueOpportunity', 'SCRUM381_LeadFollowUp', 'SCRUM414_CloseDateOverdue', 'SCRUM416_OpenOpportunities', 'SCRUM440_Rueckrufwunsch', 'SCRUM442_TestObjectAccess' });
        System.runAs(mgmt) {
            // house SCRUM-440: Account insert INSIDE runAs, immediately before the Opportunity
            Id acc = accountId('ac7');
            Opportunity o = mkOpp(acc, 'AC7 raise', 20);
            oppId = o.Id;
            o.Discount_Approval__c = 'Approved';
            update o;
            o = [SELECT Id, Discount_in_Pct__c, Discount_Approval__c, Approved_Discount_Value__c
                 FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.Discount_in_Pct__c = 22;
            update o;
        }
        Opportunity after = [SELECT Id, Discount_in_Pct__c, Discount_Approval__c, Approved_Discount_Value__c,
                                    Approval_Requested_On__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals('Pending', String.valueOf(after.Discount_Approval__c),
            'AC7: raising 20 -> 22 above the approved value invalidates the approval.');
        System.assertEquals(20, after.Approved_Discount_Value__c,
            'AC7: the old approved value is untouched (a new approval is required).');
        System.assert(after.Approval_Requested_On__c != null, 'AC7: a new request exists.');
    }

    // ---------- AC8: lowering keeps the approval, closing passes ----------
    @isTest
    static void ac8_loweringKeepsApproval() {
        User mgmt = mkUser('ac8', null);
        Id oppId = null;
        Boolean closed = false;
        grantPS(mgmt, new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner', 'SCRUM445_Discount_Manager', 'SCRUM445_DirectManager_Read', 'SCRUM445_Discount_System', 'SCRUM319_OverdueOpportunity', 'SCRUM381_LeadFollowUp', 'SCRUM414_CloseDateOverdue', 'SCRUM416_OpenOpportunities', 'SCRUM440_Rueckrufwunsch', 'SCRUM442_TestObjectAccess' });
        System.runAs(mgmt) {
            // house SCRUM-440: Account insert INSIDE runAs, immediately before the Opportunity
            Id acc = accountId('ac8');
            Opportunity o = mkOpp(acc, 'AC8 lower', 20);
            oppId = o.Id;
            o.Discount_Approval__c = 'Approved';
            update o;
            o = [SELECT Id, Discount_in_Pct__c, Discount_Approval__c, Approved_Discount_Value__c
                 FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.Discount_in_Pct__c = 18;
            update o;
            o = [SELECT Id, Discount_Approval__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.StageName = 'Closed Won';
            update o;
            closed = true;
        }
        Opportunity after = [SELECT Id, StageName, Discount_Approval__c, Approved_Discount_Value__c,
                                    Discount_in_Pct__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assert(closed, 'AC8: after lowering to 18 % the Closed Won save passes (no new approval).');
        System.assertEquals('Approved', String.valueOf(after.Discount_Approval__c),
            'AC8: the approval still counts after lowering the discount.');
        System.assertEquals('Closed Won', String.valueOf(after.StageName), 'AC8: closed as Won.');
    }

    // ---------- AC9: hard cap 25 % ----------
    @isTest
    static void ac9_hardCap_refusesAbove25() {
        User mgmt = mkUser('ac9', null);
        Id oppId = null;
        DmlException caught = null;
        grantPS(mgmt, new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner', 'SCRUM445_DirectManager_Read', 'SCRUM445_Discount_System', 'SCRUM319_OverdueOpportunity', 'SCRUM381_LeadFollowUp', 'SCRUM414_CloseDateOverdue', 'SCRUM416_OpenOpportunities', 'SCRUM440_Rueckrufwunsch', 'SCRUM442_TestObjectAccess' });
        System.runAs(mgmt) {
            // house SCRUM-440: Account insert INSIDE runAs, immediately before the Opportunity
            Id acc = accountId('ac9');
            Opportunity o = mkOpp(acc, 'AC9 cap', 10);
            oppId = o.Id;
            o.Discount_in_Pct__c = 30;
            try {
                update o;
            } catch (DmlException e) {
                caught = e;
            }
        }
        System.assert(caught != null, 'AC9: a 30 % discount is refused (hard cap).');
        Opportunity after = [SELECT Id, Discount_in_Pct__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals(10, after.Discount_in_Pct__c, 'AC9: the record keeps the old discount.');
    }

    // ---------- AC10: waiting list predicate + duration ----------
    @isTest
    static void ac10_waitingList_hasDuration() {
        User[] pair = orgFixturePair();
        User rep = pair[0];
        User mgr = pair[1];
        Id acc = accountId('ac10');
        mapRep(rep, mgr);
        Integer created = 0;
        System.runAs(rep) {
            for (Integer i = 0; i < 3; i++) {
                Opportunity o = mkOpp(acc, 'AC10 waiting ' + i, 16 + i);
                created++;
            }
        }
        List<Opportunity> waiting = [SELECT Id, Discount_Approval__c, Approval_Requested_On__c,
                                            Approval_Waiting_Days__c
                                     FROM Opportunity
                                     WHERE Discount_Approval__c = 'Pending'
                                     AND AccountId = :acc];
        System.assertEquals(3, waiting.size(),
            'AC10: all 3 created Pending approvals are listed (created 3, observed 3).');
        for (Opportunity w : waiting) {
            System.assert(w.Approval_Requested_On__c != null, 'AC10: request timestamp present.');
            System.assert(w.Approval_Waiting_Days__c != null && w.Approval_Waiting_Days__c >= 0,
                'AC10: the waiting duration is computed from the request moment.');
        }
    }

    // ---------- AC6: manager rejects with reason -> Closed Won stays blocked ----------
    @isTest
    static void ac6_rejectionBlocksClosedWon() {
        User[] pair = orgFixturePair();
        User rep = pair[0];
        User mgr = pair[1];
        Id acc = accountId('ac6');
        mapRep(rep, mgr);
        Id oppId = null;
        DmlException caught = null;
        System.runAs(rep) {
            Opportunity o = mkOpp(acc, 'AC6 rejected discount', 20);
            oppId = o.Id;
        }
        System.runAs(mgr) {
            Opportunity o = [SELECT Id, StageName, Discount_Approval__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.Discount_Approval__c = 'Rejected';
            o.Rejection_Reason__c = 'Discount too high for this account';
            update o;
        }
        System.runAs(rep) {
            Opportunity o = [SELECT Id, StageName FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.StageName = 'Closed Won';
            try {
                update o;
            } catch (DmlException e) {
                caught = e;
            }
        }
        System.assert(caught != null, 'AC6: after a rejection the Closed Won save must still be refused.');
        Opportunity after = [SELECT Id, StageName, Discount_Approval__c, Rejection_Reason__c,
                                    Approval_Decided_By__c, Approval_Decided_On__c,
                                    Approved_Discount_Value__c, Approval_Requested_On__c
                            FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals('Prospecting', String.valueOf(after.StageName), 'AC6: the record stayed open.');
        System.assertEquals('Rejected', String.valueOf(after.Discount_Approval__c), 'AC6: the rejection is recorded.');
        System.assertEquals('Discount too high for this account', String.valueOf(after.Rejection_Reason__c),
            'AC6: the manager reason is stored and readable by the rep.');
        System.assertEquals(mgr.Id, after.Approval_Decided_By__c, 'AC6: the deciding manager is recorded.');
        System.assertNotEquals(null, after.Approval_Decided_On__c, 'AC6: the decision timestamp is set.');
        System.assertEquals(null, after.Approved_Discount_Value__c,
            'AC6: a rejection never records an approved value.');
    }

    // ---------- AC13: already-closed records are never touched retroactively ----------
    @isTest
    static void ac13_closedRecordsUntouched() {
        User[] pair = orgFixturePair();
        User rep = pair[0];
        User mgr = pair[1];
        Id acc = accountId('ac13');
        mapRep(rep, mgr);
        Id lostId = null;
        Id wonId = null;
        System.runAs(rep) {
            Opportunity lost = new Opportunity(
                Name = 'AC13 closed lost', AccountId = acc, StageName = 'Closed Lost',
                CloseDate = Date.today().addMonths(-1), Discount_in_Pct__c = 20,
                Loss_Reason__c = 'Discount rejected by the customer'
            );
            insert lost;
            lostId = lost.Id;
            Opportunity won = new Opportunity(
                Name = 'AC13 closed won', AccountId = acc, StageName = 'Closed Won',
                CloseDate = Date.today().addMonths(-1), Discount_in_Pct__c = 20,
                Discount_Approval__c = 'Approved', Approved_Discount_Value__c = 20
            );
            insert won;
            wonId = won.Id;
        }
        Opportunity lost = [SELECT Id, StageName, Discount_Approval__c, Approval_Requested_On__c,
                                   Approval_Waiting_Days__c, Approved_Discount_Value__c
                           FROM Opportunity WHERE Id = :lostId LIMIT 1][0];
        Opportunity won = [SELECT Id, StageName, Discount_Approval__c, Approval_Requested_On__c,
                                  Approval_Waiting_Days__c, Approved_Discount_Value__c
                          FROM Opportunity WHERE Id = :wonId LIMIT 1][0];
        System.assertEquals(null, lost.Discount_Approval__c,
            'AC13: a Closed Lost record gets no approval request.');
        System.assertEquals(null, lost.Approval_Requested_On__c,
            'AC13: no waiting duration starts for a closed record.');
        System.assertEquals('Closed Lost', String.valueOf(lost.StageName), 'AC13: the stage is unchanged.');
        System.assertEquals('Approved', String.valueOf(won.Discount_Approval__c),
            'AC13: the existing approval of a Closed Won record is not reset.');
        System.assertEquals(20, won.Approved_Discount_Value__c, 'AC13: the approved value is untouched.');
        // A later edit of a closed record must not activate the approval path either.
        System.runAs(rep) {
            Opportunity o = [SELECT Id, Name FROM Opportunity WHERE Id = :lostId LIMIT 1][0];
            o.Name = 'AC13 closed lost renamed';
            update o;
        }
        Opportunity again = [SELECT Id, Name, StageName, Discount_Approval__c,
                                    Approval_Requested_On__c FROM Opportunity WHERE Id = :lostId LIMIT 1][0];
        System.assertEquals('AC13 closed lost renamed', String.valueOf(again.Name), 'AC13: the edit landed.');
        System.assertEquals(null, again.Discount_Approval__c,
            'AC13: the edit did not put a closed record on the waiting list.');
        System.assertEquals(null, again.Approval_Requested_On__c, 'AC13: still no approval request.');
        // Counted: neither of the two closed records is on the waiting list.
        List<Opportunity> waiting = [SELECT Id FROM Opportunity
                                     WHERE Discount_Approval__c = 'Pending'
                                     AND AccountId = :acc];
        System.assertEquals(0, waiting.size(),
            'AC13: 0 of the 2 closed records appear on the waiting list.');
    }

    // ---------- AC4: mapping resolved + per-manager grouping (FeedItem is E2E) ----------
    @isTest
    static void notification_executeBothPaths() {
        // Empty maps -> empty grouping (the guard path).
        Map<Id, List<String>> empty = DiscountApprovalNotification.notify(new Map<Id, Id>(), new Map<Id, String>());
        System.assertEquals(0, empty.size(), 'AC4: an empty request map produces no grouping.');
        User[] pair = orgFixturePair();
        User rep = pair[0];
        User mgr = pair[1];
        Id acc = accountId('notif');
        mapRep(rep, mgr);
        Integer soqlBefore = DiscountApprovalHandler.mappingSoqlCount;
        Integer enqBefore = DiscountApprovalHandler.enqueueCount;
        List<Id> oppIds = new List<Id>();
        System.runAs(rep) {
            // ONE bulk insert: two separate insert statements would be two trigger
            // invocations and two mapping SOQLs — the batch is what bulkification asserts.
            List<Opportunity> seed = new List<Opportunity>();
            for (Integer i = 0; i < 2; i++) {
                seed.add(new Opportunity(
                    Name = 'NOTIF feed ' + i, AccountId = acc, StageName = 'Prospecting',
                    CloseDate = Date.today().addMonths(3), Discount_in_Pct__c = 20));
            }
            insert seed;
            for (Opportunity o : seed) {
                oppIds.add(o.Id);
            }
        }
        // Bulkification: 2 above-threshold saves -> exactly 1 mapping SOQL, 1 enqueueJob.
        System.assertEquals(1, DiscountApprovalHandler.mappingSoqlCount - soqlBefore,
            'AC4: the whole batch resolved its manager in ONE mapping SOQL.');
        System.assertEquals(1, DiscountApprovalHandler.enqueueCount - enqBefore,
            'AC4: the whole batch produced exactly ONE notification job.');
        Map<Id, Id> m = new Map<Id, Id>();
        Map<Id, String> lines = new Map<Id, String>();
        List<Opportunity> waiting = [SELECT Id, Name, Discount_in_Pct__c FROM Opportunity WHERE Id IN :oppIds];
        System.assertEquals(2, waiting.size(), 'AC4: both seeded records exist for the notification.');
        for (Opportunity o : waiting) {
            m.put(o.Id, mgr.Id);
            lines.put(o.Id, DiscountApprovalNotification.lineFor(o));
        }
        System.assertEquals(2, m.size(), 'AC4: both waiting Opportunities carry a manager.');
        System.assertEquals(2, lines.size(), 'AC4: both waiting Opportunities carry a rendered line.');
        Map<Id, List<String>> grouped = DiscountApprovalNotification.notify(m, lines);
        System.assertEquals(1, grouped.size(),
            'AC4: both Opportunities are grouped under the ONE direct manager.');
        System.assertEquals(2, grouped.get(mgr.Id).size(),
            'AC4: the manager is informed about both of his reps waiting deals.');
        // The payload the Queueable carries names the records — that is what the FeedItem body gets.
        Boolean named = false;
        for (String l : grouped.get(mgr.Id)) {
            if (l.contains('NOTIF feed 0')) {
                named = true;
            }
        }
        System.assertEquals(true, named, 'AC4: the notice text names the waiting record, not just a count.');
    }

    // ---------- Bulk: 200 saves -> 1 mapping SOQL + 1 enqueueJob ----------
    @isTest
    static void bulk_200_updates_oneSoqlOneEnqueue() {
        User[] pair = orgFixturePair();
        User rep = pair[0];
        User mgr = pair[1];
        Id acc = accountId('bulk');
        mapRep(rep, mgr);
        System.runAs(rep) {
            // ONE bulk insert for the 200 seed records: the foreign OpportunityOverdueReset
            // rollup is bulkified (one recompute per DML batch), per-record inserts would
            // blow the 100-SOQL budget in setup, not in the asserted update.
            List<Opportunity> seed = new List<Opportunity>();
            for (Integer i = 0; i < 200; i++) {
                seed.add(new Opportunity(
                    Name = 'BULK ' + i, AccountId = acc, StageName = 'Prospecting',
                    CloseDate = Date.today().addMonths(3), Discount_in_Pct__c = 10));
            }
            insert seed;
            Integer before = DiscountApprovalHandler.mappingSoqlCount;
            Integer beforeEnq = DiscountApprovalHandler.enqueueCount;
            for (Opportunity o : seed) {
                o.Discount_in_Pct__c = 20;
            }
            update seed;
            System.assertEquals(before + 1, DiscountApprovalHandler.mappingSoqlCount,
                'Bulk: exactly ONE mapping SOQL for the 200-record batch.');
            System.assertEquals(beforeEnq + 1, DiscountApprovalHandler.enqueueCount,
                'Bulk: exactly ONE enqueueJob for the batch.');
        }
        List<Opportunity> pending = [SELECT Id, Discount_Approval__c
                                     FROM Opportunity WHERE AccountId = :acc
                                     AND Discount_Approval__c = 'Pending'];
        System.assertEquals(200, pending.size(), 'Bulk: all 200 records carry the approval request.');
    }
}
