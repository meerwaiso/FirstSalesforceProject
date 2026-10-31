/**
 * SCRUM-457: Trigger on Absence__c — one Trigger per object (house rule), one
 * block for all three after-events ("after save" is not an Apex event token,
 * measured: "Unexpected token 'save'").
 * after insert / after update: absence recorded or changed -> the mirror on the
 *   customer follows immediately (AC2, AC6).
 * after delete: absence cancelled -> mirror cleared unless the user holds
 *   another, still-open absence (AC3, AC6).
 * All logic lives in AbsenceSyncHandler; OwnerId is never touched (AC7).
 */
trigger AbsenceSyncTrigger on Absence__c (after insert, after update, after delete) {
    AbsenceSyncHandler.handleAfter();
}
