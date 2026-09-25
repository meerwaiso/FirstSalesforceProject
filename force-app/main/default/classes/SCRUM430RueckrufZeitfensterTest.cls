/**
 * [SCRUM-430] Functional test for the new picklist field
 * Contact.Rueckruf_Zeitfenster__c („Rückruf-Zeitfenster“, optional, 3 Werte).
 *
 * Covers AC1 (Wertematrix + optional/leer) and the overwrite basis of AC3:
 *   value matrix: Vormittags / Nachmittags / Abends persist round-trip
 *   optional:     field stays null when unset (leer ist der Normalzustand, ADR-6)
 *   overwrite:    value is freely assignable (Vormittags -> Abends), AC3-Grundlage
 *   schema:       exactly the 3 picklist values exist (AC1 „exakt 3 Werte“)
 *
 * ORG CONSTRAINT / DEVIATION (SCRUM-421 house shape, ADR-6):
 *   The design's TC `reject_invalid_value` expected an Apex DML exception when
 *   assigning a value that is not in the picklist. That is NOT how Salesforce
 *   behaves: DML on a picklist field does not throw on a stale/foreign literal
 *   for a user-maintained (non-translated) picklist in the way the design
 *   assumed. The „exactly 3 values“ guarantee is therefore enforced via the
 *   Schema picklist definition (picklistValues == {Vormittags, Nachmittags,
 *   Abends}), which is the authoritative, non-flaky check. See notizen +
 *   handoff comment; flagged for reviewer.
 *
 * House shape: SCRUM396BetreuungsstufeTest (makeContact + read-back via
 * SELECT). No System.runAs — pure DML+SELECT, no FLS (FLS lives in the
 * companion SCRUM430RueckrufZeitfensterFlsTest).
 */
@isTest
private class SCRUM430RueckrufZeitfensterTest {

    private static Contact makeContact(String tag, String fenster) {
        Contact c = new Contact(LastName = tag);
        if (fenster != null) {
            c.Rueckruf_Zeitfenster__c = fenster;
        }
        insert c;
        return c;
    }

    private static String readValue(String contactId) {
        return [SELECT Rueckruf_Zeitfenster__c FROM Contact WHERE Id = :contactId].Rueckruf_Zeitfenster__c;
    }

    // ---- AC1 optional / leer ----------------------------------------------

    @isTest
    static void defaultValue_empty() {
        // Leerer lassen => null (ADR-6: optional, kein Default).
        Contact c = makeContact('TEST-SCRUM-430-EMPTY', null);
        System.assertEquals(
            null, readValue(c.Id),
            'Leergelassenes Feld bleibt null (AC1 „kann leer bleiben“)'
        );
    }

    // ---- AC1 value matrix -------------------------------------------------

    @isTest
    static void value_vormittags() {
        Contact c = makeContact('TEST-SCRUM-430-VORM', 'Vormittags');
        System.assertEquals('Vormittags', readValue(c.Id), 'Vormittags persistiert (AC1)');
    }

    @isTest
    static void value_nachmittags() {
        Contact c = makeContact('TEST-SCRUM-430-NACHM', 'Nachmittags');
        System.assertEquals('Nachmittags', readValue(c.Id), 'Nachmittags persistiert (AC1)');
    }

    @isTest
    static void value_abends() {
        Contact c = makeContact('TEST-SCRUM-430-ABEND', 'Abends');
        System.assertEquals('Abends', readValue(c.Id), 'Abends persistiert (AC1)');
    }

    // ---- AC3 overwrite basis ------------------------------------------------

    @isTest
    static void overwrite_vormittags_to_abends() {
        Contact c = makeContact('TEST-SCRUM-430-OVERWRITE', 'Vormittags');
        System.assertEquals('Vormittags', readValue(c.Id), 'Precondition: Vormittags');

        c.Rueckruf_Zeitfenster__c = 'Abends';
        update c;
        System.assertEquals(
            'Abends', readValue(c.Id),
            'Feld ist frei änderbar (AC3-Grundlage: Service kann den Wert wechseln)'
        );
    }

    // ---- AC1 „exakt 3 Werte“ via Schema (robust statt DML-Exception) --------

    @isTest
    static void picklistHasExactlyThreeValues() {
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
