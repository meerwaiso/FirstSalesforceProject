trigger AccountCreatedHighRevenue on Account (after insert) {
    List<Id> highRevenueIds = new List<Id>();

    for (Account acc : Trigger.new) {
        if (acc.AnnualRevenue != null && acc.AnnualRevenue > 1000000) {
            highRevenueIds.add(acc.Id);
        }
    }

    if (!highRevenueIds.isEmpty()) {
        NotifyAccountCreated.sendEmail(highRevenueIds);
    }
}
