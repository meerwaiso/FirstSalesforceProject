/**
 * SCRUM-413: Datum des letzten echten Kontakts (abgeschlossener Call) auf dem Kontakt.
 *
 * Handelt die Recomputierung für alle übergebenen WhoIds (Contacts): ermit-
 * telt das Datum des NEUESTEN abgeschlossenen Calls (Type='Call' + Status='Comp-
 * leted') pro Kontakt und aktualisiert nur die Kontakte, deren Wert sich geän-
 * dert hat.
 *
 * ADR-1: ActivityDate unterstützt kein MAX() in AggregateResult-Queries →
 *   manueller MAX-over-List-Approach: 1 SOQL mit ORDER BY DESC, Apex-Gruppierung.
 *
 * ADR-4: null = "nie erreicht". mustWrite: `cur==null?(new!=null):(new!=cur)`.
 * Governor: 1 SOQL + 1 SOQL + 1 DML pro Aufruf.
 */
public without sharing class LastRealContactDateTrigger {

    /**
     * Rechnet für alle übergebenen Kontakte das Datum des jüngsten abgeschlos-
     * senen Calls neu und aktualisiert genau die Kontakte, deren Last_Real_Contact_Date__c
     * sich geändert hat (oder von NULL auf ein Datum aufspringen).
     */
    public static Integer recompute(Set<Id> whoIds) {
        if (whoIds == null || whoIds.isEmpty()) {
            return 0;
        }

        // SOQL — ActivityDate unterstützt MAX() in AggregateResult NICHT.
        // Stattdessen: ORDER BY DESC LIMIT 1 pro WhoId über eine Grouping-Query.
        Map<Id, Date> latest = new Map<Id, Date>();
        for (Task t : [
            SELECT WhoId, ActivityDate
            FROM Task
            WHERE Type = 'Call' AND Status = 'Completed' AND WhoId IN :whoIds
            ORDER BY ActivityDate DESC
        ]) {
            // Nur der erste Eintrag pro WhoId ist der neueste (ORDER BY DESC).
            if (!latest.containsKey(t.WhoId) && t.ActivityDate != null) {
                latest.put(t.WhoId, t.ActivityDate);
            }
        }

        // 2. SOQL: aktueller Zustand der betroffenen Kontakte.
        Map<Id, Date> cur = new Map<Id, Date>();
        for (Contact c : [
            SELECT Id, Last_Real_Contact_Date__c
            FROM Contact
            WHERE Id IN :whoIds
        ]) {
            cur.put(c.Id, c.Last_Real_Contact_Date__c);
        }

        List<Contact> toUpdate = new List<Contact>();
        for (Id wid : whoIds) {
            Date newDate     = latest.get(wid);
            Date currentDate = cur.get(wid);
            Boolean mustWrite = (currentDate == null)
                ? (newDate != null)
                : (newDate != currentDate);
            if (mustWrite) {
                toUpdate.add(new Contact(Id = wid, Last_Real_Contact_Date__c = newDate));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }
}
