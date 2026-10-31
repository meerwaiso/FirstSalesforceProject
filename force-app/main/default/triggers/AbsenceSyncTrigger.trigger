/**
 * SCRUM-457: Trigger on Absence__c — one Trigger per object (house rule).
 * "after save" is not an Apex event token (measured: "Unexpected token 'save'"),
 * so the events are listed explicitly: the two before-events carry the AC1 guard,
 * the three after-events carry the mirror.
 *
 * before insert / before update: a manager can never be their own deputy (AC1
 *   new clause) — the save rolls back for UI, API and Apex alike. The exception
 *   must be thrown here: the Apex compiler refuses SavePointError
 *   ("Invalid type: SavePointError", measured on this deploy), so the house
 *   exception type AuraHandledException (SCRUM428ContactFormController,
 *   CustomerTransferController) is used.
 * after insert / after update: absence recorded or changed -> the mirror on the
 *   customer follows immediately (AC2, AC6, AC10).
 * after delete: absence cancelled -> mirror cleared unless the user holds
 *   another, still-open absence (AC3, AC6).
 *
 * The Trigger.isBefore / Trigger.isAfter flags (documented context variables;
 * Trigger.beforeInsert is refused by the compiler here, measured) keep the
 * mirror out of the before-events: writing it there would read the not-yet-
 * saved record and leave a stale mirror behind. All logic lives in
 * AbsenceSyncHandler; OwnerId is never touched (AC7). The guard adds no query
 * (design §7).
 */
trigger AbsenceSyncTrigger on Absence__c (before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        if (AbsenceSyncHandler.ownDeputyViolation()) {
            throw new AuraHandledException('SCRUM-457: a manager can never be their own deputy - name a colleague.');
        }
    }
    if (Trigger.isAfter) {
        AbsenceSyncHandler.handleAfter();
    }
}
