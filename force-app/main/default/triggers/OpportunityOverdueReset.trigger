/**
 * Trigger for automatically resetting Is_Overdue__c flag.
 * Fires before update when an overdue opportunity is modified.
 */
trigger OpportunityOverdueReset on Opportunity (before update) {
    OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
}