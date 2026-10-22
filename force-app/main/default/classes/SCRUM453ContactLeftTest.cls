/**
 * [SCRUM-453] Functional tests of the Austritt mark (AC-1, AC-2, AC-3, AC-5, AC-8, AC-9).
 *
 * House shape: SCRUM416OpenOpportunityRollupTest (bulk recompute, governor-limit
 * counters) + SCRUM359NewsletterConsentFlsTest (consent fields).
 *
 * AC -> method:
 *   AC-1  mark + record intact ................ mark_setsDateDefault_consentUntouched
 *   AC-2  date defaults to the day, correctable mark_setsDateDefault + dateCorrectableLater
 *   AC-3  history stays reachable ............. historyStaysReachable_afterMarking
 *   AC-5  consent untouched by the mark ....... asserted in AC-1/AC-3/AC-9 methods
 *   AC-4  derived display ..................... asserted in AC-1
 *   AC-7  visible on the Case (functional) .... historyStaysReachable_afterMarking
 *   AC-8  aggregates for the overview ......... partialMark / allMarked / bulk / reParenting
 *   AC-9  nothing automatic ................... nothingAutomatic_noSideEffects
 *   AC-6  undo gate ........................... SCRUM453ContactLeftFlsTest (the security half)
 *
 * MIXED_DML (house SCRUM-442/432): fixture DML first, one context; no runAs here —
 * the FLS half lives in SCRUM453ContactLeftFlsTest.
 *
 * Fixtures are NON-ZERO on the AC-8 criterion: allMarked_customerWithoutContactPerson
 * and bulk_marking_staysWithinLimits leave Accounts with Contacts_Without_Mark__c = 0
 * and Contacts_Left_Count__c > 0, i.e. the overview matches at least one row.
 */
@isTest
private class SCRUM453ContactLeftTest {

    private static final String MARKED = 'Austritt - not there any more';
    private static final Date PAST_CONSENT = Date.today().addMonths(-6);
    private static final Date LEFT_WHEN = Date.today().addMonths(-3);

    private static Id newAccount(String tag) {
        Account a = new Account(Name = 'V453 ' + tag);
        insert a;
        return a.Id;
    }

    /** A Contact that once gave newsletter consent — AC-5 must never touch that. */
    private static Id newContact(String tag, Id accId) {
        Contact c = new Contact(LastName = tag, CompanyName = 'V453 GmbH',
                                AccountId = accId,
                                NewsletterConsent__c = true, ConsentDate__c = PAST_CONSENT);
        insert c;
        return c.Id;
    }

    private static Contact contact(Id id) {
        List<Contact> l = [SELECT Id, Has_Left_Company__c, Left_Company_Date__c,
                                  Contact_Status_Anzeige__c, NewsletterConsent__c, ConsentDate__c
                           FROM Contact WHERE Id = :id LIMIT 1];
        return l.isEmpty() ? null : l[0];
    }

    private static Account aggregates(Id accId) {
        List<Account> l = [SELECT Id, Contacts_Without_Mark__c, Contacts_Left_Count__c,
                                  Last_Contact_Left_Date__c
                           FROM Account WHERE Id = :accId LIMIT 1];
        return l.isEmpty() ? null : l[0];
    }

    // ---------- AC-1 + AC-2 + AC-4 + AC-5 ----------
    @isTest
    static void mark_setsDateDefault_consentUntouched() {
        Id accId = newAccount('Mark');
        Id cId = newContact('AC1', accId);

        Contact rec = contact(cId);
        System.assertEquals(true, rec.NewsletterConsent__c, 'fixture: consent set');
        System.assertEquals(PAST_CONSENT, rec.ConsentDate__c, 'fixture: consent date set');
        System.assertEquals('Active', rec.Contact_Status_Anzeige__c, 'AC-4: unmarked reads Active');

        rec.Has_Left_Company__c = true;
        update rec;

        Contact after = contact(cId);
        System.assert(after != null, 'AC-1: the Contact record is still there (never deleted)');
        System.assertEquals(true, after.Has_Left_Company__c, 'AC-1: the mark is set');
        System.assertEquals(Date.today(), after.Left_Company_Date__c,
            'AC-2: no date given -> the day of marking is used');
        System.assertEquals(MARKED, after.Contact_Status_Anzeige__c, 'AC-4: the display follows the mark');
        System.assertEquals(true, after.NewsletterConsent__c,
            'AC-5: the consent itself was NOT changed');
        System.assertEquals(PAST_CONSENT, after.ConsentDate__c,
            'AC-5: the consent date was NOT cleared or changed');

        Account acc = aggregates(accId);
        System.assertEquals(Decimal.valueOf(1), acc.Contacts_Left_Count__c, 'AC-8: one marked');
        System.assertEquals(Decimal.valueOf(0), acc.Contacts_Without_Mark__c, 'AC-8: none left unmarked');
        System.assertEquals(Date.today(), acc.Last_Contact_Left_Date__c, 'AC-8: the leaving date');
    }

