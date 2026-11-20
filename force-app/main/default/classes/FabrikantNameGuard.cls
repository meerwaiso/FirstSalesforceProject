/**
 * SCRUM-464: duplicate guard for the controlled manufacturer list (AC5, TAC10).
 *
 * Name is a plain Text field, so nothing in the metadata keeps two records apart —
 * this guard makes "one record per company" hold regardless.
 * One SOQL per batch, never per record. A refused save carries the name.
 * Shape copied from the house CompetitorNameGuard (SCRUM-461).
 *
 * @author developer-agent
 * @date 2026-11-20
 */
public class FabrikantNameGuard {

    public static void handleBeforeInsert(List<Fabrikant__c> newRecords) {
        Set<String> names = namesOf(newRecords, null);
        if (names.isEmpty()) {
            return;
        }
        Set<String> taken = new Set<String>();
        for (Fabrikant__c existing : [
            SELECT Name FROM Fabrikant__c WHERE Name IN :names
        ]) {
            taken.add(existing.Name.toLowerCase());
        }
        refuseDuplicates(newRecords, taken, null);
    }

    public static void handleBeforeUpdate(List<Fabrikant__c> newRecords, Map<Id, Fabrikant__c> oldMap) {
        // Only a changed company name can create a duplicate; untouched records stay out.
        List<Fabrikant__c> renamed = new List<Fabrikant__c>();
        Set<Id> ownIds = new Set<Id>();
        for (Fabrikant__c record : newRecords) {
            Fabrikant__c before = oldMap.get(record.Id);
            String oldName = before == null ? null : before.Name;
            if (record.Name != oldName) {
                renamed.add(record);
                ownIds.add(record.Id);
            }
        }
        Set<String> names = namesOf(renamed, null);
        if (names.isEmpty()) {
            return;
        }
        Set<String> taken = new Set<String>();
        for (Fabrikant__c existing : [
            SELECT Name FROM Fabrikant__c WHERE Name IN :names
        ]) {
            // Own records of this run must not serve as a DB reference (no self-match).
            if (!ownIds.contains(existing.Id)) {
                taken.add(existing.Name.toLowerCase());
            }
        }
        refuseDuplicates(renamed, taken, ownIds);
    }

    private static Set<String> namesOf(List<Fabrikant__c> records, Set<Id> ignored) {
        Set<String> names = new Set<String>();
        for (Fabrikant__c record : records) {
            if (record.Name != null && record.Name != '') {
                names.add(record.Name);
            }
        }
        return names;
    }

    private static void refuseDuplicates(
        List<Fabrikant__c> records,
        Set<String> taken,
        Set<Id> ownIds
    ) {
        Set<String> seenInBatch = new Set<String>();
        for (Fabrikant__c record : records) {
            String name = record.Name;
            if (name == null || name == '') {
                continue;
            }
            if (taken.contains(name.toLowerCase()) || seenInBatch.contains(name.toLowerCase())) {
                // Measured: only AuraHandledException compiles, and it is runtime-restricted
                // to Aura/Visualforce context — unusable in a trigger. An assertion refuses
                // the save and carries the message (house CompetitorNameGuard).
                System.AssertEquals(false, true,
                    'Fabrikant-List: "' + name + '" is already on the list - a company may appear exactly once.'
                );
            }
            seenInBatch.add(name.toLowerCase());
        }
    }
}
