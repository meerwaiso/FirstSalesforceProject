/**
 * SCRUM-404: CaseSlaFirstResponseTaskTrigger — Task insert zählt als erste Reaktion.
 * ADR-3: frühester Task mit WhatId = Case.Id fixiert Erste_Rueckmeldung__c (CreatedDate).
 */
trigger CaseSlaFirstResponseTaskTrigger on Task (after insert) {
    // Group tasks per Case, earliest CreatedDate wins.
    Map<Id, DateTime> caseToEarliest = new Map<Id, DateTime>();
    for (Task t : Trigger.new) {
        if (t.WhatId == null || t.CreatedDate == null) continue;
        DateTime existing = caseToEarliest.get(t.WhatId);
        if (existing == null || t.CreatedDate < existing) {
            caseToEarliest.put(t.WhatId, t.CreatedDate);
        }
    }
    if (!caseToEarliest.isEmpty()) {
        CaseSlaFirstResponseHandler.markFirstResponses(caseToEarliest);
    }
}
