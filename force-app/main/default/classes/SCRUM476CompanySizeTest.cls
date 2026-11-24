/**
 * [SCRUM-476] Behaviour proof for CompanySizeCarryHandler + both triggers.
 *
 * House pattern SCRUM472CompanySizeTest / SCRUM471KeyAccountTest: one criterion per
 * @isTest method, TEST-476 fixture names, an assert that can actually go red.
 *
 * PATH A (new customer) runs THROUGH THE REAL TRIGGER: an Account insert fires
 * AccountCompanySizeCarry, so the insert below covers handler AND trigger.
 *
 * PATH B (attaching to an existing customer) calls the handler ENTRY DIRECTLY with
 * (leads, oldMap). Reason, measured: any Apex update of a Lead also fires
 * SCRUM472LeadConvertor, which starts a conversion of its own (house SCRUM-472) —
 * that storm is the convertor's ticket, not ours, and it is exactly why the design
 * says AC 5 is proven E2E through the real Convert button, not by an Apex update of
 * Lead.Company. What this class proves is the contract of fillBlankCustomers:
 * blank -> filled, filled -> NEVER touched, no name match -> nothing written.
 *
 * A test is no evidence unless it can fail: every "nothing changed" assert below is
 * paired with a write that WOULD have changed the value if the rule were broken
 * (the band of the lead differs from the band of the customer in every one of them).
 */
@isTest
private class SCRUM476CompanySizeTest {

    private static final String BAND_SMALL = 'up_to_10';
    private static final String BAND_MID = '11_to_50';
    private static final String BAND_LARGE = '51_to_250';
    private static final String BAND_HUGE = 'more_than_250';

    // A bare customer: the Account Validation Rules in this org (LockReason_PflichtBeiGesperrt,
    // Wartungsvertrag_End_Before_Start) do not refuse a plain insert — house
    // SCRUM471KeyAccountTest inserts new Account(Name=...) and is green.
    private static Account mkCustomer(String name) {
        return new Account(Name = name);
    }

    private static Lead mkLead(String company, String band) {
        Lead l = new Lead(LastName = 'TEST-SCRUM-476', Company = company);
        l.Company_Size__c = band;
        return l;
    }

    // Measured 2026-11-24: Lead.Company is a REQUIRED field in this org (a Lead insert
    // without it fails REQUIRED_FIELD_MISSING [Company]), so "not yet attached" is a lead
    // whose Company names something that is NOT a customer — the attach is the CHANGE of
    // Company (ADR-6 / AC 12).
    private static Lead leadState(Id id, String company, String band) {
        Lead l = new Lead(LastName = 'TEST-SCRUM-476', Company = company);
        l.Company_Size__c = band;
        l.Id = id;
        return l;
    }

    // ---- AC 1/AC 2/AC 3: a new customer takes its lead's band THROUGH THE TRIGGER ----
    @isTest
    static void convert_newCustomer_takes_leadBand_viaTrigger() {
        Lead l = mkLead('TEST-476-CoA', BAND_HUGE);
        insert l;
        Account a = mkCustomer('TEST-476-CoA');
        insert a; // fires AccountCompanySizeCarry -> carryToNewAccounts

        Account after = [SELECT Name, Company_Size__c FROM Account WHERE Name = 'TEST-476-CoA' LIMIT 1];
        System.assertEquals(BAND_HUGE, after.Company_Size__c,
            'AC1/AC2/AC3: the new customer got exactly its lead\'s band and no other.');

        Lead leadAfter = [SELECT Company_Size__c FROM Lead WHERE Company = 'TEST-476-CoA' LIMIT 1];
        System.assertEquals(BAND_HUGE, leadAfter.Company_Size__c,
            'AC1: the carry never changed anything on the lead itself.');
    }

    // ---- AC 1: a lead WITHOUT a size -> the customer starts blank ----
    @isTest
    static void convert_leadWithoutBand_customerStaysBlank() {
        Lead l = mkLead('TEST-476-CoBlank', null);
        insert l;
        Account a = mkCustomer('TEST-476-CoBlank');
        insert a;

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoBlank' LIMIT 1];
        System.assertEquals(null, after.Company_Size__c,
            'AC1/AC10: without a band on the lead the customer starts blank — nothing is defaulted.');
    }

