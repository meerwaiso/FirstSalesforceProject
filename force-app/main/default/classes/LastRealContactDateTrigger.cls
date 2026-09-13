/**
 * SCRUM-413: Datum des letzten echten Kontakts (abgeschlossener Call) auf dem Kontakt.
 *
 * Handelt die Recomputierung für alle übergebenen WhoIds (Contacts): ermit-
 * telt das Datum des NEUESTEN abgeschlossenen Calls (Type='Call' + Status='Comp-
 * leted') per MAX(ActivityDate) und aktualisiert nur die Kontakte, deren Wert
 * sich geändert hat.
 *
 * ADR-4: null = "nie erreicht". mustWrite: `cur==null?(new!=null):(new!=cur)`.
 * Governor: 1 Aggregate-SOQL + 1 SOQL + 1 DML pro Aufruf.
 */
public without sharing class LastRealContactDateTrigger {

    static Map<Id, Date> latestCompletedCall(Set<Id> whoIds) {
        Map<Id, Date> latest = new Map<Id, Date>();
        for (AggregateResult r : [
            SELECT WhoId, MAX(ActivityDate) latest
            FROM Task
            WHERE Type = 'Call' AND Status = 'Completed' AND WhoId IN :whoIds
            GROUP BY WhoId
        ]) {
            Object v = r.get('latest');
            if (v != null) {
                latest.put((Id) r.get('WhoId'), ((Datetime) v).date());
            }
        }
        return latest;
    }

    static Map<Id, Date> currentValues(Set<Id> whoIds) {
        Map<Id, Date> cur = new Map<Id, Date>();
        for (Contact ct : [
            SELECT Id, Last_Real_Contact_Date__c
            FROM Contact
            WHERE Id IN :whoIds
        ]) {
            cur.put(ct.Id, ct.Last_Real_Contact_Date__c);
        }
        return cur;
    }

    public static Integer recompute(Set<Id> whoIds) {
        if (whoIds == null || whoIds.isEmpty()) {
            return 0;
        }
        Map<Id, Date> latest = latestCompletedCall(whoIds);
        Map<Id, Date> cur    = currentValues(whoIds);

        List<Contact> toUpdate = new List<Contact>();
        for (Id wid : whoIds) {
            Date newDate     = latest.get(wid);            // null = "nie erreicht"
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
