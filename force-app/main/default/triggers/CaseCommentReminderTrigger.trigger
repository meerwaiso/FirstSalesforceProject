/**
 * [SCRUM-436] CaseComment-Trigger — Mitarbeiter-Antwort/Antwort auf einen
 * Case = relevante Bearbeitung (PO + ADR-3, Quelle 2).
 *
 * Haus-Shape 1:1 CaseCommentFirstResponseTrigger (SCRUM-424): thin
 * trigger, static isRunning-Guard (hier: CaseReminderService.isReceiving),
 * try/finally, eigentliche Logik im Service.
 *
 * Filter (im Service): ParentId != null UND CreatedById !=
 * Case.CreatedById (STAFF-Kommentar; Kundenkommentar zaehlt NICHT,
 * 1:1 SCRUM-424-Guard).
 *
 * Der Service macht 1 SOQL (Parent) + 1 DML (update) — das `update` feuert
 * den Case-Trigger re-entrant, der faellt ueber isReceiving aus (ADR-1,
 * house SCRUM-419).
 *
 * Governor im Trigger selbst: 0 SOQL, 0 DML.
 *
 * @author developer-agent
 * @date 2026-10-02
 */
trigger CaseCommentReminderTrigger on CaseComment (after insert) {
    if (CaseReminderService.isReceiving) {
        return;
    }
    CaseReminderService.isReceiving = true;
    try {
        CaseReminderService.markRelevantWork(Trigger.new);
    } finally {
        CaseReminderService.isReceiving = false;
    }
}
