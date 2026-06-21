/**
 * Trigger for Laptop object - replaces Flow-based logic
 */
trigger LaptopTrigger on Laptop__c (before insert, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        LaptopTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isInsert) {
        LaptopTriggerHandler.handleAfterInsert(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        LaptopTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
