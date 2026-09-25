/**
 * [SCRUM-430] Functional test for the new picklist field
 * Contact.Rueckruf_Zeitfenster__c („Rückruf-Zeitfenster", optional, 3 Werte).
 *
 * Covers AC1 (Wertematrix + optional/leer) and the overwrite basis of AC3:
 *   value matrix: Vormittags / Nachmittags / Abends persist round-trip
 *   optional:     field stays null when unset (leer ist der Normalzustand, ADR-6)
 *   overwrite:    value is freely assignable (Vormittags -> Abends), AC3-Grundlage
 *   schema:       exactly the 3 picklist values exist (AC1 „exakt 3 Werte")
 *
 * FLS-Gate / CI-Lücke C (SCRUM-421/424-Hausform, DevOps-Kommentar 21194/21195):
 *   JEDE fachliche DML/SELECT-Zeile auf dem NEUEN Feld läuft unter
 *   System.runAs(einUser), der vorab die PS SCRUM430_RueckrufZeitfenster
 *   erhält. Setup-Inserts (User, PermissionSetAssignment) ZUERST, dann das
 *   fachliche DML INNERHALB von runAs — sonst MIXED_DML_OPERATION. Referenz:
 *   SCRUM424FirstResponseFlsTest (31/51 Klassen machen es so).
 *
 * Warum runAs, nicht nur für die FLS-Tests sondern hier auch für die
 * Funktions-Methode: Der Prod-Org-Drift-Gate validiert check-only gegen Prod,
 * wo das Feld durch DEPIESELBE Deploy neu angelegt wird. Feld und PermissionSet
 * sind Metadatum und wandern mit; die PermissionSetAssignment ist ein DATENSATZ
 * und wandert NICHT mit → der ausführende Testuser hätte ohne runAs kein FLS,
 * und die DML/SELECT fallen mit 'No such column' / 'fields being inaccessible'
 * durch. Mit runAs + in-Test-PSA besitzt der User FLS → beides grün.
 * (Ohne runAs schlägt zusätzlich das statische FLS-Gate Lücke C: „fasst das
 * neue Feld ohne System.runAs an".)
 *
 * DEVIATION from design TC (unchanged, already ADR-approved by Architect 16:46):
 *   The design's TC `reject_invalid_value` expected an Apex DML exception when
 *   assigning a value that is not in the picklist. Salesforce does not reliably
 *   throw that for a user-maintained picklist on a stale/foreign literal. The
 *   „exakt 3 Werte" guarantee is enforced via the Schema picklist definition
 *   (picklistValues == {Vormittags, Nachmittags, Abends}), the authoritative,
 *   non-flaky check. See docs/SCRUM-430-notizen.md + handoff comment.
 */
@isTest
private class SCRUM430RueckrufZeitfensterTest {

    private static final String PS_NAME = 'SCRUM430_RueckrufZeitfenster';

    /** Frischer Standard-User (Hausform SCRUM424 / Companion-FlsTest). */
    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Funck430',
            Alias                = 'f430' + tag,
            Email                = 'f430' + tag + sfx + '@x.invalid',
            Username             = 'f430' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** PS-Zuweisung als Setup vor dem fachlichen DML (Lücke C / PSA wandert nicht mit). */
    private static void assignPS(User u) {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = :PS_NAME LIMIT 1].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
    }

    // ---- AC1 optional / leer ----------------------------------------------

    @isTest
    static void defaultValue_empty() {
        User u = mkTestUser('em');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-430-EMPTY');
            insert c;
            v = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :c.Id LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals(
            null, v,
            'Leergelassenes Feld bleibt null (AC1 „kann leer bleiben“)'
        );
    }

    // ---- AC1 value matrix -------------------------------------------------

    @isTest
    static void value_vormittags() {
        User u = mkTestUser('v1');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-430-VORM', Rueckruf_Zeitfenster__c = 'Vormittags');
            insert c;
            v = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :c.Id LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals('Vormittags', v, 'Vormittags persistiert (AC1)');
    }

    @isTest
    static void value_nachmittags() {
        User u = mkTestUser('v2');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-430-NACHM', Rueckruf_Zeitfenster__c = 'Nachmittags');
            insert c;
            v = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :c.Id LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals('Nachmittags', v, 'Nachmittags persistiert (AC1)');
    }

    @isTest
    static void value_abends() {
        User u = mkTestUser('v3');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-430-ABEND', Rueckruf_Zeitfenster__c = 'Abends');
            insert c;
            v = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :c.Id LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals('Abends', v, 'Abends persistiert (AC1)');
    }

    // ---- AC3 overwrite basis ------------------------------------------------

    @isTest
    static void overwrite_vormittags_to_abends() {
        User u = mkTestUser('ow');
        assignPS(u);
        Id cid;
        String v1;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-430-OVERWRITE', Rueckruf_Zeitfenster__c = 'Vormittags');
            insert c;
            cid = c.Id;
            v1 = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :cid LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals('Vormittags', v1, 'Precondition: Vormittags');

        String v2;
        System.runAs(u) {
            Contact c2 = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :cid LIMIT 1];
            c2.Rueckruf_Zeitfenster__c = 'Abends';
            update c2;
            v2 = [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :cid LIMIT 1].Rueckruf_Zeitfenster__c;
        }
        System.assertEquals(
            'Abends', v2,
            'Feld ist frei änderbar (AC3-Grundlage: Service kann den Wert wechseln)'
        );
    }

    // ---- AC1 „exakt 3 Werte" via Schema (robust statt DML-Exception) --------

    @isTest
    static void picklistHasExactlyThreeValues() {
        // Schema-Reflexion (kein Feld-DML) — läuft System-Mode, unabhängig vom FLS-Gate.
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : Contact.Rueckruf_Zeitfenster__c.getDescribe().getPicklistValues()) {
            values.add(e.getValue());
        }
        System.assertEquals(
            3, values.size(),
            'Rueckruf_Zeitfenster__c muss exakt 3 Picklist-Werte haben (AC1)'
        );
        Set<String> expected = new Set<String>{ 'Vormittags', 'Nachmittags', 'Abends' };
        System.assertEquals(
            expected, new Set<String>(values),
            'Werte müssen exakt Vormittags / Nachmittags / Abends sein (AC1)'
        );
    }
}
