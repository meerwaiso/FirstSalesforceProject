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
 * Re-Entry-Schutz (SCRUM-419): der nach-Trigger `update` im Handler feuert einen
 * weiteren after-update-Lauf. Der wurde früher ausschließlich über den Status-Guard
 * (n.Status != o.Status) unterdrückt — das greift im in-Org-Apex- und in-app-UI-Pfad,
 * aber NICHT beim externen Single-Field-REST-/CLI-Update, wo der re-entrant 2. Lauf
 * aktiv bleibt und den Zähler ein zweites Mal erhöht (Reopen = 2 statt 1).
 * Dafür gibt es jetzt ein explizites Re-Entry-Flag (CaseReactionHandler.isRecomputing):
 * der Trigger setzt es um den recompute-Aufruf und springt bei true direkt raus —
 * für ALLE Pfade pfad-agnostisch.
 *
 * Governor: 0 SOQL im Trigger, 0 DML im Trigger — alles läuft im Handler
 * (1 SOQL + 1 DML pro Batch, s. CaseReactionHandler).
 *
 * @author developer-agent
 * @date 2026-09-18
 */
trigger CaseReactionTrigger on Case (after update) {
    // SCRUM-419: Re-Entry überspringen. Der laufende recompute() ruft
    // `update toWrite`, was diesen Trigger RE-ENTRANT feuert (nur Custom-
    // Felder ändern sich). Ohne dieses Flag zählte genau dieser 2. Lauf beim
    // externen Single-Field-REST-/CLI-Update den Zähler ein zweites Mal.
    if (CaseReactionHandler.isRecomputing) {
        return;
    }

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
        // Re-Entry-Flag um den recompute-Aufruf setzen (SCRUM-419): der
        // handler-interne `update toWrite` feuert diesen Trigger re-kaskadierend;
        // der 2. Lauf sieht isRecomputing=true und springt über den Guard
        // oben raus. finally stellt es zurück, damit Folge-Reopens in
        // derselben Transaktion weiterzählen.
        CaseReactionHandler.isRecomputing = true;
        try {
            CaseReactionHandler.recompute(reopens);
        } finally {
            CaseReactionHandler.isRecomputing = false;
        }
    }
}