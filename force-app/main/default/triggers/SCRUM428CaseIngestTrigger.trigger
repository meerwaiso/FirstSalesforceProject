/**
 * [SCRUM-428] Trigger auf Case: after-insert (ADR-3).
 *
 * ONLY after-insert — der eigene update (Phase A: Dedup/Kategorie/Quelle)
 * feuert diesen Trigger NICHT erneut (kein after-update). Damit ist der
 * Rekursions-Schutz per Konstruktion gegeben (ADR-3 Schritt 5).
 *
 * Interaktion mit SCRUM-421 (CaseQueueAssignmentTrigger):
 *   - 421 filtert auf Servicebereich-Wechsel (Trigger.newMap vs oldMap).
 *   - Phase A setzt Servicebereich__c (categorize) -> 421 routet auf die
 *     korrekte Queue. GEWOLLT — 421 bleibt unverändert.
 *   - Dup-Schließung: nur Status/Subject/Dedupliziert__c -> 421 continue.
 *   - Phase B setzt OwnerId (Queue->User im Queueable, kein Trigger-Kontext)
 *     -> 421 nie aktiv.
 *
 * @author developer-agent
 * @date 2026-09-24
 */
trigger SCRUM428CaseIngestTrigger on Case (after insert) {
    SCRUM428CaseIngestHandler.process(Trigger.new);
}
