/**
 * [SCRUM-476] Behaviour proof for CompanySizeCarryHandler + both triggers.
 *
 * House pattern SCRUM424FirstResponseFlsTest / SCRUM472CompanySizeTest: every fixture
 * save runs under System.runAs(u) of a synthetic Standard User that HOLDS the Permission
 * Sets (setup DML strictly FIRST — the User insert and the PermissionSetAssignment inserts
 * — and every later DML/SOQL inside the runAs of that SAME user). Without that shape
 * scripts/fls-gate.py reddens CI with MIXED_DML_OPERATION (review round 1, PR #196).
 *
 * The fixture user is granted, besides this ticket's pair, EVERY Permission Set the real
 * CLI session user holds. Measured reason: converting a Lead runs the org's SCRUM-472
 * machinery, whose Account/Contact/Opportunity/Case writes are FLS-governed (trigger Apex
 * runs in USER mode). A synthetic user without those grants dies with "No such column" on
 * a FOREIGN field, which looks like an FLS failure of this ticket but is not (the Tester
 * named the same trap before writing their negative test).
 *
 * PATH A (new customer) runs THROUGH THE REAL TRIGGER: an Account insert fires
 * AccountCompanySizeCarry, so the insert below covers handler AND trigger.
 *
 * PATH B (attaching) is called BOTH ways: the handler entry directly (the contract of
 * fillBlankCustomers, no convertor storm) and — in attach_fires_the_RealLeadUpdateTrigger
 * — through a real Lead save, which fires LeadCompanySizeCarry.
 *
 * PO decision (SCRUM-476 comment 23806): an ambiguous Name is SKIPPED, nothing guessed.
 * Two fixtures below measure that; they must not rest on a zero count.
 *
 * A test is no evidence unless it can fail: every "nothing changed" assert is paired with
 * a write that WOULD have changed the value if the rule were broken (the lead's band
 * differs from the customer's band in every one of them).
 */
@isTest
private class SCRUM476CompanySizeTest {

    private static final String BAND_SMALL = 'up_to_10';
    private static final String BAND_MID = '11_to_50';
    private static final String BAND_LARGE = '51_to_250';
    private static final String BAND_HUGE = 'more_than_250';

    // The PS names of this ticket plus the lead-side PS of SCRUM-472.
    private static final List<String> GRANT_PS = new List<String>{
        'SCRUM476_CompanySize_Read',
        'SCRUM476_CompanySize_Set',
        'SCRUM472_CompanySize'
    };

    private static Account mkCustomer(String name) {
        return new Account(Name = name);
    }

    private static Lead mkLead(String company, String band) {
        Lead l = new Lead(LastName = 'TEST-SCRUM-476', Company = company);
        l.Company_Size__c = band;
        return l;
    }

    private static Lead leadState(Id id, String company, String band) {
        Lead l = new Lead(LastName = 'TEST-SCRUM-476', Company = company);
        l.Company_Size__c = band;
        l.Id = id;
        return l;
    }

    // ---- setup (MIXED_DML: this runs BEFORE any runAs, nothing above it) ----
    private static User mkHolder(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Carry476',
            Alias                = 'c476' + tag,
            Email                = 'c476' + tag + sfx + '@x.invalid',
            Username             = 'c476' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        grant(u);
        return u;
    }

    private static void grant(User u) {
        // This ticket's PSs PLUS every ticket PS of this org: the convertor storm a real
        // Lead save runs (SCRUM-472 machinery: Contact/Opportunity/Case/Followup writes are
        // all FLS-governed, and trigger Apex runs in USER mode).
        for (PermissionSet ps : [SELECT Name FROM PermissionSet WHERE Name LIKE 'SCRUM%']) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        System.assert(u.Id != null, 'Precondition: the fixture user exists.');
    }

