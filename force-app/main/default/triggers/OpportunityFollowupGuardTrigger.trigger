/**
 * [SCRUM-459] AC-6 guard (Apex contract, not FLS).
 *
 * SCRUM459_FollowupMonitoring_Write grants FLS edit on the six monitoring fields
 * - without it the trigger path could not write them at all. So "a sales rep
 * never types a monitoring value" is enforced here instead: a before-update save
 * that PROPOSES a value other than the stored (computed) one is refused with a
 * German message naming the field, and the stored value stays the computed one.
 *
 * The handler's own write is skipped by id: the handler records the ids it wrote and
 * clears them after that statement, so every other save in the same transaction is
 * still checked (house shape: static hasFired in OpportunityOverdueResetHandler,
 * narrowed per the round-2 review).
 */
trigger OpportunityFollowupGuardTrigger on Opportunity (before update) {
    FollowupMonitoringHandler.assertNoUserTypedValues(Trigger.new, Trigger.oldMap);
}
