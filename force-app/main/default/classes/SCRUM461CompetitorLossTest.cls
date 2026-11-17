/**
 * [SCRUM-461] SCRUM461CompetitorLossTest - behaviour of the competitor fields.
 *
 * TAC1 Competitor_Gap__c reads back BLANK (not 0) when the price is unknown (AC5).
 * TAC2 the gap is negative when we were cheaper and the deal is still counted (PO decision).
 * TAC3 Lost_Last_12M__c is FALSE outside the rolling twelve months, TRUE inside.
 * TAC4 a Closed-Lost save with Loss_Reason__c = Wettbewerber and no competitor throws
 *      a validation error that names the competitor (AC2).
 * TAC5 the same save with another loss reason succeeds without a competitor (AC1).
 * TAC10 a second Competitor__c with an existing Company_Name__c is refused (AC3).
 *
 * Mixed-DML house rule (SCRUM-442): the User and its PermissionSetAssignment are
 * created in System context (a user cannot grant himself a PSA), the business
 * DML/SOQL runs inside System.runAs of a user holding the released PSs.
 *
 * Test data is CREATED here on purpose: Test-Org had 16 Closed Lost deals and
 * 0 of them with Loss_Reason__c = Wettbewerber (measured 2026-11-17), so AC2,
 * AC5, AC7 and AC8 match zero records without fixtures.
 *
 * @author developer-agent
 * @date 2026-11-17
 */
@isTest
private class SCRUM461CompetitorLossTest {

    @TestSetup
    static void setup_fixtures() {
        Account a = new Account(Name = '461 Competitor Account');
        insert a;
        Competitor__c mueller = new Competitor__c(Company_Name__c = 'Müller GmbH');
        insert mueller;
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Fls461',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    private static void grantDealRights(User u) {
        PermissionSet lost = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM461_Competitor_Lost' LIMIT 1
        ];
        PermissionSet listRead = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM461_Competitor_List_Read' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = lost.Id);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = listRead.Id);
    }

    @isTest
    static void gap_blankWhenPriceUnknown_negativeWhenCheaper() {
        User u = mkUser('fls461gap');
        insert u;
        grantDealRights(u);

        System.runAs(u) {
            Account a = [SELECT Id FROM Account WHERE Name = '461 Competitor Account' LIMIT 1];
            Competitor__c c = [
                SELECT Id, Company_Name__c FROM Competitor__c WHERE Company_Name__c = 'Müller GmbH' LIMIT 1
            ];
            System.assert(a != null && c != null, 'precondition: fixtures readable under the PSs');

            // AC5: competitor known, price unknown.
            insert new Opportunity(
                Name = '461 Gap Unknown',
                AccountId = a.Id,
                StageName = 'Closed Lost',
                CloseDate = Date.today() - 30,
                Amount = 100000,
                Loss_Reason__c = 'Wettbewerber',
                Competitor_Lost_To__c = c.Id
            );
            // PO decision: we lost despite being cheaper -> negative gap, still counted.
            insert new Opportunity(
                Name = '461 Gap Negative',
                AccountId = a.Id,
                StageName = 'Closed Lost',
                CloseDate = Date.today() - 60,
                Amount = 80000,
                Competitor_Price__c = 95000,
                Loss_Reason__c = 'Wettbewerber',
                Competitor_Lost_To__c = c.Id
            );
            // TAC3: deal lost outside the rolling twelve months.
            insert new Opportunity(
                Name = '461 Outside Window',
                AccountId = a.Id,
                StageName = 'Closed Lost',
                CloseDate = Date.today() - 400,
                Amount = 70000,
                Loss_Reason__c = 'Wettbewerber',
                Competitor_Lost_To__c = c.Id
            );

            Opportunity unknown = [
                SELECT Id, Competitor_Gap__c, Lost_Last_12M__c
                FROM Opportunity WHERE Name = '461 Gap Unknown' LIMIT 1
            ];
            System.assert(unknown.Competitor_Gap__c == null,
                'TAC1/AC5: gap must be blank, not 0, when the price is unknown');
            System.assertEquals(true, unknown.Lost_Last_12M__c,
                'TAC3: a deal lost 30 days ago is inside the window');

            Opportunity cheaper = [
                SELECT Id, Competitor_Gap__c, Amount, Competitor_Price__c
                FROM Opportunity WHERE Name = '461 Gap Negative' LIMIT 1
            ];
            System.assertEquals(new Decimal(-15000), new Decimal(cheaper.Competitor_Gap__c),
                'TAC2: our 80.000 minus the competitor 95.000 = -15.000, kept not filtered');
            System.assertEquals(true, cheaper.Lost_Last_12M__c,
                'TAC3: inside the window');

            Opportunity outside = [
                SELECT Id, Competitor_Gap__c, Lost_Last_12M__c
                FROM Opportunity WHERE Name = '461 Outside Window' LIMIT 1
            ];
            System.assertEquals(false, outside.Lost_Last_12M__c,
                'TAC3: a deal lost 400 days ago is outside the rolling twelve months');
        }
    }

    @isTest
    static void competitor_mandatoryOnlyWhenReasonNamesCompetitor() {
        User u = mkUser('fls461vr');
        insert u;
        grantDealRights(u);

        System.runAs(u) {
            Account a = [SELECT Id FROM Account WHERE Name = '461 Competitor Account' LIMIT 1];

            // AC2 / TAC4: competitor loss without a competitor is refused.
            boolean refused = false;
            String message = null;
            try {
                insert new Opportunity(
                    Name = '461 Missing Competitor',
                    AccountId = a.Id,
                    StageName = 'Closed Lost',
                    CloseDate = Date.today() - 10,
                    Amount = 50000,
                    Loss_Reason__c = 'Wettbewerber'
                );
            } catch (Exception e) {
                refused = true;
                message = e.getMessage();
            }
            System.assertEquals(true, refused,
                'AC2/TAC4: a competitor loss without a competitor must not save');
            System.assert(
                message != null && message.contains('Wettbewerber'),
                'AC2: the error message names the missing competitor'
            );

            // AC1 / TAC5: another loss reason stays free of a competitor.
            Opportunity cancelled = new Opportunity(
                Name = '461 Cancelled Deal',
                AccountId = a.Id,
                StageName = 'Closed Lost',
                CloseDate = Date.today() - 10,
                Amount = 50000,
                Loss_Reason__c = 'KontaktAbgebrochen'
            );
            insert cancelled;
            Opportunity back = [
                SELECT Id, Loss_Reason__c, Competitor_Lost_To__c
                FROM Opportunity WHERE Name = '461 Cancelled Deal' LIMIT 1
            ];
            System.assertEquals('KontaktAbgebrochen', back.Loss_Reason__c,
                'AC1/TAC5: saved without complaint');
            System.assert(back.Competitor_Lost_To__c == null,
                'AC1: no competitor was demanded for a cancelled customer project');
        }
    }

    @isTest
    static void duplicateCompanyName_refused() {
        // TAC10 / AC3: the list may not hold the same company twice.
        boolean refused = false;
        String message = null;
        try {
            insert new Competitor__c(Company_Name__c = 'Müller GmbH');
        } catch (Exception e) {
            refused = true;
            message = e.getMessage();
        }
        System.assertEquals(true, refused,
            'TAC10/AC3: a second record with an existing company name is refused');
        System.assert(message != null && message.contains('Müller'),
            'AC3: the refusal names the duplicate');
    }
}
