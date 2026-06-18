public with sharing class NotifyAccountCreated {

    @InvocableMethod(Label='Send Email for New Account')
    public static void sendEmail(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return;
        System.enqueueJob(new SendEmailQueueable(accountIds));
    }
}
