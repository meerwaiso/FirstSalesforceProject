/**
 * OpportunityOverdueResetHandler — Trigger handler for resetting Is_Overdue__c flag
 * 
 * Automatically resets Is_Overdue__c to false when an overdue opportunity is updated
 * (any field change on the opportunity indicates renewed activity).
 */
public with sharing class OpportunityOverdueResetHandler {
    // Static flag to prevent trigger recursion
    @testVisible private static Boolean hasFired = false;

    /**
     * Before-update handler: resets Is_Overdue__c to false for opportunities
     * that were previously marked overdue and are now being updated.
     *
     * @param newRecords List of updated Opportunity records (new version)
     * @param oldMap     Map of Id to Opportunity records (old version)
     */
    public static void handleBeforeUpdate(List<Opportunity> newRecords, Map<Id, Opportunity> oldMap) {
        if (hasFired) {
            return;
        }
        hasFired = true;

        for (Opportunity opp : newRecords) {
            Opportunity oldOpp = oldMap.get(opp.Id);

            // If the opportunity was overdue and is now being updated, reset the flag
            if (oldOpp != null && oldOpp.Is_Overdue__c == true && opp.Is_Overdue__c == true) {
                opp.Is_Overdue__c = false;
            }
        }
    }
}