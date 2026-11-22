/**
 * [SCRUM-470] Functional test for the hand-set picklist
 * Contact.Preferred_Contact_Method__c ("Favorit Kontaktmethod", optional, 3 Werte).
 *
 * Covers:
 *   AC1  optional: a Contact saved WITHOUT the field keeps it null (leer = nobody asked yet)
 *   AC1  value matrix: Phone / Email / Letter persist round-trip
 *   AC1  schema: exactly the three Picklist values exist → mutual exclusion by construction,
 *        no ValidationRule and nothing else that blocks a save (PO scope limit, ADR-2)
 *   AC3  a user holding SCRUM470_ContactContactWay sets the value and CHANGES it
 *   AC4  overwrite: Phone -> Letter, the old value is gone
 *   AC5  clearing back to empty saves (required=false, no ValidationRule, ADR-4)
 *   AC7  nothing automatic: a save touches ONLY this field — no OTHER Contact gets a value,
 *        the record's Phone/Email stay untouched
 *
 * FLS-Gate / CI-Lücke C (SCRUM-421/424 house form, house class SCRUM430RueckrufZeitfensterTest):
 *   JEDE fachliche DML/SELECT on the NEW field runs under System.runAs(user); the User and
 *   its PermissionSetAssignment are inserted STRICTLY FIRST (a User cannot grant himself a
 *   PSA; the mixed order reddens MIXED_DML_OPERATION in CI RunLocalTests).
 *
 * House shape 1:1 from SCRUM430RueckrufZeitfensterTest (same object, same field kind,
 * same Read+Edit PS) — verified green in this org.
 */
@isTest
private class SCRUM470PreferredContactMethodTest {

    private static final String PS_NAME = 'SCRUM470_ContactContactWay';

    /** Frischer Standard-User (Hausform SCRUM430/424; de_DE + UTC rejected in this org). */
    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId            = p.Id,
            LastName             = 'Funck470',
            Alias                = 'f470' + tag,
            Email                = 'f470' + tag + sfx + '@x.invalid',
            Username             = 'f470' + tag + sfx + '@x.invalid',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            LocaleSidKey         = 'en_US',
            TimeZoneSidKey       = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** PS-Zuweisung als Setup ZUERST, then the fachliche DML inside runAs (Lücke C). */
    private static void assignPS(User u) {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = :PS_NAME LIMIT 1].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
    }

    // ---- AC1: leer bleibt leer (nobody asked yet) --------------------------
    @isTest
    static void empty_stays_empty() {
        User u = mkTestUser('em');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-EMPTY');
            insert c;
            v = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :c.Id LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals(null, v, 'AC1: a Contact saved without a preference keeps the field null.');
    }

    // ---- AC1: value matrix -------------------------------------------------
    @isTest
    static void value_phone() {
        User u = mkTestUser('ph');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-PHONE', Preferred_Contact_Method__c = 'Phone');
            insert c;
            v = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :c.Id LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Phone', v, 'AC1: Phone persistiert.');
    }

    @isTest
    static void value_email() {
        User u = mkTestUser('em2');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-EMAIL', Preferred_Contact_Method__c = 'Email');
            insert c;
            v = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :c.Id LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Email', v, 'AC1: Email persistiert.');
    }

    @isTest
    static void value_letter() {
        User u = mkTestUser('lt');
        assignPS(u);
        String v;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-LETTER', Preferred_Contact_Method__c = 'Letter');
            insert c;
            v = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :c.Id LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Letter', v, 'AC1: Letter persistiert.');
    }

    // ---- AC3/AC4: set + change, old value gone ------------------------------
    @isTest
    static void overwrite_phone_to_letter() {
        User u = mkTestUser('ow');
        assignPS(u);
        Id cid;
        String v1;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-OVERWRITE', Preferred_Contact_Method__c = 'Phone');
            insert c;
            cid = c.Id;
            v1 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :cid LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Phone', v1, 'Precondition: Phone stored.');

        String v2;
        System.runAs(u) {
            Contact c2 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :cid LIMIT 1];
            c2.Preferred_Contact_Method__c = 'Letter';
            update c2;
            v2 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :cid LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals('Letter', v2, 'AC3/AC4: value changed, the old Phone value is gone.');
    }

    // ---- AC5: clearing back to empty ---------------------------------------
    @isTest
    static void clear_back_to_empty() {
        User u = mkTestUser('cl');
        assignPS(u);
        Id cid;
        System.runAs(u) {
            Contact c = new Contact(LastName = 'TEST-SCRUM-470-CLEAR', Preferred_Contact_Method__c = 'Email');
            insert c;
            cid = c.Id;
        }
        System.runAs(u) {
            Contact c2 = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :cid LIMIT 1];
            c2.Preferred_Contact_Method__c = null;
            update c2; // no exception = clearing is allowed (AC5)
        }
        String v;
        System.runAs(u) {
            v = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id = :cid LIMIT 1].Preferred_Contact_Method__c;
        }
        System.assertEquals(null, v, 'AC5: clearing the preference back to empty saves.');
    }

    // ---- AC1: exactly the 3 Picklist values (Schema reflection) -------------
    @isTest
    static void schema_exactly_three_values() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry e : Contact.Preferred_Contact_Method__c.getDescribe().getPicklistValues()) {
            values.add(e.getValue());
        }
        Set<String> expected = new Set<String>{ 'Phone', 'Email', 'Letter' };
        System.assertEquals(3, values.size(), 'AC1: exactly 3 Picklist values.');
        System.assertEquals(expected, values, 'AC1: the values are exactly Phone / Email / Letter.');
    }

    // ---- AC7: nothing automatic --------------------------------------------
    @isTest
    static void nothing_automated_side_effect() {
        User u = mkTestUser('auto');
        assignPS(u);
        Id cid;
        System.runAs(u) {
            Contact c = new Contact(
                LastName = 'TEST-SCRUM-470-AUTO-A',
                Phone = '+491111111111',
                Email = 'auto-a@example.invalid',
                Preferred_Contact_Method__c = 'Phone'
            );
            insert c;
            cid = c.Id;
            Contact other = new Contact(LastName = 'TEST-SCRUM-470-AUTO-B');
            insert other;
        }
        // The save touched one field only: the OTHER Contact stays empty, and the
        // record's own Phone/Email are unchanged — no trigger, no Flow, no reminder.
        List<Contact> carryingValue;
        List<Contact> othersCarryingValue;
        String phone;
        String email;
        System.runAs(u) {
            carryingValue = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Preferred_Contact_Method__c != null];
            othersCarryingValue = [SELECT Preferred_Contact_Method__c FROM Contact WHERE Id != :cid AND Preferred_Contact_Method__c != null];
            Contact after = [SELECT Phone, Email, Preferred_Contact_Method__c FROM Contact WHERE Id = :cid LIMIT 1];
            phone = after.Phone;
            email = after.Email;
        }
        System.assertEquals(1, carryingValue.size(),
            'AC7: only the record we set carries a preference — nothing filled in automatically.');
        System.assertEquals(0, othersCarryingValue.size(),
            'AC7: no second Contact received a preference (no automation).');
        System.assertEquals('+491111111111', phone, 'AC7: the Phone field of the record is untouched by the save.');
        System.assertEquals('auto-a@example.invalid', email, 'AC7: the Email field of the record is untouched by the save.');
    }
}
