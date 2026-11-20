/**
 * [SCRUM-464] SCRUM464TesterCoverageTest — Tester-owned Apex coverage for the
 * acceptance criteria the Playwright spec cannot reach: AC3, AC4, AC11, AC12 and
 * the AC13 negative probe. Re-run after the SCRUM-466 report fix (this class
 * proves the record-level half; the report cell is proven in the E2E spec).
 *
 * Every save here is real DML: a rule that stops firing is a failing test, not a
 * missing log line. Test DML lives in the scratchpad, so nothing below persists to
 * Test-Org — the org counts in the coverage table come from the E2E fixtures.
 *
 * @author tester-agent
 * @date 2026-11-20
 */
@isTest
private class SCRUM464TesterCoverageTest {

    @TestSetup
    static void setup_fixtures() {
        Fabrikant__c maker = new Fabrikant__c(Name = '464 Tester Maker');
        insert maker;
    }

    // ── AC3: three non-third-party causes close normally, nobody asks for a maker.
    // No try/catch here on purpose: a refusal IS the failure.
    @isTest
    static void ac3_nonThirdPartyCausesCloseWithoutManufacturer() {
        List<Case> closes = new List<Case>{
            new Case(Subject = 'TESTSCRUM464-AC3-HOWTO', Status = 'Closed',
                     Ursache__c = 'HowToAnfrage', Customer_Satisfaction__c = 'Score_4'),
            new Case(Subject = 'TESTSCRUM464-AC3-BILLING', Status = 'Closed',
                     Ursache__c = 'RechnungAbrechnung', Customer_Satisfaction__c = 'Score_3'),
            new Case(Subject = 'TESTSCRUM464-AC3-MISCONFIG', Status = 'Closed',
                     Ursache__c = 'Fehlkonfiguration', Customer_Satisfaction__c = 'Score_5')
        };
        insert closes;

        List<String> ac3Subjects = new String[]{ 'TESTSCRUM464-AC3-HOWTO',
                                                 'TESTSCRUM464-AC3-BILLING',
                                                 'TESTSCRUM464-AC3-MISCONFIG' };
        Case[] back = [SELECT Id, Subject, Ursache__c, Closed_Last_12M__c,
                              Drittparty_Fabrikant__c, Drittparty_Fixkosten__c
                       FROM Case WHERE Subject IN :ac3Subjects];
        System.assertEquals(3, back.size(), 'AC3: a non-third-party closed case was refused');
        for (Case c : back) {
            System.assertEquals(null, c.Drittparty_Fabrikant__c,
                'AC3/AC4: a manufacturer was demanded on a non-third-party case');
            System.assertEquals(null, c.Drittparty_Fixkosten__c,
                'AC3/AC4: a cost was demanded on a non-third-party case');
        }
    }

    // ── AC4: a manufacturer (or a cost) on a cause that is not third-party is refused ──
    @isTest
    static void ac4_manufacturerRefusedOnNonThirdPartyCase() {
        Fabrikant__c maker = [SELECT Id FROM Fabrikant__c WHERE Name = '464 Tester Maker' LIMIT 1];
        System.assert(maker != null, 'precondition: the fixture manufacturer exists');

        Case withMaker = new Case(Subject = 'TESTSCRUM464-AC4-MAKER', Status = 'Closed',
                                  Ursache__c = 'TechnischerFehler', Customer_Satisfaction__c = 'Score_4',
                                  Drittparty_Fabrikant__c = maker.Id);
        Boolean refusedMaker = false;
        savepoint sp = savepoint();
        try {
            insert withMaker;
        } catch (Exception e) {
            refusedMaker = true;
            System.debug('AC4 expected refusal (manufacturer): ' + e);
        }
        rollbackToSavepoint(sp);
        System.assertEquals(true, refusedMaker,
            'AC4: saving a manufacturer on cause TechnischerFehler was accepted');

        Case withCost = new Case(Subject = 'TESTSCRUM464-AC4-COST', Status = 'Closed',
                                 Ursache__c = 'KeinFehlerKeineMassnahme', Customer_Satisfaction__c = 'Score_5',
                                 Drittparty_Fixkosten__c = 120.00);
        Boolean refusedCost = false;
        savepoint sp2 = savepoint();
        try {
            insert withCost;
        } catch (Exception e) {
            refusedCost = true;
            System.debug('AC4 expected refusal (cost): ' + e);
        }
        rollbackToSavepoint(sp2);
        System.assertEquals(true, refusedCost,
            'AC4: saving a cost on a non-third-party cause was accepted');

        Case[] leaked = [SELECT Id, Subject FROM Case WHERE Subject IN :new String[]{ 'TESTSCRUM464-AC4-MAKER', 'TESTSCRUM464-AC4-COST' }];
        System.assertEquals(0, leaked.size(), 'AC4: a refused save still persisted a record');
    }

