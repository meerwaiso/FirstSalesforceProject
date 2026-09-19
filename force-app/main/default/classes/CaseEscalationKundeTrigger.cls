/**
 * SCRUM-420: Trigger-Wrapper fuer CaseEscalationKunde.
 *
 * Bulk wie das 365-House-Pattern (CaseOpenCountTrigger): alle Cases in
 * Trigger.new/Trigger.old in O(1)-Loops sammeln, exakt EIN Handler-Call pro
 * Operation. 2 SOQL + 1 DML pro Batch (unabhaengig von der Case-Zahl).
 *
 * relevant() = Status-Wechsel (Schliessen/Wiedererffnen) ODER Priority-Wechsel
 * ODER Kundenwechsel; plus Neuanlage (afterInsert). ADR: ohne Delta-Counting,
 * exakte Neu-Zaehlerung pro betroffener Account.
 *
 * NUR after-Phasen: der Recomputation laest den DB-Zustand — das aktuelle Record
 * traegt den neuen Status erst ab afterUpdate. (Das Design-Modell sagt «BEFORE»,
 * aber vor der DB-Persistenz waere der Zaelwert des aktuellen Cases falsch;
 * der Effekt fuer den User ist identisch — Werte stehen nach dem Commit.)
 *
 * Reentry-Guard: der Handler selbst macht Case-DML (die neuen Felder), das feuert
 * denselben Trigger erneut; da die Relevanz nur auf Status/Priority/AccountId
 * prueft, waere der zweite Gang leer — der Guard erspart ihn zusatzlich.
 * (365 hat keinen Guard, weil sein Handler auf Contact schreibt, nicht auf Case.)
 *
 * without sharing — konsistent mit CaseOpenCountTrigger (SCRUM-365 ADR) und
 * CaseEscalationKunde: die Zaehlung laeuft im Handler; der Wrapper muss nur die
 * Standard-Felder (AccountId/Status/Priority) aus trigger.old/new lesen, was
 * sharing-unabhaengig ist.
 *
 * @author developer-agent
 * @date 2026-09-19
 */
public without sharing class CaseEscalationKundeTrigger {

    /** Reentry-Schutz gegen Handler-eigene Case-DML. */
    private static Boolean isRunning = false;

    public static void afterUpdate() {
        if (isRunning) {
            return;
        }
        isRunning = true;
        try {
            Set<Id> accounts = collectRelevantAccounts(
                    (List<Case>) System.trigger.new,
                    (List<Case>) System.trigger.old);
            if (!accounts.isEmpty()) {
                CaseEscalationKunde.recompute(accounts);
            }
        } finally {
            isRunning = false;
        }
    }

    public static void afterInsert() {
        if (isRunning) {
            return;
        }
        isRunning = true;
        try {
            Set<Id> accounts = new Set<Id>();
            for (Case c : (List<Case>) System.trigger.new) {
                if (c.AccountId != null) {
                    accounts.add(c.AccountId);
                }
            }
            if (!accounts.isEmpty()) {
                CaseEscalationKunde.recompute(accounts);
            }
        } finally {
            isRunning = false;
        }
    }

    /**
     * Sammelt die betroffenen Account-Ids (neuer Account; alter Account bei
     * Kundenwechsel), O(1) Loop ueber new+old — kein SOQL hier.
     */
    private static Set<Id> collectRelevantAccounts(List<Case> newCases, List<Case> oldCases) {
        Set<Id> relatedAccounts = new Set<Id>();
        if (newCases == null || oldCases == null) {
            return relatedAccounts;
        }
        if (newCases.size() != oldCases.size()) {
            return relatedAccounts;
        }
        for (Integer i = 0; i < newCases.size(); i++) {
            Case newCase = newCases[i];
            Case oldCase = oldCases[i];
            if (isRelevantChange(newCase, oldCase)) {
                if (newCase.AccountId != null) {
                    relatedAccounts.add(newCase.AccountId);
                }
                if (oldCase.AccountId != null && oldCase.AccountId != newCase.AccountId) {
                    relatedAccounts.add(oldCase.AccountId);
                }
            }
        }
        return relatedAccounts;
    }

    /** Stimmt eine relevanten Aenderung vor (Status/Priority/Kunde)? */
    private static Boolean isRelevantChange(Case newCase, Case oldCase) {
        if (newCase.AccountId != oldCase.AccountId) {
            return true;
        }
        if (CaseEscalationKunde.isClosed(newCase.Status) != CaseEscalationKunde.isClosed(oldCase.Status)) {
            return true;
        }
        if (newCase.Priority != oldCase.Priority) {
            return true;
        }
        return false;
    }
}
