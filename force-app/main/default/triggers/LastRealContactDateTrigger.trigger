/**
 * SCRUM-413: Apex-Trigger auf Task — pflegt `Contact.Last_Real_Contact_Date__c`
 * beim Abschluss/Einplanung/Löschung von Calls.
 *
 * Events: `after insert, after update, after delete`. Ruft
 * `LastRealContactDateTrigger.recompute(affected)` EXAKT EINMAL auf (bulkified).
 *
 * Relevanz-Klausel ("die abgeschlossenen-Calls-Menge des WhoId kann sich geändert haben"):
 *   - after insert: relevantes wenn sofort abgeschlossen (z.B. "Log Call"QuickAction
 *     legt Task direkt mit Status='Completed' an).
 *   - after delete: abgeschlossener Call gelöscht → ggf. auf vorherigen zurückfallen.
 *   - after update: relevant wenn Status-Wechsel (Abschluss), Wer (WhoId) wechselt,
 *     oder Type wechselt (z.B. Mail → Call).
 *
 * Trigger-Fanout: Dieser ist der EINE Task-Trigger im Repo → keine Zyklen.
 * Trigger schreibt nur Contact, nie Task.
 *
 * @author developer-agent
 * @date 2026-09-13
 */
trigger LastRealContactDateTrigger on Task (after insert, after update, after delete) {
    Set<Id> affected = new Set<Id>();

    if (Trigger.isInsert) {
        for (Task t : Trigger.new) {
            if (t.Type == 'Call' && t.Status == 'Completed' && t.WhoId != null) {
                affected.add(t.WhoId);
            }
        }
    } else if (Trigger.isDelete) {
        for (Task t : Trigger.old) {
            if (t.Type == 'Call' && t.WhoId != null) {
                affected.add(t.WhoId);
            }
        }
    } else if (Trigger.isUpdate) {
        // Relevant wenn: Abschluss-Status wechselt, Wer wechselt, oder Typ wechselt.
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Task n = Trigger.new[i];
            Task o = Trigger.old[i];
            Boolean nCounted = (n.Type == 'Call' && n.Status == 'Completed' && n.WhoId != null);
            Boolean oCounted = (o.Type == 'Call' && o.Status == 'Completed' && o.WhoId != null);
            if (nCounted != oCounted || n.WhoId != o.WhoId || n.Type != o.Type) {
                if (n.WhoId != null) affected.add(n.WhoId);
                if (o.WhoId != null) affected.add(o.WhoId);
            }
        }
    }

    if (!affected.isEmpty()) {
        LastRealContactDateTrigger.recompute(affected);
    }
}
