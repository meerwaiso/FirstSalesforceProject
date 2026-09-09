/**
 * SCRUM-404: CaseSlaFirstResponseHandler — einmalige Fixierung der ersten Rückmeldung.
 * ADR-3: der früheste auf den Case gesetzte Task/Event (WhatId = Case.Id) zählt.
 * 1 SOQL (Cases mit Frist, ohne Rückmeldung) + 1 DML (nur-null-Write), bulkified.
 */
public without sharing class CaseSlaFirstResponseHandler {
    /**
     * Markiert Cases als erste Rückmeldung erhalten, wenn eine frühere Activity
     * als die aktuelle vorliegt. Guard-Flag WRITING_RESPONSE wird gesetzt/rückgesetzt.
     *
     * @param caseToEarliestActivity Map Case.Id → Zeitpunkt der frühesten Activity
     * @return Anzahl markierter Cases
     */
    public static Integer markFirstResponses(Map<Id, DateTime> caseToEarliestActivity) {
        if (caseToEarliestActivity == null || caseToEarliestActivity.isEmpty()) {
            return 0;
        }
        // 1 SOQL: nur Cases mit gesetzter Frist UND ohne Rückmeldung (ADR-3).
        Set<Id> caseIds = caseToEarliestActivity.keySet();
        Map<Id, Case> caseMap = new Map<Id, Case>([
            SELECT Id, Erste_Rueckmeldung__c
            FROM Case
            WHERE Id IN :caseIds
              AND Reaktionsfrist__c != null
              AND Erste_Rueckmeldung__c = null
        ]);
        if (caseMap.isEmpty()) return 0;

        // 1 DML: nur-null-Write, Guard-Flag WRITING_RESPONSE setzt den Trigger-Pfad.
        Boolean oldFlag = CaseSlaGuard.WRITING_RESPONSE;
        CaseSlaGuard.WRITING_RESPONSE = true;
        try {
            List<Case> toUpdate = new List<Case>();
            for (Id cid : caseIds) {
                Case c = caseMap.get(cid);
                if (c != null) {
                    c.Erste_Rueckmeldung__c = caseToEarliestActivity.get(cid);
                    toUpdate.add(c);
                }
            }
            if (toUpdate.isEmpty()) return 0;
            update toUpdate;
            return toUpdate.size();
        } finally {
            CaseSlaGuard.WRITING_RESPONSE = oldFlag;
        }
    }
}
