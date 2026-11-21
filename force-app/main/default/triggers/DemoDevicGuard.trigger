/**
 * SCRUM-468 Lend Devices: serial uniqueness on the device (AC2).
 * Fires on insert and on update; the handler only re-checks Serial_Number__c
 * when it actually changed. Nothing else here - no email, no task, no alert (AC12).
 * Handler: DemoDevicGuard.
 */
trigger DemoDevicGuard on Demo_Devic__c (before insert, before update) {
    if (Trigger.isInsert) {
        DemoDevicGuard.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        DemoDevicGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
