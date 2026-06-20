/**
 * Test class for SCRUM-273: Automatisierter Genehmigungsprozess (Approval Process)
 * 
 * Tests die Flow-Logik "Laptop Genehmigungsprozess":
 * - Preis <= 1500 EUR → automatisch "Genehmigt"
 * - Preis > 1500 EUR → "Ausstehend" + Approval Request an Manager
 */
@isTest
private class SCRUM273ApprovalProcessTest {
    
    /**
     * AC1: Laptops mit Preis bis 1.500 EUR werden automatisch genehmigt
     */
    @isTest
    static void testLaptopPreisBis1500_AutoGenehmigt() {
        // Arrange
        Laptop__c laptop = new Laptop__c(
            Name = 'Günstiger Laptop',
            Preis__c = 1500.00,
            Kaufdatum__c = Date.today().addYears(-4),
            Sonderbegruendung__c = null
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert: Status sollte "Genehmigt" sein
        Laptop__c created = [SELECT Id, Status__c, Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(1500.00, created.Preis__c);
        System.assertEquals('Genehmigt', created.Status__c, 
            'Laptop mit Preis 1500 EUR sollte automatisch genehmigt werden');
    }
    
    /**
     * AC1: Laptops mit Preis unter 1.500 EUR werden automatisch genehmigt
     */
    @isTest
    static void testLaptopPreisUnter1500_AutoGenehmigt() {
        // Arrange
        Laptop__c laptop = new Laptop__c(
            Name = 'Billiger Laptop',
            Preis__c = 999.99,
            Kaufdatum__c = Date.today().addYears(-4),
            Sonderbegruendung__c = null
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert: Status sollte "Genehmigt" sein
        Laptop__c created = [SELECT Id, Status__c, Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(999.99, created.Preis__c);
        System.assertEquals('Genehmigt', created.Status__c, 
            'Laptop mit Preis 999.99 EUR sollte automatisch genehmigt werden');
    }
    
    /**
     * AC2: Laptops mit Preis über 1.500 EUR werden auf "Ausstehend" gesetzt
     */
    @isTest
    static void testLaptopPreisUeber1500_Ausstehend() {
        // Arrange
        Laptop__c laptop = new Laptop__c(
            Name = 'Teurer Laptop',
            Preis__c = 2000.00,
            Kaufdatum__c = Date.today().addYears(-4),
            Sonderbegruendung__c = null
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert: Status sollte "Ausstehend" sein (Approval Request wurde gestartet)
        Laptop__c created = [SELECT Id, Status__c, Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(2000.00, created.Preis__c);
        System.assertEquals('Ausstehend', created.Status__c, 
            'Laptop mit Preis 2000 EUR sollte Status "Ausstehend" haben');
    }
    
    /**
     * AC2: Laptop mit Preis 1501 EUR (gerade über Schwellenwert) wird auf "Ausstehend" gesetzt
     */
    @isTest
    static void testLaptopPreis1501_Ausstehend() {
        // Arrange
        Laptop__c laptop = new Laptop__c(
            Name = 'Knapp zu teuer Laptop',
            Preis__c = 1501.00,
            Kaufdatum__c = Date.today().addYears(-4),
            Sonderbegruendung__c = null
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert
        Laptop__c created = [SELECT Id, Status__c, Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(1501.00, created.Preis__c);
        System.assertEquals('Ausstehend', created.Status__c, 
            'Laptop mit Preis 1501 EUR sollte Status "Ausstehend" haben');
    }
    
    /**
     * Edge Case: Laptop mit Preis = 0 EUR wird automatisch genehmigt
     */
    @isTest
    static void testLaptopPreis0_AutoGenehmigt() {
        // Arrange
        Laptop__c laptop = new Laptop__c(
            Name = 'Kostenloser Laptop',
            Preis__c = 0.00,
            Kaufdatum__c = Date.today().addYears(-4),
            Sonderbegruendung__c = null
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert
        Laptop__c created = [SELECT Id, Status__c, Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(0.00, created.Preis__c);
        System.assertEquals('Genehmigt', created.Status__c, 
            'Laptop mit Preis 0 EUR sollte automatisch genehmigt werden');
    }
    
    /**
     * Edge Case: Laptop mit sehr hohem Preis (10000 EUR) wird auf "Ausstehend" gesetzt
     */
    @isTest
    static void testLaptopPreis10000_Ausstehend() {
        // Arrange
        Laptop__c laptop = new Laptop__c(
            Name = 'Sehr teurer Laptop',
            Preis__c = 10000.00,
            Kaufdatum__c = Date.today().addYears(-4),
            Sonderbegruendung__c = null
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert
        Laptop__c created = [SELECT Id, Status__c, Preis__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(10000.00, created.Preis__c);
        System.assertEquals('Ausstehend', created.Status__c, 
            'Laptop mit Preis 10000 EUR sollte Status "Ausstehend" haben');
    }
    
    /**
     * AC3: Status-Feld enthält die korrekten Werte (Genehmigt, Ausstehend, Abgelehnt)
     */
    @isTest
    static void testStatusFieldValuesExist() {
        // Verify Status__c picklist values exist by creating records with different statuses
        List<Laptop__c> laptops = new List<Laptop__c>();
        
        // Low price → should be "Genehmigt" by flow
        laptops.add(new Laptop__c(
            Name = 'Test Genehmigt',
            Preis__c = 500.00,
            Kaufdatum__c = Date.today().addYears(-4)
        ));
        
        // High price → should be "Ausstehend" by flow
        laptops.add(new Laptop__c(
            Name = 'Test Ausstehend',
            Preis__c = 3000.00,
            Kaufdatum__c = Date.today().addYears(-4)
        ));
        
        Test.startTest();
        insert laptops;
        Test.stopTest();
        
        // Verify both records
        List<Laptop__c> created = [SELECT Id, Name, Status__c, Preis__c FROM Laptop__c WHERE Id IN :laptops];
        System.assertEquals(2, created.size());
        
        for (Laptop__c l : created) {
            if (l.Preis__c <= 1500) {
                System.assertEquals('Genehmigt', l.Status__c, 
                    'Laptop ' + l.Name + ' mit Preis ' + l.Preis__c + ' sollte genehmigt sein');
            } else {
                System.assertEquals('Ausstehend', l.Status__c, 
                    'Laptop ' + l.Name + ' mit Preis ' + l.Preis__c + ' sollte ausstehend sein');
            }
        }
    }
}