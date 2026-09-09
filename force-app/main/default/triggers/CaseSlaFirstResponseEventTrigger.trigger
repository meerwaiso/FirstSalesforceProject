/**
 * SCRUM-404: CaseSlaFirstResponseEventTrigger — Event insert zählt als erste Reaktion.
 * ADR-3: frühester Event mit RelatedToId = Case.Id fixiert Erste_Rueckmeldung__c (StartDateTime).
 */
trigger CaseSlaFirstResponseEventTrigger on Event (after insert) {
    // Group events per Case, earliest StartDateTime wins.
    Map<Id, DateTime> caseToEarliest = new Map<Id, DateTime>();
    for (Event e : Trigger.new) {
        if (e.WhatId == null) continue;
        if (e.StartDateTime == null) continue;
        DateTime existing = caseToEarliest.get(e.WhatId);
        if (existing == null || e.StartDateTime < existing) {
            caseToEarliest.put(e.WhatId, e.StartDateTime);
        }
    }
    if (!caseToEarliest.isEmpty()) {
        CaseSlaFirstResponseHandler.markFirstResponses(caseToEarliest);
    }
}
