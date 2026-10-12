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

    /** House SCRUM442TestFixtures.existingCloser, by username: an org user that ALREADY
     * carries the PSs (read of PermissionSetAssignment, no PSA DML). The CMOM mapping
     * insert is non-setup DML and cannot share a transaction with a PSA insert in EITHER
     * order (measured both directions 2026-10-12, house SCRUM-442 Cause E) — so the
     * mapping methods run as the two org users that already hold all SCRUM445 PSs. */
    private static User orgUser(String username) {
        User u = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
        System.assertNotEquals(null, u, 'Org user ' + username + ' missing — mapping proof not exercisable.');
        return u;
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
        User rep = orgUser('devops-agent@cline.test');
        User mgr = orgUser('meerwais.osmani@resourceful-bear-6f1u4j.com');
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
        User rep = orgUser('devops-agent@cline.test');
        User mgr = orgUser('meerwais.osmani@resourceful-bear-6f1u4j.com');
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

    // ---------- Notification: both execute() paths (empty map + populated map) ----------
    @isTest
    static void notification_executeBothPaths() {
        // Direct call of the Queueable body (no async enqueue) so both branches are measurable.
        DiscountApprovalNotification.notify(new Map<Id, Id>());
        User rep = orgUser('devops-agent@cline.test');
        User mgr = orgUser('meerwais.osmani@resourceful-bear-6f1u4j.com');
        Id acc = accountId('notif');
        mapRep(rep, mgr);
        Id oppId = null;
        System.runAs(rep) {
            Opportunity o = mkOpp(acc, 'NOTIF feed', 20);
            oppId = o.Id;
        }
        Map<Id, Id> m = new Map<Id, Id>();
        m.put(oppId, mgr.Id);
        DiscountApprovalNotification.notify(m);
        System.assertNotEquals(null, oppId, 'Notification: the seeded Opportunity exists.');
    }

    // ---------- Bulk: 200 saves -> 1 mapping SOQL + 1 enqueueJob ----------
    @isTest
    static void bulk_200_updates_oneSoqlOneEnqueue() {
        User rep = orgUser('devops-agent@cline.test');
        User mgr = orgUser('meerwais.osmani@resourceful-bear-6f1u4j.com');
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
