/**
 * Opportunity-Trigger:
 *   1. Auto-Reset von Is_Overdue__c bei jeglicher Aenderung (SCRUM-319).
 *   2. Auto-Clear von Loss_Reason__c bei Stage weg von 'Closed Lost' (SCRUM-381).
 *   3. Blockade neuer Opportunities am gesperrten Account (SCRUM-384, before insert).
 */
trigger OpportunityOverdueReset on Opportunity (before insert, before update) {
    if (Trigger.isUpdate) {
        OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        OpportunityLossReasonClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isInsert) {
        OpportunityLockedAccountGuard.handleBeforeInsert(Trigger.new);
    }
}
