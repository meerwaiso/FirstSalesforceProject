/**
 * [SCRUM-451] Functional test for the contract dates and the derived
 * display (ADR-1: 100 % declarative, no Apex production logic).
 *
 *   Account.Wartungsvertrag_Start__c / _End__c  — manually recorded dates
 *   Account.Wartungsvertrag_Ende_Tage__c        — whole days left, blank when
 *                                                 never recorded or expired
 *   Account.Wartungsvertrag_Status__c           — "in 45 days" / "ends today" /
 *                                                 "expired"
 *   Account.Wartungsvertrag_Active__c           — flag AND (end blank OR end
 *                                                 >= today)  (single source of
 *                                                 truth, same expression as the
 *                                                 Case indicator)
 *   Account.Wartungsvertrag_Renewal_Soon__c     — end recorded AND today <= end
 *                                                 <= ADDMONTHS(today, 3)
 *   Case.Wartungsvertrag_Anzeige__c             — SCRUM-431 indicator, now
 *                                                 derived from the same decision
 *
 * House shape: SCRUM431WartungsvertragTest (query the field back after DML —
 * formula fields are not populated on the in-memory sObject) and SCRUM424First
 * ResponseFlsTest (User + PermissionSetAssignment as setup DML, business DML
 * and SOQL inside System.runAs — otherwise MIXED_DML_OPERATION, FLS-Gate C).
 *
 * Measured split (this class, Test-Org): Account DML and the derived read-back
 * run fine under System.runAs of a fixture user. A Case insert that sets
 * AccountId does NOT: "Operation failed due to fields being inaccessible on
 * Sobject Case" for every variant tried (re-read AccountId, update after insert,
 * an Account without the flag). Widening SCRUM451_TestObjectAccess with FLS on
 * Account.Name/Owner/AccountNumber and Case.AccountId/Origin/Subject/Status
 * changed nothing — the measured reason: the platform refuses an FLS entry on
 * those required standard fields, so Test-Org stored zero field-level grants and
 * the Prod-Org Drift Gate rejects the file. The Set therefore carries object-level
 * CRUD only. The Case assertions below therefore run in System context, as in the
 * SCRUM-431 house class; the permission proof for the Case indicator lives in
 * SCRUM451WartungsvertragFlsTest (reflection) and in the Tester's E2E against a
 * real session.
 *
 * Fixtures here mirror the ones seeded in Test-Org: end = today+45, today,
 * today-1, blank, start-only, beyond the 3-month window, plus three flagged
 * customers with an empty end date (PO fixture requirement).
 */
@isTest
private class SCRUM451WartungsvertragTest {

