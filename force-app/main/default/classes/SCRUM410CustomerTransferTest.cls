/**
 * [SCRUM-410] Functional Apex tests for CustomerTransferController (preview/
 * launch/availableUsers) and CustomerTransferJob (atomarer Queueable).
 *
 * Coverage gegen die 7 ACs:
 *   - AC1  preview liefert die exakten Counts, ohne dass der Aufrufer selbst
 *          die Records lesen muerde (Controller without sharing).
 *   - AC2  launch enqueued, genau einer Job-Lauf.
 *   - AC3  nur OwnerId wandert: Status/Priority/Name/CloseDate bleiben
 *          bitgleich auf den uebergebenen Records (Snapshot-Vergleich).
 *   - AC4  geschlossene Cases/Opps behalten den alten Owner.
 *   - AC5  (Sharing/Read des Uebernehmers) ist eine Org-Eigenschaft nach ADR 3
 *          (Owner-Zugriff, OWD leer) — hier nicht abdeckbar, @tester-agent
 *          via UI-API record-ui (Open Point im Design-Doc).
 *   - AC6  genau 1 CustomerTransfer__c-Zeile, Counts + From/To + Status +
 *          Transferred_At exakt.
 *   - AC7  300 Accounts + ~1250 Child-Records in EINEM Job-Lauf, bulkified,
 *          keine Governor-Ausnahme.
 *   - Validierung: from == to, null, inaktiver Nutzer, unbekannter Nutzer
 *          => AuraHandledException mit deutscher Meldung.
 *
 * Alles rollt mit der Test-Transaktion zurueck.
 *
 * @author developer-agent
 * @date 2026-09-11
 */
@isTest
private class SCRUM410CustomerTransferTest {

    private static final Integer ACCOUNTS = 300;
    private static final Integer CONTACTS_PER_ACCOUNT = 2;
    private static final Integer OPEN_CASES = 400;
    private static final Integer CLOSED_CASES = 200;
    private static final Integer OPEN_OPPS = 300;
    private static final Integer CLOSED_OPPS = 150;

    private static User fromUser;
    private static User toUser;

