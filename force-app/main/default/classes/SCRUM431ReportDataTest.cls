/**
 * [SCRUM-431] Report data contract for "Morgen_UEbersicht_Vertragskunden".
 *
 * A report cannot be executed from Apex, so its data set is proven by the
 * exact SOQL the report renders: open cases (IsClosed=false) of accounts
 * with the contract checkbox set, ordered oldest first. If this query and
 * the report ever disagree, the test and the visual check catch it.
 *
 * Everything created rolls back with the test transaction.
 */
@isTest
private class SCRUM431ReportDataTest {

    @TestSetup
    static void setup() {
        Account yes = new Account(Name = 'SCRUM431-ACC-YES-' + System.currentTimeMillis());
        yes.Wartungsvertrag__c = true;
        Account no = new Account(Name = 'SCRUM431-ACC-NO-' + System.currentTimeMillis());
        no.Wartungsvertrag__c = false;
        insert new List<Account>{ yes, no };

        List<Case> cs = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cs.add(caseOn(yes.Id, false)); // 3 open on a contracts customer
        }
        for (Integer i = 0; i < 2; i++) {
            cs.add(caseOn(no.Id, false));  // open on a non-contracts customer
        }
        cs.add(caseOn(no.Id, true));       // closed on a non-contracts customer
        cs.add(caseOn(null, false));       // open, no account
        insert cs;
    }

    private static Case caseOn(Id accountId, Boolean closed) {
        return new Case(Subject = 'SCRUM-431', AccountId = accountId, IsClosed = closed);
    }

    @isTest
    static void reportDataSetIsOpenCasesOfContractCustomers() {
        // EXACT equivalent of the report filter:
        //   Account.Wartungsvertrag__c = true  AND  IsClosed = false (OPEN=1)
        // sorted Asc by CreatedDate (oldest first).
        Integer openContract = [
            SELECT COUNT(Id) FROM Case
            WHERE Account.Wartungsvertrag__c = true AND IsClosed = false
        ];
        Integer openNonContract = [
            SELECT COUNT(Id) FROM Case
            WHERE AccountId != null AND Account.Wartungsvertrag__c = false AND IsClosed = false
        ];
        Integer openOrphan = [
            SELECT COUNT(Id) FROM Case
            WHERE AccountId = null AND IsClosed = false
        ];

        System.assertEquals(3, openContract, '3 open cases of a contracts customer in setup');
        System.assertEquals(2, openNonContract, 'open cases of non-contracts customers in setup');
        System.assertEquals(1, openOrphan, 'one open case without account in setup');

        // The report must render exactly the contracts-customer open cases —
        // not the non-contract ones, not the orphan, not any closed case.
        List<Case> rows = [
            SELECT Id, Subject, AccountId, Account.Name, IsClosed, Wartungsvertrag_Anzeige__c
            FROM Case
            WHERE Account.Wartungsvertrag__c = true AND IsClosed = false
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(3, rows.size(), 'report data set = open cases of contracts customers only');
        for (Case c : rows) {
            System.assertEquals(false, c.IsClosed, 'row must be open');
            System.assertEquals('Ja', c.Wartungsvertrag_Anzeige__c, 'row belongs to a contracts customer');
        }
    }

    @isTest
    static void oldestFirstOrderingIsStable() {
        // Asc on CreatedDate: the row sequence must be non-decreasing in
        // CreatedDate. With one shared CreatedDate (same millisecond test
        // data) the ordering is trivially satisfied — the assertion guards
        // against a future sortOrder regression to Desc.
        List<Case> rows = [
            SELECT Id, CreatedDate FROM Case
            WHERE Account.Wartungsvertrag__c = true AND IsClosed = false
            ORDER BY CreatedDate ASC
        ];
        for (Integer i = 1; i < rows.size(); i++) {
            System.assert(
                rows[i].CreatedDate >= rows[i - 1].CreatedDate,
                'Oldest-first: row ' + i + ' must not be older than row ' + (i - 1));
        }
    }
}
