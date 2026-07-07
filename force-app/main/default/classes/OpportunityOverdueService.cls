/**
 * OpportunityOverdueService — Core logic for detecting and marking inactive opportunities
 * 
 * - Finds opportunities that are overdue (open stage + no update for >14 days)
 * - Sets Is_Overdue__c = true on overdue opportunities
 * - Returns list of newly marked opportunity IDs for notification
 */
public with sharing class OpportunityOverdueService {

    private static final Integer OVERDUE_DAYS_THRESHOLD = 14;

    /**
     * Finds all overdue opportunities and marks them with Is_Overdue__c = true.
     * Returns the list of opportunity IDs that were newly marked (were false, now true).
     *
     * @return List of Ids of newly marked overdue opportunities
     */
    public static List<Id> findAndMarkOverdueOpportunities() {
        Date thresholdDate = Date.today().addDays(-OVERDUE_DAYS_THRESHOLD);

        // Find open opportunities that are older than the threshold and not already marked
        List<Opportunity> overdueOpportunities = [
            SELECT Id, OwnerId, Name, StageName, LastModifiedDate, Is_Overdue__c
            FROM Opportunity
            WHERE StageName != 'Closed Won'
              AND StageName != 'Closed Lost'
              AND LastModifiedDate < :thresholdDate
              AND Is_Overdue__c = false
        ];

        if (overdueOpportunities.isEmpty()) {
            return new List<Id>();
        }

        // Mark all overdue opportunities in a single bulk DML
        List<Id> newlyMarkedIds = new List<Id>();
        for (Opportunity opp : overdueOpportunities) {
            opp.Is_Overdue__c = true;
            newlyMarkedIds.add(opp.Id);
        }
        update overdueOpportunities;

        System.debug('OpportunityOverdueService: ' + newlyMarkedIds.size() + ' overdue opportunities marked.');
        return newlyMarkedIds;
    }
}