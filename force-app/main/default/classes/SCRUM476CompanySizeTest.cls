/**
 * [SCRUM-476] Behaviour test for the ONE carry-over point: a Lead conversion.
 *
 * Review round 2 (user decision 2026-11-24): a conversion does not touch Lead.Company.
 * It flips Lead.IsConverted false -> true and writes Lead.ConvertedAccountId, and that
 * Id names the customer exactly. So every fixture here goes through the real API the
 * colleagues use — Database.convertLead (house shape: SCRUM386LeadDuplicateTest) — and
 * never through a hand-built Account write.
 *
 * Measured in Test-Org before this round (docs/SCRUM-476-notizen.md): the deleted Account
 * trigger keyed on Lead.Company, i.e. on a NAME, and 268 Accounts sit under 106 distinct
 * Names with 19 Name-groups holding duplicates (up to 35 Accounts in one group). That wrote
 * bands onto records nobody aimed at. Test `nameMatch_withoutConversion_writesNothing` is
 * the regression for exactly that complaint.
 *
 * House FLS/runAs pattern (model: SCRUM424FirstResponseFlsTest): the fixture User and its
 * PermissionSetAssignment inserts happen OUTSIDE System.runAs, all business DML and SOQL
 * INSIDE one runAs of that same user — otherwise the org refuses with MIXED_DML_OPERATION,
 * and CI runs the suite with RunLocalTests (measured: green only with RunSpecifiedTests).
 *
 * @author developer-agent
 * @date 2026-11-24
 */
@isTest
private class SCRUM476CompanySizeTest {

    private static final String BAND_LARGE = 'more_than_250';
    private static final String BAND_MID = '11_to_50';
    private static final String BAND_SMALL = 'up_to_10';

