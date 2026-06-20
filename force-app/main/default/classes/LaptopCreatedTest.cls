@isTest
private class LaptopCreatedTest {
    @isTest
    static void test_createLaptopWithAllFields() {
        Test.startTest();

        Laptop__c laptop = new Laptop__c(
            Name = 'Test Laptop Vollständig',
            Seriennummer__c = 'SN123456789',
            Marke__c = 'Lenovo',
            Modell__c = 'ThinkPad X1 Carbon',
            Kunde__c = 'Max Mustermann',
            Verkaeufer__c = 'Anna Schmidt',
            Preis__c = 1999.99,
            Kondition__c = 'Neu',
            Farbe__c = 'Schwarz',
            CPU__c = 'Intel Core i7-1260P',
            RAM__c = '16 GB DDR5',
            Speicherkapazitaet__c = '512 GB SSD',
            Kaufdatum__c = Date.today(),
            Verkaufsdatum__c = Date.today(),
            Garantie_bis__c = Date.today().addYears(2),
            Gewaehrleistungsnummer__c = 'GW987654321',
            Status__c = 'Verfuegbar'
        );
        insert laptop;

        Test.stopTest();

        System.assert(laptop.Id != null, 'Laptop should be created');

        // Verify all fields are saved correctly
        Laptop__c saved = [SELECT Id, Name, Seriennummer__c, Marke__c, Modell__c, Kunde__c,
                           Verkaeufer__c, Preis__c, Kondition__c, Farbe__c, CPU__c, RAM__c,
                           Speicherkapazitaet__c, Kaufdatum__c, Verkaufsdatum__c, Garantie_bis__c,
                           Gewaehrleistungsnummer__c, Status__c
                           FROM Laptop__c WHERE Id = :laptop.Id];

        System.assertEquals('Test Laptop Vollständig', saved.Name, 'Name should match');
        System.assertEquals('SN123456789', saved.Seriennummer__c, 'Seriennummer should match');
        System.assertEquals('Lenovo', saved.Marke__c, 'Marke should match');
        System.assertEquals('ThinkPad X1 Carbon', saved.Modell__c, 'Modell should match');
        System.assertEquals('Max Mustermann', saved.Kunde__c, 'Kunde should match');
        System.assertEquals('Anna Schmidt', saved.Verkaeufer__c, 'Verkaeufer should match');
        System.assertEquals(1999.99, saved.Preis__c, 'Preis should match');
        System.assertEquals('Neu', saved.Kondition__c, 'Kondition should match');
        System.assertEquals('Schwarz', saved.Farbe__c, 'Farbe should match');
        System.assertEquals('Intel Core i7-1260P', saved.CPU__c, 'CPU should match');
        System.assertEquals('16 GB DDR5', saved.RAM__c, 'RAM should match');
        System.assertEquals('512 GB SSD', saved.Speicherkapazitaet__c, 'Speicherkapazitaet should match');
        System.assertEquals('Verfuegbar', saved.Status__c, 'Status should match');
    }

    @isTest
    static void test_createLaptopOnlyName() {
        Test.startTest();

        Laptop__c laptop = new Laptop__c(
            Name = 'Test Laptop Minimal'
        );
        insert laptop;

        Test.stopTest();

        System.assert(laptop.Id != null, 'Laptop should be created with only Name');
    }