    // ---------- AC-2: an exact date is kept, and correctable later ----------
    @isTest
    static void dateCorrectableLater() {
        Id accId = newAccount('DateFix');
        Id cId = newContact('AC2', accId);

        Contact rec = contact(cId);
        rec.Has_Left_Company__c = true;
        rec.Left_Company_Date__c = LEFT_WHEN;
        update rec;
        Contact kept = contact(cId);
        System.assertEquals(LEFT_WHEN, kept.Left_Company_Date__c,
            'AC-2: an exact date given by the user is kept, not overwritten by today');

        kept.Left_Company_Date__c = LEFT_WHEN.addMonths(-1);
        update kept;
        Contact fixed = contact(cId);
        System.assertEquals(LEFT_WHEN.addMonths(-1), fixed.Left_Company_Date__c,
            'AC-2: the date is correctable later');
        System.assertEquals(LEFT_WHEN.addMonths(-1), aggregates(accId).Last_Contact_Left_Date__c,
            'AC-8: the Account aggregate follows the corrected date');
    }

    // ---------- AC-8 partial: a customer with SOME contacts left ----------
    @isTest
    static void partialMark_customerStillHasContacts() {
        Id accId = newAccount('Partial');
        Id c1 = newContact('P1', accId);
        Id c2 = newContact('P2', accId);
        Id c3 = newContact('P3', accId);

        Contact rec = contact(c1);
        rec.Has_Left_Company__c = true;
        rec.Left_Company_Date__c = LEFT_WHEN;
        update rec;

        Account acc = aggregates(accId);
        System.assertEquals(Decimal.valueOf(1), acc.Contacts_Left_Count__c, 'AC-8: 1 marked');
        System.assertEquals(Decimal.valueOf(2), acc.Contacts_Without_Mark__c,
            'AC-8: 2 still there -> this customer is NOT in the overview');
        System.assertEquals(LEFT_WHEN, acc.Last_Contact_Left_Date__c, 'AC-8: the date');
    }

    // ---------- AC-8 exact: the overview row (NON-ZERO fixture) ----------
    @isTest
    static void allMarked_customerWithoutContactPerson() {
        Id accId = newAccount('AllLeft');
        Id c1 = newContact('A1', accId);
        Id c2 = newContact('A2', accId);
        Id c3 = newContact('A3', accId);

        List<Contact> marked = new List<Contact>{ contact(c1), contact(c2), contact(c3) };
        for (Integer i = 0; i < marked.size(); i++) {
            marked[i].Has_Left_Company__c = true;
            marked[i].Left_Company_Date__c = LEFT_WHEN.addMonths(i);
        }
        update marked;

        Account acc = aggregates(accId);
        System.assertEquals(Decimal.valueOf(3), acc.Contacts_Left_Count__c, 'AC-8: all 3 marked');
        System.assertEquals(Decimal.valueOf(0), acc.Contacts_Without_Mark__c,
            'AC-8: filter row (Contacts_Without_Mark__c = 0 AND Contacts_Left_Count__c > 0)');
        System.assertEquals(LEFT_WHEN.addMonths(2), acc.Last_Contact_Left_Date__c,
            'AC-8: the NEWEST leaving date, oldest-first sorting basis');
    }

    // ---------- AC-3 + AC-7: history stays reachable, Case shows the mark ----------
    @isTest
    static void historyStaysReachable_afterMarking() {
        Id accId = newAccount('History');
        Id cId = newContact('AC3', accId);
        Case cs = new Case(Status = 'Open', Subject = 'V453 old case', AccountId = accId, ContactId = cId);
        insert cs;

        Contact rec = contact(cId);
        rec.Has_Left_Company__c = true;
        rec.Left_Company_Date__c = LEFT_WHEN;
        update rec;

        List<Case> cases = [SELECT Id, Subject, ContactId, AccountId, Contact_Left_Anzeige__c
                            FROM Case WHERE Id = :cs LIMIT 1];
        System.assertEquals(1, cases.size(), 'AC-3: the old Case is still reachable');
        Case after = cases[0];
        System.assertEquals('V453 old case', after.Subject, 'AC-3: the history was not altered');
        System.assertEquals(cId, after.ContactId, 'AC-3: the Case still points at the Contact');
        System.assert(after.Contact_Left_Anzeige__c != null
                      && after.Contact_Left_Anzeige__c.length() > 0,
            'AC-7: the Case shows the Austritt without opening the Contact');
        System.assertEquals(true, after.Contact_Left_Anzeige__c.startsWith(MARKED),
            'AC-7: the indicator names the mark');
    }

