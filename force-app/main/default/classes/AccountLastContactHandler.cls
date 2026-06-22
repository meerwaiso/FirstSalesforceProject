/**
 * AccountLastContactHandler — Aktualisiert LastContactDate__c auf dem Account
 * 
 * Wird vom Task/Event Trigger aufgerufen. Wenn ein Task oder Event mit einem
 * Account verknüpft ist (WasId), wird die LastContactDate__c auf TODAY() gesetzt.
 */
public with sharing class AccountLastContactHandler {

    /**
     * Aktualisiert LastContactDate__c für alle Accounts, die mit den
     * übergebenen Tasks/Events verknüpft sind
     */
    public static void updateLastContactDateOnCreate(List<SObject> records) {
        if (records == null || records.isEmpty()) return;

        Set<Id> accountIds = new Set<Id>();

        for (SObject record : records) {
            Id whatId;
            if (record instanceof Task) {
                whatId = ((Task) record).WhatId;
            } else if (record instanceof Event) {
                whatId = ((Event) record).WhatId;
            } else {
                continue;
            }

            // WasId kann auf Account zeigen (beginnt mit '001')
            if (whatId != null && String.valueOf(whatId).startsWith('001')) {
                accountIds.add(whatId);
            }
        }

        if (accountIds.isEmpty()) return;

        // Bulk-Update aller betroffenen Accounts
        List<Account> accountsToUpdate = [
            SELECT Id, LastContactDate__c
            FROM Account
            WHERE Id IN :accountIds
        ];
        for (Account acc : accountsToUpdate) {
            acc.LastContactDate__c = Date.today();
        }
        update accountsToUpdate;
    }

    /**
     * Bei Update: prüft, ob sich die WasId geändert hat
     */
    public static void updateLastContactDateOnUpdate(
        List<SObject> newRecords,
        Map<Id, SObject> oldRecordsMap
    ) {
        if (newRecords == null || newRecords.isEmpty()) return;

        Set<Id> accountIds = new Set<Id>();

        for (SObject newRecord : newRecords) {
            Id newWhatId;
            Id oldWhatId;

            if (newRecord instanceof Task) {
                newWhatId = ((Task) newRecord).WhatId;
                oldWhatId = ((Task) oldRecordsMap.get(newRecord.Id)).WhatId;
            } else if (newRecord instanceof Event) {
                newWhatId = ((Event) newRecord).WhatId;
                oldWhatId = ((Event) oldRecordsMap.get(newRecord.Id)).WhatId;
            } else {
                continue;
            }

            // Wenn sich WasId geändert hat und neue WasId ein Account ist
            if (newWhatId != oldWhatId && newWhatId != null && String.valueOf(newWhatId).startsWith('001')) {
                accountIds.add(newWhatId);
            }
        }

        if (accountIds.isEmpty()) return;

        List<Account> accountsToUpdate = [
            SELECT Id, LastContactDate__c
            FROM Account
            WHERE Id IN :accountIds
        ];
        for (Account acc : accountsToUpdate) {
            acc.LastContactDate__c = Date.today();
        }
        update accountsToUpdate;
    }
}