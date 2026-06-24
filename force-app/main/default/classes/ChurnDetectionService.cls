/**
 * ChurnDetectionService — Kernlogik für die automatische Erkennung inaktiver Kunden
 * 
 * - Liest die konfigurierbare Schwelle aus ChurnThreshold__mdt
 * - Findet Accounts, deren LastContactDate__c älter als die Schwelle ist
 * - Setzt ChurnStatus__c auf den konfigurierten Wert
 * - Erstellt Aufgaben für Account Owner (SCRUM-294)
 */
public with sharing class ChurnDetectionService {

    /**
     * Liest die Konfiguration aus ChurnThreshold__mdt
     * Gibt Standardwerte zurück, falls kein Record existiert
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
     * Liefert die Churn-Konfiguration aus ChurnThreshold__mdt.
     * Falls kein Record existiert, werden Standardwerte zurückgegeben.
     */
    public static ChurnConfig getConfig() {
        ChurnConfig config = new ChurnConfig();

        List<ChurnThreshold__mdt> thresholds = [
            SELECT Days_Threshold__c, Churn_Status_Value__c, Task_Subject__c, Task_Due_Days__c
            FROM ChurnThreshold__mdt
            LIMIT 1
        ];

        if (!thresholds.isEmpty()) {
            ChurnThreshold__mdt t = thresholds[0];
            config.daysThreshold = Integer.valueOf(t.Days_Threshold__c);
            config.churnStatusValue = t.Churn_Status_Value__c;
            config.taskSubject = t.Task_Subject__c;
            config.taskDueDays = Integer.valueOf(t.Task_Due_Days__c);
        }

        return config;
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
     * Berechnet das Fälligkeitsdatum in Werktagen (Montag–Freitag, keine Feiertagsprüfung).
     * Startet ab morgen (TODAY + 1), da heute bereits ein Arbeitstag verbraucht ist.
     *
     * Verwendet Datetime.newInstance() + formatGmt('E') für den Wochentag:
     * Gibt 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' zurück.
     * Werktage sind Montag–Freitag (nicht Sat/Sun).
     */
    private static Date addBusinessDays(Date startDate, Integer businessDays) {
        Date result = startDate;
        Integer added = 0;
        while (added < businessDays) {
            result = result.addDays(1);
            Datetime dt = Datetime.newInstance(result, Time.newInstance(0, 0, 0, 0));
            String dayName = dt.formatGmt('E'); // 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
            if (dayName != 'Sat' && dayName != 'Sun') {
                added++;
            }
        }
        return result;
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
        // Fälligkeitsdatum: config.taskDueDays Werktage ab morgen
        Date dueDate = addBusinessDays(Date.today(), config.taskDueDays);

        for (Account acc : accounts) {
            if (!accountsWithOpenTask.contains(acc.Id)) {
                // Berechne Inaktivitätsdauer für Kontext-Beschreibung
                Integer inactiveDays;
                if (acc.LastContactDate__c != null) {
                    inactiveDays = Integer.valueOf(Date.today().daysBetween(acc.LastContactDate__c));
                } else {
                    inactiveDays = null; // kein Kontakt-Datum vorhanden
                }

                // Baue Beschreibung mit Kontext
                String description = 'Dieser Kunde hat seit längerer Zeit keinen Kontakt mit uns gehabt. Bitte zeitnah Kontakt aufnehmen, um Churn zu verhindern.';
                if (inactiveDays != null) {
                    description += ' Letzter Kontakt: ' + String.valueOf(acc.LastContactDate__c) + ' (' + inactiveDays + ' Tage her).';
                } else {
                    description += ' Kein letzter Kontakt-Datum vorhanden.';
                }

                Task newTask = new Task(
                    WhatId = acc.Id,
                    OwnerId = acc.OwnerId,
                    Subject = config.taskSubject.replace('{AccountName}', acc.Name),
                    Priority = 'High',
                    Status = 'In Progress',
                    ActivityDate = dueDate,
                    Description = description
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