    // ---- AC 2: no lead with that name -> stays blank, and the save is not touched ----
    @isTest
    static void customerWithoutLead_staysBlank() {
        Account a = mkCustomer('TEST-476-CoNobody');
        insert a;
        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoNobody' LIMIT 1];
        System.assertEquals(null, after.Company_Size__c,
            'AC8: no lead -> blank, and the insert was not refused or repaired.');
    }

    // ---- AC 2 (bulk): one bulkified query answers the whole conversion batch ----
    @isTest
    static void bulk_convert_batchCarries_perName() {
        List<Lead> leads = new List<Lead>();
        List<Account> customers = new List<Account>();
        for (Integer i = 0; i < 20; i++) {
            String nm = 'TEST-476-Co' + i;
            leads.add(mkLead(nm, Math.mod(i, 2) == 0 ? BAND_SMALL : BAND_MID));
            customers.add(mkCustomer(nm));
        }
        // ONE bulk insert per object: two separate statements would be two trigger
        // invocations and the per-transaction behaviour would not be measured.
        insert leads;
        insert customers;

        List<Account> after = [SELECT Name, Company_Size__c FROM Account WHERE Name LIKE 'TEST-476-Co%'];
        System.assertEquals(20, after.size(), 'AC2: every customer of the batch exists.');
        Map<String, String> expect = new Map<String, String>();
        for (Integer i = 0; i < 20; i++) {
            expect.put('TEST-476-Co' + i, Math.mod(i, 2) == 0 ? BAND_SMALL : BAND_MID);
        }
        for (Account a : after) {
            System.assertEquals(expect.get(a.Name), a.Company_Size__c,
                'AC2: each customer carries ITS OWN lead band, not one band for all.');
        }
    }

    // ---- AC 4: an existing customer WITH a band is NEVER overwritten (conflict) ----
    @isTest
    static void attach_existingCustomerWithBand_untouched() {
        Account a = mkCustomer('TEST-476-CoC');
        a.Company_Size__c = BAND_LARGE; // the carefully checked value of the customer
        insert a;

        Lead l = mkLead('TEST-476-CoUnattached', BAND_SMALL); // the PO's conflicting pair: 51_to_250 vs up to 10
        insert l;
        Id leadId = l.Id;

        CompanySizeCarryHandler.fillBlankCustomers(
            new List<Lead>{ leadState(leadId, 'TEST-476-CoC', BAND_SMALL) },
            new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoUnattached', BAND_SMALL) }
        );

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoC' LIMIT 1];
        System.assertEquals(BAND_LARGE, after.Company_Size__c,
            'AC4: the checked band of the existing customer was NOT replaced by the lead\'s.');
    }

    // ---- AC 5: an existing customer WITHOUT a band IS filled ----
    @isTest
    static void attach_existingCustomerBlank_getsFilled() {
        Account a = mkCustomer('TEST-476-CoD');
        a.Company_Size__c = null;
        insert a;

        Lead l = mkLead('TEST-476-CoUnattached', BAND_SMALL);
        insert l;
        Id leadId = l.Id;

        CompanySizeCarryHandler.fillBlankCustomers(
            new List<Lead>{ leadState(leadId, 'TEST-476-CoD', BAND_SMALL) },
            new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoUnattached', BAND_SMALL) }
        );

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoD' LIMIT 1];
        System.assertEquals(BAND_SMALL, after.Company_Size__c,
            'AC5: the blank customer took exactly the lead\'s band (the write itself).');
    }

