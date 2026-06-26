/**
 * Handler for OpportunityClosedLostNotification trigger.
 * Identifies opportunities that just became "Closed Lost" with Amount > 50,000
 * and enqueues a single Queueable to notify the managers.
 */
public with sharing class OpportunityClosedLostHandler {
    // Static flag to prevent trigger recursion
    private static Boolean _hasFired = false;

    /**
     * After-update handler: collects qualifying opportunities and enqueues notification.
     *
     * @param newRecords List of updated Opportunity records (new version)
     * @param oldMap     Map of Id to Opportunity records (old version)
     */
    public static void handleAfterUpdate(List<Opportunity> newRecords, Map<Id, Opportunity> oldMap) {
        if (_hasFired) {
            return;
        }
        _hasFired = true;

        List<Id> qualifyingOpportunityIds = new List<Id>();

        for (Opportunity opp : newRecords) {
            Opportunity oldOpp = oldMap.get(opp.Id);

            // Status must have changed to "Closed Lost"
            if (oldOpp != null
                    && String.valueOf(oldOpp.Status) != 'Closed Lost'
                    && String.valueOf(opp.Status) == 'Closed Lost') {
                // Amount must be greater than 50,000
                if (opp.Amount != null && opp.Amount > 50000) {
                    qualifyingOpportunityIds.add(opp.Id);
                }
            }
        }

        if (!qualifyingOpportunityIds.isEmpty()) {
            System.enqueueJob(new SendLostOpportunityNotification(qualifyingOpportunityIds));
        }
    }
}