/**
 * Opportunity-Trigger:
 *   1. Auto-Reset von Is_Overdue__c bei jeglicher Aenderung (SCRUM-319).
 *   2. Auto-Clear von Loss_Reason__c bei Stage weg von 'Closed Lost' (SCRUM-381).
 *   3. Blockade neuer Opportunities am gesperrten Account (SCRUM-384, before insert).
 *   4. Rollup offener Chancen auf den Account (SCRUM-416, after insert/update/delete,
 *      Handler: OpenOpportunityRollupHandler — bulkified Vollrecompute per GROUP BY).
 */
trigger OpportunityOverdueReset on Opportunity (
    before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
            OpportunityLossReasonClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isInsert) {
            OpportunityLockedAccountGuard.handleBeforeInsert(Trigger.new);
        }
    } else {
        // SCRUM-416: Rollup der offenen Chancen auf den Account
        if (Trigger.isInsert) {
            OpenOpportunityRollupHandler.onOpportunityInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            OpenOpportunityRollupHandler.onOpportunityUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            OpenOpportunityRollupHandler.onOpportunityDelete(Trigger.old);
        }
    }
}
