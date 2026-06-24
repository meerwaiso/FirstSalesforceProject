/**
 * SCRUM293ChurnStatusTest — Apex-Tests für ChurnStatus__c Picklist-Feld
 *
 * Testet SCRUM-293: Inaktive Kunden automatisch als Churn-Gefahr markieren
 * - AC1: ChurnStatus__c Picklist-Feld existiert mit korrekten Werten
 * - AC2: 90+ Tage Inaktivität → automatisch "Churn-Gefahr"
 * - AC4: Manuelle Überschreibung des ChurnStatus möglich
 * - AC5: Apex-first — keine Flow-Lösung
 */
@isTest
private class SCRUM293ChurnStatusTest {

    /**
     * AC1: ChurnStatus__c Picklist-Feld existiert mit korrekten Werten
     * Testet, dass alle 4 Picklist-Werte verfügbar sind: Aktiv, Risikokunde, Churn-Gefahr, Churn
     */
    @isTest
    static void AC1_ChurnStatus_hasAllPicklistValues() {
        // Arrange & Act: Erstelle einen Account und setze jeden Picklist-Wert
        Account acc = new Account(Name = 'Picklist Test Kunde');
        insert acc;

        // Assert: Alle 4 Werte sollten gesetzt werden können
        String[] expectedValues = new String[] { 'Aktiv', 'Risikokunde', 'Churn_Gefahr', 'Churn' };

        for (String value : expectedValues) {
            acc.ChurnStatus__c = value;
            update acc;

            Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(value, updatedAcc.ChurnStatus__c,
                'ChurnStatus__c sollte den Wert "' + value + '" akzeptieren');
        }
    }

