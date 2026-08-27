/**
 * SCRUM-365: Offene Fälle auf dem Kontakt — Case-Trigger.
 *
 * Sammelt bei jedem relevanten Case-Event die betroffenen Kontakte und ruft den
 * bulkifieden Recomputation-Handler (CaseOpenCountTrigger.recompute) EXAKT EINMAL
 * auf. Der Handler zählt pro betroffener Kontakt die offenen Fälle per
 * GROUP-BY-Query neu und schreibt nur die Contacts, deren sich geändert hat.
 * Detail im ADR (SCRUM-365).
 *
 * Betroffene Kontakte je Event:
 *   - after insert : ContactId aus Trigger.new
 *   - after delete : ContactId aus Trigger.old (Delete senkt die Zahl)
 *   - after update : nur wenn sich ContactId (Umhängen) oder Status (öffnen/schliessen)
 *                    geändert hat — dann alter UND neuer Kontakt (old + new), damit
 *                    beide in einem Schritt stimmen. Sonst reinert → die bestehende
 *                    Cases-Automatisierung (CasePriorityTrigger, SCRUM-333) läuft unverändert weiter.
 *
 * @author developer-agent
 * @date 2026-08-25
 */
trigger CaseOpenCountTrigger on Case (after insert, after update, after delete) {
    Set<Id> affectedContactIds = new Set<Id>();

    if (Trigger.isInsert) {
        for (Case c : Trigger.new) {
            if (c.ContactId != null) {
                affectedContactIds.add(c.ContactId);
            }
        }
    } else if (Trigger.isDelete) {
        for (Case c : Trigger.old) {
            if (c.ContactId != null) {
                affectedContactIds.add(c.ContactId);
            }
        }
    } else if (Trigger.isUpdate) {
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Case cNew = Trigger.new[i];
            Case cOld = Trigger.old[i];
            // Relevanz-Prüfung: nur Reassign (ContactId) oder Status-Wechsel.
            if (cNew.ContactId != cOld.ContactId || cNew.Status != cOld.Status) {
                if (cNew.ContactId != null) {
                    affectedContactIds.add(cNew.ContactId);
                }
                if (cOld.ContactId != null) {
                    affectedContactIds.add(cOld.ContactId);
                }
            }
        }
    }

    if (!affectedContactIds.isEmpty()) {
        CaseOpenCountTrigger.recompute(affectedContactIds);
    }
}
