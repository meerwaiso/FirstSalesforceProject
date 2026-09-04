/**
 * Account-Trigger (SCRUM-384): Auto-Clear von Lock_Reason__c, wenn die
 * Sperre (Is_Locked__c) aufgehoben wird (AC4). Ein Trigger pro Objekt.
 * Before update; ValRule wertet danach auf dem Endstand — siehe Handler.
 */
trigger AccountLockGuard on Account (before update) {
    AccountLockClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
}