    // ---------- AC-9: nothing automatic ----------
    @isTest
    static void nothingAutomatic_noSideEffects() {
        Id accId = newAccount('Silent');
        Id cId = newContact('AC9', accId);

        Contact rec = contact(cId);
        rec.Has_Left_Company__c = true;
        update rec;

        List<Task> ts = [SELECT Id, Subject FROM Task WHERE AccountId = :accId OR ContactId = :cId];
        System.assertEquals(0, ts.size(),
            'AC-9: marking created no Task, no reminder, no email');
        Contact after = contact(cId);
        System.assertEquals(true, after.Has_Left_Company__c, 'AC-9 sanity: the mark itself applied');
        System.assertEquals(PAST_CONSENT, after.ConsentDate__c,
            'AC-9: not even the consent date was touched');
    }

    // ---------- AC-8 bulk + governor limits ----------
    @isTest
    static void bulk_marking_staysWithinLimits() {
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            accs.add(new Account(Name = 'V453 bulk ' + i));
        }
        insert accs;

        List<Contact> seeds = new List<Contact>();
        for (Account a : accs) {
            for (Integer j = 0; j < 20; j++) {
                seeds.add(new Contact(LastName = 'bulk-' + j, CompanyName = 'V453 GmbH',
                                      AccountId = a.Id, Has_Left_Company__c = true));
            }
        }
        // ONE bulk insert = ONE trigger invocation (two inserts would be two).
        insert seeds;

        Set<String> names = new Set<String>{'V453 bulk 0', 'V453 bulk 1', 'V453 bulk 2',
                                            'V453 bulk 3', 'V453 bulk 4', 'V453 bulk 5',
                                            'V453 bulk 6', 'V453 bulk 7', 'V453 bulk 8',
                                            'V453 bulk 9'};
        Integer rows = 0;
        for (Account a : [SELECT Id, Contacts_Without_Mark__c, Contacts_Left_Count__c,
                                 Last_Contact_Left_Date__c
                          FROM Account WHERE Name IN :names]) {
            System.assertEquals(Decimal.valueOf(20), a.Contacts_Left_Count__c, 'AC-8 bulk: all marked');
            System.assertEquals(Decimal.valueOf(0), a.Contacts_Without_Mark__c, 'AC-8 bulk: overview row');
            System.assertEquals(Date.today(), a.Last_Contact_Left_Date__c, 'AC-8 bulk: default date');
            rows++;
        }
        System.assertEquals(10, rows, 'AC-8 bulk: 10 overview rows, non-zero');
    }

    // ---------- ADR-4: re-parenting heals old AND new Account ----------
    @isTest
    static void reParenting_healsBothAccounts() {
        Id fromId = newAccount('From');
        Id toId = newAccount('To');
        Id cId = newContact('Moved', fromId);

        Contact rec = contact(cId);
        rec.Has_Left_Company__c = true;
        rec.Left_Company_Date__c = LEFT_WHEN;
        update rec;
        System.assertEquals(Decimal.valueOf(1), aggregates(fromId).Contacts_Left_Count__c,
            'before move: From holds the marked contact');

        Contact moved = contact(cId);
        moved.AccountId = toId;
        update moved;

        Account from = aggregates(fromId);
        Account to = aggregates(toId);
        System.assertEquals(Decimal.valueOf(0), from.Contacts_Left_Count__c, 'ADR-4: old Account healed');
        System.assert(from.Last_Contact_Left_Date__c == null, 'ADR-4: old Account date cleared');
        System.assertEquals(Decimal.valueOf(1), to.Contacts_Left_Count__c, 'ADR-4: new Account counted');
        System.assertEquals(Decimal.valueOf(0), to.Contacts_Without_Mark__c, 'ADR-4: new Account is an overview row');
        System.assertEquals(LEFT_WHEN, to.Last_Contact_Left_Date__c, 'ADR-4: date carried over');
    }

    // ---------- idempotence of the full recompute ----------
    @isTest
    static void recompute_isIdempotent() {
        Id accId = newAccount('Idem');
        Id cId = newContact('I1', accId);
        Contact rec = contact(cId);
        rec.Has_Left_Company__c = true;
        update rec;

        Account first = aggregates(accId);
        Integer soqlBefore = SCRUM453ContactLeftHandler.recomputeSoqlCount;
        SCRUM453ContactLeftHandler.recompute(new Set<Id>{ accId });
        Account second = aggregates(accId);
        Integer soqlAfter = SCRUM453ContactLeftHandler.recomputeSoqlCount;

        System.assertEquals(first.Contacts_Left_Count__c, second.Contacts_Left_Count__c, 'idempotent: count stable');
        System.assertEquals(first.Contacts_Without_Mark__c, second.Contacts_Without_Mark__c, 'idempotent: unmarked stable');
        System.assertEquals(first.Last_Contact_Left_Date__c, second.Last_Contact_Left_Date__c, 'idempotent: date stable');
        System.assertEquals(2, soqlAfter - soqlBefore,
            'one recompute call = 2 aggregate SOQL, independent of the batch');
    }
}
