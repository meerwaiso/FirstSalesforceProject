/**
 * Test class for TopAccountsService
 * Covers getTopAccounts with various scenarios:
 * - Normal case: multiple accounts with revenue
 * - Empty case: no accounts with revenue
 * - Tie case: accounts with same revenue (alphabetical sorting)
 */
@isTest
private class TopAccountsServiceTest {
    @isTest
    static void testGetTopAccounts_NormalCase() {
        // Arrange: create 5 accounts with different revenues
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Alpha Corp', AnnualRevenue = 500000),
            new Account(Name = 'Beta Corp', AnnualRevenue = 1000000),
            new Account(Name = 'Gamma Corp', AnnualRevenue = 2000000),
            new Account(Name = 'Delta Corp', AnnualRevenue = 800000),
            new Account(Name = 'Epsilon Corp', AnnualRevenue = 1500000)
        };
        insert accounts;

        // Act
        List<TopAccountsService.AccountEntry> result = TopAccountsService.getTopAccounts();

        // Assert: top 3 by revenue DESC
        System.assertEquals(3, result.size(), 'Should return exactly 3 accounts');
        System.assertEquals('Gamma Corp', result[0].accountName, 'Rank 1 should be Gamma Corp (2M)');
        System.assertEquals(2000000, result[0].annualRevenue);
        System.assertEquals(1, result[0].rank);

        System.assertEquals('Epsilon Corp', result[1].accountName, 'Rank 2 should be Epsilon Corp (1.5M)');
        System.assertEquals(1500000, result[1].annualRevenue);
        System.assertEquals(2, result[1].rank);

        System.assertEquals('Beta Corp', result[2].accountName, 'Rank 3 should be Beta Corp (1M)');
        System.assertEquals(1000000, result[2].annualRevenue);
        System.assertEquals(3, result[2].rank);
    }

    @isTest
    static void testGetTopAccounts_EmptyCase() {
        // Arrange: no accounts with revenue
        Account acc = new Account(Name = 'No Revenue Corp');
        insert acc;

        // Act
        List<TopAccountsService.AccountEntry> result = TopAccountsService.getTopAccounts();

        // Assert
        System.assertEquals(0, result.size(), 'Should return empty list when no accounts have revenue');
    }

    @isTest
    static void testGetTopAccounts_TieCase() {
        // Arrange: accounts with same revenue — alphabetical tie-break expected
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Zebra Corp', AnnualRevenue = 1000000),
            new Account(Name = 'Apple Corp', AnnualRevenue = 1000000),
            new Account(Name = 'Mango Corp', AnnualRevenue = 1000000)
        };
        insert accounts;

        // Act
        List<TopAccountsService.AccountEntry> result = TopAccountsService.getTopAccounts();

        // Assert: sorted alphabetically when revenue is equal
        System.assertEquals(3, result.size(), 'Should return 3 accounts');
        System.assertEquals('Apple Corp', result[0].accountName, 'Rank 1 should be Apple Corp (alphabetical first)');
        System.assertEquals(1, result[0].rank);

        System.assertEquals('Mango Corp', result[1].accountName, 'Rank 2 should be Mango Corp');
        System.assertEquals(2, result[1].rank);

        System.assertEquals('Zebra Corp', result[2].accountName, 'Rank 3 should be Zebra Corp');
        System.assertEquals(3, result[2].rank);
    }

    @isTest
    static void testGetTopAccounts_LessThanThree() {
        // Arrange: only 2 accounts with revenue
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Solo Corp', AnnualRevenue = 500000),
            new Account(Name = 'Duo Corp', AnnualRevenue = 750000)
        };
        insert accounts;

        // Act
        List<TopAccountsService.AccountEntry> result = TopAccountsService.getTopAccounts();

        // Assert
        System.assertEquals(2, result.size(), 'Should return only 2 accounts when less than 3 exist');
        System.assertEquals('Duo Corp', result[0].accountName, 'Rank 1 should be Duo Corp (750K)');
        System.assertEquals('Solo Corp', result[1].accountName, 'Rank 2 should be Solo Corp (500K)');
    }

    @isTest
    static void testGetTopAccounts_MixedZeroAndPositive() {
        // Arrange: mix of zero and positive revenue
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Zero Corp', AnnualRevenue = 0),
            new Account(Name = 'Positive Corp', AnnualRevenue = 1000000),
            new Account(Name = 'Null Corp'),  // AnnualRevenue is null
            new Account(Name = 'Negative Corp', AnnualRevenue = -50000)
        };
        insert accounts;

        // Act
        List<TopAccountsService.AccountEntry> result = TopAccountsService.getTopAccounts();

        // Assert: only accounts with revenue > 0
        System.assertEquals(1, result.size(), 'Should return only accounts with revenue > 0');
        System.assertEquals('Positive Corp', result[0].accountName);
    }
}