/**
 * [SCRUM-464] SCRUM464DrittpartyTest - behaviour of the third-party fields on Case.
 *
 * TAC1 / AC2 : a closed Case whose cause is DrittpartyProdukt without a manufacturer
 *              is refused, and the message names the missing manufacturer.
 * TAC2 / AC3+AC4: a closed Case whose cause is Fehlkonfiguration (how-to, billing, our
 *              own misconfiguration) saves clean and nobody is asked for a manufacturer.
 * TAC3 / AC4 : a manufacturer or a cost on a NON-third-party case is refused, so the
 *              field stays empty.
 * TAC4 / AC7 : a third-party case with a manufacturer and NO cost saves; the 0/1
 *              denominator reads 0, so the case counts in the case count only.
 * TAC5       : the same denominator reads 1 when the cost is known.
 * TAC6 / AC8 : the rolling-window gate is TRUE for a case closed today, FALSE while
 *              the case is open (ClosedDate blank). The outside-window half cannot be
 *              built in Apex - ClosedDate is system-written and a test case closed
 *              today is always inside - it is measured on the org's 46 historical
 *              closed cases instead (see the notizen).
 * TAC10 / AC5: a second Fabrikant__c for a company that is already on the list is
 *              refused, in any casing, so the overview shows the company once.
 *
 * Test data is CREATED here on purpose: Test-Org had 46 closed Cases, 4 with any
 * Ursache__c, 0 third-party cases and 0 manufacturer records (measured 2026-11-20),
 * so AC2, AC5, AC7 and AC8 match zero records without fixtures.
 *
 * Mixed-DML house rule (SCRUM-442): the User and its PermissionSetAssignment are
 * created in System context - a user cannot grant himself a Permission Set - the
 * business DML/SOQL runs inside System.runAs of a user holding the released PSs.
 *
 * @author developer-agent
 * @date 2026-11-20
 */
@isTest
private class SCRUM464DrittpartyTest {

    @TestSetup
    static void setup_fixtures() {
        Contact c = new Contact(LastName = '464 Drittparty Contact');
        insert c;
        Fabrikant__c siemens = new Fabrikant__c(Name = 'Siemens');
        insert siemens;
        Fabrikant__c miele = new Fabrikant__c(Name = 'Miele');
        insert miele;
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Fls464',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    // The released SCRUM464 PSs plus the PSs that already grant the OTHER Case fields
    // a closing agent writes (Ursache__c = SCRUM434, Customer_Satisfaction__c = SCRUM-442
    // write) plus the test-local object CRUD (house SCRUM451_TestObjectAccess): a
    // Standard User without Case CRUD cannot save a Case at all.
    private static void grantPS(String[] psNames, Id userId) {
        for (String name : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + name + ' deployed');
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
        }
    }

    private static String[] closerRights() {
        return new String[] {
            'SCRUM464_Drittparty_Team',
            'SCRUM464_Fabrikant_List_Read',
            'SCRUM434_Ursache',
            'SCRUM442_Satisfaction_Write',
            'SCRUM451_TestObjectAccess'
        };
    }

    @isTest
    static void thirdPartyCase_withoutManufacturer_refused() {
        User u = mkUser('fls464a');
        insert u;
        grantPS(closerRights(), u.Id);

        System.runAs(u) {
            Contact c = [SELECT Id FROM Contact WHERE LastName = '464 Drittparty Contact' LIMIT 1];
            System.assert(c != null, 'precondition: fixture Contact readable');

            boolean refused = false;
            String message = null;
            try {
                insert new Case(
                    Subject = '464 third-party without manufacturer',
                    ContactId = c.Id,
                    Status = 'Closed',
                    Ursache__c = 'DrittpartyProdukt',
                    Customer_Satisfaction__c = 'Score_4'
                );
            } catch (Exception e) {
                refused = true;
                message = e.getMessage();
            }
            System.assertEquals(true, refused,
                'AC2/TAC1: a third-party case cannot be closed without a manufacturer');
            System.assert(
                message != null && message.toLowerCase().contains('fabrikant'),
                'AC2: the message names the missing manufacturer'
            );
        }
    }

