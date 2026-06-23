/**
 * SCRUM292ChurnDetectionTest — Apex-Tests für Churn-Erkennung
 *
 * Testet:
 * - ChurnDetectionService.getConfig()
 * - ChurnDetectionService.findAndMarkInactiveAccounts()
 * - ChurnDetectionService.createChurnTasks() (indirekt)
 * - ChurnDetectionScheduler.execute()
 * - AccountLastContactHandler.updateLastContactDateOnCreate()
 * - AccountLastContactHandler.updateLastContactDateOnUpdate()
 */
@isTest
private class SCRUM292ChurnDetectionTest {

    /**
     * Testet, dass getConfig() Standardwerte zurückgibt
     */
    @isTest
    static void getConfig_returnsDefaultValues() {
        ChurnDetectionService.ChurnConfig config = ChurnDetectionService.getConfig();

        System.assertEquals(90, config.daysThreshold, 'daysThreshold sollte 90 sein');
        System.assertEquals('Churn_Gefahr', config.churnStatusValue, 'churnStatusValue sollte Churn_Gefahr sein');
        System.assertEquals(2, config.taskDueDays, 'taskDueDays sollte 2 sein');
        System.assertNotEquals(null, config.taskSubject, 'taskSubject sollte nicht null sein');
    }

    /**
     * Testet, dass inaktive Accounts (LastContactDate < threshold) als Churn-Gefahr markiert werden
     */
    @isTest
    static void findAndMarkInactiveAccounts_marksInactiveAccounts() {
        // Arrange: Erstelle einen Account mit alter LastContactDate
        Account acc = new Account(
            Name = 'Inaktiver Kunde',
            LastContactDate__c = Date.today().addDays(-100),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Arrange: Erstelle einen aktiven Account
        Account activeAcc = new Account(
            Name = 'Aktiver Kunde',
            LastContactDate__c = Date.today().addDays(-10),
            ChurnStatus__c = 'Aktiv'
        );
        insert activeAcc;

        // Act
        Test.startTest();
        Integer inactiveCount = ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert: Nur der inaktive Account wurde markiert
        System.assertEquals(1, inactiveCount, 'Es sollte genau 1 inaktiver Account gefunden werden');

        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c, 'Inaktiver Account sollte als Churn_Gefahr markiert sein');

        Account updatedActiveAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :activeAcc.Id];
        System.assertEquals('Aktiv', updatedActiveAcc.ChurnStatus__c, 'Aktiver Account sollte unverändert bleiben');

