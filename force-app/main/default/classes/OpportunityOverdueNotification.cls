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

            String body = 'Die folgenden Opportunity/Opportunities wurden als überfällig markiert — keine Aktivität seit >14 Tagen:';
            for (Opportunity opp : opps) {
                body += '\n\n• ' + opp.Name + ' (' + opp.Id + ')';
            }

            // Use ConnectApi to create a Chatter post on the owner's feed as in-app notification
            if (!Test.isRunningTest()) {
                try {
                    ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
                    feedItemInput.body = new ConnectApi.MessageBodyInput();
                    feedItemInput.body.messageSegments = new List<ConnectApi.MessageSegmentInput>();

                    // Text segment
                    ConnectApi.TextOnlyInput textInput = new ConnectApi.TextOnlyInput();
                    textInput.text = body;
                    feedItemInput.body.messageSegments.add(textInput);

                    // Link segment to the first opportunity
                    ConnectApi.MentionSegmentInput mentionInput = new ConnectApi.LinkSegmentInput();
                    mentionInput.label = opps[0].Name + ' - Details ansehen';
                    mentionInput.url = '/' + opps[0].Id;

                    feedItemInput.body.messageSegments.add(mentionInput);
                    feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;

                    ConnectApi.FeedElement result = ConnectApi.ChatterUsers.postToFeed(
                        null,
                        ConnectApi.FeedType.UserProfile,
                        ownerId,
                        feedItemInput
                    );
                } catch (Exception e) {
                    System.debug('OpportunityOverdueNotification: Failed to send notification to owner ' + ownerId + ': ' + e.getMessage());
                }
            }
        }
    }
}