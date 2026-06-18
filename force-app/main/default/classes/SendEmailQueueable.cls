public with sharing class SendEmailQueueable implements Queueable {
    private final List<Id> accountIds;

    public SendEmailQueueable(List<Id> accountIds) {
        this.accountIds = accountIds;
    }

    public void execute(QueueableContext ctx) {
        List<Account> accounts = [
            SELECT Id, Name, AnnualRevenue, Industry, Phone
            FROM Account
            WHERE Id IN :accountIds
        ];

        for (Account acc : accounts) {
            String subject = 'Neuer Account erstellt: ' + acc.Name;

            String body = '<h2>Neuer Account mit hohem Annual Revenue</h2>'
                + '<p>Ein neuer Account mit Annual Revenue über 1\'000\'000 wurde erstellt:</p>'
                + '<table border=\"1\" cellpadding=\"4\">'
                + '<tr><td><b>Account</b></td><td>' + acc.Name + '</td></tr>'
                + '<tr><td><b>Annual Revenue</b></td><td>' + acc.AnnualRevenue + '</td></tr>'
                + (acc.Industry != null ? '<tr><td><b>Industry</b></td><td>' + acc.Industry + '</td></tr>' : '')
                + (acc.Phone != null ? '<tr><td><b>Phone</b></td><td>' + acc.Phone + '</td></tr>' : '')
                + '</table>';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String> { 'meerwais.osmani@gmail.com' });
            email.setSubject(subject);
            email.setHtmlBody(body);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage> { email });
        }
    }
}