    private static Profile standardProfile() {
        return [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    }

    /** Setup DML: a user that may record the dates (both SCRUM451 PS). */
    private static User newDateEditor(String tag) {
        Profile p = standardProfile();
        String uName = 'scr451-' + tag + '-' + DateTime.now().getTime() + '@example.invalid';
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr451-' + tag,
            Alias = ('45' + tag).left(8),
            Email = uName,
            Username = uName,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        // A team lead in this org holds the SCRUM-431 PS as well: the recorded
        // flag lives there, and an insert that sets it fails without it
        // ("fields being inaccessible on Sobject Account").
        for (String psName : new String[] {
                'SCRUM431_Wartungsvertrag_Teamleitung',
                'SCRUM451_Wartungsvertrag_Dates_Teamleitung',
                'SCRUM451_Wartungsvertrag_Dates_Read',
                'SCRUM451_TestObjectAccess' }) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static Account newContractAccount(String name, Boolean flag, Date startDt, Date endDt) {
        return new Account(
            Name = name,
            Wartungsvertrag__c = flag,
            Wartungsvertrag_Start__c = startDt,
            Wartungsvertrag_End__c = endDt
        );
    }

    /** Formula fields are read back, never written (they are not updatable). */
    private static Account readDerived(Id accountId) {
        return [SELECT
            Wartungsvertrag__c, Wartungsvertrag_Start__c, Wartungsvertrag_End__c,
            Wartungsvertrag_Ende_Tage__c, Wartungsvertrag_Status__c,
            Wartungsvertrag_Active__c, Wartungsvertrag_Renewal_Soon__c
            FROM Account WHERE Id = :accountId];
    }

    // ---- AC3: contract ending 45 calendar days out shows "45" --------------
    @isTest
    static void endsIn45Days_remainingTimeAndStatus() {
        User u = newDateEditor('a45');
        System.runAs(u) {
            Account a = newContractAccount('TEST-SCRUM-451-T45', true,
                Date.today().addMonths(-9), Date.today().addDays(45));
            insert a;
            Account r = readDerived(a.Id);
            System.assertEquals(45, (Decimal) r.Wartungsvertrag_Ende_Tage__c,
                'AC3: 45 calendar days left -> Ede_Tage = 45');
            System.assertEquals('in 45 days', r.Wartungsvertrag_Status__c,
                'AC3: the glance value reads "in 45 days"');
            System.assertEquals(true, r.Wartungsvertrag_Active__c, 'AC3: still counts');
            System.assertEquals(true, r.Wartungsvertrag_Renewal_Soon__c, 'AC10: inside the 3-month window');
        }
    }

    // ---- AC4: ends today still counts, end date is inclusive ---------------
    @isTest
    static void endsToday_stillCountsAsMaintenanceCustomer() {
        User u = newDateEditor('today');
        System.runAs(u) {
            Account a = newContractAccount('TEST-SCRUM-451-TODAY', true,
                Date.today().addMonths(-3), Date.today());
            insert a;
            Account r = readDerived(a.Id);
            System.assertEquals(0, (Decimal) r.Wartungsvertrag_Ende_Tage__c, 'AC4: end = today -> 0 days left');
            System.assertEquals('ends today', r.Wartungsvertrag_Status__c, 'AC4: states "ends today"');
            System.assertEquals(true, r.Wartungsvertrag_Active__c, 'AC4: end date inclusive -> still counts');
        }
    }

    // ---- AC5: expired states it, and there is never a negative count ------
    @isTest
    static void expired_noNegativeCount_statesExpired() {
        User u = newDateEditor('exp');
        System.runAs(u) {
            Account a = newContractAccount('TEST-SCRUM-451-EXPIRED', true,
                Date.today().addMonths(-4), Date.today().addDays(-1));
            insert a;
            Account r = readDerived(a.Id);
            System.assert(r.Wartungsvertrag_Ende_Tage__c == null,
                'AC5: an expired contract shows NO day count (never a negative one)');
            System.assertEquals('expired', r.Wartungsvertrag_Status__c, 'AC5: states that it already expired');
            System.assertEquals(false, r.Wartungsvertrag_Active__c, 'AC6: no longer counts as maintenance customer');
            System.assertEquals(false, r.Wartungsvertrag_Renewal_Soon__c, 'AC11: already expired is not in the overview');
        }
    }

    // ---- AC7 + AC8: empty end date (and start-only) keeps today's behaviour
    @isTest
    static void emptyEndDate_keepsTodayBehaviour() {
        User u = newDateEditor('blank');
        System.runAs(u) {
            // ONE bulk insert: three flagged customers without any dates (PO
            // fixture requirement) plus one with a start date only.
            Account[] seeds = new Account[] {
                newContractAccount('TEST-SCRUM-451-BLANK-1', true, null, null),
                newContractAccount('TEST-SCRUM-451-BLANK-2', true, null, null),
                newContractAccount('TEST-SCRUM-451-BLANK-3', true, null, null),
                newContractAccount('TEST-SCRUM-451-STARTONLY', true, Date.today().addMonths(-2), null)
            };
            insert seeds;
            Account[] back = [SELECT Name, Wartungsvertrag__c, Wartungsvertrag_Start__c,
                              Wartungsvertrag_End__c, Wartungsvertrag_Ende_Tage__c,
                              Wartungsvertrag_Status__c, Wartungsvertrag_Active__c,
                              Wartungsvertrag_Renewal_Soon__c
                              FROM Account WHERE Name IN ('TEST-SCRUM-451-BLANK-1',
                                                          'TEST-SCRUM-451-BLANK-2',
                                                          'TEST-SCRUM-451-BLANK-3',
                                                          'TEST-SCRUM-451-STARTONLY')];
            System.assertEquals(4, back.size(), 'all four seeded customers are back');
            for (Account r : back) {
                System.assertEquals(true, r.Wartungsvertrag__c, 'AC7: the recorded flag is untouched');
                System.assertEquals(true, r.Wartungsvertrag_Active__c,
                    'AC7/AC8: empty end date keeps the customer as maintenance customer');
                System.assert(r.Wartungsvertrag_Ende_Tage__c == null, 'AC7: no day count without an end date');
                System.assert(r.Wartungsvertrag_Status__c == null, 'AC7: no status word without an end date');
                System.assertEquals(false, r.Wartungsvertrag_Renewal_Soon__c, 'AC11: no end date -> not in the overview');
            }
        }
    }

    // ---- AC10/AC11: the window gate counts exactly the in-window contracts
    @isTest
    static void windowGate_countsOnlyContractsEndingWithinThreeMonths() {
        User u = newDateEditor('win');
        System.runAs(u) {
            Account[] seeds = new Account[] {
                newContractAccount('TEST-SCRUM-451-WIN-1', true, null, Date.today().addDays(10)),
                newContractAccount('TEST-SCRUM-451-WIN-2', true, null, Date.today().addMonths(3)),
                newContractAccount('TEST-SCRUM-451-OFF-1', true, null, Date.today().addDays(120))
            };
            insert seeds;
            System.assertEquals(2, [SELECT COUNT() FROM Account
                                    WHERE Name LIKE 'TEST-SCRUM-451-WIN%' AND Wartungsvertrag_Renewal_Soon__c = true],
                'AC10: two contracts end inside today -> today + 3 months');
            System.assertEquals(0, [SELECT COUNT() FROM Account
                                    WHERE Name LIKE 'TEST-SCRUM-451-OFF%' AND Wartungsvertrag_Renewal_Soon__c = true],
                'AC11: a contract ending beyond the window is not in the overview');
            Account far = [SELECT Wartungsvertrag_Status__c FROM Account
                           WHERE Name = 'TEST-SCRUM-451-OFF-1'];
            System.assertEquals('in 120 days', far.Wartungsvertrag_Status__c,
                'AC3: outside the window the remaining time is still shown');
        }
    }

    // ---- AC12: end before start is refused (ValidationRule) ---------------
    @isTest
    static void endBeforeStart_isRefused() {
        User u = newDateEditor('val');
        System.runAs(u) {
            Account a = newContractAccount('TEST-SCRUM-451-INVALID', true,
                Date.today().addDays(10), Date.today().addDays(5));
            DmlException ex = null;
            try {
                insert a;
            } catch (DmlException e) {
                ex = e;
            }
            System.assertNotEquals(null, ex, 'AC12: an end date before the start date MUST be refused');
            System.assert(ex.getMessage().contains('Enddate before Startdate'),
                'The message names the contract dates. Actually: ' + ex.getMessage());
            System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'TEST-SCRUM-451-INVALID'],
                'AC12: nothing was stored');
        }
    }

