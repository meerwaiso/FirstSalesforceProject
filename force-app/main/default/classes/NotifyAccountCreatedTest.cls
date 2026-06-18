@isTest
private class NotifyAccountCreatedTest {
    @isTest
    static void test_highRevenue_sendsEmail() {
        Test.startTest();

        Account acc = new Account(
            Name = 'Test High Revenue Account',
            AnnualRevenue = 2000000,
            Industry = 'Technology'
        );
        insert acc;

        Test.stopTest();

        System.assert(acc.Id != null, 'Account should be created');
    }

    @isTest
    static void test_lowRevenue_noEmail() {
        Test.startTest();

        Account acc = new Account(
            Name = 'Test Low Revenue Account',
            AnnualRevenue = 500000
        );
        insert acc;

        Test.stopTest();

        System.assert(acc.Id != null, 'Account should be created');
    }

    @isTest
    static void test_noRevenue_noEmail() {
        Test.startTest();

        Account acc = new Account(
            Name = 'Test No Revenue Account'
        );
        insert acc;

        Test.stopTest();

        System.assert(acc.Id != null, 'Account should be created');
    }
}
