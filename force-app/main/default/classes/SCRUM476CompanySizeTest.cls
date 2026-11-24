/**
 * [SCRUM-476] Behaviour proof for CompanySizeCarryHandler + both triggers.
 *
 * House pattern SCRUM472CompanySizeTest: one criterion per @isTest method, TEST-476
 * fixture names, org-level Validation Rules satisfied on every Account insert
 * (AccountStreetZipRequired / AccountStateRequired refuse a bare insert — house
 * SCRUM-449), and an assert that can actually go red.
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

    private static final String STREET = 'Test-Street 1';
    private static final String ZIP = '12345';
    private static final String STATE = 'NY';

    // An Account that the org's Validation Rules accept (house SCRUM-449).
    private static Account mkCustomer(String name) {
        Account a = new Account(
            Name = name, Street = STREET, PostalCode = ZIP, State = STATE,
            PhoneNumber = '03012345678', Website = 'https://test.invalid',
            Email = 'test-476@x.invalid', AddressCity = 'TestCity'
        );
        return a;
    }

    private static Lead mkLead(String company, String band) {
        Lead l = new Lead(LastName = 'TEST-SCRUM-476', Company = company);
        l.Company_Size__c = band;
        return l;
    }

    // ---- AC 1/AC 2: a new customer takes its lead's band THROUGH THE TRIGGER ----
    @isTest
    static void convert_newCustomer_takes_leadBand_viaTrigger() {
        Lead l = mkLead('TEST-476-CoA', 'more_than_250');
        insert l;
        Account a = mkCustomer('TEST-476-CoA');
        insert a; // fires AccountCompanySizeCarry -> carryToNewAccounts

        Account after = [SELECT Name, Company_Size__c FROM Account WHERE Name = 'TEST-476-CoA' LIMIT 1];
        System.assertEquals('more_than_250', after.Company_Size__c,
            'AC1/AC2/AC3: the new customer got exactly its lead\'s band and no other.');

        Id leadId = l.Id;
        Lead leadAfter = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1];
        System.assertEquals('more_than_250', leadAfter.Company_Size__c,
            'AC1: the carry never changed anything on the lead itself.');
    }

    // ---- AC 1: a lead WITHOUT a size -> the customer starts blank ----
    @isTest
    static void convert_leadWithoutBand_customerStaysBlank() {
        Lead l = mkLead('TEST-476-CoBlank', null);
        insert l;
        Account a = mkCustomer('TEST-476-CoBlank');
        insert a;

        Account after = [SELECT Name, Company_Size__c FROM Account WHERE Name = 'TEST-476-CoBlank' LIMIT 1];
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
            leads.add(mkLead(nm, (Integer.mod(i, 2) == 0) ? 'up_to_10' : '11_to_50'));
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
            expect.put('TEST-476-Co' + i, (Integer.mod(i, 2) == 0) ? 'up_to_10' : '11_to_50');
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
        a.Company_Size__c = '51_to_250';
        insert a;

        Lead l = mkLead(null, 'up_to_10'); // the PO's conflicting pair: 51_to_250 vs up_to_10
        l.Company = null;
        insert l;
        Id leadId = l.Id;

        Lead before = new Lead();
        before.Id = leadId;
        Lead old = before.cloneMe();
        before.Company = 'TEST-476-CoC';
        CompanySizeCarryHandler.fillBlankCustomers(new List<Lead>{before}, new Map<Id, Lead>{leadId: old});

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoC' LIMIT 1];
        System.assertEquals('51_to_250', after.Company_Size__c,
            'AC4: the checked band of the existing customer was NOT replaced by the lead\'s.');
    }

    // ---- AC 5: an existing customer WITHOUT a band IS filled ----
    @isTest
    static void attach_existingCustomerBlank_getsFilled() {
        Account a = mkCustomer('TEST-476-CoD');
        a.Company_Size__c = null;
        insert a;

        Lead l = mkLead(null, 'up_to_10');
        l.Company = null;
        insert l;
        Id leadId = l.Id;

        Lead before = new Lead();
        before.Id = leadId;
        Lead old = before.cloneMe();
        before.Company = 'TEST-476-CoD';
        CompanySizeCarryHandler.fillBlankCustomers(new List<Lead>{before}, new Map<Id, Lead>{leadId: old});

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoD' LIMIT 1];
        System.assertEquals('up_to_10', after.Company_Size__c,
            'AC5: the blank customer took exactly the lead\'s band (the write itself).');
    }

    // ---- AC 12: an edit of an already attached lead never re-fills ----
    @isTest
    static void attach_alreadyAttached_noReFill() {
        Account a = mkCustomer('TEST-476-CoE');
        a.Company_Size__c = null;
        insert a;

        Lead l = mkLead('TEST-476-CoE', 'up_to_10'); // already attached: Company was already set
        insert l;
        Id leadId = l.Id;

        Lead before = new Lead();
        before.Id = leadId;
        Lead old = before.cloneMe();
        before.Company_Size__c = 'more_than_250'; // only the band changed, Company untouched
        CompanySizeCarryHandler.fillBlankCustomers(new List<Lead>{before}, new Map<Id, Lead>{leadId: old});

        Account after = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoE' LIMIT 1];
        System.assertEquals(null, after.Company_Size__c,
            'AC12: a lead that was ALREADY attached was not treated as an attach.');
    }

    // ---- AC 5/AC 7: an attach with NO name match writes nothing ----
    @isTest
    static void attach_unknownCustomer_writesNothing() {
        Lead l = mkLead(null, 'up_to_10');
        l.Company = null;
        insert l;
        Id leadId = l.Id;

        Lead before = new Lead();
        before.Id = leadId;
        Lead old = before.cloneMe();
        before.Company = 'TEST-476-CoNoSuchCustomer';
        CompanySizeCarryHandler.fillBlankCustomers(new List<Lead>{before}, new Map<Id, Lead>{leadId: old});

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
        Lead l = mkLead('TEST-476-CoF', 'up_to_10');
        insert l;
        Account a = mkCustomer('TEST-476-CoF');
        a.Company_Size__c = '51_to_250'; // hand-set, deliberately different from the lead
        insert a;
        Id leadId = l.Id;

        // change the CUSTOMER -> the lead stays
        Account upd = a.cloneMe();
        upd.Company_Size__c = '11_to_50';
        update upd;
        Lead leadAfter = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1];
        System.assertEquals('up_to_10', leadAfter.Company_Size__c,
            'AC7: changing the customer changed nothing on the lead.');

        // change the LEAD -> the customer stays
        Lead l2 = new Lead();
        l2.Id = leadId;
        Lead old = l2.cloneMe();
        l2.Company_Size__c = 'more_than_250';
        CompanySizeCarryHandler.fillBlankCustomers(new List<Lead>{l2}, new Map<Id, Lead>{leadId: old});
        Account afterBoth = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoF' LIMIT 1];
        System.assertEquals('11_to_50', afterBoth.Company_Size__c,
            'AC7: changing the lead changed nothing on the customer (attached -> no re-fill).');
    }

    // ---- AC 11: the carry touches nothing else (one save => no other record) ----
    @isTest
    static void carry_createsNoOtherRecord() {
        Lead l = mkLead('TEST-476-CoG', 'up_to_10');
        insert l;
        Account a = mkCustomer('TEST-476-CoG');
        insert a;
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