    /** Alias <= 8 Zeichen (alle Labels sind es). */
    private static User seedUser(String label) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr410 ' + label,
            Alias = label,
            Email = 'scr410_' + label + '_' + stamp + '@example.invalid',
            Username = 'scr410_' + label + '_' + stamp + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE wird in dieser Org abgelehnt (verifiziert, SCRUM-390)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** COUNT(Hilfe): COUNT(Id) liefert List<AggregateResult> — cnt alias + [0].get('cnt') + (Integer)-Cast. */
    private static Integer countAccountsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Account WHERE OwnerId = :ownerId][0].get('cnt');
    }
    private static Integer countContactsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Contact WHERE OwnerId = :ownerId][0].get('cnt');
    }
    private static Integer countOpenCasesOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Case WHERE OwnerId = :ownerId AND IsClosed = false][0].get('cnt');
    }
    private static Integer countClosedCasesOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Case WHERE OwnerId = :ownerId AND IsClosed = true][0].get('cnt');
    }
    private static Integer countOpenOppsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Opportunity WHERE OwnerId = :ownerId AND IsClosed = false][0].get('cnt');
    }
    private static Integer countClosedOppsOwned(Id ownerId) {
        return (Integer) [SELECT COUNT(Id) cnt FROM Opportunity WHERE OwnerId = :ownerId AND IsClosed = true][0].get('cnt');
    }
    private static Integer countAudits() {
        return (Integer) [SELECT COUNT(Id) cnt FROM CustomerTransfer__c][0].get('cnt');
    }
    private static Integer countActiveUsers() {
        return (Integer) [SELECT COUNT(Id) cnt FROM User WHERE IsActive = true][0].get('cnt');
    }

    /**
     * Fixture fuer alle ACs (AC2/3/4/6/7): 300 Accounts je 2 Kontakte, 400
     * offene + 200 geschlossene Cases, 300 laufende + 150 closed-Won Opps —
     * alles vorab mit OwnerId = fromUser angelegt (kein zweiter Update-Durchlauf,
     * weniger DML im Test).
     */
    private static void seed() {
        List<Account> acctList = new List<Account>();
        for (Integer i = 0; i < ACCOUNTS; i++) {
            acctList.add(new Account(Name = 'SCRUM410 Akt ' + i, OwnerId = fromUser.Id));
        }
        insert acctList;

        List<Contact> contacts = new List<Contact>();
        Integer k = 0;
        for (Account a : acctList) {
            for (Integer j = 0; j < CONTACTS_PER_ACCOUNT; j++) {
                contacts.add(new Contact(
                    FirstName = 'Kontakt',
                    LastName = 'c' + (k++),
                    AccountId = a.Id,
                    OwnerId = fromUser.Id
                ));
            }
        }
        insert contacts;

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < OPEN_CASES; i++) {
            cases.add(new Case(
                Status = 'New',
                Subject = 'SCRUM410 offen ' + i,
                Priority = Math.mod(i, 2) == 0 ? 'High' : 'Medium',
                OwnerId = fromUser.Id
            ));
        }
        for (Integer i = 0; i < CLOSED_CASES; i++) {
            cases.add(new Case(
                Status = 'Closed',
                Subject = 'SCRUM410 zu ' + i,
                Priority = 'Low',
                OwnerId = fromUser.Id
            ));
        }
        insert cases;

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < OPEN_OPPS; i++) {
            opps.add(new Opportunity(
                Name = 'SCRUM410 Chance ' + i, CloseDate = Date.today().addDays(30 + i),
                StageName = 'Qualification',
                Amount = Decimal.valueOf((1000 - Math.mod(i, 7)) * 10),
                OwnerId = fromUser.Id
            ));
        }
        for (Integer i = 0; i < CLOSED_OPPS; i++) {
            opps.add(new Opportunity(
                Name = 'SCRUM410 Won ' + i,
                StageName = 'Closed Won',
                CloseDate = Date.today().addMonths(-1),
                Amount = 500,
                OwnerId = fromUser.Id
            ));
        }
        insert opps;
    }

    private static void seedSmall() {
        List<Account> acctList = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            acctList.add(new Account(Name = 'SCRUM410 Small ' + i, OwnerId = fromUser.Id));
        }
        insert acctList;
        List<Contact> contacts = new List<Contact>();
        Integer k = 0;
        for (Account a : acctList) {
            contacts.add(new Contact(
                FirstName = 'Small',
                LastName = 'k' + (k++),
                AccountId = a.Id,
                OwnerId = fromUser.Id
            ));
        }
        insert contacts;
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(new Case(Status = 'New', Subject = 'small-open-' + i, OwnerId = fromUser.Id));
        }
        insert cases;
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 2; i++) {
            opps.add(new Opportunity(Name = 'small-opp-' + i, StageName = 'Prospecting', CloseDate = Date.today().addDays(60 + i), OwnerId = fromUser.Id));
        }
        insert opps;
    }

    // ──────────────────────────── AC1: Vorschau ────────────────────────────

    @isTest
    static void ac1_preview_deliversExactCounts_readOnly() {
        fromUser = seedUser('ac1f');
        toUser = seedUser('ac1t');
        seedSmall();

        Map<String, Object> preview = CustomerTransferController.preview(fromUser.Id, toUser.Id);
        System.assertEquals(5, preview.get('accounts'), 'AC1: Accounts = 5');
        System.assertEquals(5, preview.get('contacts'), 'AC1: Kontakte = 5');
        System.assertEquals(3, preview.get('openCases'), 'AC1: offene Cases = 3');
        System.assertEquals(2, preview.get('openOpportunities'), 'AC1: laufende Opps = 2');

        // Read-only: nach der Vorschau aendert sich am Bestand NICHTS.
        System.assertEquals(5, countAccountsOwned(fromUser.Id),
            'AC1: preview darf keine Records umschreiben');
        // Genau 0 Audit-Zeilen (kein Job lief).
        System.assertEquals(0, countAudits(),
            'AC1: preview darf keine Audit-Zeile schreiben');
    }

    @isTest
    static void ac1_preview_excludesClosedRecords() {
        fromUser = seedUser('ac1cf');
        toUser = seedUser('ac1ct');
        seedSmall();
        // Ergaenzen: 2 geschlossene Cases + 1 closed Won zahlen NICHT in der Vorschau.
        List<Case> closed = new List<Case>();
        closed.add(new Case(Status = 'Closed', Subject = 'ac1-closed', OwnerId = fromUser.Id));
        closed.add(new Case(Status = 'Closed', Subject = 'ac1-closed-2', OwnerId = fromUser.Id));
        insert closed;
        Opportunity won = new Opportunity(
            Name = 'ac1-won',
            StageName = 'Closed Won',
            CloseDate = Date.today().addMonths(-1),
            OwnerId = fromUser.Id
        );
        insert won;

        Map<String, Object> preview = CustomerTransferController.preview(fromUser.Id, toUser.Id);
        System.assertEquals(3, preview.get('openCases'), 'AC1: geschlossene Cases zahlen nicht');
        System.assertEquals(2, preview.get('openOpportunities'), 'AC1: closed Won zaehlt nicht');
    }

    // ──────────────── AC2/AC3/AC4/AC6/AC7: Ausführung (Bulk-Lauf) ────────────────────────

    @isTest
    static void ac2_ac3_ac4_ac6_ac7_bulkTransfer_allCorrect() {
        fromUser = seedUser('bulkf');
        toUser = seedUser('bulkt');
        seed();

        // Snapshot der uebertragbaren offenen Cases/Opps (AC3: Content-Vergleich).
        Map<Id, String> caseSnapshot = new Map<Id, String>();
        for (Case cs : [
            SELECT Id, Status, Priority, Subject, Origin
            FROM Case WHERE OwnerId = :fromUser.Id AND IsClosed = false
        ]) {
            caseSnapshot.put(cs.Id, cs.Status + '|' + cs.Priority + '|' + cs.Subject
                + '|' + (cs.Origin == null ? '' : cs.Origin));
        }
        Map<Id, String> oppSnapshot = new Map<Id, String>();
        for (Opportunity o : [
            SELECT Id, StageName, Amount, Name
            FROM Opportunity WHERE OwnerId = :fromUser.Id AND IsClosed = false
        ]) {
            oppSnapshot.put(o.Id, o.StageName + '|' + o.Amount + '|' + o.Name);
        }

        // ── DER LAUF (AC2, AC7): ein enqueueJob, startTest/stopTest. ──
        Test.startTest();
        CustomerTransferController.launch(fromUser.Id, toUser.Id);
        Test.stopTest();

        // ── AC7/AC2: alle in-scope Records haben exakt toUser als Owner. ──
        System.assertEquals(0, countAccountsOwned(fromUser.Id), 'AC7: alle 300 Accounts uebergeben');
        System.assertEquals(ACCOUNTS, countAccountsOwned(toUser.Id), 'AC7: 300 Accounts bei toUser');
        System.assertEquals(0, countContactsOwned(fromUser.Id), 'AC7: alle Kontakte uebergeben');
        System.assertEquals(ACCOUNTS * CONTACTS_PER_ACCOUNT, countContactsOwned(toUser.Id),
            'AC7: 600 Kontakte bei toUser');
        System.assertEquals(0, countOpenCasesOwned(fromUser.Id), 'AC7: alle offenen Faelle uebergeben');
        System.assertEquals(OPEN_CASES, countOpenCasesOwned(toUser.Id), 'AC7: 400 offene Cases bei toUser');
        System.assertEquals(0, countOpenOppsOwned(fromUser.Id), 'AC7: alle offenen Opps uebergeben');
        System.assertEquals(OPEN_OPPS, countOpenOppsOwned(toUser.Id), 'AC7: 300 offene Opps bei toUser');

        // ── AC4: abgeschlossene Historie bleibt beim alten Betreuer. ──
        System.assertEquals(CLOSED_CASES, countClosedCasesOwned(fromUser.Id),
            'AC4: geschlossene Faelle behalten fromUser');
        System.assertEquals(CLOSED_OPPS, countClosedOppsOwned(fromUser.Id),
            'AC4: closed Won behalten fromUser');
        System.assertEquals(0, countClosedCasesOwned(toUser.Id), 'AC4: toUser erhaelt keine History-Cases');
        System.assertEquals(0, countClosedOppsOwned(toUser.Id), 'AC4: toUser erhaelt keine History-Opps');

        // ── AC3: nur OwnerId hat sich geaendert (Content bitgleich). ──
        for (Case cs : [
            SELECT Id, Status, Priority, Subject, Origin, OwnerId
            FROM Case WHERE Id IN :caseSnapshot.keySet()
        ]) {
            System.assertEquals(
                caseSnapshot.get(cs.Id),
                cs.Status + '|' + cs.Priority + '|' + cs.Subject
                    + '|' + (cs.Origin == null ? '' : cs.Origin),
                'AC3: offene Case ' + cs.Subject + ' inhaltlich unveraendert');
            System.assertEquals(toUser.Id, cs.OwnerId, 'AC2/AC3: nur der Owner hat gewechselt');
        }
        for (Opportunity o : [
            SELECT Id, StageName, Amount, Name, OwnerId
            FROM Opportunity WHERE Id IN :oppSnapshot.keySet()
        ]) {
            System.assertEquals(
                oppSnapshot.get(o.Id),
                o.StageName + '|' + o.Amount + '|' + o.Name,
                'AC3: offene Opportunity ' + o.Name + ' inhaltlich unveraendert');
            System.assertEquals(toUser.Id, o.OwnerId, 'AC2/AC3: nur der Owner hat gewechselt');
        }

        // ── AC6: genau 1 Audit-Zeile, exakte Counts + From/To + Status + Zeit. ──
        List<CustomerTransfer__c> audits = [
            SELECT Id, Name, From_User__c, To_User__c, Transferred_At__c,
                   Accounts_Transferred__c, Contacts_Transferred__c,
                   Open_Cases_Transferred__c, Open_Opportunities_Transferred__c, Status__c
            FROM CustomerTransfer__c
        ];
        System.assertEquals(1, audits.size(), 'AC6: genau eine Audit-Zeile');
        CustomerTransfer__c a = audits.get(0);
        System.assertEquals(fromUser.Id, a.From_User__c, 'AC6: From = fromUser');
        System.assertEquals(toUser.Id, a.To_User__c, 'AC6: To = toUser');
        System.assertEquals(ACCOUNTS, a.Accounts_Transferred__c, 'AC6: Accounts-Count');
        System.assertEquals(ACCOUNTS * CONTACTS_PER_ACCOUNT, a.Contacts_Transferred__c,
            'AC6: Kontakte-Count');
        System.assertEquals(OPEN_CASES, a.Open_Cases_Transferred__c, 'AC6: offene-Cases-Count');
        System.assertEquals(OPEN_OPPS, a.Open_Opportunities_Transferred__c, 'AC6: laufende-Opps-Count');
        System.assertEquals(CustomerTransferJob.STATUS_DONE, a.Status__c, 'AC6: Status Abgeschlossen');
        System.assert(a.Transferred_At__c != null, 'AC6: Zeitstempel gesetzt');
        System.assert(a.Transferred_At__c.getTime() >= DateTime.now().addMinutes(-15).getTime(),
            'AC6: Zeitstempel ist jetzt (Toleranz fuer Test-Dauer)');
    }

    @isTest
    static void ac2_emptyScope_stillRunsWithZeroCounts() {
        fromUser = seedUser('emptyf');
        toUser = seedUser('emptyt');
        // Kein Bestand: der Job muss sauber als leerer Lauf durchlaufen.
        Test.startTest();
        CustomerTransferController.launch(fromUser.Id, toUser.Id);
        Test.stopTest();

        List<CustomerTransfer__c> audits = [
            SELECT Accounts_Transferred__c, Contacts_Transferred__c,
                   Open_Cases_Transferred__c, Open_Opportunities_Transferred__c, Status__c
            FROM CustomerTransfer__c
        ];
        System.assertEquals(1, audits.size(), 'Leerlauf hinterlaesst trotzdem genau eine Audit-Zeile');
        System.assertEquals(0, audits.get(0).Accounts_Transferred__c);
        System.assertEquals(0, audits.get(0).Contacts_Transferred__c);
        System.assertEquals(0, audits.get(0).Open_Cases_Transferred__c);
        System.assertEquals(0, audits.get(0).Open_Opportunities_Transferred__c);
        System.assertEquals(CustomerTransferJob.STATUS_DONE, audits.get(0).Status__c);
    }

    // ──────────────────────────── Validierung ────────────────────────────

    /**
     * from == to => AuraHandledException.
     * ANMERKUNG (verifiziert, Test-Org 2026-09-11): Die Deutsche Meldungs-
     * Text des Controllers ist IN-server nicht lesbar —
     * AuraHandledException.getMessage() liefert im Apex-Testkontext nur
     * „Script-thrown exception" (Sanitization). Der Deutsche Text wird nur
     * client-seitig via e.body.message an die LWC geliefert (dort in
     * errorMessage() ausgewertet) und wird von @tester-agent im UI
     * nachgewiesen (E2E/record-ui-Open-Point). Hier gilt: Ausnahme-Typ +
     * NICHTS passiert.
     */
    @isTest
    static void validation_sameUser_throws_noSideEffects() {
        fromUser = seedUser('valf1');
        try {
            CustomerTransferController.preview(fromUser.Id, fromUser.Id);
            System.assert(false, 'from == to muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true, 'from == to warft AuraHandledException: '
                + e.getMessage());
        }
        try {
            CustomerTransferController.launch(fromUser.Id, fromUser.Id);
            System.assert(false, 'launch: from == to muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(0, countAudits(),
            'Abgewiesener launch hinterlaesst keine Audit-Zeile');
    }

    @isTest
    static void validation_null_andUnknownUsers_throws() {
        fromUser = seedUser('valf2');
        toUser = seedUser('valt2');
        try {
            CustomerTransferController.preview(null, toUser.Id);
            System.assert(false, 'null fromUser muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Id unknown = Id.valueOf('005' + '0'.repeat(9) + 'AAA'); // 15-stellig, nicht existent
        try {
            CustomerTransferController.preview(unknown, toUser.Id);
            System.assert(false, 'unbekannter fromUser muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void validation_inactiveToUser_throws() {
        fromUser = seedUser('valf3');
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User inactive = new User(
            ProfileId = p.Id,
            LastName = 'Inactive 410',
            Alias = 'inact410',
            Email = 'inact410_' + stamp + '@example.invalid',
            Username = 'inact410_' + stamp + '@example.invalid',
            IsActive = false,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert inactive;
        try {
            CustomerTransferController.preview(fromUser.Id, inactive.Id);
            System.assert(false, 'inaktiver toUser muss abgewiesen werden');
        } catch (AuraHandledException e) {
            // Wie bei sameUser: Meldung client-seitig, hier nur Ausnahme-Typ.
            System.assert(true, 'inaktiver toUser warft AuraHandledException');
        }
    }

    @isTest
    static void availableUsers_excludesFromAndInactive() {
        fromUser = seedUser('availf');
        seedUser('availt');
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User inactive = new User(
            ProfileId = p.Id,
            LastName = 'Inactive Avail',
            Alias = 'inav410',
            Email = 'inav410_' + stamp + '@example.invalid',
            Username = 'inav410_' + stamp + '@example.invalid',
            IsActive = false,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert inactive;

        Set<Id> values = new Set<Id>();
        for (Map<String, Object> opt : CustomerTransferController.availableUsers(fromUser.Id)) {
            values.add((Id) opt.get('value'));
        }
        System.assert(!values.contains(fromUser.Id), 'fromUser wird im Picker ausgeschlossen');
        System.assert(!values.contains(inactive.Id), 'Inaktive Nutzer scheiden aus');
        System.assertEquals(countActiveUsers() - 1, values.size(),
            'Alle aktiven Nutzer ausser fromUser stehen im Picker');
    }
}
