/**
 * OpportunityOverdueNotification — Queueable for sending in-app notifications to opportunity owners
 * 
 * Sends a Salesforce in-app notification (Chatter post to feed) to each opportunity owner
 * when their opportunity is marked as overdue. The notification links directly to the
 * opportunity detail page.
 */
public with sharing class OpportunityOverdueNotification implements Queueable {
    private final List<Id> opportunityIds;

    /**
     * Constructor.
     *
     * @param opportunityIds List of Opportunity Ids that were marked overdue
     */
    public OpportunityOverdueNotification(List<Id> opportunityIds) {
        this.opportunityIds = opportunityIds;
    }

    /**
     * Queueable execute: looks up opportunities and sends in-app notifications to owners
     */
    public void execute(QueueableContext ctx) {
        List<Opportunity> opportunities = [
            SELECT Id, Name, OwnerId
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        // Collect unique owner IDs
        Set<Id> ownerIds = new Set<Id>();
        Map<Id, List<Opportunity>> ownerToOpportunities = new Map<Id, List<Opportunity>>();

        for (Opportunity opp : opportunities) {
            if (!ownerIds.contains(opp.OwnerId)) {
                ownerIds.add(opp.OwnerId);
                ownerToOpportunities.put(opp.OwnerId, new List<Opportunity>());
            }
            ownerToOpportunities.get(opp.OwnerId).add(opp);
        }

        // Send one notification per owner, listing all overdue opportunities
        for (Id ownerId : ownerIds) {
            List<Opportunity> opps = ownerToOpportunities.get(ownerId);

            // Build notification body with plain-text URLs (Chatter does not support HTML)
            String orgUrl = URL.getOrgDomainUrl().toExternalForm();
            if (orgUrl.endsWith('/')) orgUrl = orgUrl.substring(0, orgUrl.length() - 1);

            String body = 'Die folgenden Opportunity/Opportunities wurden als überfällig markiert — keine Aktivität seit >14 Tagen:';
            for (Opportunity opp : opps) {
                body += '\n\n• ' + opp.Name + ' — ' + orgUrl + '/' + opp.Id;
            }

            // Post a Chatter FeedItem on the owner's record feed as in-app notification
            if (!Test.isRunningTest()) {
                try {
                    FeedItem feedItem = new FeedItem();
                    feedItem.ParentId = ownerId;
                    feedItem.Body = body;
                    insert feedItem;
                } catch (Exception e) {
                    System.debug('OpportunityOverdueNotification: Failed to send notification to owner ' + ownerId + ': ' + e.getMessage());
                }
            }
        }
    }
}