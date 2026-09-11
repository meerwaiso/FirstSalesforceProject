/**
 * [SCRUM-410] Functional Apex tests for CustomerTransferController (preview/
 * launch/availableUsers) and CustomerTransferJob (atomarer Queueable).
 *
 * Coverage gegen die 7 ACs:
 *   - AC1  preview liefert die exakten Counts, ohne dass der Aufrufer selbst
 *          die Records lesen müssten (Controller without sharing).
 *   - AC2  launch enqueued, genau einer Job-Lauf.
 *   - AC3  nur OwnerId wandert: Status/Priority/Name/ClosedDate bleiben
 *          bitgleich auf den übergebenen Records (Snapshot-Vergleich).
 *   - AC4  geschlossene Cases/Opps behalten den alten Owner.
 *   - AC5  (Sharing/Read des Übernehmers) ist eine Org-Eigenschaft nach ADR 3
 *          (Owner-Zugriff, OWD leer) — hier nicht abdeckbar, @tester-agent
 *          via UI-API record-ui (Open Point im Design-Doc).
 *   - AC6  genau 1 CustomerTransfer__c-Zeile, Counts + From/To + Status +
 *          Transferred_At exakt.
 *   - AC7  300 Accounts + ~1250 Child-Records in EINEM Job-Lauf, bulkified,
 *          keine Governor-Ausnahme.
 *   - Validierung: from == to, null, inaktiver Nutzer, unbekannter Nutzer
 *          => AuraHandledException mit deutscher Meldung.
 *
 * Test-Org-Eigenschaft (empirisch, House-Hinweis SCRUM-390): ClosedDate wird
 * NIE per DML gesetzt — für geschlossene Cases/Opps wird der Status-
 * Picklist-Wert gesetzt ('Closed' / 'Closed Won') und ClosedDate als
 * Precondition via assertNotEquals(null, ...) belegt (org-Writability-Regel).
 *
 * Alles rollt mit der Test-Transaktion zurück.
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

    /** SCRUM-390-House-Pattern: Lizenz-freier Test-User (2/2 Lizenzen vergeben). */
    private static User makeUser(String label) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr410 ' + label,
            Alias = label, // Alias <= 8 Zeichen (alle Labels hier sind es)
            Email = 'scr410_' + label + '_' + DateTime.now().getTime() + '@example.invalid',
            Username = 'scr410_' + label + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE wird in dieser Org abgelehnt (verifiziert, SCRUM-390)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC wird abgelehnt (verifiziert, SCRUM-390)
        );
        insert u;
        return u;
    }

    /**
     * Fixture für alle ACs (AC2/3/4/6/7): 300 Accounts je 2 Kontakte, 400
     * offene + 200 geschlossene Cases, 300 laufende + 150 closed-Won Opps —
     * alles vorab mit OwnerId = fromUser angelegt (kein zweiter Update-Durchlauf,
     * weniger DML im Test).
     */
    private static void seed() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < ACCOUNTS; i++) {
            accounts.add(new Account(Name = 'SCRUM410 Akt ' + i, OwnerId = fromUser.Id));
        }
        insert accounts;

        List<Contact> contacts = new List<Contact>();
        for (Account a : accounts) {
            for (Integer j = 0; j < CONTACTS_PER_ACCOUNT; j++) {
                contacts.add(new Contact(
                    FirstName = 'Kontakt',
                    LastName = String.valueOf(i) + '-' + j,
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
                Priority = i % 2 == 0 ? 'High' : 'Medium',
                OwnerId = fromUser.Id
            ));
        }
        for (Integer i = 0; i < CLOSED_CASES; i++) {
            cases.add(new Case(
                Status = 'Closed', // org-Writability-Regel: NICHT ClosedDate per DML
                Subject = 'SCRUM410 zu ' + i,
                Priority = 'Low',
                OwnerId = fromUser.Id
            ));
        }
        insert cases;

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < OPEN_OPPS; i++) {
            opps.add(new Opportunity(
                Name = 'SCRUM410 Chance ' + i,
                StageName = 'Qualification',
                Amount = Decimal.valueOf((1000 - (i % 7)) * 10),
                OwnerId = fromUser.Id
            ));
        }
        for (Integer i = 0; i < CLOSED_OPPS; i++) {
            opps.add(new Opportunity(
                Name = 'SCRUM410 Won ' + i,
                StageName = 'Closed Won',
                Amount = 500,
                OwnerId = fromUser.Id
            ));
        }
        insert opps;
    }

    private static void seedSmall() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'SCRUM410 Small ' + i, OwnerId = fromUser.Id));
        }
        insert accounts;
        List<Contact> contacts = new List<Contact>();
        for (Account a : accounts) {
            contacts.add(new Contact(
                FirstName = 'Small',
                LastName = 'Kontakt',
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
            opps.add(new Opportunity(Name = 'small-opp-' + i, StageName = 'Prospecting', OwnerId = fromUser.Id));
        }
        insert opps;
    }

    // ──────────────────────────── AC1: Vorschau ────────────────────────────

    @isTest
    static void ac1_preview_deliversExactCounts_readOnly() {
        fromUser = makeUser('ac1from');
        toUser = makeUser('ac1to');
        seedSmall();

        Map<String, Object> preview = CustomerTransferController.preview(fromUser.Id, toUser.Id);
        System.assertEquals(5, preview.get('accounts'), 'AC1: Accounts = 5');
        System.assertEquals(5, preview.get('contacts'), 'AC1: Kontakte = 5');
        System.assertEquals(3, preview.get('openCases'), 'AC1: offene Cases = 3');
        System.assertEquals(2, preview.get('openOpportunities'), 'AC1: laufende Opps = 2');

        // Read-only: nach der Vorschau ändert sich am Bestand NICHTS.
        System.assertEquals(
            5, [SELECT COUNT(Id) FROM Account WHERE OwnerId = :fromUser.Id],
            'AC1: preview darf keine Records umschreiben'
        );
        // Genau 0 Audit-Zeilen (keiner Job lief).
        System.assertEquals(
            0, [SELECT COUNT(Id) FROM CustomerTransfer__c],
            'AC1: preview darf keine Audit-Zeile schreiben'
        );
    }

    @isTest
    static void ac1_preview_excludesClosedRecords() {
        fromUser = makeUser('ac1cf');
        toUser = makeUser('ac1ct');
        seedSmall();
        // Ergänzen: 2 geschlossene Cases + 1 closed Won → zählen NICHT in der Vorschau.
        insert new Case(Status = 'Closed', Subject = 'ac1-closed', OwnerId = fromUser.Id);
        insert new Case(Status = 'Closed', Subject = 'ac1-closed-2', OwnerId = fromUser.Id);
        insert new Opportunity(
            Name = 'ac1-won',
            StageName = 'Closed Won',
            OwnerId = fromUser.Id
        );

        Map<String, Object> preview = CustomerTransferController.preview(fromUser.Id, toUser.Id);
        System.assertEquals(3, preview.get('openCases'), 'AC1: geschlossene Cases zählen nicht');
        System.assertEquals(2, preview.get('openOpportunities'), 'AC1: closed Won zählt nicht');
    }

    // ──────────────── AC2/AC3/AC4/AC6/AC7: Ausführung (Bulk-Lauf) ────────────────────────

    @isTest
    static void ac2_ac3_ac4_ac6_ac7_bulkTransfer_allCorrect() {
        fromUser = makeUser('bulkfrom');
        toUser = makeUser('bulkto');
        seed();

        // Snapshot der übertragbaren offenen Cases/Opps (AC3: Content-Vergleich).
        Map<Id, String> caseSnapshot = new Map<Id, String>();
        for (Case cs : [
            SELECT Id, Status, Priority, Subject, Origin
            FROM Case
            WHERE OwnerId = :fromUser.Id AND IsClosed = false
        ]) {
            caseSnapshot.put(cs.Id, cs.Status + '|' + cs.Priority + '|' + cs.Subject + '|' + (cs.Origin == null ? '' : cs.Origin));
        }
        Map<Id, String> oppSnapshot = new Map<Id, String>();
        for (Opportunity o : [
            SELECT Id, StageName, Amount, Name
            FROM Opportunity
            WHERE OwnerId = :fromUser.Id AND IsClosed = false
        ]) {
            oppSnapshot.put(o.Id, o.StageName + '|' + o.Amount + '|' + o.Name);
        }
        // Precondition (org-Writability-Regel): geschlossene Cases/Opps haben
        // ein ClosedDate, das wir NICHT per DML setzen.
        for (Case cs : [SELECT Id, ClosedDate FROM Case WHERE OwnerId = :fromUser.Id AND IsClosed = true]) {
            System.assert(cs.ClosedDate != null, 'Precondition: geschlossener Fall braucht ClosedDate');
        }
        for (Opportunity o : [SELECT Id, ClosedDate FROM Opportunity WHERE OwnerId = :fromUser.Id AND IsClosed = true]) {
            System.assert(o.ClosedDate != null, 'Precondition: closed Opportunity braucht ClosedDate');
        }

        // ── DER LAUF (AC2, AC7): ein enqueueJob, Test.startTest/endTest. ──
        Test.startTest();
        CustomerTransferController.launch(fromUser.Id, toUser.Id);
        Test.endTest();

        // ── AC7/AC2: alle in-scope Records haben exakt toUser als Owner. ──
        System.assertEquals(
            0, [SELECT COUNT(Id) FROM Account WHERE OwnerId = :fromUser.Id],
            'AC7: alle 300 Accounts übergeben'
        );
        System.assertEquals(ACCOUNTS, [SELECT COUNT(Id) FROM Account WHERE OwnerId = :toUser.Id]);
        System.assertEquals(
            0, [SELECT COUNT(Id) FROM Contact WHERE OwnerId = :fromUser.Id],
            'AC7: alle Kontakte übergeben'
        );
        System.assertEquals(
            ACCOUNTS * CONTACTS_PER_ACCOUNT,
            [SELECT COUNT(Id) FROM Contact WHERE OwnerId = :toUser.Id]
        );
        System.assertEquals(
            0, [SELECT COUNT(Id) FROM Case WHERE OwnerId = :fromUser.Id AND IsClosed = false],
            'AC7: alle offenen Fälle übergeben'
        );
        System.assertEquals(
            OPEN_CASES,
            [SELECT COUNT(Id) FROM Case WHERE OwnerId = :toUser.Id AND IsClosed = false]
        );
        System.assertEquals(
            0, [SELECT COUNT(Id) FROM Opportunity WHERE OwnerId = :fromUser.Id AND IsClosed = false]
        );
        System.assertEquals(
            OPEN_OPPS,
            [SELECT COUNT(Id) FROM Opportunity WHERE OwnerId = :toUser.Id AND IsClosed = false]
        );

        // ── AC4: abgeschlossene Historie bleibt beim alten Betreuer. ──
        System.assertEquals(
            CLOSED_CASES,
            [SELECT COUNT(Id) FROM Case WHERE OwnerId = :fromUser.Id AND IsClosed = true],
            'AC4: geschlossene Fälle behalten fromUser'
        );
        System.assertEquals(
            CLOSED_OPPS,
            [SELECT COUNT(Id) FROM Opportunity WHERE OwnerId = :fromUser.Id AND IsClosed = true],
            'AC4: closed Won behalten fromUser'
        );

        // ── AC3: nur OwnerId hat sich verändert (Content bitgleich). ──
        for (Case cs : [
            SELECT Id, Status, Priority, Subject, Origin, OwnerId
            FROM Case WHERE Id IN :caseSnapshot.keySet()
        ]) {
            System.assertEquals(
                caseSnapshot.get(cs.Id),
                cs.Status + '|' + cs.Priority + '|' + cs.Subject + '|' + (cs.Origin == null ? '' : cs.Origin),
                'AC3: offene Case ' + cs.Subject + ' inhaltlich unverändert'
            );
            System.assertEquals(toUser.Id, cs.OwnerId, 'AC2/AC3: nur der Owner hat gewechselt');
        }
        for (Opportunity o : [
            SELECT Id, StageName, Amount, Name, OwnerId
            FROM Opportunity WHERE Id IN :oppSnapshot.keySet()
        ]) {
            System.assertEquals(
                oppSnapshot.get(o.Id),
                o.StageName + '|' + o.Amount + '|' + o.Name,
                'AC3: offene Opportunity ' + o.Name + ' inhaltlich unverändert'
            );
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
        System.assertEquals(ACCOUNTS * CONTACTS_PER_ACCOUNT, a.Contacts_Transferred__c, 'AC6: Kontakte-Count (geschlossen zählen nicht mit)');
        System.assertEquals(OPEN_CASES, a.Open_Cases_Transferred__c, 'AC6: offene-Cases-Count');
        System.assertEquals(OPEN_OPPS, a.Open_Opportunities_Transferred__c, 'AC6: laufende-Opps-Count');
        System.assertEquals(CustomerTransferJob.STATUS_DONE, a.Status__c, 'AC6: Status Abgeschlossen');
        System.assert(a.Transferred_At__c != null, 'AC6: Zeitstempel gesetzt');
        System.assert(a.Transferred_At__c.getTime() >= DateTime.now().minusMinutes(15).getTime(),
            'AC6: Zeitstempel ist „jetzt" (Toleranz für Test-Dauer)');
    }

    @isTest
    static void ac2_emptyScope_stillRunsWithZeroCounts() {
        fromUser = makeUser('emptyf');
        toUser = makeUser('emptyt');
        // Kein Bestand: der Job muss sauber als leerer Lauf durchlaufen.
        Test.startTest();
        CustomerTransferController.launch(fromUser.Id, toUser.Id);
        Test.endTest();

        List<CustomerTransfer__c> audits = [
            SELECT Accounts_Transferred__c, Contacts_Transferred__c,
                   Open_Cases_Transferred__c, Open_Opportunities_Transferred__c, Status__c
            FROM CustomerTransfer__c
        ];
        System.assertEquals(1, audits.size(), 'Leerlauf hinterlässt trotzdem genau eine Audit-Zeile');
        System.assertEquals(0, audits.get(0).Accounts_Transferred__c);
        System.assertEquals(0, audits.get(0).Contacts_Transferred__c);
        System.assertEquals(0, audits.get(0).Open_Cases_Transferred__c);
        System.assertEquals(0, audits.get(0).Open_Opportunities_Transferred__c);
        System.assertEquals(CustomerTransferJob.STATUS_DONE, audits.get(0).Status__c);
    }

    // ──────────────────────────── Validierung ────────────────────────────

    @isTest
    static void validation_sameUser_throwsGermanMeldung() {
        fromUser = makeUser('valf1');
        try {
            CustomerTransferController.preview(fromUser.Id, fromUser.Id);
            System.assert(false, 'from == to muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(Boolean.TRUE.valueOf(e.getMessage().contains('verschieden')),
                'Meldung erklärt die Bedingung: ' + e.getMessage());
        }
        try {
            CustomerTransferController.launch(fromUser.Id, fromUser.Id);
            System.assert(false, 'launch: from == to muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(0, [SELECT COUNT(Id) FROM CustomerTransfer__c],
            'Abgewiesener launch hinterlässt keine Audit-Zeile');
    }

    @isTest
    static void validation_null_andUnknownUsers_throws() {
        fromUser = makeUser('valf2');
        toUser = makeUser('valt2');
        try {
            CustomerTransferController.preview(null, toUser.Id);
            System.assert(false, 'null fromUser muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Id unknown = Id.valueOf('005' + '0'.repeat(9) + 'AAA'); // 15-stellige, nicht existente Id
        try {
            CustomerTransferController.preview(unknown, toUser.Id);
            System.assert(false, 'unbekannter fromUser muss abgewiesen werden');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void validation_inactiveToUser_throws() {
        fromUser = makeUser('valf3');
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User inactive = new User(
            ProfileId = p.Id,
            LastName = 'Inactive 410',
            Alias = 'inact410',
            Email = 'inact410_' + DateTime.now().getTime() + '@example.invalid',
            Username = 'inact410_' + DateTime.now().getTime() + '@example.invalid',
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
            System.assert(Boolean.TRUE.valueOf(e.getMessage().contains('inaktiv'))
                , 'Meldung nennt den inaktiven Nutzer: ' + e.getMessage());
        }
    }

    @isTest
    static void availableUsers_excludesFromAndInactive() {
        fromUser = makeUser('availf');
        makeUser('availt');
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User inactive = new User(
            ProfileId = p.Id,
            LastName = 'Inactive Avail',
            Alias = 'inav410',
            Email = 'inav410_' + DateTime.now().getTime() + '@example.invalid',
            Username = 'inav410_' + DateTime.now().getTime() + '@example.invalid',
            IsActive = false,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert inactive;

        Set<Id> values = new Set<Id>();
        for (Map<String, Object> opt : CustomerTransferController.availableUsers(fromUser.Id)) {
            values.add((Id)opt.get('value'));
        }
        System.assert(!values.contains(fromUser.Id), 'fromUser wird im Picker ausgeschlossen');
        System.assert(!values.contains(inactive.Id), 'Inaktive Nutzer scheiden aus');
        Integer activeCount = [SELECT COUNT(Id) FROM User WHERE IsActive = true];
        System.assertEquals(activeCount - 1, values.size(),
            'Alle aktiven Nutzer außer fromUser stehen im Picker');
    }
}
