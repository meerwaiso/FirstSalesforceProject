/**
 * [SCRUM-453] Contact-Trigger for the Austritt mark (AC-2, AC-6, AC-8).
 *
 * before update : undo gate (a non-team-lead may NOT clear the mark), then the
 *                 date default — the default runs after the gate so a refused
 *                 clearing never half-applies.
 * before insert : date default only (nothing to undo on a fresh record).
 * after *       : full recompute of the Account aggregates for the touched
 *                 Accounts (SCRUM-416 handler pattern).
 *
 * One Trigger per object (house rule, SCRUM-384). Handler: SCRUM453ContactLeftHandler.
 * Nothing automatic beyond this: no email, no task, no reminder, no FeedItem (AC-9).
 */
trigger ContactLeftGuardTrigger on Contact (
    before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            SCRUM453ContactLeftHandler.guardUndo(Trigger.new, Trigger.oldMap);
            SCRUM453ContactLeftHandler.defaultLeftDate(Trigger.new);
        } else if (Trigger.isInsert) {
            SCRUM453ContactLeftHandler.defaultLeftDate(Trigger.new);
        }
    } else {
        Set<Id> accIds = new Set<Id>();
        if (Trigger.isInsert) {
            accIds = SCRUM453ContactLeftHandler.accountIds(Trigger.new);
        } else if (Trigger.isUpdate) {
            accIds = SCRUM453ContactLeftHandler.accountIdsChanged(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            accIds = SCRUM453ContactLeftHandler.accountIds(Trigger.old);
        }
        SCRUM453ContactLeftHandler.recompute(accIds);
    }
}
