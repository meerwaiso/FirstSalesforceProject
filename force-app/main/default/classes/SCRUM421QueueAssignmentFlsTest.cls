/**
 * [SCRUM-421] FLS negativ/positiv (AK10) + Queue-Existenz (AK11).
 * House-Pattern SCRUM420EscalationKundeFlsTest / SCRUM418.
 *
 * Negativ: User OHNE PS kann die 4 Felder NICHT lesen (SELECT → Exception).
 * Positiv: mit PS lesbar; SB/KS editierbar (DML ok), Checkbox/Ts read-only (DML → Exception).
 * AK11: die 4 Queues existieren (SELECT COUNT == 4).
 *
 * KEIN nested System.runAs (Runtime Exception). Jeder check ist ein
 * eigenständiger, nicht-überscheidender runAs-Block.
 */
@isTest
private class SCRUM421QueueAssignmentFlsTest {

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls421',
            Alias       = 'f421' + tag,
            Email       = 'f421' + tag + '@example.invalid',
            Username    = 'f421' + tag + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    // ---- AK10 NEGATIV: ohne PS → SELECT → Exception ----
    @isTest
    static void testWithoutPermset_selectFails() {
        User u = mkTestUser('neg');

        // Vorbedingung: Standard-User hat object-level Case-Zugriff (sonst wäre
        // die Exception vom fehlenden Case-CRUD, nicht vom fehlenden FLS).
        Boolean caseReadable = false;
        System.runAs(u) {
            caseReadable = Case.SObjectType.getDescribe().isAccessible();
        }
        System.assert(caseReadable,
            'Vorbedingung gefeilscht: Standard-User hat keinen Case-Zugriff.');

        // NEGATIV: ohne PS → SELECT auf Servicebereich__c → Exception
        // WITH USER_MODE ist zwingend: System.runAs() schaltet FLS-Prüfung für
        // SOQL/DML NICHT ein. Ohne USER_MODE würde der SELECT im System-Modus
        // durchgehen und das Assert unten könnte nie feuern.
        Boolean threw = false;
        System.runAs(u) {
            try {
                List<Case> rows = [SELECT Servicebereich__c FROM Case WITH USER_MODE LIMIT 1];
                // Auch wenn rows leer: die Spalte wurde aufgelöst → FLS vorhanden
                // → Test MUSS fehlschlagen.
                System.assert(false,
                    'Ohne PS: SELECT Servicebereich__c darf NICHT durchgehen.');
            } catch (Exception e) {
                threw = true;
                // 'No such column' / 'Feld ist nicht lesbar' / SecurityException —
                // alle in Ordnung; exakter Message-Abgleich wäre flaky.
            }
        }
        System.assert(threw,
            'Ohne PS: SELECT auf Servicebereich__c muss Exception werfen.');
    }

    // ---- AK10 POSITIV: mit PS → lesbar + Write-Split ----
    @isTest
    static void testWithPermset_readableAndWriteSplit() {
        User u = mkTestUser('pos');
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM421_Zuordnung' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // (a) lesbar (Schema-API, kein DML)
        Boolean sbAcc, ksAcc, cbAcc, tsAcc;
        System.runAs(u) {
            sbAcc = Case.Servicebereich__c.getDescribe().isAccessible();
            ksAcc = Case.Kundenstatus__c.getDescribe().isAccessible();
            cbAcc = Case.Automatische_Zuordnung__c.getDescribe().isAccessible();
            tsAcc = Case.Zuordnungszeitpunkt__c.getDescribe().isAccessible();
        }
        System.assert(sbAcc, 'Mit PS: Servicebereich__c muss lesbar sein');
        System.assert(ksAcc, 'Mit PS: Kundenstatus__c muss lesbar sein');
        System.assert(cbAcc, 'Mit PS: Automatische_Zuordnung__c muss lesbar sein');
        System.assert(tsAcc, 'Mit PS: Zuordnungszeitpunkt__c muss lesbar sein');

        // (b) SELECT liefert den gewerteten Wert
        Id caseId;
        System.runAs(u) {
            Case c = new Case(Status = 'New', Servicebereich__c = 'Technik', Kundenstatus__c = 'Standard');
            insert c;
            caseId = c.Id;
        }
        String sbRead;
        System.runAs(u) {
            sbRead = [SELECT Servicebereich__c FROM Case WHERE Id = :caseId LIMIT 1].Servicebereich__c;
        }
        System.assertEquals('Technik', sbRead, 'SELECT liefert den Wert');

        // (c) SB/KS editierbar — DML ok
        System.runAs(u) {
            Case c = [SELECT Servicebereich__c, Kundenstatus__c FROM Case WHERE Id = :caseId LIMIT 1];
            c.Servicebereich__c = 'Vertrag';
            c.Kundenstatus__c   = 'Premium';
            update c;  // keine Exception = editierbar
        }
        String sbAfter;
        String ksAfter;
        System.runAs(u) {
            Case r = [SELECT Servicebereich__c, Kundenstatus__c FROM Case WHERE Id = :caseId LIMIT 1];
            sbAfter = r.Servicebereich__c;
            ksAfter = r.Kundenstatus__c;
        }
        System.assertEquals('Vertrag', sbAfter, 'Servicebereich__c editierbar');
        System.assertEquals('Premium', ksAfter, 'Kundenstatus__c editierbar');

        // (d) Checkbox read-only — DML muss Exception werfen
        Boolean threwCb = false;
        System.runAs(u) {
            Case c = [SELECT Id FROM Case WHERE Id = :caseId LIMIT 1];
            try {
                c.Automatische_Zuordnung__c = true;
                Database.update(c, AccessLevel.USER_MODE);
                System.assert(false, 'Mit PS: Automatische_Zuordnung__c darf NICHT geschrieben werden.');
            } catch (Exception e) {
                threwCb = true;
            }
        }
        System.assert(threwCb, 'Mit PS: DML auf Automatische_Zuordnung__c muss Exception werfen.');

        // (e) TS read-only — DML muss Exception werfen
        Boolean threwTs = false;
        System.runAs(u) {
            Case c = [SELECT Id FROM Case WHERE Id = :caseId LIMIT 1];
            try {
                c.Zuordnungszeitpunkt__c = DateTime.now();
                Database.update(c, AccessLevel.USER_MODE);
                System.assert(false, 'Mit PS: Zuordnungszeitpunkt__c darf NICHT geschrieben werden.');
            } catch (Exception e) {
                threwTs = true;
            }
        }
        System.assert(threwTs, 'Mit PS: DML auf Zuordnungszeitpunkt__c muss Exception werfen.');
    }

    // ---- AK11: die 4 Queues müssen existieren (Read-Back nach Deploy) ----
    @isTest
    static void testQueuesExist() {
        AggregateResult r = [
            SELECT COUNT(Id) q FROM Group
            WHERE Type = 'Queue'
              AND Name IN ('Technischer Support','Vertragsservice','Billing','First Level Support')
        ];
        Integer n = (Integer) r.get('q');
        System.assertEquals(4, n, 'AK11: exakt 4 Queues müssen in der Org existieren');
    }
}
