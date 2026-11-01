/**
 * [SCRUM-459] Follow-up Monitoring rollup on Opportunity (ADR: Apex, not Flow).
 *
 * Six derived values on the monitored Opportunity, computed from the child
 * records of Followup_Obligation__c (Lookup, ADR-2) - never typed by a human:
 *   Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c,
 *   Last_Customer_Interaction__c, Followup_Status__c, Needs_Manager_Attention__c
 *
 * Semantics (PO decisions 31.10.2026, docs/SCRUM-459-design.md):
 *   overdue(o)   := Status__c != Completed AND Due_Date__c <> null AND Due_Date__c < today
 *   nextDate     := min Due_Date__c over outstanding obligations that have one
 *   status       := Overdue  if overdueCount > 0
 *                   Due Soon if overdueCount = 0 AND nextDate <> null AND nextDate <= today + 2
 *                   Up to Date otherwise            (precedence Overdue > Due Soon > Up to Date)
 *   required     := outstandingCount > 0
 *   attention    := Amount > 50000 STRICTLY (exactly 50000 does NOT flag)
 *                   AND overdueCount >= 1 AND IsClosed = false
 *   lastInteraction := max Completed_Date__c over ALL obligations of the Opportunity
 *   IsClosed = true  -> out of monitoring, all six values cleared
 *
 * Governor limits: 2 SOQL + 1 update batch per trigger batch, independent of
 * batch size (no SOQL in a loop). Parent ids go into a Set<Id>, so AC-11
 * (20 obligations in one bulk save) recomputes each parent once and counts
 * each obligation exactly once, order-independent.
 *
 * RECURSION: writing the six fields re-fires OpportunityFollowupMonitorTrigger
 * (unlike the SCRUM-416 Account rollup, where the write hit no Opportunity
 * trigger). onOpportunityUpdate returns unless IsClosed or Amount changed -
 * our own write changes neither -> terminates. Measured: no AssignmentRule
 * exists on Opportunity in Test-Org (only Case and Lead), so no second save
 * cycle can double-count (the SCRUM-418 trap).
 *
 * FLS AND THE WRITE PATH (measured 2026-10-31, PR round 1): trigger code runs in
 * USER mode, so FLS governs the `update toUpdate` batch below. It passes because
 * SCRUM459_FollowupMonitoring_Write grants edit on the six fields to the acting
 * user - a Read PS with editable=false made every trigger write fail. The update
 * also writes ONLY fresh sObjects whose cache holds Id + the six fields: `update`
 * writes every cached field, and the Q1 record carries IsClosed, which is not
 * writeable at all (the compiler says "Field is not writeable: Opportunity.IsClosed").
 * "A sales rep never edits the monitoring values" is therefore NOT an FLS
 * property: it is the Apex contract in assertNoUserTypedValues below (AC-6),
 * enforced by OpportunityFollowupGuardTrigger (before update).
 */
