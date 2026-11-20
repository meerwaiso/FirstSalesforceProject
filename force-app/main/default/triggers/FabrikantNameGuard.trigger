/**
 * SCRUM-464: duplicate guard on the controlled manufacturer list (AC5, TAC10).
 * before insert : batch + org against each other, one SOQL per batch.
 * before update : only when the company Name changed.
 * Nothing else fires here — no email, no task, no feed post, no alert (AC11).
 * Handler: FabrikantNameGuard.
 */
trigger FabrikantNameGuard on Fabrikant__c (before insert, before update) {
    if (Trigger.isInsert) {
        FabrikantNameGuard.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        FabrikantNameGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
