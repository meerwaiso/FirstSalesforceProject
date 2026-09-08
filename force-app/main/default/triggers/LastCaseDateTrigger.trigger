/**
 * SCRUM-403: Datum des letzten Anliegens auf dem Kontakt — Case-Trigger.
 *
 * Sammelt bei jedem relevanten Case-Event die betroffenen Kontakte und ruft den
 * bulkifieden Recomputation-Handler (LastCaseDateTrigger.recompute) EXAKT EINMAL
 * auf. Der Handler rechnet pro betroffener Kontakt das Datum des JÜNGSTEN
 * zugewiesenen Falls (offen UND erledigt) per MAX(CreatedDate)/GROUP-BY neu und
 * schreibt nur die Contacts, deren sich das Datum geändert hat (ADR-4).
 *
 * Betroffene Kontakte je Event (ADR-3: Zeitbasis = CreatedDate, also die ANLAGE
 * des Falls — Status-Wechsel spielt NICHT für dieses Feld eine Rolle):
 *   - after insert : ContactId aus Trigger.new (immer relevant — neues Anliegen
 *                    verschiebt das Datum auf das heutige).
 *   - after delete : ContactId aus Trigger.old (jüngster Fall weg → Rückfall auf
 *                    den vorherigen; letzter Fall weg → NULL).
 *   - after update : NUR wenn sich ContactId geändert hat (Umbuchung) → dann alter
 *                    UND neuer Kontakt (old + new). Status-/Datum/Notiz-Änderungen
 *                    eines bestehenden Falls sind NICHT relevant (ADR-3).
 *
 * Trigger-Fanout: 2 Trigger auf Case (CaseOpenCountTrigger + dieser) — beide
 * bulkified, beide mit no-op-DML-Schutz, beide schreiben Contact (nie Case) →
 * keine Zyklen. (ADR-6/§6.)
 *
 * @author developer-agent
 * @date 2026-09-09
 */
trigger LastCaseDateTrigger on Case (after insert, after update, after delete) {
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
        // Relevanz: NUR ContactId (Umbuchung). Status-Wechsel ist für das
        // «Letzte Anliegen»-Datum irrelevant (ADR-3).
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Case cNew = Trigger.new[i];
            Case cOld = Trigger.old[i];
            if (cNew.ContactId != cOld.ContactId) {
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
        LastCaseDateTrigger.recompute(affectedContactIds);
    }
}
