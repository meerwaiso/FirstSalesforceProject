/**
 * AccountLockClearHandler — Trigger handler fur das automatische Leeren
 * des Sperrgrundes (Account.Lock_Reason__c) beim Aufheben der Sperre,
 * SCRUM-384. SCRUM-381-Muster 1:1.
 *
 * Verhalten:
 *   Jeder Account, dessen Is_Locked__c sich von TRUE auf FALSE andert,
 *   bekommt Lock_Reason__c auf null gesetzt (AC4).
 *
 * Interaktion mit ValRule LockReason_PflichtBeiGesperrt:
 *   Die ValRule wird auf dem ENDSTAND ausgewertet (nach Before-Update).
 *   In derselben Transaktion ist Is_Locked__c schon FALSE, das Gate
 *   ist inaktiv — kein falsch-positiver Block (SCRUM-381-ADR-2).
 *
 * Bulk: 0 SOQL, 1 Zuweisung pro geandertem Record, eigenes hasFired-Flag.
 */
public with sharing class AccountLockClearHandler {
    @testVisible
    private static Boolean hasFired = false;

    public static void handleBeforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        if (hasFired) {
            return;
        }
        hasFired = true;

        for (Account acct : newAccounts) {
            Account oldAcct = oldMap.get(acct.Id);
            if (oldAcct != null && oldAcct.Is_Locked__c && !acct.Is_Locked__c) {
                acct.Lock_Reason__c = null;
            }
        }
    }
}