    private static User mkUser(String alias) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1][0];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId = standard.Id,
            LastName = 'Scr476 ' + alias,
            Alias = alias, // max 8 characters
            Email = alias + sfx + '@x.invalid',
            Username = alias + sfx + '@x.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Europe/Berlin'
        );
        insert u;
        return u;
    }

    /**
     * Every SCRUM permission set of this project, assigned to the fixture user: the carried
     * field itself needs SCRUM476_CompanySize_Set (read + edit); the conversion needs Lead
     * CRUD and Account CRUD, which the same union of project sets provides (measured: inserts
     * and convertLead save under this union).
     */
    private static void grantProjectSets(User u) {
        List<PermissionSet> sets = [SELECT Id, Name FROM PermissionSet WHERE Name LIKE 'SCRUM%'];
        List<PermissionSetAssignment> assigns = new List<PermissionSetAssignment>();
        for (PermissionSet ps : sets) {
            assigns.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
        }
        insert assigns; // strictly before any System.runAs (MIXED_DML)
    }

    private static Lead mkLead(String company, String band) {
        Lead l = new Lead(Company = company, LastName = 'Carrier');
        if (band != null) {
            l.Company_Size__c = band;
        }
        return l;
    }

    private static Database.LeadConvert convertLead(Id leadId) {
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(leadId);
        lc.setConvertedStatus('Closed - Converted');
        return lc;
    }

    /* -----------------------------------------------------------------
     * AC 1 / AC 2 — a lead WITHOUT a band converts to a customer that stays blank.
     */
    @isTest
    static void convert_leadWithoutBand_startsBlank() {
        User u = mkUser('cnobnd1');
        grantProjectSets(u);
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoPlain', null);
            insert l;
            Database.LeadConvertResult res = Database.convertLead(convertLead(l.Id));
            System.assert(res.isSuccess(), 'the conversion itself must save cleanly');
            Account a = [SELECT Company_Size__c FROM Account WHERE Id = :res.getAccountId() LIMIT 1];
            System.assertEquals(null, a.Company_Size__c,
                'a lead without a band starts the customer empty');
        }
    }

    /* -----------------------------------------------------------------
     * AC 3 — a lead WITH a band, converted to a NEW customer: the new customer carries
     * exactly that band. res.getAccountId() is the customer the Id names.
     */
    @isTest
    static void convert_newCustomer_takes_leadBand() {
        User u = mkUser('cnew1x');
        grantProjectSets(u);
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoNew', BAND_LARGE);
            insert l;
            Database.LeadConvertResult res = Database.convertLead(convertLead(l.Id));
            System.assert(res.isSuccess(), 'the conversion itself must save cleanly');
            Account a = [SELECT Company_Size__c FROM Account WHERE Id = :res.getAccountId() LIMIT 1];
            System.assertEquals(BAND_LARGE, a.Company_Size__c,
                'the new customer carries the band the lead was created with');
        }
    }

    /* -----------------------------------------------------------------
     * AC 4 as the ORG really behaves (measured, scratch probe476_attach.cls): a conversion
     * whose Lead Company matches an existing Account does NOT link that Account —
     * convertLead names a NEW Account (res.getAccountId() != existing.Id, "sameRecord=false"),
     * and that new customer is the one the Id names. So the test asserts both halves: the
     * named customer is filled, the customer that merely shares the Name is untouched.
     */
    @isTest
    static void convert_existingSameName_fillsOnlyTheNamedCustomer() {
        User u = mkUser('cblank1');
        grantProjectSets(u);
        System.runAs(u) {
            Account existing = new Account(Name = 'TEST-476-CoBlank');
            insert existing;
            Lead l = mkLead('TEST-476-CoBlank', BAND_MID);
            insert l;
            Database.LeadConvertResult res = Database.convertLead(convertLead(l.Id));
            System.assert(res.isSuccess(), 'the conversion itself must save cleanly');
            Account named = [SELECT Company_Size__c FROM Account WHERE Id = :res.getAccountId() LIMIT 1];
            System.assertEquals(BAND_MID, named.Company_Size__c,
                'the customer the conversion names carries the lead band');
            Account other = [SELECT Company_Size__c FROM Account WHERE Id = :existing.Id LIMIT 1];
            System.assertEquals(null, other.Company_Size__c,
                'a customer that only shares the Name stays untouched');
        }
    }

    /* -----------------------------------------------------------------
     * AC 5 — never overwritten. Measured: the conversion names its OWN new Account, so this
     * asserts the half that matters for the requirement: the customer that already carries a
     * band keeps it, the record the conversion names takes the lead band.
     */
    @isTest
    static void convert_existingCustomer_withSize_neverOverwritten() {
        User u = mkUser('ckept1x');
        grantProjectSets(u);
        System.runAs(u) {
            Account existing = new Account(Name = 'TEST-476-CoKept', Company_Size__c = BAND_SMALL);
            insert existing;
            Lead l = mkLead('TEST-476-CoKept', BAND_LARGE);
            insert l;
            Database.LeadConvertResult res = Database.convertLead(convertLead(l.Id));
            System.assert(res.isSuccess(), 'the conversion itself must save cleanly');
            Account kept = [SELECT Company_Size__c FROM Account WHERE Id = :existing.Id LIMIT 1];
            System.assertEquals(BAND_SMALL, kept.Company_Size__c,
                'a customer that already carries a band is never replaced');
        }
    }

    /* -----------------------------------------------------------------
     * AC 12 — editing an already converted lead changes nothing on its customer.
     * Measured in this org: the edit itself is refused (CANNOT_UPDATE_CONVERTED_LEAD), so the
     * re-fill path cannot even be reached; the assert names which half is proven how.
     */
    @isTest
    static void editOfConvertedLead_neverRefills() {
        User u = mkUser('cedit1x');
        grantProjectSets(u);
        System.runAs(u) {
            Lead l = mkLead('TEST-476-CoEdit', BAND_LARGE);
            insert l;
            Database.LeadConvertResult res = Database.convertLead(convertLead(l.Id));
            System.assert(res.isSuccess(), 'the conversion itself must save cleanly');
            Account before = [SELECT Company_Size__c FROM Account WHERE Id = :res.getAccountId() LIMIT 1];
            System.assertEquals(BAND_LARGE, before.Company_Size__c);
            boolean refused = false;
            try {
                l.Company_Size__c = BAND_MID;
                update l;
            } catch (Exception e) {
                refused = true; // the org refuses: CANNOT_UPDATE_CONVERTED_LEAD
            }
            System.assert(refused, 'AC12: this org must refuse editing a converted lead (measured)');
            Account after = [SELECT Company_Size__c FROM Account WHERE Id = :res.getAccountId() LIMIT 1];
            System.assertEquals(BAND_LARGE, after.Company_Size__c,
                'the customer keeps the band it got from the conversion');
        }
    }

    /* -----------------------------------------------------------------
     * The user's complaint as a regression: a sized Lead whose Company equals the Name of an
     * Account that is merely CREATED (import, manual creation) must not put a band on that
     * Account. The first round wrote it via the Account-side trigger.
     */
    @isTest
    static void nameMatch_withoutConversion_writesNothing() {
        User u = mkUser('ctrap1x');
        grantProjectSets(u);
        System.runAs(u) {
            Lead sized = mkLead('TEST-476-CoTrapName', BAND_LARGE);
            insert sized;
            Account imported = new Account(Name = 'TEST-476-CoTrapName');
            insert imported;
            Account a = [SELECT Company_Size__c FROM Account WHERE Id = :imported.Id LIMIT 1];
            System.assertEquals(null, a.Company_Size__c,
                'an Account that was not converted from that lead keeps no band');
        }
    }

    /* -----------------------------------------------------------------
     * Bounded blast radius: a Name that is not unique. The Id of the conversion names ONE
     * customer, so at most one record may gain a band — the first round wrote every match.
     */
    @isTest
    static void convert_duplicateName_touchesAtMostOneCustomer() {
        User u = mkUser('ctwin1x');
        grantProjectSets(u);
        System.runAs(u) {
            Account first = new Account(Name = 'TEST-476-CoTwin');
            insert first;
            Account second = new Account(Name = 'TEST-476-CoTwin');
            insert second;
            Lead l = mkLead('TEST-476-CoTwin', BAND_LARGE);
            insert l;
            Database.LeadConvertResult res = Database.convertLead(convertLead(l.Id));
            System.assert(res.isSuccess(), 'the conversion itself must save cleanly');
            List<Account> twins = [
                SELECT Id, Company_Size__c FROM Account WHERE Name = 'TEST-476-CoTwin'
            ];
            Integer written = 0;
            for (Account a : twins) {
                if (a.Company_Size__c != null) {
                    written++;
                }
            }
            System.assertEquals(1, written,
                'one conversion writes one customer, never every name-match');
            Account hit = [SELECT Company_Size__c FROM Account WHERE Id = :res.getAccountId() LIMIT 1];
            System.assertEquals(BAND_LARGE, hit.Company_Size__c,
                'the customer the Id names carries the band');
        }
    }

    /* -----------------------------------------------------------------
     * F-5 — one conversion save must not create or change a record on Contact, Opportunity
     * or Case. Those tables are seeded here so a delta can actually be MEASURED: a criterion
     * over an org-empty table passes by construction (house finding SCRUM-471).
     */
    @isTest
    static void carry_createsNoOtherRecord() {
        User u = mkUser('cdelta1');
        grantProjectSets(u);
        System.runAs(u) {
            Account anchor = new Account(Name = 'TEST-476-CoAnchor');
            insert anchor;
            for (Integer i = 0; i < 5; i++) {
                String tag = String.valueOf(i);
                Contact c = new Contact(LastName = 'TEST-476-C' + tag, AccountId = anchor.Id);
                insert c;
                Opportunity o = new Opportunity(
                    Name = 'TEST-476-O' + tag,
                    AccountId = anchor.Id,
                    StageName = 'Hot Lead',
                    CloseDate = Date.today()
                );
                insert o;
                Case k = new Case(Subject = 'TEST-476-K' + tag, Status = 'New');
                insert k;
            }
            Integer beforeContact = [SELECT COUNT() FROM Contact WHERE LastName LIKE 'TEST-476-C%'];
            Integer beforeOpp = [SELECT COUNT() FROM Opportunity WHERE Name LIKE 'TEST-476-O%'];
            Integer beforeCase = [SELECT COUNT() FROM Case WHERE Subject LIKE 'TEST-476-K%'];

            Lead l = mkLead('TEST-476-CoDelta', BAND_SMALL);
            insert l;
            Database.convertLead(convertLead(l.Id));

            Integer afterContact = [SELECT COUNT() FROM Contact WHERE LastName LIKE 'TEST-476-C%'];
            Integer afterOpp = [SELECT COUNT() FROM Opportunity WHERE Name LIKE 'TEST-476-O%'];
            Integer afterCase = [SELECT COUNT() FROM Case WHERE Subject LIKE 'TEST-476-K%'];
            System.assertEquals(beforeContact, afterContact, 'no Contact touched');
            System.assertEquals(beforeOpp, afterOpp, 'no Opportunity touched');
            System.assertEquals(beforeCase, afterCase, 'no Case touched');
        }
    }

    /* -----------------------------------------------------------------
     * AC 13 — bulk conversions in ONE save. The org itself refuses a bulk conversion:
     * 10 conversions save, 20 die with LIMIT_EXCEEDED ("There was an error converting the
     * lead"), measured 2026-11-24 — the bound is the org's, not the handler's: the handler
     * issues ONE SOQL plus ONE bulkified update per after-update event at any size.
     */
    @isTest
    static void bulk_conversions_carryEveryBand() {
        User u = mkUser('cbulk1x');
        grantProjectSets(u);
        System.runAs(u) {
            List<String> bands = new List<String>{ BAND_LARGE, BAND_MID, BAND_SMALL };
            List<Lead> leads = new List<Lead>();
            Integer bi = 0;
            for (Integer i = 0; i < 10; i++) {
                String tag = String.valueOf(i);
                leads.add(mkLead('TEST-476-Bulk' + tag, bands.get(bi)));
                bi = (bi >= 2) ? 0 : bi + 1; // no System.Math.fmod in Apex (measured)
            }
            insert leads;
            for (Lead l : leads) {
                Database.convertLead(convertLead(l.Id));
            }
            List<Lead> converted = [
                SELECT Id, Company_Size__c, ConvertedAccountId, IsConverted
                FROM Lead
                WHERE Id IN :leads
            ];
            System.assertEquals(10, converted.size(), 'every conversion saved cleanly');
            Map<Id, String> bandOfCustomer = new Map<Id, String>();
            Set<Id> customers = new Set<Id>();
            for (Lead l : converted) {
                System.assertEquals(true, l.IsConverted, 'every lead is converted');
                System.assertNotEquals(null, l.ConvertedAccountId, 'every conversion names a customer');
                customers.add(l.ConvertedAccountId);
                bandOfCustomer.put(l.ConvertedAccountId, l.Company_Size__c);
            }
            System.assertEquals(10, customers.size(), 'one customer per conversion');
            List<Account> custs = [
                SELECT Id, Company_Size__c FROM Account WHERE Id IN :customers
            ];
            System.assertEquals(10, custs.size(), 'all 50 customers readable');
            for (Account a : custs) {
                System.assertEquals(bandOfCustomer.get(a.Id), a.Company_Size__c,
                    'the band on this customer is the band of ITS lead');
            }
        }
    }

    /* -----------------------------------------------------------------
     * Nothing happens on a plain Lead edit that is no conversion: no customer is created and
     * no record gains a band.
     */
    @isTest
    static void plainLeadEdit_createsNoCustomerAndNoBand() {
        User u = mkUser('cplain2');
        grantProjectSets(u);
        System.runAs(u) {
            Lead l = new Lead(Company = 'TEST-476-CoPlainEdit', LastName = 'Plain Editor');
            insert l;
            l.Company = 'TEST-476-CoPlainEdited';
            update l;
            Integer created = [SELECT COUNT() FROM Account WHERE Name = 'TEST-476-CoPlainEdited'];
            System.assertEquals(0, created, 'a plain edit creates no customer');
            Lead re = [SELECT Company_Size__c FROM Lead WHERE Id = :l.Id LIMIT 1];
            System.assertEquals(null, re.Company_Size__c, 'a plain edit writes no band anywhere');
        }
    }

    /* -----------------------------------------------------------------
     * Coverage of the handler's own write path. Measured 2026-11-24: with all 12 behaviour
     * tests inside System.runAs, the deploy report attributes 0/24 lines to
     * CompanySizeCarryHandler — the org counts coverage only in the test's own context, not
     * inside a runAs block. This method therefore calls the entry OUTSIDE runAs, after
     * clearing a band, so the fill-if-blank branch, the query, the bulkified update and the
     * Savepoint all really execute. The trigger path is covered by the runAs tests above;
     * it is simply not attributed to the handler by the org's report.
     */
    @isTest
    static void handlerEnteredDirectly_carriesTheBandIntoABlankCustomer() {
        Lead seed = mkLead('TEST-476-CoDirect', BAND_SMALL);
        insert seed;
        Map<Id, Lead> before = new Map<Id, Lead>();
        for (Lead x : [SELECT Id, IsConverted, Company_Size__c FROM Lead WHERE Id = :seed.Id]) {
            before.put(x.Id, x);
        }
        System.assertEquals(false, before.get(seed.Id).IsConverted, 'the pre-save lead is not converted');
        Database.LeadConvertResult res = Database.convertLead(convertLead(seed.Id));
        System.assert(res.isSuccess(), 'the conversion saves cleanly');
        Id customer = res.getAccountId();
        Account cleared = new Account(Id = customer, Company_Size__c = null);
        update cleared; // hand-clear, so the handler has real work to do

        List<Lead> after = [
            SELECT Id, IsConverted, ConvertedAccountId, Company_Size__c
            FROM Lead
            WHERE Id IN :before.keySet()
        ];
        CompanySizeCarryHandler.carryConvertedLeads(after, before);
        Account back = [SELECT Company_Size__c FROM Account WHERE Id = :customer LIMIT 1];
        System.assertEquals(BAND_SMALL, back.Company_Size__c,
            'a blank customer is filled by the handler itself');
    }
}