    @isTest
    static void closedCase_otherCause_savesWithoutManufacturer() {
        User u = mkUser('fls464b');
        insert u;
        grantPS(closerRights(), u.Id);

        System.runAs(u) {
            Contact c = [SELECT Id FROM Contact WHERE LastName = '464 Drittparty Contact' LIMIT 1];

            // AC3/AC4: a how-to question, a billing issue or our own misconfiguration
            // closes normally and nobody is asked for a manufacturer.
            insert new Case(
                Subject = '464 own misconfiguration',
                ContactId = c.Id,
                Status = 'Closed',
                Ursache__c = 'Fehlkonfiguration',
                Customer_Satisfaction__c = 'Score_4'
            );
            Case back = [
                SELECT Id, Ursache__c, Drittparty_Fabrikant__c, Drittparty_Fixkosten__c, Closed_Last_12M__c
                FROM Case WHERE Subject = '464 own misconfiguration' LIMIT 1
            ];
            System.assert(back != null, 'AC3/TAC2: the case saved');
            System.assert(back.Drittparty_Fabrikant__c == null,
                'AC4/TAC3: no manufacturer demanded, the field stays empty');
            System.assert(back.Drittparty_Fixkosten__c == null,
                'AC4: no cost demanded either');
            System.assertEquals(true, back.Closed_Last_12M__c,
                'TAC6: closed today => inside the rolling twelve months');
        }
    }

    @isTest
    static void manufacturerOrCost_onNonThirdPartyCase_refused() {
        User u = mkUser('fls464c');
        insert u;
        grantPS(closerRights(), u.Id);

        System.runAs(u) {
            Contact c = [SELECT Id FROM Contact WHERE LastName = '464 Drittparty Contact' LIMIT 1];
            Fabrikant__c siemens = [SELECT Id FROM Fabrikant__c WHERE Name = 'Siemens' LIMIT 1];
            System.assert(siemens != null, 'precondition: fixture manufacturer readable');

            // TAC3: a manufacturer on a case whose cause is NOT third-party is refused.
            boolean refusedFabrikant = false;
            try {
                insert new Case(
                    Subject = '464 wrong manufacturer',
                    ContactId = c.Id,
                    Status = 'Closed',
                    Ursache__c = 'Fehlkonfiguration',
                    Customer_Satisfaction__c = 'Score_4',
                    Drittparty_Fabrikant__c = siemens.Id
                );
            } catch (Exception e) {
                refusedFabrikant = true;
            }
            System.assertEquals(true, refusedFabrikant,
                'AC4/TAC3: a manufacturer on a non-third-party case is refused');

            // TAC3, cost half.
            boolean refusedCost = false;
            try {
                insert new Case(
                    Subject = '464 wrong cost',
                    ContactId = c.Id,
                    Status = 'Closed',
                    Ursache__c = 'RechnungAbrechnung',
                    Customer_Satisfaction__c = 'Score_4',
                    Drittparty_Fixkosten__c = 900
                );
            } catch (Exception e) {
                refusedCost = true;
            }
            System.assertEquals(true, refusedCost,
                'AC4/TAC3: a repair cost on a non-third-party case is refused');
        }
    }

    @isTest
    static void thirdPartyCase_knownAndUnknownCost_denominator() {
        User u = mkUser('fls464d');
        insert u;
        grantPS(closerRights(), u.Id);

        System.runAs(u) {
            Contact c = [SELECT Id FROM Contact WHERE LastName = '464 Drittparty Contact' LIMIT 1];
            Fabrikant__c siemens = [SELECT Id FROM Fabrikant__c WHERE Name = 'Siemens' LIMIT 1];

            // One bulk insert: two records, ONE trigger evaluation (house lesson -
            // two separate inserts are two invocations).
            insert new Case[] {
                new Case(
                    Subject = '464 cost unknown',
                    ContactId = c.Id,
                    Status = 'Closed',
                    Ursache__c = 'DrittpartyProdukt',
                    Customer_Satisfaction__c = 'Score_3',
                    Drittparty_Fabrikant__c = siemens.Id
                ),
                new Case(
                    Subject = '464 cost known',
                    ContactId = c.Id,
                    Status = 'Closed',
                    Ursache__c = 'DrittpartyProdukt',
                    Customer_Satisfaction__c = 'Score_4',
                    Drittparty_Fabrikant__c = siemens.Id,
                    Drittparty_Fixkosten__c = 1250.00
                )
            };

            Case unknown = [
                SELECT Id, Drittparty_Fixkosten__c, Drittparty_Fixkosten_Known__c
                FROM Case WHERE Subject = '464 cost unknown' LIMIT 1
            ];
            System.assert(unknown.Drittparty_Fixkosten__c == null,
                'AC7/TAC4: the unknown cost stays blank, not 0');
            System.assertEquals(0, unknown.Drittparty_Fixkosten_Known__c,
                'AC7/TAC4: the denominator is 0, so this case is out of total and average');

            Case known = [
                SELECT Id, Drittparty_Fixkosten__c, Drittparty_Fixkosten_Known__c
                FROM Case WHERE Subject = '464 cost known' LIMIT 1
            ];
            System.assertEquals(1, known.Drittparty_Fixkosten_Known__c,
                'TAC5: a known cost sets the denominator to 1');
            System.assertEquals(1250.00, known.Drittparty_Fixkosten__c,
                'AC7: the known cost is kept exactly');
        }
    }

