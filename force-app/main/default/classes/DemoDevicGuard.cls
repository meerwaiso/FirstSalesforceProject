/**
 * SCRUM-468 Lend Devices: serial uniqueness on the device record (AC2, TAC2n).
 *
 * Serial_Number__c is also marked unique in the metadata, but that platform gate
 * says nothing about WHICH device owns the serial. This guard refuses the save
 * and names the owning device, so the sales colleague can see which record already
 * has it. One SOQL per batch, never per record (governor limits).
 *
 * House shape: CompetitorNameGuard / FabrikantNameGuard (origin/master). A refused
 * save carries the message via System.AssertEquals - a plain Exception constructor
 * is not valid Apex, and AssertionFailed is runtime-restricted.
 *
 * @author developer-agent
 * @date 2026-11-21
 */
public class DemoDevicGuard {

    public static void handleBeforeInsert(List<Demo_Devic__c> newRecords) {
        refuseDuplicates(newRecords, null);
    }

    public static void handleBeforeUpdate(List<Demo_Devic__c> newRecords, Map<Id, Demo_Devic__c> oldMap) {
        // Only a changed serial can create a duplicate; untouched records stay out of the query.
        List<Demo_Devic__c> changed = new List<Demo_Devic__c>();
        Set<Id> ownIds = new Set<Id>();
        for (Demo_Devic__c record : newRecords) {
            Demo_Devic__c before = oldMap.get(record.Id);
            String oldSerial = (before == null) ? null : before.Serial_Number__c;
            if (record.Serial_Number__c != oldSerial) {
                changed.add(record);
                ownIds.add(record.Id);
            }
        }
        refuseDuplicates(changed, ownIds);
    }

    private static void refuseDuplicates(List<Demo_Devic__c> records, Set<Id> ownIds) {
        Set<String> serials = new Set<String>();
        for (Demo_Devic__c record : records) {
            String serial = record.Serial_Number__c;
            if (serial != null && serial != '') {
                serials.add(serial);
            }
        }
        if (serials.isEmpty()) {
            return;
        }
        Set<String> taken = new Set<String>();
        Map<String, String> owner = new Map<String, String>();
        for (Demo_Devic__c existing : [SELECT Id, Name, Serial_Number__c FROM Demo_Devic__c WHERE Serial_Number__c IN :serials]) {
            // Own records of this run must not serve as a DB reference (no self-match on Update).
            if (ownIds != null && ownIds.contains(existing.Id)) {
                continue;
            }
            taken.add(existing.Serial_Number__c);
            owner.put(existing.Serial_Number__c, existing.Name);
        }
        Set<String> seenInBatch = new Set<String>();
        for (Demo_Devic__c record : records) {
            String serial = record.Serial_Number__c;
            if (serial == null || serial == '') {
                continue;
            }
            if (taken.contains(serial) || seenInBatch.contains(serial)) {
                String ownerName = owner.containsKey(serial) ? owner.get(serial) : 'another device in this save';
                record.addError('Lend Devices: serial "' + serial + '" is already on device ' + ownerName
                    + ' - one serial number may belong to exactly one device.');
            }
            seenInBatch.add(serial);
        }
    }
}
