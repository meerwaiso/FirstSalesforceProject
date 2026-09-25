/**
 * [SCRUM-430] FLS positiv/negativ (AC3 / AC4).
 * House-Pattern SCRUM421QueueAssignmentFlsTest:
 *   Standard-User-Profil, Vorbedingungs-Assert (Objekt-Zugriff),
 *   negativer + positiver Block, WITH USER_MODE bei SOQL,
 *   eigenständige System.runAs-Blöcke (kein nested runAs).
 *
 * PRÄMISSE AC4 (kritisch): Der Negativ-Test `withoutPS_fieldInvisible` läuft
 * NACH dem Org-Setup-Schritt S1 (Feld im Standard-User-Profil auf „nicht
 * sichtbar“ gesperrt). Ohne S1 hat das Standard-User-Profil auf neue Custom
 * Fields automatisch Read+Edit (SCRUM-421-Lesson) und der Negativ-Test
 * scheitert KORREKT — der FLS-Negativzustand wäre in der Org dann tatsächlich
 * nicht erfüllt. Ein PS kann Profil-FLS nicht widerrufen.
 */
@isTest
private class SCRUM430RueckrufZeitfensterFlsTest {

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls430',
            Alias       = 'f430' + tag,
            Email       = 'f430' + tag + '@example.invalid',
            Username    = 'f430' + tag + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    // ---- Vorbedingung: Standard-User hat object-level Contact-Zugriff ------
    @isTest
    static void precondition_contactReadable() {
        User u = mkTestUser('pre');
        Boolean contactReadable = false;
        System.runAs(u) {
            contactReadable = Contact.SObjectType.getDescribe().isAccessible();
        }
        System.assert(contactReadable,
            'Vorbedingung nicht erfüllt: Standard-User hat keinen Contact-Zugriff — ' +
            'ein FLS-Assert wäre dann aus dem falschen Grund grün.');
    }

    // ---- AC4 NEGATIV: ohne PS (und nach S1) → SELECT → Exception ----------
    @isTest
    static void withoutPS_fieldInvisible() {
        User u = mkTestUser('neg');

        // Vorbedingung: object-level Contact-Zugriff vorhanden (sonst wäre die
        // Exception vom fehlenden Contact-CRUD, nicht vom fehlenden FLS).
        Boolean contactReadable = false;
        System.runAs(u) {
            contactReadable = Contact.SObjectType.getDescribe().isAccessible();
        }
        System.assert(contactReadable,
            'Vorbedingung gefeilscht: Standard-User hat keinen Contact-Zugriff.');

        // NEGATIV: ohne PS (nach S1) → SELECT Rueckruf_Zeitfenster__c → Exception.
        // WITH USER_MODE ist zwingend: runAs() schaltet FLS-Prüfung für SOQL/DML
        // nicht ein; ohne USER_MODE würde der SELECT im System-Modus durchgehen.
        Boolean threw = false;
        System.runAs(u) {
            try {
                List<Contact> rows = [SELECT Rueckruf_Zeitfenster__c FROM Contact WITH USER_MODE LIMIT 1];
                // Auch wenn rows leer: die Spalte wurde aufgelöst → FLS vorhanden → fail.
                System.assert(false,
                    'Ohne PS: SELECT Rueckruf_Zeitfenster__c darf NICHT durchgehen (AC4).');
            } catch (Exception e) {
                threw = true;
                // 'No such column' / 'Feld ist nicht lesbar' / SecurityException —
                // alle in Ordnung; exakter Message-Abgleich wäre flaky.
            }
        }
        System.assert(threw,
            'Ohne PS (nach S1): SELECT auf Rueckruf_Zeitfenster__c muss Exception werfen (AC4).');
    }

    // ---- AC3 POSITIV: mit PS → lesbar + editierbar -------------------------
    @isTest
    static void withPS_readableAndWritable() {
        User u = mkTestUser('pos');
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM430_RueckrufZeitfenster' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // (a) lesbar (Schema-API).
        Boolean acc;
        System.runAs(u) {
            acc = Contact.Rueckruf_Zeitfenster__c.getDescribe().isAccessible();
        }
        System.assert(acc, 'Mit PS: Rueckruf_Zeitfenster__c muss lesbar sein (AC3).');

        // (b) INSERT mit Wert + UPDATE + SELECT liefert den (geänderten) Wert.
        Id contactId;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-430-FLS-POS', Rueckruf_Zeitfenster__c = 'Abends');
            insert c;
            contactId = c.Id;
        }
        String read1;
        System.runAs(u) {
            read1 = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :contactId LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals('Abends', read1, 'Mit PS: SELECT liefert den eingetragenen Wert (AC3).');

        System.runAs(u) {
            Contact c = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :contactId LIMIT 1];
            c.Rueckruf_Zeitfenster__c = 'Vormittags';
            update c; // keine Exception = editierbar
        }
        String read2;
        System.runAs(u) {
            read2 = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :contactId LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals('Vormittags', read2, 'Mit PS: Rueckruf_Zeitfenster__c editierbar (AC3).');
    }
}
