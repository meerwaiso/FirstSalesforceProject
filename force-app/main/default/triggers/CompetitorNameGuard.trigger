/**
 * SCRUM-461: duplicate guard on the controlled competitor list (AC3, TAC10).
 * before insert : batch + org against each other, one SOQL per batch.
 * before update : only when Company_Name__c changed.
 * Nothing else fires here — no email, no task, no feed post, no alert (AC9).
 * Handler: CompetitorNameGuard.
 */
trigger CompetitorNameGuard on Competitor__c (before insert, before update) {
    if (Trigger.isInsert) {
        CompetitorNameGuard.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        CompetitorNameGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
