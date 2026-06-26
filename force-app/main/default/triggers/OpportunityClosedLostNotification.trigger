/**
 * Trigger for Opportunity Closed Lost notification.
 * Fires after update when status changes to "Closed Lost" and Amount > 50,000.
 * Enqueues a Queueable to notify the Opportunity Owner's manager.
 */
trigger OpportunityClosedLostNotification on Opportunity (after update) {
    OpportunityClosedLostHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}