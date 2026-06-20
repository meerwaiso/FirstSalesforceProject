/**
 * Test class for SCRUM-274: Lagerbestandspruefung
 * 
 * Der Lagerbestands-Flow ist ein Update-Trigger (triggerType=Update).
 * Tests muessen Records erst erstellen und dann den Status auf 'Genehmigt' aktualisieren,
 * damit der Flow feuert. Picklist-Werte verwenden Unterstrich (Auf_Lager, nicht 'Auf Lager').
 */
@isTest
private class SCRUM274LagerbestandspruefungTest {
    
    @isTest
    static void testLaptopAufLager_Verfuegbar_Zugewiesen() {
        // Lager-Laptop mit korrektem Picklist-Wert 'Auf_Lager'
        Laptop__c lagerLaptop = new Laptop__c(
            Name = 'Lager-Laptop Dell XPS',
            Modell__c = 'Dell XPS 15',
            Status__c = 'Auf_Lager',
            Kaufdatum__c = Date.today().addYears(-4)
        );
        insert lagerLaptop;
        
        // Antrag zuerst ohne Status erstellen, dann auf 'Genehmigt' setzen (Update-Trigger)
        Laptop__c antrag = new Laptop__c(
            Name = 'Antrag Dell XPS',
            Modell__c = 'Dell XPS 15',
            Kaufdatum__c = Date.today().addYears(-4)
        );
        insert antrag;
        
        Test.startTest();
        antrag.Status__c = 'Genehmigt';
        update antrag;
        Test.stopTest();
        
        Laptop__c createdAntrag = [SELECT Id, Status__c FROM Laptop__c WHERE Id = :antrag.Id];
        System.assertEquals('Zugewiesen', createdAntrag.Status__c, 
            'Antrag sollte Zugewiesen sein, da Laptop auf Lager ist');
        
        Laptop__c updatedLager = [SELECT Id, Status__c FROM Laptop__c WHERE Id = :lagerLaptop.Id];
        System.assertEquals('Zugewiesen', updatedLager.Status__c, 
            'Lager-Laptop sollte Zugewiesen sein');
    }
    
    @isTest
    static void testLaptopNichtAufLager_Nachbestellung() {
        // Antrag erst erstellen, dann auf 'Genehmigt' setzen (Update-Trigger)
        Laptop__c antrag = new Laptop__c(
            Name = 'Antrag Rares Modell',
            Modell__c = 'Rares Modell X',
            Kaufdatum__c = Date.today().addYears(-4)
        );
        insert antrag;
        
        Test.startTest();
        antrag.Status__c = 'Genehmigt';
        update antrag;
        Test.stopTest();
        
        Laptop__c createdAntrag = [SELECT Id, Status__c FROM Laptop__c WHERE Id = :antrag.Id];
        System.assertEquals('Nachbestellung', createdAntrag.Status__c, 
            'Antrag sollte Nachbestellung sein, da kein Laptop auf Lager ist');
    }
    
    @isTest
    static void testAndereModelleAufLager_Nachbestellung() {
        Laptop__c lagerLaptop = new Laptop__c(
            Name = 'Lager-Laptop HP',
            Modell__c = 'HP Pavilion',
            Status__c = 'Auf_Lager',
            Kaufdatum__c = Date.today().addYears(-4)
        );
        insert lagerLaptop;
        
        Laptop__c antrag = new Laptop__c(
            Name = 'Antrag Dell',
            Modell__c = 'Dell XPS 15',
            Kaufdatum__c = Date.today().addYears(-4)
        );
        insert antrag;
        
        Test.startTest();
        antrag.Status__c = 'Genehmigt';
        update antrag;
        Test.stopTest();
        
        Laptop__c createdAntrag = [SELECT Id, Status__c FROM Laptop__c WHERE Id = :antrag.Id];
        System.assertEquals('Nachbestellung', createdAntrag.Status__c, 
            'Antrag sollte Nachbestellung sein, da Dell nicht auf Lager ist');
        
        Laptop__c updatedLager = [SELECT Id, Status__c FROM Laptop__c WHERE Id = :lagerLaptop.Id];
        System.assertEquals('Auf_Lager', updatedLager.Status__c, 
            'HP Laptop sollte unveraendert Auf_Lager bleiben');
    }
}
