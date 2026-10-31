/**
 * SCRUM-459: Second trigger beside OpportunityOverdueReset (house pattern of
 * SCRUM-449, which added OpportunityRiskTrigger beside it).
 * after update only; the relevance filter (IsClosed or Amount changed) lives
 * in FollowupMonitoringHandler.onOpportunityUpdate and is the TERMINATION
 * GUARD: our own write of the six monitoring fields re-fires this trigger,
 * sees neither change and returns.
 */
trigger OpportunityFollowupMonitorTrigger on Opportunity (after update) {
    FollowupMonitoringHandler.onOpportunityUpdate(Trigger.new, Trigger.oldMap);
}
