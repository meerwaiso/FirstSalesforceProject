@isTest
private class SCRUM386LeadDuplicateTest {

    private static String status = 'Open - Not Contacted';

    private static Lead newLead(String name, String email) {
        return new Lead(Name = name, Status = status, Email = email);
    }

    // AC2: existing lead in DB, new insert with same email (other case) -> marked.
    @isTest
    static void ac2_insertMatchesExistingDbLead_caseInsensitive() {
        Lead older = newLead('Max Muster', 'max@beispiel.pde');
        insert older;

        Lead newer = newLead('New Comer', 'MAX@beispiel.pde');
        insert newer;

        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c, Email_Norm__c FROM Lead WHERE Id = :newer.Id];
        System.assertEquals(true, re.Likely_Duplicate__c, 'new lead must be marked');
        System.assertEquals('Max Muster', re.Duplicate_Of__c, 'ref = older lead Name');
        System.assertEquals('max@beispiel.pde', re.Email_Norm__c, 'norm = lower(trim(email))');
    }

    // AC4: no email -> never marked, Email_Norm__c stays null.
    @isTest
    static void ac4_leadsWithoutEmail_neverMarked() {
        Lead a = newLead('No Mail One', null);
        Lead b = newLead('No Mail Two', '   ');
        insert new List<Lead> { a, b };

        List<Lead> re = [SELECT Likely_Duplicate__c, Duplicate_Of__c, Email_Norm__c FROM Lead WHERE Email = null];
        Integer blankCount = [SELECT COUNT() FROM Lead WHERE TRIM(COALESCE(Email, '')) = ''];
        System.assertEquals(blankCount, re.size(), 'sanity: queried all email-blank leads');
        for (Lead l : re) {
            System.assertEquals(false, l.Likely_Duplicate__c, 'no-email lead must never be marked');
            System.assertEquals(null, l.Email_Norm__c, 'no-email lead keeps Email_Norm__c null');
        }
    }

    // AC2 tie-break: two DB leads same email -> reference is the OLDER one.
    @isTest
    static void ac4a_oldestDbLeadIsReference() {
        Lead first = newLead('First In', 'shared@example.pde');
        insert first;
        Lead second = newLead('Second In', 'SHARED@example.pde');
        insert second;

        Lead probe = newLead('Third In', 'shared@EXAMPLE.pde');
        insert probe;

        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(true, re.Likely_Duplicate__c);
        System.assertEquals('First In', re.Duplicate_Of__c, 'oldest CreatedDate wins (Tie-Breaker Id)');
    }

    // ADR-6: only duplicate is a converted lead -> NOT marked, converted lead is never reference.
    @isTest
    static void adr6_convertedLead_neverReference_neverMarked() {
        Lead conv = newLead('Converted Guy', 'conv@example.pde');
        insert conv;
        conv.IsConverted = true;
        update conv;

        Lead probe = newLead('Fresh Guy', 'conv@EXAMPLE.pde');
        insert probe;

        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(false, re.Likely_Duplicate__c, 'converted lead is never a reference');
        System.assertEquals(null, re.Duplicate_Of__c);
    }

    // AC3: update on existing email -> marked.
    @isTest
    static void ac3_updateOnExistingEmail_marksLead() {
        Lead older = newLead('Old Guy', 'old@example.pde');
        insert older;

        Lead probe = newLead('Probe Guy', 'unique@example.pde');
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
        Lead older = newLead('Old Guy', 'old@example.pde');
        insert older;
        Lead probe = newLead('Probe Guy', 'OLD@example.pde');
        insert probe;

        Lead pre = [SELECT Likely_Duplicate__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(true, pre.Likely_Duplicate__c, 'precondition: probe marked');

        probe.Email = 'unique-new@example.pde';
        update probe;

        Lead re = [SELECT Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Id = :probe.Id];
        System.assertEquals(false, re.Likely_Duplicate__c, 'AC3b: unique email clears flag');
        System.assertEquals(null, re.Duplicate_Of__c, 'AC3b: unique email clears reference');
    }

    // AC3b (variant): update to null email -> cleared.
    @isTest
    static void ac3b_updateToNullEmail_clearsMarkers() {
        Lead older = newLead('Old Guy', 'old@example.pde');
        insert older;
        Lead probe = newLead('Probe Guy', 'OLD@example.pde');
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
        // Seed 10 existing DB leads (db-10 through db-19) to act as DB references.
        List<Lead> seed = new List<Lead>();
        for (int i = 0; i < 10; i++) {
            seed.add(newLead('Db Seed ' + i, 'db-' + i + '@seed.pde'));
        }
        insert seed;

        // Build 200 leads in one list:
        //   - leads 0-9:   duplicate of seed 0-9  (DB match)
        //   - leads 10-19:  intra-batch duplicate of lead 0-9 (same email, same batch)
        //   - leads 20-199: unique emails (no match anywhere)
        List<Lead> batch = new List<Lead>();
        for (int i = 0; i < 10; i++) {
            batch.add(newLead('Db Dup ' + i, 'DB-' + i + '@seed.pde'));      // duplicates seed 0-9
            batch.add(newLead('Batch Dup ' + i, 'DB-' + i + '@SEED.pde'));    // same email as above (intra-batch)
        }
        for (int i = 20; i < 200; i++) {
            batch.add(newLead('Unique ' + i, 'unique-' + i + '@example.pde'));
        }
        Integer qBefore = Limits.getQueries();
        insert batch;
        Integer qUsed = Limits.getQueries() - qBefore;
        System.assert(qUsed <= 1, 'AK-T1: max 1 SOQL for whole 200-batch (got ' + qUsed + ')');

        for (int i = 0; i < 10; i++) {
            String norm = 'db-' + i + '@seed.pde';
            String seedName = 'Db Seed ' + i;
            List<Lead> group = [SELECT Name, Likely_Duplicate__c, Duplicate_Of__c FROM Lead WHERE Email_Norm__c = :norm];
            System.assertEquals(3, group.size(), 'seed + two dups per email (' + norm + ')');
            for (Lead g : group) {
                if (g.Name == seedName) {
                    System.assertEquals(false, g.Likely_Duplicate__c, 'oldest seed not marked');
                } else {
                    System.assertEquals(true, g.Likely_Duplicate__c, 'dup of ' + norm + ' marked');
                    System.assertEquals(seedName, g.Duplicate_Of__c, 'ref = oldest DB lead ' + norm);
                }
            }
        }
        Integer markedUnique = [SELECT COUNT() FROM Lead WHERE Likely_Duplicate__c = true AND Email_Norm__c LIKE 'unique-%'];
        System.assertEquals(0, markedUnique, 'unique leads never marked');
    }
}