/**
 * Test class for SCRUM-272: Garantie- und Altersprüfung bei Laptop-Anträgen
 * 
 * Tests die Validation Rule "Sonderbegruendung_erforderlich":
 * - Gerät älter als 3 Jahre → keine Sonderbegründung erforderlich
 * - Gerät jünger als 3 Jahre → Sonderbegründung erforderlich
 */
@isTest
private class SCRUM272SpecialJustificationTest {
    
    // Helper: Create a Laptop with Kaufdatum older than 3 years (should succeed without Sonderbegruendung)
    @isTest
    static void testLaptopOlderThan3Years_NoSonderbegruendungRequired() {
        // Arrange: Kaufdatum 4 years ago (older than 3 years = 1095 days)
        Date oldKaufdatum = Date.today().addYears(-4);
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Alter Laptop - 4 Jahre',
            Kaufdatum__c = oldKaufdatum,
            Sonderbegruendung__c = null
        );
        
        // Act & Assert: Should succeed without error
        Test.startTest();
        try {
            insert laptop;
            Test.stopTest();
            
            // Verify record was created
            Laptop__c created = [SELECT Id, Name, Kaufdatum__c FROM Laptop__c WHERE Id = :laptop.Id];
            System.assertEquals('Alter Laptop - 4 Jahre', created.Name);
            System.assertEquals(oldKaufdatum, created.Kaufdatum__c);
        } catch (Exception e) {
            Test.stopTest();
            System.assert(false, 'Expected no error for device older than 3 years, but got: ' + e.getMessage());
        }
    }
    
    // Helper: Create a Laptop with Kaufdatum younger than 3 years without Sonderbegruendung (should fail)
    @isTest
    static void testLaptopYoungerThan3Years_SonderbegruendungRequired() {
        // Arrange: Kaufdatum 1 year ago (younger than 3 years)
        Date recentKaufdatum = Date.today().addYears(-1);
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Neuer Laptop - 1 Jahr',
            Kaufdatum__c = recentKaufdatum,
            Sonderbegruendung__c = null
        );
        
        // Act & Assert: Should fail with validation error
        Test.startTest();
        try {
            insert laptop;
            Test.stopTest();
            System.assert(false, 'Expected validation error for device younger than 3 years without Sonderbegruendung');
        } catch (DmlException e) {
            Test.stopTest();
            String errorMessage = e.getMessage();
            System.assert(
                errorMessage.contains('weniger als 3 Jahre alt') || 
                errorMessage.contains('Sonderbegründung') ||
                errorMessage.contains('Sonderbegruendung'),
                'Expected validation error about 3-year rule, but got: ' + errorMessage
            );
        }
    }
    
    // Helper: Create a Laptop with Kaufdatum younger than 3 years WITH Sonderbegruendung (should succeed)
    @isTest
    static void testLaptopYoungerThan3Years_WithSonderbegruendung_Success() {
        // Arrange: Kaufdatum 1 year ago, but with Sonderbegruendung filled
        Date recentKaufdatum = Date.today().addYears(-1);
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Neuer Laptop mit Begründung',
            Kaufdatum__c = recentKaufdatum,
            Sonderbegruendung__c = 'Gerät ist defekt und muss ersetzt werden'
        );
        
        // Act & Assert: Should succeed with Sonderbegruendung
        Test.startTest();
        try {
            insert laptop;
            Test.stopTest();
            
            // Verify record was created
            Laptop__c created = [SELECT Id, Name, Kaufdatum__c, Sonderbegruendung__c FROM Laptop__c WHERE Id = :laptop.Id];
            System.assertEquals('Neuer Laptop mit Begründung', created.Name);
            System.assertEquals(recentKaufdatum, created.Kaufdatum__c);
            System.assertNotEquals(null, created.Sonderbegruendung__c);
        } catch (Exception e) {
            Test.stopTest();
            System.assert(false, 'Expected success with Sonderbegruendung, but got: ' + e.getMessage());
        }
    }
    
    // Helper: Create a Laptop with today's Kaufdatum without Sonderbegruendung (should fail)
    @isTest
    static void testLaptopTodayKaufdatum_SonderbegruendungRequired() {
        // Arrange: Kaufdatum = today (definitely younger than 3 years)
        Date todayKaufdatum = Date.today();
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Heutiges Gerät',
            Kaufdatum__c = todayKaufdatum,
            Sonderbegruendung__c = null
        );
        
        // Act & Assert: Should fail
        Test.startTest();
        try {
            insert laptop;
            Test.stopTest();
            System.assert(false, 'Expected validation error for today\'s Kaufdatum without Sonderbegruendung');
        } catch (DmlException e) {
            Test.stopTest();
            String errorMessage = e.getMessage();
            System.assert(
                errorMessage.contains('weniger als 3 Jahre alt') || 
                errorMessage.contains('Sonderbegründung') ||
                errorMessage.contains('Sonderbegruendung'),
                'Expected validation error about 3-year rule, but got: ' + errorMessage
            );
        }
    }
    
    // Helper: Boundary test - Kaufdatum exactly at 3 years (1095 days) - should NOT require Sonderbegruendung
    @isTest
    static void testLaptopExactly3Years_NoSonderbegruendungRequired() {
        // Arrange: Kaufdatum exactly 1095 days ago (3 years = 1095 days)
        // TODAY() - 1095 = exactly 3 years ago
        // Validation rule triggers when Kaufdatum__c > TODAY() - 1095
        // So Kaufdatum = TODAY() - 1095 should NOT trigger (equal, not greater)
        Date exactly3YearsAgo = Date.today().addDays(-1095);
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Genau 3 Jahre alt',
            Kaufdatum__c = exactly3YearsAgo,
            Sonderbegruendung__c = null
        );
        
        // Act & Assert: Should succeed (Kaufdatum is NOT greater than TODAY()-1095, it equals it)
        Test.startTest();
        try {
            insert laptop;
            Test.stopTest();
            
            // Verify record was created
            Laptop__c created = [SELECT Id, Name, Kaufdatum__c FROM Laptop__c WHERE Id = :laptop.Id];
            System.assertEquals('Genau 3 Jahre alt', created.Name);
        } catch (Exception e) {
            Test.stopTest();
            System.assert(false, 'Expected no error for device exactly 3 years old, but got: ' + e.getMessage());
        }
    }
    
    // Helper: Boundary test - Kaufdatum 1 day less than 3 years (1094 days) - should require Sonderbegruendung
    @isTest
    static void testLaptopJustUnder3Years_SonderbegruendungRequired() {
        // Arrange: Kaufdatum 1094 days ago (1 day less than 3 years)
        Date justUnder3Years = Date.today().addDays(-1094);
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Fast 3 Jahre alt',
            Kaufdatum__c = justUnder3Years,
            Sonderbegruendung__c = null
        );
        
        // Act & Assert: Should fail (Kaufdatum IS greater than TODAY()-1095)
        Test.startTest();
        try {
            insert laptop;
            Test.stopTest();
            System.assert(false, 'Expected validation error for device just under 3 years without Sonderbegruendung');
        } catch (DmlException e) {
            Test.stopTest();
            String errorMessage = e.getMessage();
            System.assert(
                errorMessage.contains('weniger als 3 Jahre alt') || 
                errorMessage.contains('Sonderbegründung') ||
                errorMessage.contains('Sonderbegruendung'),
                'Expected validation error about 3-year rule, but got: ' + errorMessage
            );
        }
    }
    
    // Helper: Verify Sonderbegruendung__c field exists and is writable
    @isTest
    static void testSonderbegruendungFieldExists() {
        // Arrange
        String longJustification = 'Dieses Gerät ist leider defekt und kann nicht mehr verwendet werden. ' +
            'Ein Ersatz ist dringend erforderlich für die tägliche Arbeit am Arbeitsplatz.';
        
        Laptop__c laptop = new Laptop__c(
            Name = 'Feld-Test Laptop',
            Kaufdatum__c = Date.today(),
            Sonderbegruendung__c = longJustification
        );
        
        // Act
        Test.startTest();
        insert laptop;
        Test.stopTest();
        
        // Assert
        Laptop__c created = [SELECT Id, Sonderbegruendung__c FROM Laptop__c WHERE Id = :laptop.Id];
        System.assertEquals(longJustification, created.Sonderbegruendung__c);
    }
}