    @isTest
    static void test_createLaptopUpdatesSuccessfully() {
        Test.startTest();

        Laptop__c laptop = new Laptop__c(
            Name = 'Test Laptop Update',
            Status__c = 'Verfuegbar'
        );
        insert laptop;

        laptop.Status__c = 'Verkauft';
        laptop.Kunde__c = 'Neuer Kunde';
        update laptop;

        Test.stopTest();

        Laptop__c updated = [SELECT Status__c, Kunde__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals('Verkauft', updated.Status__c, 'Status should be updated');
        System.assertEquals('Neuer Kunde', updated.Kunde__c, 'Kunde should be updated');
    }

    @isTest
    static void test_createLaptopDeletesSuccessfully() {
        Test.startTest();

        Laptop__c laptop = new Laptop__c(
            Name = 'Test Laptop Delete'
        );
        insert laptop;
        Id laptopId = laptop.Id;

        delete laptop;

        Test.stopTest();

        List<Laptop__c> deleted = [SELECT Id FROM Laptop__c WHERE Id = :laptopId];
        System.assertEquals(0, deleted.size(), 'Laptop should be deleted');
    }

    @isTest
    static void test_createMultipleLaptops() {
        Test.startTest();

        List<Laptop__c> laptops = new List<Laptop__c>();
        for (Integer i = 0; i < 5; i++) {
            laptops.add(new Laptop__c(
                Name = 'Laptop ' + i,
                Marke__c = 'Apple',
                Modell__c = 'MacBook Pro',
                Status__c = 'Bestellt'
            ));
        }
        insert laptops;

        Test.stopTest();

        List<Laptop__c> saved = [SELECT Id, Name, Marke__c, Status__c FROM Laptop__c WHERE Marke__c = 'Apple'];
        System.assertEquals(5, saved.size(), 'Should have 5 Apple laptops');
    }

    @isTest
    static void test_laptopPicklistValues() {
        Test.startTest();

        // Test Kondition picklist values
        Laptop__c neu = new Laptop__c(Name = 'Neu', Kondition__c = 'Neu');
        Laptop__c gebraucht = new Laptop__c(Name = 'Gebraucht', Kondition__c = 'Gebraucht');
        Laptop__c refurbished = new Laptop__c(Name = 'Refurbished', Kondition__c = 'Refurbished');

        // Test Status picklist values
        Laptop__c verfuegbar = new Laptop__c(Name = 'Verfuegbar', Status__c = 'Verfuegbar');
        Laptop__c verkauft = new Laptop__c(Name = 'Verkauft', Status__c = 'Verkauft');
        Laptop__c inReparatur = new Laptop__c(Name = 'In_Reparatur', Status__c = 'In_Reparatur');
        Laptop__c bestellt = new Laptop__c(Name = 'Bestellt', Status__c = 'Bestellt');

        insert new List<Laptop__c>{neu, gebraucht, refurbished, verfuegbar, verkauft, inReparatur, bestellt};

        Test.stopTest();

        System.assertEquals(7, [SELECT Count() FROM Laptop__c], 'All 7 laptops should be created');
    }

    @isTest
    static void test_laptopCurrencyField() {
        Test.startTest();

        Laptop__c laptop = new Laptop__c(
            Name = 'Teurer Laptop',
            Preis__c = 4999.99
        );
        insert laptop;

        Test.stopTest();

        Laptop__c saved = [SELECT Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(4999.99, saved.Preis__c, 'Preis should be 4999.99');
    }

    @isTest
    static void test_laptopDateFields() {
        Test.startTest();

        Date kaufDatum = Date.newInstance(2025, 1, 15);
        Date verkaufsDatum = Date.newInstance(2025, 2, 1);
        Date garantieBis = Date.newInstance(2027, 1, 15);

        Laptop__c laptop = new Laptop__c(
            Name = 'Laptop mit Daten',
            Kaufdatum__c = kaufDatum,
            Verkaufsdatum__c = verkaufsDatum,
            Garantie_bis__c = garantieBis
        );
        insert laptop;

        Test.stopTest();

        Laptop__c saved = [SELECT Kaufdatum__c, Verkaufsdatum__c, Garantie_bis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(kaufDatum, saved.Kaufdatum__c, 'Kaufdatum should match');
        System.assertEquals(verkaufsDatum, saved.Verkaufsdatum__c, 'Verkaufsdatum should match');
        System.assertEquals(garantieBis, saved.Garantie_bis__c, 'Garantie_bis should match');
    }
}