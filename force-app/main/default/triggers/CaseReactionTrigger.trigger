/**
 * SCRUM-418: Wiederaufmachen eines geschlossenen Cases erkennen — Trigger.
 *
 * after update: sammelt alle Cases, deren Status aus 'Closed' in einen offenen
 * Status (New/Working/Escalated) zurückgewechselt ist, und ruft den
 * bulkifieden Handler (CaseReactionHandler.recompute) EXAKT EINMAL auf.
 *
 * Guard (1:1 SCRUM-365-Klassifizierung, ADR SCRUM-418):
 *   - nur bei Statuswechsel (n.Status != o.Status)
 *   - o.Status == 'Closed'  UND  n.Status != 'Closed'
 *     ⇒ Wiederaufmachen. Die ERSTE Öffnung zählt NICHT (old != Closed).
 *
 * Re-Entry-Schutz: der nach-Trigger `update` im Handler feuert einen weiteren
 * after-update-Lauf; dort ist old.Status bereits offen ⇒ Guard=false ⇒ kein
 * zweites Inkrement, keine Rekursion.
 *
 * Governor: 0 SOQL im Trigger, 0 DML im Trigger — alles läuft im Handler
 * (1 SOQL + 1 DML pro Batch, s. CaseReactionHandler).
 *
 * @author developer-agent
 * @date 2026-09-18
 */
trigger CaseReactionTrigger on Case (after update) {
    List<Case> reopens = new List<Case>();

    for (Integer i = 0; i < Trigger.new.size(); i++) {
        Case o = Trigger.old[i];
        Case n = Trigger.new[i];

        // Nur bei Status-Wechsel relevant (sonst Inert, s. SCRUM-365).
        if (n.Status != o.Status) {
            // Wiederaufmachen: aus Closed zurück in einen offenen Status.
            if (o.Status == CaseReactionHandler.CLOSED_STATUS
                    && n.Status != CaseReactionHandler.CLOSED_STATUS) {
                reopens.add(n);
            }
        }
    }

    if (!reopens.isEmpty()) {
        CaseReactionHandler.recompute(reopens);
    }
}