    // ---- AC6 + AC7 on the Case indicator (System context, house shape of
    //      SCRUM431WartungsvertragTest: no User is created in this transaction)
    @isTest
    static void caseIndicator_followsTheSameDecision() {
        Account active = newContractAccount('TEST-SCRUM-451-CASE-ACTIVE', true,
            Date.today().addMonths(-9), Date.today().addDays(45));
        Account expired = newContractAccount('TEST-SCRUM-451-CASE-EXPIRED', true,
            Date.today().addMonths(-4), Date.today().addDays(-1));
        Account blank = newContractAccount('TEST-SCRUM-451-CASE-BLANK', true, null, null);
        insert new Account[] { active, expired, blank };

        Case cActive = new Case(
            Subject = 'TEST-SCRUM-451-CASEIND-ACTIVE', AccountId = active.Id,
            Origin = 'Phone', Status = 'Open');
        Case cExpired = new Case(
            Subject = 'TEST-SCRUM-451-CASEIND-EXPIRED', AccountId = expired.Id,
            Origin = 'Phone', Status = 'Open');
        Case cBlank = new Case(
            Subject = 'TEST-SCRUM-451-CASEIND-BLANK', AccountId = blank.Id,
            Origin = 'Phone', Status = 'Open');
        insert new Case[] { cActive, cExpired, cBlank };

        Map<Id, String> bySubject = new Map<Id, String>();
        for (Case c : [SELECT Id, Subject, Wartungsvertrag_Anzeige__c
                       FROM Case WHERE Subject LIKE 'TEST-SCRUM-451-CASEIND%']) {
            bySubject.put(c.Id, c.Wartungsvertrag_Anzeige__c);
        }
        System.assertEquals(3, bySubject.size(), 'all three seeded cases are back');
        for (Case c : [SELECT Id, Subject, Wartungsvertrag_Anzeige__c
                       FROM Case WHERE Subject LIKE 'TEST-SCRUM-451-CASEIND%']) {
            if (c.Subject.contains('EXPIRED')) {
                System.assertEquals('Nein', c.Wartungsvertrag_Anzeige__c,
                    'AC6: the case of an expired customer no longer shows the indicator');
            } else {
                System.assertEquals('Ja', c.Wartungsvertrag_Anzeige__c,
                    'AC4/AC7: an active or never-recorded contract still shows the indicator');
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Case
                                WHERE Subject = 'TEST-SCRUM-451-CASEIND-EXPIRED'
                                    AND Wartungsvertrag_Anzeige__c = 'Ja'],
            'AC6: cases of expired-contract customers that still show the indicator must be 0');
    }

    // ---- Schema: the derived fields are formulas, never writable ----------
    @isTest
    static void derivedFieldsAreFormulasNotWritable() {
        User u = newDateEditor('schema');
        System.runAs(u) {
            Schema.DescribeFieldResult[] derived = new Schema.DescribeFieldResult[] {
                Account.Wartungsvertrag_Ende_Tage__c.getDescribe(),
                Account.Wartungsvertrag_Status__c.getDescribe(),
                Account.Wartungsvertrag_Active__c.getDescribe(),
                Account.Wartungsvertrag_Renewal_Soon__c.getDescribe()
            };
            for (Schema.DescribeFieldResult f : derived) {
                System.assert(f.isCalculated(), 'derived field is a formula field (ADR-1)');
                System.assertEquals(false, f.isUpdateable(),
                    'derived field is read-only, the derived value is never written');
            }
            Schema.DescribeFieldResult days = Account.Wartungsvertrag_Ende_Tage__c.getDescribe();
            System.assert(days.getType() == Schema.DisplayType.Integer
                          || days.getType() == Schema.DisplayType.Double, 'remaining days is a Number field');
            Schema.DescribeFieldResult status = Account.Wartungsvertrag_Status__c.getDescribe();
            System.assert(status.getType() == Schema.DisplayType.STRING, 'the glance value is a Text field');
            System.assertEquals(0, status.getPicklistValues().size(),
                'the status words live in the formula, not in a picklist');
        }
    }
}