        // Assert: Task wurde für den inaktiven Account erstellt
        List<Task> churnTasks = [
            SELECT Id, WhatId, Subject, Priority
            FROM Task
            WHERE WhatId = :acc.Id
              AND Subject LIKE '%Churn-Gefahr%'
        ];
        System.assertEquals(1, churnTasks.size(), 'Es sollte genau 1 Churn-Task erstellt werden');
        System.assertEquals('High', churnTasks[0].Priority, 'Task-Priorität sollte High sein');
    }

    /**
     * Testet, dass Accounts mit NULL LastContactDate als inaktiv gelten
     */
    @isTest
    static void findAndMarkInactiveAccounts_handlesNullLastContactDate() {
        // Arrange
        Account acc = new Account(
            Name = 'Kein Kontakt-Datum',
            LastContactDate__c = null,
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act
        Test.startTest();
        Integer inactiveCount = ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        System.assertEquals(1, inactiveCount, 'Account mit NULL LastContactDate sollte als inaktiv gelten');

        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c, 'Account sollte als Churn_Gefahr markiert sein');
    }

    /**
     * Testet, dass bereits als Churn-Gefahr markierte Accounts nicht erneut markiert werden
     */
    @isTest
    static void findAndMarkInactiveAccounts_skipsAlreadyMarked() {
        // Arrange
        Account acc = new Account(
            Name = 'Bereits markiert',
            LastContactDate__c = Date.today().addDays(-100),
            ChurnStatus__c = 'Churn_Gefahr'
        );
        insert acc;

        // Act
        Test.startTest();
        Integer inactiveCount = ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert
        System.assertEquals(0, inactiveCount, 'Bereits markierte Accounts sollten nicht erneut gezählt werden');
    }

    /**
     * Testet, dass keine duplizierte Tasks erstellt werden
     */
    @isTest
    static void createChurnTasks_noDuplicateTasks() {
        // Arrange: Account mit alter LastContactDate
        Account acc = new Account(
            Name = 'Mit bestehender Aufgabe',
            LastContactDate__c = Date.today().addDays(-100),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Erstellt eine bestehende Churn-Aufgabe (IsClosed nicht setzen — standardmäßig offen)
        Task existingTask = new Task(
            WhatId = acc.Id,
            Subject = 'Kunde inaktiv — Churn-Gefahr: Mit bestehender Aufgabe',
            Priority = 'High',
            Status = 'In Progress'
        );
        insert existingTask;

        // Act
        Test.startTest();
        ChurnDetectionService.findAndMarkInactiveAccounts();
        Test.stopTest();

        // Assert: Es sollte nur die bestehende Aufgabe geben, keine neue
        List<Task> churnTasks = [
            SELECT Id FROM Task
            WHERE WhatId = :acc.Id
              AND Subject LIKE '%Churn-Gefahr%'
        ];
        System.assertEquals(1, churnTasks.size(), 'Es sollte keine duplizierte Aufgabe erstellt werden');
    }

    /**
     * Testet den ChurnDetectionScheduler
     */
    @isTest
    static void ChurnDetectionScheduler_executesSuccessfully() {
        // Arrange
        Account acc = new Account(
            Name = 'Scheduler Test Kunde',
            LastContactDate__c = Date.today().addDays(-95),
            ChurnStatus__c = 'Aktiv'
        );
        insert acc;

        // Act
        Test.startTest();
        String jobId = System.schedule('Test Churn Detection', '0 0 22 * * ?', new ChurnDetectionScheduler());
        Test.stopTest();

        // Assert: Der Job wurde geplant
        System.assertNotEquals(null, jobId, 'Der Scheduler-Job sollte geplant werden');

        Account updatedAcc = [SELECT ChurnStatus__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churn_Gefahr', updatedAcc.ChurnStatus__c, 'Account sollte nach Scheduler-Lauf als Churn_Gefahr markiert sein');
    }

    /**
     * Testet, dass AccountLastContactHandler die LastContactDate bei Task-Erstellung aktualisiert
     */
    @isTest
    static void AccountLastContactHandler_updatesOnTaskCreate() {
        // Arrange
        Account acc = new Account(Name = 'Kontakt Test');
        insert acc;

        // Act: Erstelle einen Task mit WhatId = Account
        Task task = new Task(
            WhatId = acc.Id,
            Subject = 'Test Kontakt',
            Status = 'Completed',
            Priority = 'Normal'
        );
        insert task;

        // Assert
        Account updatedAcc = [SELECT LastContactDate__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(Date.today(), updatedAcc.LastContactDate__c, 'LastContactDate sollte auf TODAY() aktualisiert werden');
    }

    /**
     * Testet, dass nur Account-WhatIds (001...) verarbeitet werden
     */
    @isTest
    static void AccountLastContactHandler_ignoresNonAccountWhatId() {
        // Arrange: Erstelle einen Laptop (Custom Object, ID beginnt nicht mit 001)
        Laptop__c laptop = new Laptop__c(
            Name = 'Test Laptop',
            Marke__c = 'Dell',
            Modell__c = 'XPS 15',
            Status__c = 'Auf_Lager'
        );
        insert laptop;

        Account acc = new Account(Name = 'Sollte nicht aktualisiert werden');
        insert acc;

        // Act: Task mit WhatId = Laptop (nicht Account)
        Task task = new Task(
            WhatId = laptop.Id,
            Subject = 'Laptop Kontakt',
            Status = 'Completed',
            Priority = 'Normal'
        );
        insert task;

        // Assert: Account sollte nicht aktualisiert werden
        Account updatedAcc = [SELECT LastContactDate__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updatedAcc.LastContactDate__c, 'Account sollte nicht aktualisiert werden bei nicht-Account WhatId');
    }

    /**
     * Testet, dass Event-Erstellung auch LastContactDate aktualisiert
     */
    @isTest
    static void AccountLastContactHandler_updatesOnEventCreate() {
        // Arrange
        Account acc = new Account(Name = 'Event Kontakt Test');
        insert acc;

        // Act: Erstelle ein Event mit WhatId = Account
        Event event = new Event(
            WhatId = acc.Id,
            Subject = 'Meeting',
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            IsAllDayEvent = false
        );
        insert event;

        // Assert
        Account updatedAcc = [SELECT LastContactDate__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(Date.today(), updatedAcc.LastContactDate__c, 'LastContactDate sollte bei Event-Erstellung aktualisiert werden');
    }

    /**
     * Testet Bulk-Verarbeitung: mehrere Tasks auf einmal
     */
    @isTest
    static void AccountLastContactHandler_bulkProcessing() {
        // Arrange
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Bulk Account ' + i));
        }
        insert accounts;

        // Act: Erstelle Tasks für alle Accounts
        List<Task> tasks = new List<Task>();
        for (Account acc : accounts) {
            tasks.add(new Task(
                WhatId = acc.Id,
                Subject = 'Bulk Kontakt',
                Status = 'Completed',
                Priority = 'Normal'
            ));
        }
        insert tasks;

        // Assert: Alle Accounts sollten aktualisiert sein
        List<Account> updatedAccounts = [
            SELECT Id, LastContactDate__c FROM Account WHERE Id IN :accounts
        ];
        System.assertEquals(5, updatedAccounts.size(), 'Alle 5 Accounts sollten existieren');
        for (Account acc : updatedAccounts) {
            System.assertEquals(Date.today(), acc.LastContactDate__c, 'Account ' + acc.Id + ' sollte aktualisiert sein');
        }
    }
}