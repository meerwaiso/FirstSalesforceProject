/**
 * SCRUM-437: Wiedererkennende Servicefälle (Problemkategorie + Problemserie) —
 * Case-Trigger.
 *
 * Sammelt bei jedem relevanten Case-Event die betroffenen Accounts und ruft den
 * bulkifieden Recomputation-Handler (CaseProblemSerieHandler.recompute) EXAKT
 * EINMAL auf. Der Handler liest alle Fälle der betroffenen Accounts mit einer
 * einzigen IN-Query, rechnet die 4 Berechnungsfelder neu und aktualisiert nur
 * die geänderten (no-op-skip).
 *
 * Betroffene Accounts je Event:
 *   - after insert : AccountId aus Trigger.new (alle Fälle, auch ohne Kategorie)
 *   - after delete : AccountId aus Trigger.old (Delete senkt die Zählung)
 *   - after update : nur wenn sich AccountId ODER Problemkategorie__c geändert
 *                    hat — dann alter UND neuer Account (old + new), damit beide
 *                    Gruppen in einem Schritt stimmen.
 *
 * Kein Re-Trigger-Loop: Der Handler schreibt nur die 4 Systemfelder
 * (Wiederkehrendes_Problem__c, Anzahl_aehnlicher_offener_Cases__c,
 * Letzter_aehnlicher_Case__c, Problemserie__c) — niemals AccountId oder
 * Problemkategorie__c. Daher sieht der Trigger beim After-Update des Handler
 * keine Änderung der relevanten Felder → kein erneuter recompute-Call.
 *
 * @author developer-agent
 * @date 2026-10-03
 */
trigger CaseProblemSerieTrigger on Case (after insert, after update, after delete) {
    Set<Id> affectedAccountIds = new Set<Id>();

    if (Trigger.isInsert) {
        for (Case c : Trigger.new) {
            if (c.AccountId != null) {
                affectedAccountIds.add(c.AccountId);
            }
        }
    } else if (Trigger.isDelete) {
        for (Case c : Trigger.old) {
            if (c.AccountId != null) {
                affectedAccountIds.add(c.AccountId);
            }
        }
    } else if (Trigger.isUpdate) {
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Case cNew = Trigger.new[i];
            Case cOld = Trigger.old[i];
            // Relevanz-Prüfung: nur AccountId-Reassign oder Kategorie-Änderung.
            if (cNew.AccountId != cOld.AccountId
                    || cNew.Problemkategorie__c != cOld.Problemkategorie__c) {
                if (cNew.AccountId != null) {
                    affectedAccountIds.add(cNew.AccountId);
                }
                if (cOld.AccountId != null) {
                    affectedAccountIds.add(cOld.AccountId);
                }
            }
        }
    }

    if (!affectedAccountIds.isEmpty()) {
        CaseProblemSerieHandler.recompute(affectedAccountIds);
    }
}
