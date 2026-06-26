/**
 * Service class for Top Accounts Dashboard
 * Queries the top 3 Accounts by AnnualRevenue (descending).
 * Ties are broken alphabetically by Name (ascending).
 */
public with sharing class TopAccountsService {
    /**
     * Represents a single account entry for the dashboard
     */
    public class AccountEntry {
        @AuraEnabled public Integer rank { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Decimal annualRevenue { get; set; }
    }

    /**
     * Returns the top 3 accounts with AnnualRevenue > 0,
     * sorted by AnnualRevenue DESC, then Name ASC on tie.
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountEntry> getTopAccounts() {
        List<AccountEntry> result = new List<AccountEntry>();

        List<Account> accounts = [
            SELECT Name, AnnualRevenue
            FROM Account
            WHERE AnnualRevenue > 0
            ORDER BY AnnualRevenue DESC, Name ASC
            LIMIT 3
        ];

        Integer rank = 1;
        for (Account acc : accounts) {
            AccountEntry entry = new AccountEntry();
            entry.rank = rank++;
            entry.accountName = acc.Name;
            entry.annualRevenue = acc.AnnualRevenue;
            result.add(entry);
        }

        return result;
    }
}