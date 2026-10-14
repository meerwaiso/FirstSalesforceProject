/**
 * SCRUM-449: Automatic risk assessment on Opportunity.
 * Runs BEFORE insert/update so the computed values are saved with the record
 * (no extra DML, no recursion). Handler: OpportunityRiskHandler.
 * Service (the rule contract): OpportunityRiskService.
 * Nightly recompute: OpportunityRiskScheduler.
 */
trigger OpportunityRiskTrigger on Opportunity (
    before insert, before update) {
    if (Trigger.isInsert) {
        OpportunityRiskHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        OpportunityRiskHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
