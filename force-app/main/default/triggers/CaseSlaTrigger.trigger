/**
 * SCRUM-404: CaseSlaTrigger — before-insert + before-update.
 * before-insert: CaseSlaService.setDeadlinesForNewCases (Deadline setzen + Pre-Fills entfernen, ADR-2/5).
 * before-update : CaseSlaGuard.guardOnUpdate (stummer Revert, ADR-5).
 */
trigger CaseSlaTrigger on Case (before insert, before update) {
    if (Trigger.isInsert) {
        CaseSlaService.setDeadlinesForNewCases(Trigger.new);
    }
    if (Trigger.isUpdate) {
        CaseSlaGuard.guardOnUpdate(Trigger.old, Trigger.new);
    }
}
