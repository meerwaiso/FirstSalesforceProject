@isTest
private class SmartphoneObjectTest {
    @isTest
    static void smartphone_object_creates_record() {
        Test.startTest();

        Smartphone__c sp = new Smartphone__c(
            Name = 'Test-Smartphone-001'
        );
        insert sp;

        Test.stopTest();

        System.assert(sp.Id != null, 'Smartphone-Record sollte erstellt werden');

        // Re-query to confirm persistence
        Smartphone__c fromDB = [SELECT Id, Name FROM Smartphone__c WHERE Id = :sp.Id];
        System.assertEquals('Test-Smartphone-001', fromDB.Name, 'Name muss stimmen');
    }

    @isTest
    static void all_14_fields_writable_and_queryable() {
        Test.startTest();

        Account acc = new Account(Name = 'Testkunde' );
        insert acc;

        User[] users = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        System.assert(users.size() == 1, 'Mindestens ein aktiver User muss existieren');

        Date today    = Date.today();
        Date warranty = today.addDays(365);

        Smartphone__c sp = new Smartphone__c(
            Name                       = 'Full-Field-Phone',
            Modell__c                   = 'Galaxy S24',
            Marke__c                    = 'Samsung',
            Kaufdatum__c                = today,
            Kunde__c                    = acc.Id,
            Preis__c                    = 899.99,
            Seriennummer__c             = 'SN-TEST-001',
            Status__c                   = 'Verfübar',
            Verkaeufer__c               = users[0].Id,
            Verkaufsdatum__c            = today,
            Farbe__c                    = 'Schwarz',
            Speicherkapazitaet__c       = '256GB',
            Garantie_bis__c             = warranty,
            Kondition__c                = 'Neu',
            Gewaehrleistungsnummer__c   = 'GLR-987654321'
        );
        insert sp;

        Test.stopTest();

        // Re-query ALL fields
        Smartphone__c fromDB = [
            SELECT Id, Name, Modell__c, Marke__c, Kaufdatum__c, Kunde__c,
                   Preis__c, Seriennummer__c, Status__c, Verkaeufer__c,
                   Verkaufsdatum__c, Farbe__c, Speicherkapazitaet__c,
                   Garantie_bis__c, Kondition__c, Gewaehrleistungsnummer__c
            FROM   Smartphone__c
            WHERE  Id = :sp.Id
        ];

        System.assertEquals('Galaxy S24',     fromDB.Modell__c,                   'Modell');
        System.assertEquals('Samsung',        fromDB.Marke__c,                    'Marke');
        System.assertEquals(today,            fromDB.Kaufdatum__c,                'Kaufdatum');
        System.assertEquals(acc.Id,           fromDB.Kunde__c,                    'Kunde (Account)');
        System.assertEquals(899.99,           fromDB.Preis__c,                    'Preis');
        System.assertEquals('SN-TEST-001',    fromDB.Seriennummer__c,             'Seriennummer');
        System.assertEquals('Verfübar',       fromDB.Status__c,                   'Status');
        System.assertEquals(users[0].Id,      fromDB.Verkaeufer__c,               'Verkäufer (User)');
        System.assertEquals(today,            fromDB.Verkaufsdatum__c,            'Verkaufsdatum');
        System.assertEquals('Schwarz',        fromDB.Farbe__c,                    'Farbe');
        System.assertEquals('256GB',          fromDB.Speicherkapazitaet__c,       'Speicherkapazität');
        System.assertEquals(warranty,         fromDB.Garantie_bis__c,             'Garantie bis');
        System.assertEquals('Neu',            fromDB.Kondition__c,                'Kondition');
        System.assertEquals('GLR-987654321',  fromDB.Gewaehrleistungsnummer__c,   'Gewährleistungsnummer');
    }

    @isTest
    static void status_picklist_correct_values() {
        Test.startTest();

        String[] expected = new String[]{'Verfübar', 'Reserviert', 'In_Betrieb', 'Verkauft', 'Ausgemustert'};

        for (String val : expected) {
            Smartphone__c sp = new Smartphone__c(
                Name           = 'Status-' + val,
                Seriennummer__c = 'SN-STATUS-' + val,
                Status__c      = val
            );
            insert sp;

            Smartphone__c fromDB = [SELECT Status__c FROM Smartphone__c WHERE Id = :sp.Id];
            System.assertEquals(val, fromDB.Status__c, 'Status-Picklist Wert: ' + val);
        }

        Test.stopTest();
    }

    @isTest
    static void speicherkapazitaet_picklist_correct_values() {
        Test.startTest();

        String[] expected = new String[]{'64GB', '128GB', '256GB', '512GB', '1TB'};

        for (String val : expected) {
            Smartphone__c sp = new Smartphone__c(
                Name                      = 'Speicher-' + val,
                Seriennummer__c           = 'SN-SP-' + val,
                Speicherkapazitaet__c     = val
            );
            insert sp;

            Smartphone__c fromDB = [SELECT Speicherkapazitaet__c FROM Smartphone__c WHERE Id = :sp.Id];
            System.assertEquals(val, fromDB.Speicherkapazitaet__c, 'Speicherkapazität-Picklist Wert: ' + val);
        }

        Test.stopTest();
    }

    @isTest
    static void kondition_picklist_correct_values() {
        Test.startTest();

        String[] expected = new String[]{'Neu', 'Wie_Neu', 'Gut', 'Angezischt'};

        for (String val : expected) {
            Smartphone__c sp = new Smartphone__c(
                Name           = 'Kondition-' + val,
                Seriennummer__c = 'SN-KOND-' + val,
                Kondition__c   = val
            );
            insert sp;

            Smartphone__c fromDB = [SELECT Kondition__c FROM Smartphone__c WHERE Id = :sp.Id];
            System.assertEquals(val, fromDB.Kondition__c, 'Kondition-Picklist Wert: ' + val);
        }

        Test.stopTest();
    }

    @isTest
    static void seriennummer_unique_constraint() {
        Smartphone__c sp1 = new Smartphone__c(
            Name           = 'Unique-Phone-01',
            Seriennummer__c = 'SN-UNIQUE-123'
        );
        insert sp1;

        Smartphone__c sp2 = new Smartphone__c(
            Name           = 'Unique-Phone-02',
            Seriennummer__c = 'SN-UNIQUE-123'
        );

        boolean exceptionThrown = false;
        try {
            insert sp2;
        } catch (DmlException e) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'Doppelte Seriennummer muss DmlException werfen');
    }
}
