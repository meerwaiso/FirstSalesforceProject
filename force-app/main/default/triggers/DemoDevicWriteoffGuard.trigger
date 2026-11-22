/**
 * SCRUM-468 Lend Devices: only sales team leads may write a device off (AC9, AC9n).
 * The handler queries PermissionSetAssignment for membership in the marker set
 * SCRUM468_Writeoff; nothing is granted by that set itself.
 * Handler: DemoDevicWriteoffGuard.
 */
trigger DemoDevicWriteoffGuard on Demo_Devic__c (before update) {
    if (Trigger.isUpdate) {
        DemoDevicWriteoffGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
