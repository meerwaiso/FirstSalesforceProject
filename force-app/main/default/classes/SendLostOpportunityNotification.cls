/**
 * Queueable that sends email notifications to the manager of the Opportunity Owner
 * when a high-value opportunity (> 50,000) is closed as "Closed Lost".
 *
 * Follows the same pattern as SendEmailQueueable.
 */
public with sharing class SendLostOpportunityNotification implements Queueable {
    private final List<Id> opportunityIds;

    /**
     * Constructor.
     *
     * @param opportunityIds List of Opportunity Ids that qualified for notification
     */
    public SendLostOpportunityNotification(List<Id> opportunityIds) {
        this.opportunityIds = opportunityIds;
    }

    /**
     * Queueable execute: looks up opportunities and their owner's managers,
     * then sends an email to each manager.
     */
    public void execute(QueueableContext ctx) {
        // Retrieve opportunities with owner and owner's manager
        List<Opportunity> opportunities = [
            SELECT Id, Name, Amount, Status, Verlustgrund__c, Verlustgrund_Detail__c,
                   OwnerId, Owner.ManagerId, Owner.Manager.Email, Owner.Manager.Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        // Collect manager emails to avoid duplicate emails per manager
        Map<String, List<Opportunity>> managerEmailToOpps = new Map<String, List<Opportunity>>();

        for (Opportunity opp : opportunities) {
            // Skip if no manager or no manager email
            if (opp.Owner.ManagerId == null || opp.Owner.Manager.Email == null) {
                continue;
            }

            String managerEmail = opp.Owner.Manager.Email;
            if (!managerEmailToOpps.containsKey(managerEmail)) {
                managerEmailToOpps.put(managerEmail, new List<Opportunity>());
            }
            managerEmailToOpps.get(managerEmail).add(opp);
        }

        // Send one email per manager, listing all lost opportunities in that email
        for (String managerEmail : managerEmailToOpps.keySet()) {
            List<Opportunity> opps = managerEmailToOpps.get(managerEmail);

            String subject = 'Verlorenes Opportunity-Deal(s) - Manager-Benachrichtigung';

            // Build HTML body with a table of lost opportunities
            String body = '<h2>Verlorenes Opportunity-Deal(s)</h2>'
                + '<p>Der folgende Deal wurde als "Closed Lost" markiert:</p>';

            body += '<table border="1" cellpadding="4" style="border-collapse: collapse;">'
                + '<tr>'
                + '<th style="background-color: #f0f0f0;">Opportunity</th>'
                + '<th style="background-color: #f0f0f0;">Betrag</th>'
                + '<th style="background-color: #f0f0f0;">Verlustgrund</th>'
                + '<th style="background-color: #f0f0f0;">Detail</th>'
                + '</tr>';

            for (Opportunity opp : opps) {
                String amountFormatted = opp.Amount != null
                    ? String.valueOf(opp.Amount).format()
                    : 'N/A';
                String lossReason = opp.Verlustgrund__c != null
                    ? String.valueOf(opp.Verlustgrund__c)
                    : 'N/A';
                String lossDetail = (opp.Verlustgrund__c == 'Sonstiges' && opp.Verlustgrund_Detail__c != null)
                    ? opp.Verlustgrund_Detail__c
                    : '-';

                body += '<tr>'
                    + '<td>' + String.escapeHtml4(opp.Name) + '</td>'
                    + '<td>' + amountFormatted + '</td>'
                    + '<td>' + String.escapeHtml4(lossReason) + '</td>'
                    + '<td>' + String.escapeHtml4(lossDetail) + '</td>'
                    + '</tr>';
            }

            body += '</table>';
            body += '<p>Bitte prüfen Sie den Verlustgrund und ziehen Sie gegebenenfalls Lehren für künftige Deals.</p>';

            // Send email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String> { managerEmail });
            email.setSubject(subject);
            email.setHtmlBody(body);
            // Associate with the first opportunity for activity tracking
            if (!opps.isEmpty()) {
                email.setWhatId(opps[0].Id);
            }

            // Only send in non-test context
            if (!Test.isRunningTest()) {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage> { email });
            }
        }
    }
}