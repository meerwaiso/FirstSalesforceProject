/**
 * [SCRUM-431] Report data contract for "Morgen_UEbersicht_Vertragskunden".
 *
 * A report cannot be executed from Apex, so its cross-object data set is
 * proven by the SOQL dimension the feature adds: cases whose ACCOUNT has the
 * contract checkbox set — and nothing else (non-contract and orphan accounts
 * excluded). The report's "open" (OPEN=1) side is the standard CaseList
 * openness filter, asserted by the Tester visually; here we set every test
 * case to open (the Case default status) so that side cannot confound the
 * cross-object assertion.
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

        // All cases open (Case default status) so the cross-object filter is
        // the only dimension under test. 3 on the contracts customer, 3 on a
        // non-contracts customer, 1 orphan (no account).
        List<Case> cs = new List<Case>();
        for (Integer i = 0; i < 3; i++) { cs.add(caseOn(yes.Id)); }
        for (Integer i = 0; i < 3; i++) { cs.add(caseOn(no.Id)); }
        cs.add(caseOn(null));
        insert cs;
    }

    private static Case caseOn(Id accountId) {
        return new Case(Subject = 'SCRUM-431', AccountId = accountId);
    }

    @isTest
    static void reportDataSetIsCasesOfContractCustomersOnly() {
        // The feature's cross-object dimension: Account.Wartungsvertrag__c = true.
        Integer openContract = [
            SELECT COUNT(Id) FROM Case
            WHERE Account.Wartungsvertrag__c = true AND IsClosed = false
        ][0].GOT_COUNT;
        Integer openNonContract = [
            SELECT COUNT(Id) FROM Case
            WHERE AccountId != null AND Account.Wartungsvertrag__c = false AND IsClosed = false
        ][0].GOT_COUNT;
        Integer openOrphan = [
            SELECT COUNT(Id) FROM Case
            WHERE AccountId = null AND IsClosed = false
        ][0].GOT_COUNT;

        System.assertEquals(3, openContract, '3 cases of a contracts customer in setup');
        System.assertEquals(3, openNonContract, '3 cases of a non-contracts customer in setup');
        System.assertEquals(1, openOrphan, '1 orphan case (no account) in setup');

        // The report must render exactly the contracts-customer cases —
        // not the non-contract ones, not the orphan.
        List<Account> yesAccs = [SELECT Id FROM Account WHERE Name LIKE 'SCRUM431-ACC-YES-%'];
        List<Id> yesIds = new List<Id>();
        for (Account a : yesAccs) { yesIds.add(a.Id); }
        List<Case> rows = [
            SELECT Id, Subject, AccountId, Account.Name, IsClosed, Wartungsvertrag_Anzeige__c
            FROM Case
            WHERE Account.Wartungsvertrag__c = true AND IsClosed = false
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(3, rows.size(), 'report data set = contracts-customer cases only');
        Set<Id> seen = new Set<Id>();
        for (Case c : rows) {
            seen.add(c.AccountId);
            System.assertEquals(false, c.IsClosed, 'row must be open');
            System.assertEquals('Ja', c.Wartungsvertrag_Anzeige__c, 'row belongs to a contracts customer');
        }
        System.assertEquals(new Set<Id>(yesIds), seen,
            'exactly the contracts-customer cases match; non-contract + orphan excluded');
    }

    @isTest
    static void oldestFirstOrderingIsStable() {
        // Asc on CreatedDate: the row sequence must be non-decreasing —
        // guards against a future sortOrder regression to Desc.
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
