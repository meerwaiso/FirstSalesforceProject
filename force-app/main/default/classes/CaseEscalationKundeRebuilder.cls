/**
 * SCRUM-420: Rebuilder für Bestandsdaten.
 *
 * Nach dem Deploy des Triggers (SCRUM-420) sind alle bestehenden Fälle noch ohne
 * Werte in den vier neuen Feldern — der Trigger feuert nur bei neuen Events.
 * Damit das Feature sofort vollständig nutzbar ist, füllt der Rebuilder alle
 * Fälle in einem Lauf. Einmaliger Admin-Aufruf:
 *
 *     CaseEscalationKundeRebuilder.run(null);
 *
 * Bulk über alle Accounts; nutzt denselben Handler (1 SOQL + 1 DML pro
 * recompute-Call), keine eigenen Aggregationen.
 *
 * without sharing — konsistent mit CaseOpenCountRebuilder (SCRUM-365).
 *
 * @author developer-agent
 * @date 2026-09-19
 */
public without sharing class CaseEscalationKundeRebuilder {

    /**
     * Füllt die vier Felder für alle Accounts, bei denen mindestens ein
     * offener Fall existiert. Gibt die Anzahl der aktualisierten Fälle zurück.
     *
     * @param accountId optional — null = alle Accounts
     */
    public static Integer run(Id accountId) {
        Set<Id> accountIds;
        if (accountId == null) {
            accountIds = new Set<Id>();
            for (Account a : [SELECT Id FROM Account]) {
                accountIds.add(a.Id);
            }
        } else {
            accountIds = new Set<Id> { accountId };
        }
        return CaseEscalationKunde.recompute(accountIds);
    }
}