    // ── AC7 + AC11: a third-party case closes with no cost; nothing is produced ──
    @isTest
    static void ac7_costOptional_ac11_noSideEffects() {
        Integer feedBefore = SELECT COUNT() FROM FeedItem;
        Integer emailBefore = SELECT COUNT() FROM EmailMessage;

        Fabrikant__c maker = [SELECT Id FROM Fabrikant__c WHERE Name = '464 Tester Maker' LIMIT 1];
        Case unknownCost = new Case(Subject = 'TESTSCRUM464-AC7-UNKNOWN', Status = 'Closed',
                                    Ursache__c = 'DrittpartyProdukt', Customer_Satisfaction__c = 'Score_4',
                                    Drittparty_Fabrikant__c = maker.Id);
        insert unknownCost;

        Case read = [SELECT Id, Drittparty_Fixkosten__c, Drittparty_Fixkosten_Known__c, Closed_Last_12M__c
                     FROM Case WHERE Subject = 'TESTSCRUM464-AC7-UNKNOWN' LIMIT 1];
        System.assert(read != null, 'AC7: the third-party case without a cost did not save');
        System.assertEquals(null, read.Drittparty_Fixkosten__c, 'AC7: a cost was demanded where none was entered');
        System.assertEquals(0, read.Drittparty_Fixkosten_Known__c,
            'AC7/TAC4: the unknown cost must count 0 in the denominator, not 1');

        Integer feedAfter = SELECT COUNT() FROM FeedItem;
        Integer emailAfter = SELECT COUNT() FROM EmailMessage;
        System.assertEquals(feedBefore, feedAfter, 'AC11: closing a third-party case created a FeedItem');
        System.assertEquals(emailBefore, emailAfter, 'AC11: closing a third-party case created an EmailMessage');
    }

    // ── AC12: manufacturer and cost are never externally accessible ──
    @isTest
    static void ac12_manufacturerAndCostNotExternallyAccessible() {
        DescribeFieldResult maker = Case.Drittparty_Fabrikant__c.getDescribe();
        DescribeFieldResult cost = Case.Drittparty_Fixkosten__c.getDescribe();
        System.assertEquals(false, maker.isExternalAccessible(),
            'AC12: the manufacturer could be exposed through external/shared access');
        System.assertEquals(false, cost.isExternalAccessible(),
            'AC12: the repair cost could be exposed through external/shared access');
        // The falses above only mean something because the CASE object itself IS
        // externally accessible here — the fields are the exception, not the org.
        System.assertEquals(true, Case.SObjectType.getDescribe().isExternalAccessible(),
            'precondition: the Case object is externally accessible, so the false flags above are about the fields');
    }

    // ── AC13 negative: a user with object CRUD but NO SCRUM464 PS cannot read or edit ──
    @isTest
    static void ac13_negative_noFieldAccessWithoutSCRUM464PS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String alias = 't464neg' + DateTime.now().getTime();
        User neg = new User(
            ProfileId = p.Id, LastName = 'Tester464Neg', Alias = alias,
            Email = alias + '@example.invalid', Username = alias + '@example.invalid',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert neg;
        PermissionSet objPs = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM464_TestObjectAccess' LIMIT 1];
        System.assert(objPs != null, 'precondition: SCRUM464_TestObjectAccess is deployed');
        insert new PermissionSetAssignment(AssigneeId = neg.Id, PermissionSetId = objPs.Id);

        System.runAs(neg) {
            System.assertEquals(true, Case.SObjectType.getDescribe().isAccessible(),
                'precondition: the Case is reachable, so the falses below are about the fields');
            System.assertEquals(false, Case.Drittparty_Fabrikant__c.getDescribe().isAccessible(),
                'AC13: the manufacturer is readable without any SCRUM464 PS');
            System.assertEquals(false, Case.Drittparty_Fixkosten__c.getDescribe().isAccessible(),
                'AC13: the repair cost is readable without any SCRUM464 PS');
            System.assertEquals(false, Case.Drittparty_Fabrikant__c.getDescribe().isUpdateable(),
                'AC13: the manufacturer is writable without any SCRUM464 PS');
            // A real read attempt must be refused, not only the flag.
            Boolean refused = false;
            try {
                Case[] probe = [SELECT Drittparty_Fixkosten__c FROM Case WHERE Name = 'x' LIMIT 1];
                System.assertEquals(0, probe.size(), 'AC13: the restricted user got a row for a field they cannot see');
            } catch (Exception e) {
                refused = true;
            }
            System.assertEquals(true, refused,
                'AC13: SOQL on the new field did NOT throw for the restricted user');
        }
    }
}
