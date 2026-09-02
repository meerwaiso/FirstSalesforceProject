/**
 * Opportunity-Trigger — zwei Verantwortlichkeiten (ein Trigger pro Objekt):
 *
 *   1. Auto-Reset von Is_Overdue__c bei jeglicher Aenderung (SCRUM-319, vorhanden).
 *   2. Auto-Clear von Loss_Reason__c, wenn sich die Stage WEW von 'Closed Lost'
 *      wegaendert — Reopen oder Closed Won (SCRUM-381, neu).
 *
 * Beide Handler laufen in before update und nutzen ein eigenes
 * hasFired-Flag zur Rekursionsvermeidung.
 */
trigger OpportunityOverdueReset on Opportunity (before update) {
    OpportunityOverdueResetHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    OpportunityLossReasonClearHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
}