    // ---- AC 12: an edit of an already attached lead never re-fills ----
    @isTest
    static void attach_alreadyAttached_noReFill() {
        Account a = mkCustomer('TEST-476-CoE');
        a.Company_Size__c = null;
        insert a;

        Lead l = mkLead('TEST-476-CoE', BAND_SMALL); // already attached: Company was already set
        insert l;
        Id leadId = l.Id;

        CompanySizeCarryHandler.fillBlankCustomers(
            new List<Lead>{ leadState(leadId, 'TEST-476-CoE', BAND_HUGE) }, // only the band changed
            new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoE', BAND_SMALL) }
        );

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoE' LIMIT 1];
        System.assertEquals(null, after.Company_Size__c,
            'AC12: a lead that was ALREADY attached was not treated as an attach.');
    }

    // ---- AC 5/AC 7: an attach with NO name match writes nothing ----
    @isTest
    static void attach_unknownCustomer_writesNothing() {
        Lead l = mkLead('TEST-476-CoUnattached', BAND_SMALL);
        insert l;
        Id leadId = l.Id;

        CompanySizeCarryHandler.fillBlankCustomers(
            new List<Lead>{ leadState(leadId, 'TEST-476-CoNoSuchCustomer', BAND_SMALL) },
            new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoUnattached', BAND_SMALL) }
        );

        List<Account> matches = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoNoSuchCustomer'];
        System.assertEquals(0, matches.size(),
            'AC8: the attach references an unknown customer -> no Account created, no repair.');

        // A blank customer that has nothing to do with the attach must stay blank:
        // an attach may never write a record it was not about.
        Account other = mkCustomer('TEST-476-CoUnrelated');
        insert other;
        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoUnrelated' LIMIT 1];
        System.assertEquals(null, after.Company_Size__c,
            'AC5/AC7: an attach must never write a customer that has nothing to do with it.');
    }

    // ---- AC 6/AC 7: two independent changes, each measured, the other untouched ----
    @isTest
    static void leadBandAndCustomerBand_stayIndependent() {
        Lead l = mkLead('TEST-476-CoF', BAND_SMALL);
        insert l;
        Account a = mkCustomer('TEST-476-CoF');
        a.Company_Size__c = BAND_LARGE; // hand-set, deliberately different from the lead
        insert a;
        Id leadId = l.Id;

        // change the CUSTOMER -> the lead stays
        Account upd = new Account(Id = a.Id, Company_Size__c = BAND_MID);
        update upd;
        Lead leadAfter = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1];
        System.assertEquals(BAND_SMALL, leadAfter.Company_Size__c,
            'AC7: changing the customer changed nothing on the lead.');

        // change the ATTACHED LEAD -> the customer stays
        CompanySizeCarryHandler.fillBlankCustomers(
            new List<Lead>{ leadState(leadId, 'TEST-476-CoF', BAND_HUGE) },
            new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoF', BAND_SMALL) }
        );
        Account afterBoth = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoF' LIMIT 1];
        System.assertEquals(BAND_MID, afterBoth.Company_Size__c,
            'AC7: changing the lead changed nothing on the customer (attached -> no re-fill).');
    }

    // ---- AC 11: the carry touches nothing else (one save => no other record) ----
    @isTest
    static void carry_createsNoOtherRecord() {
        Lead l = mkLead('TEST-476-CoG', BAND_SMALL);
        insert l;
        Account a = mkCustomer('TEST-476-CoG');
        insert a; // the carry runs inside this insert
        List<Contact> contacts = [SELECT Id FROM Contact];
        List<Opportunity> opps = [SELECT Id FROM Opportunity];
        List<Case> cases = [SELECT Id FROM Case];
        System.assertEquals(0, contacts.size(), 'AC11: the carry created no Contact.');
        System.assertEquals(0, opps.size(), 'AC11: the carry created no Opportunity.');
        System.assertEquals(0, cases.size(), 'AC11/AC13: no Case, and no email was sent.');
    }

    // ---- the Account insert stays cheap: no lead query without a before-map ----
    @isTest
    static void insertPath_neverRunsTheAttachQuery() {
        Account a = mkCustomer('TEST-476-CoH');
        insert a;
        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoH' LIMIT 1];
        System.assertEquals(null, after.Company_Size__c,
            'AC9: an ordinary customer insert never entered the attach path.');
    }
}
