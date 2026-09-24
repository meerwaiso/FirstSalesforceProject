/**
 * [SCRUM-428] Phase B Queueable (ADR-3 Schritte 7–8, ADR-4).
 *
 * Wird vom Trigger nach der Phase A eingereiht (System.enqueueJob).
 * Führt Zuteilung (SCRUM428AssignmentService) und Eingangsbestätigung
 * (SCRUM428CaseConfirmation) aus.
 *
 * Warum Queueable und nicht inline im Trigger?
 *   - Phase A (Trigger) = synchronous, deterministic, testbar
 *   - Phase B (Queueable) = async, Bulk-frei, kein DML im Trigger,
 *     keine Governor-Timeouts bei 200 Cases im Batch
 *   - 421-Trigger feuert auf update: Phase B setz OwnerId Queue->User,
 *     das ist ein Owner-Wechsel — 421 filtert (kein Servicebereich-Wechsel)
 *     und macht continue. Kein Konflikt (ADR-3 Schritt 5).
 *
 * @author developer-agent
 * @date 2026-09-24
 */
public without sharing class SCRUM428AssignmentQueueable implements Queueable {

    private final List<Id> caseIds;

    public SCRUM428AssignmentQueueable(List<Id> ids) {
        this.caseIds = ids == null ? new List<Id>() : ids;
    }

    public void execute(QueueableContext ctx) {
        if (caseIds.isEmpty()) {
            return;
        }

        // Cases mit allen für die Zuteilung + Bestätigung nötigen Feldern laden.
        Map<Id, Case> cases = new Map<Id, Case>();
        for (Case c : [
            SELECT Id, OwnerId, ContactId, SuppliedEmail, SuppliedName,
                   CaseNumber, Dedupliziert__c, Status,
                   IsClosed, Servicebereich__c,
                   Contact.Name, Contact.Email
            FROM Case
            WHERE Id IN :caseIds
        ]) {
            cases.put(c.Id, c);
        }

        // Phase B Schritt 1: Zuteilung (Owner Queue -> User).
        List<Case> toAssign = new List<Case>();
        for (Case c : cases.values()) {
            // Nur offene Cases zuteilen (Dup-Cases sind closed — s. Phase A).
            if (c.IsClosed != true && c.OwnerId != null) {
                toAssign.add(c);
            }
        }
        if (!toAssign.isEmpty()) {
            SCRUM428AssignmentService.assign(toAssign);
        }

        // Phase B Schritt 2: Eingangsbestätigung (nur für nicht-Dup-Cases).
        // Dup-Cases werden im Handler per Dedupliziert__c=true markiert
        // und hier übersprungen.
        List<Case> toConfirm = new List<Case>();
        for (Case c : cases.values()) {
            if (c.Dedupliziert__c != true) {
                toConfirm.add(c);
            }
        }
        if (!toConfirm.isEmpty()) {
            SCRUM428CaseConfirmation.sendAll(toConfirm);
        }
    }
}
