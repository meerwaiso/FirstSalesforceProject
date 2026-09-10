/**
 * [SCRUM-405] Functional test for the new formula field
 * Contact.Firmen_Telefonnummer__c ("Telefon Firma").
 *
 * Formula: Account.Phone (Lookup-Cross-Reference, read-only, Text).
 * The value is a LIVE reference to the Account record, so:
 *   - Account has a Phone        -> Contact shows that phone
 *   - Account has no Phone       -> Contact shows null (blank)
 *   - Contact has no Account     -> Contact shows null (blank)
 *   - Account phone is changed   -> Contact immediately shows the new number
 * The field must be a system-calculated Formelfeld (ADR-6), never user-updatable.
 *
 * Everything created here rolls back with the test transaction.
 * Vorbild 1:1 SCRUM-382 (erprobt). Kein Trigger, kein Apex außer Tests.
 */
@isTest
private class SCRUM405FirmenTelefonnummerValueTest {

    @isTest
    static void accountWithPhone_contactShowsAccountPhone_readOnlyFormula() {
        // Account WITH a phone number (the primary case we want to prove).
        Account acc = new Account(Name = '[SCRUM-405-Test]Acme', Phone = '+4355123456');
        insert acc;

        Contact c = new Contact(LastName = 'Mustermann', AccountId = acc.Id, Phone = '+43660888888');
        insert c;

        // Formula fields are NOT populated on the in-memory sObject after DML —
        // query the record back so Firmen_Telefonnummer__c is computed.
        Contact fresh = [SELECT Phone, Firmen_Telefonnummer__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(
            '+4355123456', fresh.Firmen_Telefonnummer__c,
            'Contact must show the Account phone (Account.Phone live reference)'
        );

        // It is the FIRM's number, not the Contact's own Durchwahl.
        System.assertNotEquals(
            fresh.Phone, fresh.Firmen_Telefonnummer__c,
            'Firmen_Telefonnummer__c is the firm number, not the contact direct dial'
        );

        // Field must be a system-calculated Formelfeld (ADR-6): Text type, read-only.
        Schema.DescribeFieldResult f = Contact.Firmen_Telefonnummer__c.getDescribe();
        System.assertEquals(
            true, f.isCalculated(),
            'Firmen_Telefonnummer__c must be a calculated (formula) field'
        );
        System.assertEquals(
            false, f.isUpdateable(),
            'Firmen_Telefonnummer__c must be read-only (formula, no user edit)'
        );
        System.assertEquals(
            'STRING', f.getType().name(),
            'Firmen_Telefonnummer__c must be a Text (String) formula field'
        );
    }

    @isTest
    static void accountWithoutPhone_contactShowsBlank() {
        Account acc = new Account(Name = '[SCRUM-405-Test]NoPhone'); // no Phone
        insert acc;
        Contact c = new Contact(LastName = 'BlankPhone', AccountId = acc.Id);
        insert c;
        Contact fresh = [SELECT Firmen_Telefonnummer__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(
            null, fresh.Firmen_Telefonnummer__c,
            'Account without a phone number -> Contact firm-phone field stays blank'
        );
    }

    @isTest
    static void contactWithoutAccount_contactShowsBlank() {
        Contact c = new Contact(LastName = 'NoFirm'); // no AccountId
        insert c;
        Contact fresh = [SELECT Firmen_Telefonnummer__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(
            null, fresh.Firmen_Telefonnummer__c,
            'Contact without an Account -> firm-phone field stays blank'
        );
    }

    @isTest
    static void accountPhoneChanged_contactShowsNewNumber() {
        Account acc = new Account(Name = '[SCRUM-405-Test]Change', Phone = '+43551000000');
        insert acc;
        Contact c = new Contact(LastName = 'ChangeWatch', AccountId = acc.Id);
        insert c;
        System.assertEquals(
            '+43551000000',
            [SELECT Firmen_Telefonnummer__c FROM Contact WHERE Id = :c.Id].Firmen_Telefonnummer__c,
            'before change: Contact shows the Account phone'
        );

        // Live reference: change the Account phone; no Contact change, no recalc/rollup.
        acc.Phone = '+4355198765';
        update acc;
        System.assertEquals(
            '+4355198765',
            [SELECT Firmen_Telefonnummer__c FROM Contact WHERE Id = :c.Id].Firmen_Telefonnummer__c,
            'after Account phone change: Contact immediately shows the new number (live reference)'
        );
    }
}
