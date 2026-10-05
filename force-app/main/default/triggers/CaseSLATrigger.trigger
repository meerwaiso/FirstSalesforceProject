/**
 * [SCRUM-438] Case-SLA-Trigger — reaktive Bewertung (AC9). Thin, 0 SOQL,
 * 0 DML (before-Kontext: Felder direkt auf Trigger.new[i] gesetzt -> der
 * Insert/Update traegt sie mit, kein separates DML).
 *
 * Fire-Bedingungen (im Service gelost, hier nur die Ausloeser-Unterscheidung):
 *   before insert:  initSLA        -> Zielzeit + Status + Anker auf dem neuen
 *                                     Record (PO-AC1/AC2).
 *   before update:  nur bei RELEVANTER Aenderung (PO-Feld, 436-Regeln):
 *                     - Priority-Wechsel ODER Kundenstatus(=Premium)-Wechsel
 *                       -> onPriorityChange (AC7: neue Ziel-Minuten, bereits
 *                          Arbeitetes anhaken, Deadline neu).
 *                     - sonst Status-Wechsel -> evaluate (AC5/6: Pause-Stop /
 *                          Resume-Fortlauf, Uhr_gestoppt, Eskalation monoton).
 *                     - keine der drei -> NICHTS (nur Name/Kommentar etc.
 *                       fuehrt zu keiner Re-Buchung, 436-Idempotenz).
 *
 * Re-Entry (house SCRUM-419/436): das `update` im Batch (SLAJobBatch.execute)
 * feuert diesen Trigger re-entrant. SLAService.isRunning=true ueber die
 * Batch-DML macht diesen Lauf inert (das Flag ist der pfad-agnostische
 * Schutz; SCRUM-419-Lektion: externe/CLI-Updates laufen in mehreren
 * Execution-Contexts und umgehen Status-Guards).
 *
 * bhId wird EINMAL pro Execution geholt, nicht pro Row (Governor, house:
 * eine SOQL pro Trigger-Lauf wie im Batch).
 *
 * @author developer-agent
 * @date 2026-10-04
 */
trigger CaseSLATrigger on Case (before insert, before update) {

    if (Trigger.isInsert) {
        Id   bh   = SLAService.bhId();      // 1x pro Execution
        DateTime now = System.now();
        for (Case c : Trigger.new) {
            // Geschlossene Cases NIE tracken (AC6). ACHTUNG: ClosedDate wird
            // erst BEIM insert auto-gesetzt -> im before-Kontext ist sie null,
            // selbst wenn Status='Closed'. Das brauchbare Signal hier ist
            // Status (Design Note 4: Closed ist der geschlossene Picklist-Wert).
            if (c.Status != 'Closed') {
                SLAService.initSLA(c, now, bh);
            }
        }
        return;
    }

    // Re-Entry ueberspringen (house SCRUM-419/436): Batch-`update` feuert
    // diesen Trigger re-entrant (aendert nur SLA-Buchungsfelder, nie
    // Priority/Status) -> pfad-agnostisch ueber das Flag inert.
    if (SLAService.isRunning) {
        return;
    }

    if (!Trigger.isUpdate) {
        return;
    }

    Id   bh   = SLAService.bhId();
    DateTime now = System.now();
    for (Integer i = 0; i < Trigger.new.size(); i++) {
        Case n = Trigger.new[i];
        Case o = Trigger.old[i];
        if (n.ClosedDate != null) { continue; }   // geschlossene nie (AC6)

        Boolean prioChanged =
            (n.Priority       != o.Priority)
         || (n.Kundenstatus__c != o.Kundenstatus__c);      // Reuse ADR-6
        Boolean statusChanged = (n.Status != o.Status);

        if (prioChanged) {
            // AC7: Priority-/Premium-Wechsel -> Zielzeit neu, Arbeitetes
            // erhalten. (Greift auch, wenn gleichzeitig Status wechselt —
            // onPriorityChange bewertet Status/Eskalation ohnehin neu.)
            SLAService.onPriorityChange(n, now, bh);
        } else if (statusChanged) {
            // AC5/6: Pause-Stop / Resume -> Uhr freeze/forward, Eskalation
            // monoton, Status neu.
            SLAService.evaluate(n, now, bh);
        }
        // sonst: keine relevante Aenderung -> bewusst 0 (436-Idempotenz).
    }
}