    /**
     * AC1 (Default): Neuer Account hat ChurnStatus__c = "Aktiv" als Default-Wert
     */
    @isTest
    static void AC1_NewAccount_hasDefaultAktiv() {
        // Arrange & Act
        Account acc = new Account(Name = 'Default Test Kunde');
        insert acc;

        // Assert
        Account createdAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Aktiv', createdAcc.ChurnStatus__c,
            'Neuer Account sollte Default-Wert "Aktiv" haben');
    }

    /**
     * AC2: 90+ Tage Inaktivität → automatisch "Churn-Gefahr"
     * Testet, dass der Scheduled Apex Job den Status korrekt aktualisiert
     */
    @isTest
    static void AC2_InactiveAccount_markedAsChurnGefahr() {
        // Arrange
        Account acc = new Account(
            Name = 'Inaktiver Kunde 90+ Tage',
            LastContactDate__c = Date.today().addDays(-95),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act
        Test.startTest();
        ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c,
            'Account mit 95 Tagen Inaktivität sollte als Churn_Gefahr markiert sein');
    }

    /**
     * AC2 (Grenzwert): Account mit genau 89 Tagen Inaktivität sollte NICHT markiert werden
     */
    @isTest
    static void AC2_AccountWith89Days_notMarked() {
        // Arrange
        Account acc = new Account(
            Name = 'Nur 89 Tage inaktiv',
            LastContactDate__c = Date.today().addDays(-89),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act
        Test.startTest();
        ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Aktiv', updatedAcc.ChurnStatus__c,
            'Account mit 89 Tagen Inaktivität sollte NICHT als Churn_Gefahr markiert sein');
    }

    /**
     * AC2 (Grenzwert): Account mit genau 90 Tagen Inaktivität SOLLTE markiert werden
     */
    @isTest
    static void AC2_AccountWithExactly90Days_isMarked() {
        // Arrange
        Account acc = new Account(
            Name = 'Genau 90 Tage inaktiv',
            LastContactDate__c = Date.today().addDays(-90),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act
        Test.startTest();
        ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c,
            'Account mit genau 90 Tagen Inaktivität sollte als Churn_Gefahr markiert sein');
    }

    /**
     * AC4: Manuelle Überschreibung des ChurnStatus möglich
     * Testet, dass der Account-Manager den Status manuell zurücksetzen kann
     */
    @isTest
    static void AC4_ManualOverride_possible() {
        // Arrange: Account wurde als Churn-Gefahr markiert
        Account acc = new Account(
            Name = 'Manuell überschreiben',
            LastContactDate__c = Date.today().addDays(-100),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Markiere als Churn-Gefahr
        Test.startTest();
        ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        Account markedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', markedAcc.ChurnStatus__c,
            'Account sollte zuerst als Churn_Gefahr markiert sein');

        // Act: Manuelle Überschreibung — Account-Manager setzt Status zurück auf "Aktiv"
        acc.ChurnStatus__c = 'Aktiv';
        update acc;

        // Assert
        Account overriddenAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Aktiv', overriddenAcc.ChurnStatus__c,
            'Manuelle Überschreibung auf "Aktiv" sollte möglich sein');
    }

    /**
     * AC4: Manuelle Überschreibung auf alle Picklist-Werte möglich
     */
    @isTest
    static void AC4_ManualOverride_toAllValues() {
        // Arrange
        Account acc = new Account(
            Name = 'Alle Werte testen',
            LastContactDate__c = Date.today().addDays(-100),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act & Assert: Setze jeden Wert manuell
        String[] values = new String[] { 'Risikokunde', 'Churn_Gefahr', 'Churn', 'Aktiv' };
        for (String value : values) {
            acc.ChurnStatus__c = value;
            update acc;

            Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
            System.assertEquals(value, updatedAcc.ChurnStatus__c,
                'Manuelle Überschreibung auf "' + value + '" sollte möglich sein');
        }
    }

    /**
     * AC5: Apex-first — keine Flow-Lösung
     * Testet, dass die ChurnDetectionService (Apex) die Logik implementiert,
     * nicht ein Flow. Dies wird durch das Vorhandensein und die Funktionalität
     * der Apex-Klasse verifiziert.
     */
    @isTest
    static void AC5_ApexFirst_NoFlowUsed() {
        // Arrange
        Account acc = new Account(
            Name = 'Apex-first Test',
            LastContactDate__c = Date.today().addDays(-100),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act: Die Apex-Service-Methode sollte die Logik ausführen
        Test.startTest();
        Integer result = ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert: Die Apex-Methode hat den Account markiert
        System.assertEquals(1, result,
            'Apex-Methode sollte 1 inaktiven Account finden und markieren');

        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c,
            'Apex-Logik sollte den ChurnStatus auf Churn_Gefahr setzen');
    }

    /**
     * Edge Case: Account mit NULL LastContactDate wird als inaktiv behandelt
     */
    @isTest
    static void EdgeCase_NullLastContactDate_isInactive() {
        // Arrange
        Account acc = new Account(
            Name = 'Kein Kontakt-Datum',
            LastContactDate__c = null,
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act
        Test.startTest();
        ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c,
            'Account mit NULL LastContactDate sollte als Churn_Gefahr markiert sein');
    }

    /**
     * Edge Case: Bulk-Verarbeitung — mehrere Accounts gleichzeitig
     */
    @isTest
    static void EdgeCase_BulkProcessing() {
        // Arrange
        List<Account> accounts = new List<Account>();

        // 3 inaktive Accounts
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(
                Name = 'Inaktiv Bulk ' + i,
                LastContactDate__c = Date.today().addDays(-100),
                ChurnStatus__c = 'Aktiv'
            ));
        }

        // 2 aktive Accounts
        for (Integer i = 0; i < 2; i++) {
            accounts.add(new Account(
                Name = 'Aktiv Bulk ' + i,
                LastContactDate__c = Date.today().addDays(-10),
                ChurnStatus__c = 'Aktiv'
            ));
        }

        insert accounts;

        // Act
        Test.startTest();
        Integer inactiveCount = ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        System.assertEquals(3, inactiveCount,
            'Es sollten genau 3 inaktive Accounts markiert werden');

        List<Account> updatedAccounts = [
            SELECT Name, ChurnStatus__c FROM Account WHERE Id IN :accounts
        ];

        Integer churnGefahrCount = 0;
        Integer aktivCount = 0;
        for (Account acc : updatedAccounts) {
            if (acc.ChurnStatus__c == 'Churn_Gefahr') {
                churnGefahrCount++;
            } else if (acc.ChurnStatus__c == 'Aktiv') {
                aktivCount++;
            }
        }

        System.assertEquals(3, churnGefahrCount,
            '3 Accounts sollten als Churn_Gefahr markiert sein');
        System.assertEquals(2, aktivCount,
            '2 Accounts sollten als Aktiv bleiben');
    }
}