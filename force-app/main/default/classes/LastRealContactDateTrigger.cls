/**
 * SCRUM-413: Datum des letzten echten Kontakts (abgeschlossener Call) auf dem Kontakt.
 *
 * Handelt die Recomputierung für ALLE übergebenen WhoIds (Contacts): ermittelt das
 * Datum des NEUESTEN abgeschlossenen Calls (Task mit Type='Call' AND Status='Completed')
 * per MAX(ActivityDate) und aktualisiert nur die Kontakte, deren Wert sich geändert hat.
 *
 * ADR-1 (MAX(ActivityDate) für abgeschlossene Calls): Ein Kontakt OHNE abgeschlossene
 * Calls liefert KEINE AggregateResult-Zeile → Fehlen = null (= ADR-4: "nie erreicht").
 * Bei mehreren Calls gewinnt das NEUESTE ActivityDate.
 *
 * ADR-4 (NULL-Semantik): `Last_Real_Contact_Date__c = null` bedeutet "nie ein abgeschlossener
 * Call" (= "nie erreicht", AC5). mustWrite pro WhoId: `cur == null ? (new != null) : (new != cur)`
 * → NULL→Wert schreiben · Wert→Wert nur bei Änderung · NULL→NULL no-op.
 *
 * Governor (Bulk 200): 1 Aggregate-SOQL + 1 SOQL + 1 DML pro Aufruf, unabhängig von
 * der Call-Anzahl. Kein SOQL-in-Loop.
 *
 * without sharing — das Datum zeigt ALLE echten abgeschlossenen Calls des Kontakts.
 * Systemwrites umgehen FLS.
 *
 * @author developer-agent
 * @date 2026-09-13
 */
public without sharing class LastRealContactDateTrigger {

    /**
     * ERMITLE das neueste ActivityDate pro WhoId NUR über ABGESCHLOSSENE Calls.
     *
     * @param whoIds die getroffenen WhoIds (Contacts)
     * @return Map WhoId → neueste ActivityDate (null wenn kein abgeschlossener Call)
     */
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

    /**
     * ERMITLE den aktuellen Zustand der betroffenen Kontakte.
     *
     * @param whoIds die betroffenen Contact-Ids
     * @return Map ContactId → aktueller Last_Real_Contact_Date__c-Wert
     */
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

    /**
     * Recompute: Für alle übergebenen WhoIds das Datum des neuesten abgeschlossenen
     * Calls neu berechnen und nur die Kontakte updaten, deren sich der Wert geändert hat.
     *
     * @param whoIds die betroffenen WhoIds (Contacts)
     * @return Anzahl der tatsächlich aktualisierten Kontakte (0 = kein Wert geändert)
     */
    public static Integer recompute(Set<Id> whoIds) {
        if (whoIds == null || whoIds.isEmpty()) {
            return 0;
        }

        Map<Id, Date> latest = latestCompletedCall(whoIds);
        Map<Id, Date> cur    = currentValues(whoIds);

        List<Contact> toUpdate = new List<Contact>();
        for (Id wid : whoIds) {
            Date newDate     = latest.get(wid);            // null wenn "nie erreicht"
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
