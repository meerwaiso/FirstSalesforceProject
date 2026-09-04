@isTest
private class SCRUM386LeadDuplicateTest {

    private static String leadStatus = 'Open - Not Contacted';

    private static Lead mkLead(String nm, String em) {
        Lead l = new Lead();
        l.LastName = nm;
        l.Company = 'Acme Test';
        l.Email = em;
        l.Status = leadStatus;
        return l;
    }

    // AC2: existing lead in DB, new insert with same email (other case) -> marked.
    @isTest
    static void ac2_insertMatchesExistingDbLead_caseInsensitive() {
        Lead older = mkLead('Max Muster', 'max@beispiel.pde');
        insert older;
        Lead newer = mkLead('New Comer', 'MAX@beispiel.pde');
        insert newer;
        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c, Email_Norm__c FROM Lead WHERE Id = :newer.Id];
        System.assertEquals(true, re.Likely_Duplicate__c, 'new lead must be marked');
        System.assertEquals('Max Muster', re.Duplicate_Of__c, 'ref = older lead Name');
        System.assertEquals('max@beispiel.pde', re.Email_Norm__c, 'norm = lower(trim(email))');
    }

    // AC4: no email -> never marked, Email_Norm__c stays null.
    @isTest
    static void ac4_leadsWithoutEmail_neverMarked() {
        Lead a = mkLead('No Mail One', null);
        Lead b = mkLead('No Mail Two', '   ');
        insert new List<Lead> { a, b };
        List<Lead> re = [SELECT Likely_Duplicate__c, Duplicate_Of__c, Email_Norm__c FROM Lead WHERE Id IN :new Set<Id>{a.Id, b.Id}];
        System.assertEquals(2, re.size(), 'safetycheck - both no-email leads found');
        for (Lead l : re) {
            System.assertEquals(false, l.Likely_Duplicate__c, 'no-email lead must never be marked');
            System.assertEquals(null, l.Email_Norm__c, 'no-email lead keeps Email_Norm__c null');
        }
    }

    // AC2 tie-break: two DB leads same email -> reference is the OLDER one.
    @isTest
    static void ac4a_oldestDbLeadIsReference() {
        Lead first = mkLead('First In', 'shared@example.pde');
        insert first;
        Lead second = mkLead('Second In', 'SHARED@example.pde');
        insert second;
        Lead probe = mkLead('Third In', 'shared@EXAMPLE.pde');
        insert probe;
        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(true, re.Likely_Duplicate__c);
        System.assertEquals('First In', re.Duplicate_Of__c, 'oldest CreatedDate wins');
    }

    // ADR-6: only duplicate is a converted lead -> NOT marked.
    @isTest
    static void adr6_convertedLead_neverReference_neverMarked() {
        Lead conv = mkLead('Converted Guy', 'conv@example.pde');
        insert conv;
        // IsConverted is NOT writeable via DML in this org (verified via describe),
        // so set it through a real Lead conversion only.
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(conv.Id);
        lc.setConvertedStatus('Closed - Converted');
        Database.LeadConvertResult res = Database.convertLead(lc);
        System.assert(res.isSuccess(), 'Lead conversion must succeed');
        Lead probe = mkLead('Fresh Guy', 'conv@EXAMPLE.pde');
        insert probe;
        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(false, re.Likely_Duplicate__c, 'converted lead is never a reference');
        System.assertEquals(null, re.Duplicate_Of__c);
    }

    // AC3: update on existing email -> marked.
    @isTest
    static void ac3_updateOnExistingEmail_marksLead() {
        Lead older = mkLead('Old Guy', 'old@example.pde');
        insert older;
        Lead probe = mkLead('Probe Guy', 'unique@example.pde');
        insert probe;
        probe.Email = 'OLD@example.pde';
        update probe;
        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(true, re.Likely_Duplicate__c, 'update to existing email must mark');
        System.assertEquals('Old Guy', re.Duplicate_Of__c);
    }

    // AC3b: update to unique email -> both fields cleared.
    @isTest
    static void ac3b_updateToUniqueEmail_clearsMarkers() {
        Lead older = mkLead('Old Guy2', 'oldq@example.pde');
        insert older;
        Lead probe = mkLead('Probe G2', 'oldq@example.pde');
        insert probe;
        Lead pre = [SELECT Likely_Duplicate__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(true, pre.Likely_Duplicate__c, 'precondition: probe marked');
        probe.Email = 'unique-new2@example.pde';
        update probe;
        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(false, re.Likely_Duplicate__c, 'AC3b: unique email clears flag');
        System.assertEquals(null, re.Duplicate_Of__c, 'AC3b: unique email clears reference');
    }

    // AC3b (variant): update to null email -> cleared.
    @isTest
    static void ac3b_updateToNullEmail_clearsMarkers() {
        Lead older = mkLead('Old Guy3', 'oldr@example.pde');
        insert older;
        Lead probe = mkLead('Probe G3', 'oldr@example.pde');
        insert probe;
        probe.Email = null;
        update probe;
        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c, Email_Norm__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(false, re.Likely_Duplicate__c);
        System.assertEquals(null, re.Duplicate_Of__c);
        System.assertEquals(null, re.Email_Norm__c);
    }

    // AC5: 200 new leads in one insert; some duplicates against existing DB, some intra-batch.
    @isTest
    static void ac5_bulk200_correctMarking_includingIntraBatchDuplicates() {
        List<Lead> seed = new List<Lead>();
        for (Integer i = 0; i < 10; i++) {
            seed.add(mkLead('Db Seed ' + String.valueOf(i), 'db-' + String.valueOf(i) + '@seed.pde'));
        }
        insert seed;
        List<Lead> batch = new List<Lead>();
        for (Integer i = 0; i < 10; i++) {
            batch.add(mkLead('Db Dup ' + String.valueOf(i), 'DB-' + String.valueOf(i) + '@seed.pde'));
            batch.add(mkLead('Batch Dup ' + String.valueOf(i), 'DB-' + String.valueOf(i) + '@SEED.pde'));
        }
        for (Integer i = 20; i < 200; i++) {
            batch.add(mkLead('Unique ' + String.valueOf(i), 'unique-' + String.valueOf(i) + '@example.pde'));
        }
        Integer qBefore = Limits.getQueries();
        insert batch;
        Integer qUsed = Limits.getQueries() - qBefore;
        System.assert(qUsed <= 1, 'AK-T1: max 1 SOQL for whole 200-batch (got ' + String.valueOf(qUsed) + ')');
        for (Integer i = 0; i < 10; i++) {
            String norm = 'db-' + String.valueOf(i) + '@seed.pde';
            String seedName = 'Db Seed ' + String.valueOf(i);
            List<Lead> grp3 = [SELECT Name, Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Email_Norm__c = :norm];
            System.assertEquals(3, grp3.size(), 'seed plus two dups per email ' + norm);
            for (Lead g : grp3) {
                if (g.Name == seedName) {
                    System.assertEquals(false, g.Likely_Duplicate__c, 'oldest seed not marked');
                } else {
                    System.assertEquals(true, g.Likely_Duplicate__c, 'dup of ' + norm + ' marked');
                    System.assertEquals(seedName, g.Duplicate_Of__c, 'ref = oldest DB lead');
                }
            }
        }
    }
}