/**
 * ChurnDetectionService — Kernlogik für die automatische Erkennung inaktiver Kunden
 * 
 * - Verwendet Standardwerte für die Churn-Konfiguration
 * - Findet Accounts, deren LastContactDate__c älter als die Schwelle ist
 * - Setzt ChurnStatus__c auf den konfigurierten Wert
 * - Erstellt Aufgaben für Account Owner (SCRUM-294)
 * 
 * NOTE: ChurnThreshold__mdt Custom Metadata Type wird nicht benötigt.
 * Konfiguration ist im ChurnConfig-Objekt als Default hardcodiert.
 */
public with sharing class ChurnDetectionService {

    /**
     * Churn-Konfiguration mit Standardwerten.
     * Diese Werte können bei Bedarf angepasst werden.
     */
    public class ChurnConfig {
        public Integer daysThreshold;
        public String churnStatusValue;
        public String taskSubject;
        public Integer taskDueDays;

        public ChurnConfig() {
            this.daysThreshold = 90;
            this.churnStatusValue = 'Churn_Gefahr';
            this.taskSubject = 'Kunde inaktiv — Churn-Gefahr: {AccountName}';
            this.taskDueDays = 2;
        }
    }

    /**
     * Liefert die Churn-Konfiguration mit Standardwerten.
     */
    public static ChurnConfig getConfig() {
        return new ChurnConfig();
    }

    /**
     * Findet alle Accounts, die seit mehr als threshold Tagen keinen Kontakt hatten
     * und aktualisiert deren ChurnStatus__c
     */
    public static Integer findAndMarkInactiveAccounts() {
        ChurnConfig config = getConfig();
        Date thresholdDate = Date.today().addDays(-config.daysThreshold);

        // Finde Accounts mit LastContactDate__c älter als die Schwelle (oder NULL)
        List<Account> inactiveAccounts = [
            SELECT Id, Name, OwnerId, LastContactDate__c, ChurnStatus__c
            FROM Account
            WHERE (LastContactDate__c < :thresholdDate OR LastContactDate__c = NULL)
              AND ChurnStatus__c != :config.churnStatusValue
        ];

        if (inactiveAccounts.isEmpty()) {
            return 0;
        }

        // Aktualisiere ChurnStatus__c
        List<Account> accountsToUpdate = new List<Account>();
        for (Account acc : inactiveAccounts) {
            acc.ChurnStatus__c = config.churnStatusValue;
            accountsToUpdate.add(acc);
        }
        update accountsToUpdate;

        // Erstelle Aufgaben für jeden inaktiven Account (SCRUM-294)
        createChurnTasks(inactiveAccounts, config);

        return inactiveAccounts.size();
    }

    /**
     * Erstellt eine Churn-Aufgabe für jeden inaktiven Account,
     * falls noch keine offene Aufgabe existiert
     */
    private static void createChurnTasks(List<Account> accounts, ChurnConfig config) {
        // Hole Account-IDs, die bereits eine offene Churn-Aufgabe haben
        Set<Id> accountsWithOpenTask = new Set<Id>();
        List<Task> existingTasks = [
            SELECT WhatId
            FROM Task
            WHERE WhatId IN :accounts
              AND IsClosed = false
              AND Subject LIKE '%Churn-Gefahr%'
        ];
        for (Task t : existingTasks) {
            accountsWithOpenTask.add(t.WhatId);
        }

        // Erstelle neue Aufgaben nur für Accounts ohne offene Aufgabe
        List<Task> tasksToCreate = new List<Task>();
        Date dueDate = Date.today().addDays(config.taskDueDays);

        for (Account acc : accounts) {
            if (!accountsWithOpenTask.contains(acc.Id)) {
                Task newTask = new Task(
                    WhatId = acc.Id,
                    OwnerId = acc.OwnerId,
                    Subject = config.taskSubject.replace('{AccountName}', acc.Name),
                    Priority = 'High',
                    Status = 'In Progress',
                    ActivityDate = dueDate,
                    Description = 'Dieser Kunde hat seit längerer Zeit keinen Kontakt mit uns gehabt. Bitte zeitnah Kontakt aufnehmen, um Churn zu verhindern.'
                );
                tasksToCreate.add(newTask);
            }
        }

        if (!tasksToCreate.isEmpty()) {
            insert tasksToCreate;
        }
    }

    /**
     * Aktualisiert LastContactDate__c auf dem Account bei einem neuen Kontakt
     */
    public static void updateLastContactDate(Id accountId) {
        if (accountId == null) return;

        Account acc = [SELECT Id, LastContactDate__c FROM Account WHERE Id = :accountId];
        acc.LastContactDate__c = Date.today();
        update acc;
    }
}