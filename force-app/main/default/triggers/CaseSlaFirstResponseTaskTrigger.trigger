/**
 * SCRUM-404: CaseSlaFirstResponseTaskTrigger — Task insert zählt als erste Reaktion.
 * ADR-3: Zeitstempel = ActivityDate der Activity (backdatebar — die Lücke, die ADR-3
 * schliessen soll). Früheste ActivityDate pro Case fixiert Erste_Rueckmeldung__c.
 */
trigger CaseSlaFirstResponseTaskTrigger on Task (after insert) {
    Map<Id, DateTime> caseToEarliest = new Map<Id, DateTime>();
    for (Task t : Trigger.new) {
        if (t.WhatId == null) continue;
        // ActivityDate ist der ADR-3-Zeitstempel (backdatebar).
        // Fallback auf CreatedDate, falls ActivityDate null ist.
        DateTime ts = t.ActivityDate != null
            ? DateTime.newInstance(t.ActivityDate.year(), t.ActivityDate.month(), t.ActivityDate.day(), 0, 0, 0)
            : t.CreatedDate;
        if (ts == null) continue;
        DateTime existing = caseToEarliest.get(t.WhatId);
        if (existing == null || ts < existing) {
            caseToEarliest.put(t.WhatId, ts);
        }
    }
    if (!caseToEarliest.isEmpty()) {
        CaseSlaFirstResponseHandler.markFirstResponses(caseToEarliest);
    }
}
