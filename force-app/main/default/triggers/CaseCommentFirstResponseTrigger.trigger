/**
 * [SCRUM-424] CaseComment-Trigger — erste Mitarbeiter-Reaktion pro Case.
 *
 * Setzt exakt einmal beim ersten qualifizierenden Kommentar (Creator != Case-Ersteller)
 * - First_Response_Time__c (DateTime)
 * - First_Response_Working_Mins__c (Number, Arbeitsminuten per BusinessHours)
 * - First_Response_Target_Missed__c (Checkbox)
 *
 * House-Pattern: nach SCRUM-421 (QueueAssignment), static isRunning-Guard.
 * Zielwerte: Premium 60 min, Standard/leerer Kundenstatus 240 min.
 *
 * @author developer-agent
 * @date 2026-09-22
 */
trigger CaseCommentFirstResponseTrigger on CaseComment (after insert) {
    if (CaseCommentFirstResponseTrigger.isRunning) return;
    CaseCommentFirstResponseTrigger.isRunning = true;
    try {
        CaseCommentFirstResponse.afterInsert(Trigger.new);
    } finally {
        CaseCommentFirstResponseTrigger.isRunning = false;
    }
}
