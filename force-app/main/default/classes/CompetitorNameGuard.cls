/**
 * SCRUM-461: duplicate guard for the controlled competitor list (AC3, TAC10).
 *
 * Company_Name__c is declared unique/case-sensitive, but its runtime enforcement
 * is unverified — this guard makes "one record per company" hold regardless.
 * One SOQL per batch, never per record. A refused save carries the name.
 *
 * @author developer-agent
 * @date 2026-11-17
 */
public class CompetitorNameGuard {

    public static void handleBeforeInsert(List<Competitor__c> newRecords) {
        Set<String> names = namesOf(newRecords, null);
        if (names.isEmpty()) {
            return;
        }
        Set<String> taken = new Set<String>();
        for (Competitor__c existing : [
            SELECT Company_Name__c FROM Competitor__c WHERE Company_Name__c IN :names
        ]) {
            taken.add(existing.Company_Name__c);
        }
        refuseDuplicates(newRecords, taken, null);
    }

    public static void handleBeforeUpdate(List<Competitor__c> newRecords, Map<Id, Competitor__c> oldMap) {
        // Only a changed company name can create a duplicate; untouched records stay out.
        List<Competitor__c> renamed = new List<Competitor__c>();
        Set<Id> ownIds = new Set<Id>();
        for (Competitor__c record : newRecords) {
            Competitor__c before = oldMap.get(record.Id);
            String oldName = before == null ? null : before.Company_Name__c;
            if (record.Company_Name__c != oldName) {
                renamed.add(record);
                ownIds.add(record.Id);
            }
        }
        Set<String> names = namesOf(renamed, null);
        if (names.isEmpty()) {
            return;
        }
        Set<String> taken = new Set<String>();
        for (Competitor__c existing : [
            SELECT Company_Name__c FROM Competitor__c WHERE Company_Name__c IN :names
        ]) {
            // Own records of this run must not serve as a DB reference (no self-match).
            if (!ownIds.contains(existing.Id)) {
                taken.add(existing.Company_Name__c);
            }
        }
        refuseDuplicates(renamed, taken, ownIds);
    }

    private static Set<String> namesOf(List<Competitor__c> records, Set<Id> ignored) {
        Set<String> names = new Set<String>();
        for (Competitor__c record : records) {
            if (record.Company_Name__c != null && record.Company_Name__c != '') {
                names.add(record.Company_Name__c);
            }
        }
        return names;
    }

    private static void refuseDuplicates(
        List<Competitor__c> records,
        Set<String> taken,
        Set<Id> ownIds
    ) {
        Set<String> seenInBatch = new Set<String>();
        for (Competitor__c record : records) {
            String name = record.Company_Name__c;
            if (name == null || name == '') {
                continue;
            }
            if (taken.contains(name) || seenInBatch.contains(name)) {
                // Measured: only AuraHandledException compiles, and it is runtime-restricted
                // to Aura/Visualforce context — unusable in a trigger. An assertion refuses
                // the save and carries the message (house FollowupMonitoringHandler).
                System.AssertEquals(false, true,
                    'Competitor-List: "' + name + '" is already on the list - a company may appear exactly once.'
                );
            }
            seenInBatch.add(name);
        }
    }
}
