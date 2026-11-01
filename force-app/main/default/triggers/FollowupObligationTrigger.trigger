/**
 * SCRUM-459: Follow-up obligation trigger on Followup_Obligation__c.
 * after insert / update / delete -> recompute the monitoring values of every
 * affected parent Opportunity (Handler: FollowupMonitoringHandler).
 * Delete is System Administrator only: neither Permission Set grants it.
 */
trigger FollowupObligationTrigger on Followup_Obligation__c (
    after insert, after update, after delete) {
    if (Trigger.isInsert) {
        FollowupMonitoringHandler.onObligationInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        FollowupMonitoringHandler.onObligationUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isDelete) {
        FollowupMonitoringHandler.onObligationDelete(Trigger.old);
    }
}