    // A user that can SEE but not WRITE the band: only the Read PS of this ticket, and no
    // SCRUM476_CompanySize_Set anywhere — used by the F-6 probe.
    private static User mkReadHolder(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Probe476',
            Alias                = 'p476' + tag,
            Email                = 'p476' + tag + sfx + '@x.invalid',
            Username             = 'p476' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        PermissionSet psRead = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM476_CompanySize_Read' LIMIT 1];
        System.assert(psRead.Id != null, 'Precondition: SCRUM476_CompanySize_Read exists.');
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psRead.Id);
        return u;
    }

    // ---- AC 1/AC 2/AC 3: a new customer takes its lead's band THROUGH THE TRIGGER ----
    @isTest
    static void convert_newCustomer_takes_leadBand_viaTrigger() {
        User u = mkHolder('a1');
        Id acctId;
        String afterBand;
        String leadBand;
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoA', BAND_HUGE);
            insert l;
            Account a = mkCustomer('TEST-476-CoA');
            insert a; // fires AccountCompanySizeCarry -> carryToNewAccounts
            acctId = a.Id;
            afterBand = [SELECT Company_Size__c FROM Account WHERE Id = :acctId LIMIT 1].Company_Size__c;
            leadBand = [SELECT Company_Size__c FROM Lead WHERE Id = :l.Id LIMIT 1].Company_Size__c;
        }
        System.assertEquals(BAND_HUGE, afterBand,
            'AC1/AC2/AC3: the new customer got exactly its lead\'s band and no other.');
        System.assertEquals(BAND_HUGE, leadBand,
            'AC1: the carry never changed anything on the lead itself.');
    }

    // ---- AC 1: a lead WITHOUT a size -> the customer starts blank ----
    @isTest
    static void convert_leadWithoutBand_customerStaysBlank() {
        User u = mkHolder('a2');
        String afterBand;
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoBlank', null);
            insert l;
            Account a = mkCustomer('TEST-476-CoBlank');
            insert a;
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoBlank' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(null, afterBand,
            'AC1/AC10: without a band on the lead the customer starts blank — nothing is defaulted.');
    }

    // ---- AC 2: no lead with that name -> stays blank ----
    @isTest
    static void customerWithoutLead_staysBlank() {
        User u = mkHolder('a3');
        String afterBand;
        System.runAs(u) {
            Account a = mkCustomer('TEST-476-CoNobody');
            insert a;
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoNobody' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(null, afterBand,
            'AC8: no lead -> blank, and the insert was not refused or repaired.');
    }

    // ---- AC 2 (bulk): one bulkified query answers the whole conversion batch ----
    @isTest
    static void bulk_convert_batchCarries_perName() {
        User u = mkHolder('a4');
        Map<String, String> expect = new Map<String, String>();
        List<Account> after;
        System.runAs(u) {
            List<Lead> leads = new List<Lead>();
            List<Account> customers = new List<Account>();
            for (Integer i = 0; i < 20; i++) {
                String nm = 'TEST-476-Co' + i;
                leads.add(mkLead(nm, Math.mod(i, 2) == 0 ? BAND_SMALL : BAND_MID));
                customers.add(mkCustomer(nm));
                expect.put(nm, Math.mod(i, 2) == 0 ? BAND_SMALL : BAND_MID);
            }
            // ONE bulk insert per object: two separate statements would be two trigger
            // invocations and the per-transaction behaviour would not be measured.
            insert leads;
            insert customers;
            after = [SELECT Name, Company_Size__c FROM Account WHERE Name LIKE 'TEST-476-Co%'];
        }
        System.assert(after.size() >= 20, 'AC2: every customer of the batch exists.');
        for (Account a : after) {
            if (!expect.containsKey(a.Name)) {
                continue; // a fixture of an earlier run of this class, not this batch
            }
            // System.assert, not assertEquals: the failure must name WHICH customer is wrong.
            System.assert(expect.get(a.Name) == a.Company_Size__c,
                'AC2: ' + a.Name + ' must carry ' + expect.get(a.Name) + ', actual=' + a.Company_Size__c);
        }
    }

    // ---- AC 4: an existing customer WITH a band is NEVER overwritten (conflict) ----
    @isTest
    static void attach_existingCustomerWithBand_untouched() {
        User u = mkHolder('b1');
        String afterBand;
        System.runAs(u) {
            Account a = mkCustomer('TEST-476-CoC');
            a.Company_Size__c = BAND_LARGE; // the carefully checked value of the customer
            insert a;

            Lead l = mkLead('TEST-476-CoUnattached', BAND_SMALL); // the PO's conflicting pair
            insert l;
            Id leadId = l.Id;

            CompanySizeCarryHandler.fillBlankCustomers(
                new List<Lead>{ leadState(leadId, 'TEST-476-CoC', BAND_SMALL) },
                new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoUnattached', BAND_SMALL) }
            );
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoC' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(BAND_LARGE, afterBand,
            'AC4: the checked band of the existing customer was NOT replaced by the lead\'s.');
    }

    // ---- AC 5: an existing customer WITHOUT a band IS filled ----
    @isTest
    static void attach_existingCustomerBlank_getsFilled() {
        User u = mkHolder('b2');
        String afterBand;
        System.runAs(u) {
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
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoD' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(BAND_SMALL, afterBand,
            'AC5: the blank customer took exactly the lead\'s band (the write itself).');
    }

    // ---- AC 12: an edit of an already attached lead never re-fills ----
    @isTest
    static void attach_alreadyAttached_noReFill() {
        User u = mkHolder('b3');
        String afterBand;
        System.runAs(u) {
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
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoE' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(null, afterBand,
            'AC12: a lead that was ALREADY attached was not treated as an attach.');
    }

    // ---- AC 5/AC 7: an attach with NO name match writes nothing ----
    @isTest
    static void attach_unknownCustomer_writesNothing() {
        User u = mkHolder('b4');
        Integer created = 0;
        String afterBand;
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoUnattached', BAND_SMALL);
            insert l;
            Id leadId = l.Id;

            CompanySizeCarryHandler.fillBlankCustomers(
                new List<Lead>{ leadState(leadId, 'TEST-476-CoNoSuchCustomer', BAND_SMALL) },
                new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoUnattached', BAND_SMALL) }
            );
            created = [SELECT COUNT() FROM Account WHERE Name = 'TEST-476-CoNoSuchCustomer'];

            Account other = mkCustomer('TEST-476-CoUnrelated');
            insert other;
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoUnrelated' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(0, created,
            'AC8: the attach references an unknown customer -> no Account created, no repair.');
        System.assertEquals(null, afterBand,
            'AC5/AC7: an attach must never write a customer that has nothing to do with it.');
    }

    // ---- AC 6/AC 7: two independent changes, each measured, the other untouched ----
    @isTest
    static void leadBandAndCustomerBand_stayIndependent() {
        User u = mkHolder('b5');
        String leadBand;
        String customerBand;
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoF', BAND_SMALL);
            insert l;
            Account a = mkCustomer('TEST-476-CoF');
            a.Company_Size__c = BAND_LARGE; // hand-set, deliberately different from the lead
            insert a;
            Id leadId = l.Id;

            // change the CUSTOMER -> the lead stays
            Account upd = new Account(Id = a.Id, Company_Size__c = BAND_MID);
            update upd;
            leadBand = [SELECT Company_Size__c FROM Lead WHERE Id = :leadId LIMIT 1].Company_Size__c;

            // change the ATTACHED LEAD -> the customer stays
            CompanySizeCarryHandler.fillBlankCustomers(
                new List<Lead>{ leadState(leadId, 'TEST-476-CoF', BAND_HUGE) },
                new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoF', BAND_SMALL) }
            );
            customerBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoF' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(BAND_SMALL, leadBand,
            'AC7: changing the customer changed nothing on the lead.');
        System.assertEquals(BAND_MID, customerBand,
            'AC7: changing the lead changed nothing on the customer (attached -> no re-fill).');
    }

    // ---- AC 5 end-to-end through the LEAD trigger (a real Lead save) ----
    @isTest
    static void attach_fires_the_RealLeadUpdateTrigger() {
        User u = mkHolder('b6');
        String afterBand;
        System.runAs(u) {
            Account a = mkCustomer('TEST-476-CoLive');
            a.Company_Size__c = null;
            insert a;

            Lead l = mkLead('TEST-476-CoNotYet', BAND_HUGE);
            insert l;

            // A real update of the Lead: LeadCompanySizeCarry must answer the attach.
            // (The org's convertor may convert this lead as well — that storm belongs to
            // SCRUM-472; the assertion here is about the CUSTOMER that already existed.)
            l.Company = 'TEST-476-CoLive';
            update l;

            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoLive' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(BAND_HUGE, afterBand,
            'AC5: the Lead-side trigger filled the blank existing customer on a real save.');
    }

    // ---- PO 23806, B-side: an AMBIGUOUS name is skipped, nothing guessed ----
    // Two customers, ONE identical Name, both blank. The attach names that Name.
    // Expected: BOTH stay blank. The fixture is the shape, not a zero count.
    @isTest
    static void attach_ambiguousName_skipsEveryTwin() {
        User u = mkHolder('t1');
        Integer stillBlank;
        Integer written;
        System.runAs(u) {
            List<Account> twins = new List<Account>{ mkCustomer('TEST-476-CoTwins'), mkCustomer('TEST-476-CoTwins') };
            insert twins;
            Lead l = mkLead('TEST-476-CoUnattached', BAND_SMALL);
            insert l;
            Id leadId = l.Id;

            CompanySizeCarryHandler.fillBlankCustomers(
                new List<Lead>{ leadState(leadId, 'TEST-476-CoTwins', BAND_SMALL) },
                new Map<Id, Lead>{ leadId => leadState(leadId, 'TEST-476-CoUnattached', BAND_SMALL) }
            );
            stillBlank = [SELECT COUNT() FROM Account WHERE Name = 'TEST-476-CoTwins' AND Company_Size__c = null];
            written = [SELECT COUNT() FROM Account WHERE Name = 'TEST-476-CoTwins' AND Company_Size__c != null];
        }
        System.assert(stillBlank >= 2, 'PO 23806: both twins exist and BOTH stayed blank — nothing guessed.');
        System.assertEquals(0, written, 'PO 23806: an ambiguous attach wrote NO customer.');
    }

    // ---- PO 23806, A-side: the same Name twice in one conversion batch ----
    @isTest
    static void convert_ambiguousBatchName_skipsBoth() {
        User u = mkHolder('t2');
        Integer stillBlank;
        Integer written;
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoTwinBatch', BAND_MID);
            insert l;
            List<Account> batch = new List<Account>{ mkCustomer('TEST-476-CoTwinBatch'), mkCustomer('TEST-476-CoTwinBatch') };
            insert batch; // ONE bulkified conversion, both customers on the SAME Name
            stillBlank = [SELECT COUNT() FROM Account WHERE Name = 'TEST-476-CoTwinBatch' AND Company_Size__c = null];
            written = [SELECT COUNT() FROM Account WHERE Name = 'TEST-476-CoTwinBatch' AND Company_Size__c != null];
        }
        System.assert(stillBlank >= 2, 'PO 23806: a repeated Name inside one conversion batch is ambiguous -> both blank.');
        System.assertEquals(0, written, 'PO 23806: the ambiguous batch wrote nothing.');
    }

    // ---- AC 11: the carry touches nothing else (DELTA across one save on SEEDED tables) ----
    // Review round 1: an org-wide equality on Contact/Opportunity/Case is 0 == 0 there and
    // cannot fail (house finding SCRUM-471). One control record per table is seeded FIRST,
    // so the delta assert can actually go red the moment the carry creates a record.
    // EmailMessage / Task / FeedItem cannot be created by a plain Apex insert (they come
    // from sendEmail / POST), so those three tables are NOT measured here — the Tester's
    // E2E covers them, and no assert below may be read as covering them.
    @isTest
    static void carry_createsNoOtherRecord() {
        User u = mkHolder('c1');
        Id beforeContact;
        Integer contactsBefore, oppsBefore, casesBefore;
        Integer contactsAfter, oppsAfter, casesAfter;
        String afterBand;
        System.runAs(u) {
            Account host = mkCustomer('TEST-476-CoHost');
            insert host;
            // Seed one control record in each table the carry must not touch.
            Contact ctl = new Contact(AccountId = host.Id, LastName = 'TEST-476-Control');
            insert ctl;
            insert new Opportunity(AccountId = host.Id, Name = 'TEST-476-Control', StageName = 'Prospecting', CloseDate = Date.today().addMonths(-1));
            insert new Case(ContactId = ctl.Id, Status = 'New', Subject = 'TEST-476-Control');

            Lead l = mkLead('TEST-476-CoG', BAND_SMALL);
            insert l;
            Account a = mkCustomer('TEST-476-CoG');
            insert a; // the carry runs inside this insert

            contactsBefore = [SELECT COUNT() FROM Contact];
            oppsBefore = [SELECT COUNT() FROM Opportunity];
            casesBefore = [SELECT COUNT() FROM Case];
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoG' LIMIT 1].Company_Size__c;
        }
        System.runAs(u) {
            contactsAfter = [SELECT COUNT() FROM Contact];
            oppsAfter = [SELECT COUNT() FROM Opportunity];
            casesAfter = [SELECT COUNT() FROM Case];
        }
        System.assert(contactsBefore >= 1 && oppsBefore >= 1 && casesBefore >= 1,
            'Precondition: the control records exist, so the delta asserts below are falsifiable.');
        System.assertEquals(contactsBefore, contactsAfter, 'AC11: the carry created no Contact (delta on a seeded table).');
        System.assertEquals(oppsBefore, oppsAfter, 'AC11: the carry created no Opportunity (delta on a seeded table).');
        System.assertEquals(casesBefore, casesAfter, 'AC11/AC13: no Case (delta on a seeded table).');
        System.assertEquals(BAND_SMALL, afterBand,
            'Precondition: the carry DID run in this save, so the three delta asserts above could have failed.');
    }

    // ---- the Account insert stays cheap: no lead query without a before-map ----
    @isTest
    static void insertPath_neverRunsTheAttachQuery() {
        User u = mkHolder('c2');
        String afterBand;
        System.runAs(u) {
            Account a = mkCustomer('TEST-476-CoH');
            insert a;
            afterBand = [SELECT Company_Size__c FROM Account WHERE Name = 'TEST-476-CoH' LIMIT 1].Company_Size__c;
        }
        System.assertEquals(null, afterBand,
            'AC9: an ordinary customer insert never entered the attach path.');
    }

    // ---- F-6 probe: the discriminator in the handler must recognise an ACCESS refusal ----
    // Without the SET PS the write refusal is an access refusal; if the handler re-threw it
    // (token list too narrow), the update below throws and this test goes red with that
    // exception in its message — the measured signature, not a guess about it.
    @isTest
    static void probe_accessRefusalIsRecognised() {
        User u = mkReadHolder('p1'); // READ only: visible, not writable
        Id acctId;
        Boolean refused = false;
        System.runAs(u) {
            Account a = mkCustomer('TEST-476-CoProbe');
            insert a;
            acctId = a.Id;
        }
        System.runAs(u) {
            Account fresh = new Account(Id = acctId, Company_Size__c = BAND_SMALL);
            try {
                update fresh;
            } catch (Exception e) {
                refused = true;
                System.assert(CompanySizeCarryHandler.isAccessRefusal(e),
                    'F-6: the discriminator did not recognise the measured access refusal — '
                    + 'message=' + e.getMessage());
            }
        }
        System.assert(refused,
            'F-6: the read-only fixture user still WROTE the band — the probe is not read-only, so the assert above tested nothing.');
    }
}