public without sharing class FollowupMonitoringHandler {

    private static final Decimal ATTENTION_THRESHOLD = 50000;

    // The ids the handler wrote in THIS transaction. The before-update guard skips
    // exactly those records, so any other save in the same transaction is still
    // checked (house shape: static hasFired in OpportunityOverdueResetHandler,
    // narrowed to ids per the round-2 review).
    private static Set<Id> systemWrittenIds = new Set<Id>();

    // --- entry points ---------------------------------------------------------

    public static void onObligationInsert(List<SObject> after) {
        Set<Id> ids = parentIds(after);
        if (!ids.isEmpty()) {
            recalculate(ids);
        }
    }

    // update: old AND new parent, so an obligation moved to another Opportunity
    // recomputes both sides.
    public static void onObligationUpdate(List<SObject> after, Map<Id, SObject> before) {
        Set<Id> ids = parentIds(after);
        ids.addAll(parentIds(before.values()));
        if (!ids.isEmpty()) {
            recalculate(ids);
        }
    }

    public static void onObligationDelete(List<SObject> before) {
        Set<Id> ids = parentIds(before);
        if (!ids.isEmpty()) {
            recalculate(ids);
        }
    }

    // Relevance filter (termination guard): only a stage close/open (IsClosed)
    // or an Amount re-evaluation changes the monitoring values here.
    public static void onOpportunityUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity o : newOpps) {
            Opportunity old = oldMap.get(o.Id);
            if (old == null || o.IsClosed != old.IsClosed || o.Amount != old.Amount) {
                ids.add(o.Id);
            }
        }
        if (!ids.isEmpty()) {
            recalculate(ids);
        }
    }

    private static Set<Id> parentIds(List<SObject> recs) {
        Set<Id> ids = new Set<Id>();
        for (SObject s : recs) {
            Followup_Obligation__c ob = (Followup_Obligation__c) s;
            if (ob.Opportunity__c != null) {
                ids.add(ob.Opportunity__c);
            }
        }
        return ids;
    }

    // --- the single recompute -------------------------------------------------

    public static void recalculate(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }
        Date today = Date.today();

        Map<Id, Opportunity> current = new Map<Id, Opportunity>(
            [SELECT Id, IsClosed, Amount,
                    Followup_Required__c, Next_Followup_Date__c, Overdue_Followup_Count__c,
                    Last_Customer_Interaction__c, Followup_Status__c, Needs_Manager_Attention__c
             FROM Opportunity WHERE Id IN :opportunityIds]);

        Set<Id> closed = new Set<Id>();
        for (Opportunity o : current.values()) {
            if (o.IsClosed) {
                closed.add(o.Id);
            }
        }

        Map<Id, Integer> outstanding = new Map<Id, Integer>();
        Map<Id, Integer> overdue = new Map<Id, Integer>();
        Map<Id, Date> minDue = new Map<Id, Date>();
        Map<Id, Date> maxCompleted = new Map<Id, Date>();

        // Q2: one query for all obligations of the affected parents.
        for (Followup_Obligation__c ob : [SELECT Opportunity__c, Status__c, Due_Date__c, Completed_Date__c
                                          FROM Followup_Obligation__c
                                          WHERE Opportunity__c IN :opportunityIds]) {
            Id parentId = ob.Opportunity__c;
            if (parentId == null || closed.contains(parentId)) {
                continue;
            }
            if (ob.Completed_Date__c != null
                && (maxCompleted.get(parentId) == null || ob.Completed_Date__c > maxCompleted.get(parentId))) {
                maxCompleted.put(parentId, ob.Completed_Date__c);
            }
            // Status__c has exactly two values; blank counts as still outstanding.
            if (ob.Status__c == null || ob.Status__c != 'Completed') {
                outstanding.put(parentId, outstanding.get(parentId) == null ? 1 : outstanding.get(parentId) + 1);
                if (ob.Due_Date__c != null) {
                    if (ob.Due_Date__c < today) {
                        overdue.put(parentId, overdue.get(parentId) == null ? 1 : overdue.get(parentId) + 1);
                    }
                    if (minDue.get(parentId) == null || ob.Due_Date__c < minDue.get(parentId)) {
                        minDue.put(parentId, ob.Due_Date__c);
                    }
                }
            }
        }

        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Id oppId : opportunityIds) {
            Opportunity o = current.get(oppId);
            if (o == null) {
                continue;
            }
            boolean isClosed = o.IsClosed;
            boolean required = !isClosed && outstanding.get(oppId) != null;
            Integer overdueCount = isClosed ? 0 : (overdue.get(oppId) == null ? 0 : overdue.get(oppId));
            Date nextDate = isClosed ? null : minDue.get(oppId);
            Date lastInteraction = isClosed ? null : maxCompleted.get(oppId);
            String status;
            if (isClosed) {
                status = null;
            } else if (overdueCount > 0) {
                status = 'Overdue';
            } else if (nextDate != null && nextDate <= today + 2) {
                status = 'Due Soon';
            } else {
                status = 'Up to Date';
            }
            boolean attention = !isClosed
                                && overdueCount >= 1
                                && o.Amount != null
                                && o.Amount > ATTENTION_THRESHOLD;

            if (o.Followup_Required__c != required
                || o.Next_Followup_Date__c != nextDate
                || o.Overdue_Followup_Count__c != overdueCount
                || o.Last_Customer_Interaction__c != lastInteraction
                || o.Followup_Status__c != status
                || o.Needs_Manager_Attention__c != attention) {
                // A FRESH sObject, not the record from Q1: `update` writes every
                // field in the record's cache, and the Q1 record carries
                // IsClosed - which the compiler rejects outright ("Field is not
                // writeable: Opportunity.IsClosed", measured 2026-10-31). With the
                // before-update guard trigger active that write failed as
                // "fields being inaccessible on Sobject Opportunity"; with the
                // cache reduced to Id + the six writable fields it succeeds.
                Opportunity upd = new Opportunity(Id = oppId);
                upd.Followup_Required__c = required;
                upd.Next_Followup_Date__c = nextDate;
                upd.Overdue_Followup_Count__c = overdueCount;
                upd.Last_Customer_Interaction__c = lastInteraction;
                upd.Followup_Status__c = status;
                upd.Needs_Manager_Attention__c = attention;
                toUpdate.add(upd);
            }
        }
        // ONE update batch; write only on actual change (idempotent, drift-free).
        // The ids of THIS write are remembered so the before-update guard skips
        // exactly those records; every other save in this transaction is still
        // checked (house shape: static hasFired in OpportunityOverdueResetHandler).
        if (!toUpdate.isEmpty()) {
            for (Opportunity upd : toUpdate) {
                systemWrittenIds.add(upd.Id);
            }
            try {
                update toUpdate;
            } finally {
                // Cleared even when the update throws: the window in which the
                // guard is skipped is that one statement.
                systemWrittenIds.clear();
            }
        }
    }

    // --- AC-6 guard: a human may not type a monitoring value -------------------
    //
    // The Write PS grants FLS edit so the trigger path can write at all, so the
    // rule cannot be a permission any more. It is checked here instead: a save
    // that PROPOSES a value other than the stored one is refused. The stored
    // value is the computed one - the handler rewrites it on every obligation
    // save and on every IsClosed/Amount change - so "differs from the computed
    // value" and "differs from the stored value" are the same test, and this
    // guard needs no SOQL.
    //
    public static void assertNoUserTypedValues(List<Opportunity> newRecs, Map<Id, Opportunity> oldMap) {
        for (Opportunity o : newRecs) {
            if (systemWrittenIds.contains(o.Id)) {
                // the handler's own write in this transaction, not a user save
                continue;
            }
            Opportunity old = oldMap.get(o.Id);
            if (old == null) {
                continue;
            }
            if (o.Followup_Required__c != old.Followup_Required__c) {
                refuseTypedValue('Followup_Required__c');
            }
            if (o.Next_Followup_Date__c != old.Next_Followup_Date__c) {
                refuseTypedValue('Next_Followup_Date__c');
            }
            if (o.Overdue_Followup_Count__c != old.Overdue_Followup_Count__c) {
                refuseTypedValue('Overdue_Followup_Count__c');
            }
            if (o.Last_Customer_Interaction__c != old.Last_Customer_Interaction__c) {
                refuseTypedValue('Last_Customer_Interaction__c');
            }
            if (o.Followup_Status__c != old.Followup_Status__c) {
                refuseTypedValue('Followup_Status__c');
            }
            if (o.Needs_Manager_Attention__c != old.Needs_Manager_Attention__c) {
                refuseTypedValue('Needs_Manager_Attention__c');
            }
        }
    }

    private static void refuseTypedValue(String field) {
        // Measured: only AuraHandledException compiles, and it is runtime-restricted
        // to Aura/Visualforce context ("Can only throw this exception type from
        // VisualForce or Aura context") - unusable in a trigger. An assertion
        // refuses the save and carries the message.
        System.AssertEquals(false, true,
            'Follow-up Monitoring: "' + field + '" is written by the system - the user must not type a value there.'
        );
    }
}
