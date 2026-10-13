/**
 * [SCRUM-445] DiscountApprovalHandler — Trigger handler for the discount-approval rules.
 *
 * House pattern: OpportunityOverdueResetHandler (SCRUM-319) / RueckrufTaskHandler (SCRUM-440):
 * static methods, bulkified, ONE mapping SOQL per batch, no SOQL in a loop, one enqueueJob per batch.
 *
 * Business rules (SCRUM-445, confirmed with Head of Sales):
 *   - discount > 15 % requires an approval by the rep's DIRECT MANAGER before the
 *     Opportunity may be closed as Won — the save itself is blocked by the ValidationRule
 *     No_Won_Without_Approval, the handler creates/refreshes the Pending request;
 *   - raising the discount above the approved value invalidates the approval (new Pending
 *     request, waiting duration restarts); lowering it keeps the approval;
 *   - the approval state is only editable via Permission Set SCRUM445_Discount_Manager
 *     (manager + sales management); the handler WRITES it in system context;
 *   - the direct manager is resolved from the mapping object DiscountApprovalManager__c
 *     (role hierarchy unusable: every ForecastUserId null, measured SCRUM-445);
 *   - the manager is informed WITHOUT an email: one FeedItem on the manager's feed
 *     via the Queueable DiscountApprovalNotification.
 *
 * @testVisible counters prove bulkification in SCRUM445DiscountApprovalTest
 * (200 records -> 1 mapping SOQL + 1 enqueueJob).
 */
public with sharing class DiscountApprovalHandler {

    private static final Decimal APPROVAL_THRESHOLD = 15;

    @testVisible public static Integer mappingSoqlCount = 0;
    @testVisible public static Integer enqueueCount = 0;

    /** before-update: approval request + approval/rejection decision in one pass. */
    public static void handleBeforeUpdate(List<Opportunity> newRecords, Map<Id, Opportunity> oldMap) {
        Set<Id> ownerIds = new Set<Id>();
        Map<Id, Opportunity> requesting = new Map<Id, Opportunity>();
        List<Opportunity> deciding = new List<Opportunity>();

        for (Opportunity opp : newRecords) {
            Opportunity old = oldMap.get(opp.Id);
            if (old == null) {
                continue;
            }
            String oldAppr = old.Discount_Approval__c;
            String newAppr = opp.Discount_Approval__c;

            // 1. Decision transition (only a User holding SCRUM445_Discount_Manager can
            //    change the picklist at all — house FLS gate).
            if (newAppr != oldAppr && (newAppr == 'Approved' || newAppr == 'Rejected')) {
                deciding.add(opp);
                if (opp.OwnerId != null) {
                    ownerIds.add(opp.OwnerId);
                }
                continue;
            }

            // 2. Approval request: discount above the threshold without a covering approval.
            if (needsApproval(opp)) {
                if (newAppr == 'Pending') {
                    // request already waiting -> duration stays measured from its creation
                    continue;
                }
                opp.Discount_Approval__c = 'Pending';
                opp.Approval_Requested_On__c = DateTime.now();
                requesting.put(opp.Id, opp);
                if (opp.OwnerId != null) {
                    ownerIds.add(opp.OwnerId);
                }
            }
        }

        if (requesting.isEmpty() && deciding.isEmpty()) {
            return;
        }

        // ONE batchified SOQL for the mapping records of the whole batch.
        Map<Id, Id> repToManager = loadMappings(ownerIds);

        for (Opportunity opp : deciding) {
            if (opp.Discount_Approval__c == 'Approved') {
                opp.Approved_Discount_Value__c = opp.Discount_in_Pct__c;
            }
            opp.Approval_Decided_On__c = DateTime.now();
            Id managerId = repToManager.get(opp.OwnerId);
            if (managerId != null) {
                opp.Approval_Decided_By__c = managerId;
            }
        }

        if (requesting.isEmpty()) {
            return;
        }
        Map<Id, Id> oppToManager = new Map<Id, Id>();
        for (Id oppId : requesting.keySet()) {
            Id mgr = repToManager.get(requesting.get(oppId).OwnerId);
            if (mgr != null) {
                oppToManager.put(oppId, mgr);
            }
        }
        if (!oppToManager.isEmpty()) {
            System.enqueueJob(new DiscountApprovalNotification(oppToManager));
            enqueueCount++;
        }
    }

    /** before-insert: a new Opportunity already carrying a discount above the threshold
     * gets its approval request at once, so the waiting list and the manager notice cover
     * it from the first save (the ValRule blocks a direct Closed Won either way). */
    public static void handleBeforeInsert(List<Opportunity> newRecords) {
        Set<Id> ownerIds = new Set<Id>();
        Map<Id, Opportunity> requesting = new Map<Id, Opportunity>();
        for (Opportunity opp : newRecords) {
            if (opp.Discount_Approval__c == 'Pending') {
                // request already on the record -> duration keeps measuring from it
                continue;
            }
            if (needsApproval(opp)) {
                opp.Discount_Approval__c = 'Pending';
                opp.Approval_Requested_On__c = DateTime.now();
                requesting.put(opp.Id, opp);
                if (opp.OwnerId != null) {
                    ownerIds.add(opp.OwnerId);
                }
            }
        }
        if (requesting.isEmpty()) {
            return;
        }
        Map<Id, Id> repToManager = loadMappings(ownerIds);
        Map<Id, Id> oppToManager = new Map<Id, Id>();
        for (Id oppId : requesting.keySet()) {
            Id mgr = repToManager.get(requesting.get(oppId).OwnerId);
            if (mgr != null) {
                oppToManager.put(oppId, mgr);
            }
        }
        if (!oppToManager.isEmpty()) {
            System.enqueueJob(new DiscountApprovalNotification(oppToManager));
            enqueueCount++;
        }
    }

    /** AC13 (no retroactive change): an Opportunity already in a closed stage needs no
     * approval request — approval only gates CLOSING as Won. Without this guard a Closed
     * Lost record with a 20 % discount would land on the waiting list forever (measured
     * by the AC13 test on 2026-10-13). The decision path is NOT guarded: only a holder of
     * SCRUM445_Discount_Manager can change the picklist at all. */
    private static Boolean alreadyClosed(Opportunity opp) {
        String s = opp.StageName;
        return s == 'Closed Won' || s == 'Closed Lost';
    }

    private static Boolean needsApproval(Opportunity opp) {
        if (alreadyClosed(opp)) {
            return false;
        }
        if (opp.Discount_Approval__c == 'Rejected') {
            // the manager already decided — the rejection and its reason stay visible;
            // a new request only comes from raising the discount or a fresh save
            return false;
        }
        Decimal d = opp.Discount_in_Pct__c;
        if (d == null || d <= APPROVAL_THRESHOLD) {
            return false;
        }
        Decimal approved = opp.Approved_Discount_Value__c;
        return approved == null || d > approved;
    }

    private static Map<Id, Id> loadMappings(Set<Id> ownerIds) {
        Map<Id, Id> repToManager = new Map<Id, Id>();
        if (ownerIds.isEmpty()) {
            return repToManager;
        }
        List<DiscountApprovalManager__c> mappings = [
            SELECT Id, Rep__c, Manager__c FROM DiscountApprovalManager__c
            WHERE Rep__c IN :ownerIds
        ];
        mappingSoqlCount++;
        for (DiscountApprovalManager__c m : mappings) {
            if (m.Rep__c != null && m.Manager__c != null) {
                repToManager.put(m.Rep__c, m.Manager__c);
            }
        }
        return repToManager;
    }
}
