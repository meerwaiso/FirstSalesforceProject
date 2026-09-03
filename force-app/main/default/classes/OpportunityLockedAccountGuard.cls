/**
 * OpportunityLockedAccountGuard — blockiert die ANLAGE von Opportunities
 * am gesperrten Account (SCRUM-384 AC3).
 *
 * Warum Trigger und keine ValRule: AC3 verlangt eine Meldung, die den
 * Account-NAMEN und den SPERRGRUND nennt — ValRule-Meldungen sind statisch
 * Text und koennen das nicht. Der before-insert-Trigger feuert auf jedem
 * Anlagepfad (UI, Quick Action, API, Flow RecordCreate, Bulk) = PO-AC
 * "unabhaengig vom anlegenden Profil".
 *
 * without sharing (bewusste Entscheidung): Der Block ist ein
 * Sicherheits-Gate. Waere die Klasse with sharing, waere ein anlegender
 * User, dem der Account per Sharing unsichtbar ist, auf dem Lookup-Miss
 * die Anlage trotzdem durch — das Gate waere dann profilabhaengig, genau
 * das, was die PO ausschliesst. without sharing + SELECT nur auf die
 * noetigen Read-Only-Felder (Name, Is_Locked__c, Lock_Reason__c).
 *
 * Bulk: 1 SOQL im Vorfeld (IN :accountIds, leerer-Set-Guard), 0 SOQL im Loop,
 * addError pro betroffener Record.
 */
public without sharing class OpportunityLockedAccountGuard {

    public static void handleBeforeInsert(List<Opportunity> newOpportunities) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : newOpportunities) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        Map<Id, Account> byId = new Map<Id, Account>([
            SELECT Id, Name, Is_Locked__c, Lock_Reason__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Opportunity opp : newOpportunities) {
            Account acct = byId.get(opp.AccountId);
            if (acct != null && acct.Is_Locked__c) {
                opp.addError('Anlage blockiert: Der Account „' + acct.Name + '“ ist gesperrt. Sperrgrund: ' + acct.Lock_Reason__c);
            }
        }
    }
}
