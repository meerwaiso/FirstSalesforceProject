/**
 * SCRUM-457: Trigger on Absence__c — one Trigger per object (house rule).
 * after save: record created or changed (dates / deputy edited) -> mirror
 * follows immediately (AC2, AC6).
 * after delete: absence cancelled -> mirror cleared unless the user holds
 * another, still-open absence (AC3, AC6).
 * All logic lives in AbsenceSyncHandler; OwnerId is never touched (AC7).
 */
trigger AbsenceSyncTrigger on Absence__c (after save) {
    AbsenceSyncHandler.handleAfterSave(NewRecord);
}

trigger AbsenceSyncTrigger on Absence__c (after delete) {
    AbsenceSyncHandler.handleAfterDelete(OldRecord);
}