    @isTest
    static void windowGate_falseWhileOpen() {
        User u = mkUser('fls464e');
        insert u;
        grantPS(closerRights(), u.Id);

        System.runAs(u) {
            Contact c = [SELECT Id FROM Contact WHERE LastName = '464 Drittparty Contact' LIMIT 1];
            insert new Case(
                Subject = '464 still open',
                ContactId = c.Id,
                Status = 'Working',
                Ursache__c = 'DrittpartyProdukt'
            );
            Case open = [
                SELECT Id, Closed_Last_12M__c, Drittparty_Fabrikant__c
                FROM Case WHERE Subject = '464 still open' LIMIT 1
            ];
            System.assertEquals(false, open.Closed_Last_12M__c,
                'TAC6: an open case without ClosedDate is outside the window');
            System.assert(open.Drittparty_Fabrikant__c == null,
                'AC10: an open case is never asked for a manufacturer');
        }
    }

    @isTest
    static void duplicateManufacturer_refused_anyCasing() {
        // TAC10 / AC5: the list may not hold the same company twice, so the overview
        // shows the company exactly once. Guard only - no email, no task, no alert (AC11).
        User u = mkUser('fls464lead');
        insert u;
        grantPS(new String[] { 'SCRUM464_Fabrikant_List_Read', 'SCRUM464_Fabrikant_List_Lead', 'SCRUM451_TestObjectAccess' }, u.Id);

        System.runAs(u) {
            boolean refused = false;
            String message = null;
            try {
                insert new Fabrikant__c(Name = 'Siemens');
            } catch (Exception e) {
                refused = true;
                message = e.getMessage();
            }
            System.assertEquals(true, refused,
                'AC5/TAC10: a second record with an existing company name is refused');
            System.assert(message != null && message.contains('Siemens'),
                'AC5: the refusal names the duplicate');

            boolean refusedCasing = false;
            try {
                insert new Fabrikant__c(Name = 'SIEMENS');
            } catch (Exception e) {
                refusedCasing = true;
            }
            System.assertEquals(true, refusedCasing,
                'AC5: a different casing of an existing company is refused as well');

            Fabrikant__c fresh = new Fabrikant__c(Name = '464 Fresh Manufacturer');
            insert fresh;
            Fabrikant__c back = [SELECT Id, Name FROM Fabrikant__c WHERE Name = '464 Fresh Manufacturer' LIMIT 1];
            System.assertEquals('464 Fresh Manufacturer', back.Name, 'AC6: a new manufacturer was added to the list');
        }
    }

    @isTest
    static void thirdPartyCases_qualifyingForTheOverview() {
        // AC8 precondition that travels to the Tester: every closed third-party case
        // this run created carries a manufacturer, so the overview row is comparable
        // to a real count. The count is a lower bound, never a cross-method total -
        // Apex rolls back per test method, so the order of the methods must not matter.
        User u = mkUser('fls464f');
        insert u;
        grantPS(closerRights(), u.Id);

        System.runAs(u) {
            Integer qualifying = 0;
            Integer withoutManufacturer = 0;
            Integer inWindow = 0;
            for (Case c : [
                SELECT Id, Drittparty_Fabrikant__c, Closed_Last_12M__c
                FROM Case WHERE IsClosed = true AND Ursache__c = 'DrittpartyProdukt'
            ]) {
                qualifying++;
                if (c.Drittparty_Fabrikant__c == null) {
                    withoutManufacturer++;
                }
                if (c.Closed_Last_12M__c) {
                    inWindow++;
                }
            }
            System.assert(qualifying >= 2,
                'AC8: at least the two Siemens cases of this run are closed third-party cases');
            System.assertEquals(0, withoutManufacturer,
                'AC2: no closed third-party case survived without a manufacturer');
            System.assertEquals(qualifying, inWindow,
                'AC8: every case closed today is inside the rolling twelve months');
            System.debug('SCRUM-464 AC8 count: qualifying=' + qualifying + ' inWindow=' + inWindow);
        }
    }
}
