/**
 * TaskLastContactTrigger — Aktualisiert LastContactDate__c auf dem Account
 * 
 * Wenn ein Task erstellt oder aktualisiert wird und mit einem Account verknüpft
 * ist (WhatId), wird die LastContactDate__c auf den aktuellen Tag gesetzt.
 */
trigger TaskLastContactTrigger on Task (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        AccountLastContactHandler.updateLastContactDateOnCreate(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        AccountLastContactHandler.updateLastContactDateOnUpdate(Trigger.new, Trigger.oldMap);
    }
}