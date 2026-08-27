/**
 * SCRUM-365: Offene Fälle auf dem Kontakt — bulkifieder Recomputation-Handler.
 *
 * ADR (SCRUM-365): Bei jedem Case-Event werden ALLE betroffenen Kontakte (alter +
 * neuer Kontakt beim Reassign) mit einer einzigen GROUP-BY-Query neu gezählt —
 * exakte Neu-Zählung, kein Delta-Counting, kein Drift. Ein Contact wird nur
 * aktualisiert, wenn sich der Wert tatsächlich geändert hat (keine no-op-Updates,
 * keine unnötigen LastModified-Änderungen, keine endlosen After-Update-Zyklen).
 *
 * Governance (Bulk 200): 1 SOQL (GROUP BY) + 1 SOQL (aktueller Zustand) + 1 DML
 * (update contacts) pro Batch, unabhängig von der Anzahl der Fälle. Kein SOQL-in-Loop.
 *
 * «offen» = Case.Status != CLOSED_STATUS. CLOSED_STATUS wird aus der Test-Org
 * gelesen (Picklist Case.Status: New / Working / Escalated / Closed) → 'Closed'.
 *
 * without sharing: die Zählung zeigt ALLE echten offenen Fälle des Kontakts —
 * deterministisch und unabhängig vom Sharing des aufrufenden Users (PO-/Arch-
 * Entscheidung, SCRUM-365). Systemwrites laufen im System-Modus und umgehen FLS,
 * daher ist kein Update-FLS für irgendwen nötig («manuell nicht änderbar»).
 *
 * @author developer-agent
 * @date 2026-08-25
 */
public without sharing class CaseOpenCountTrigger {

    /**
     * Der Case-Status, der als «geschlossen» gilt. Alle anderen Status gelten als offen.
     * Aus der Test-Org gelesen: Case.Status Picklist = New / Working / Escalated / Closed.
     * (Dokumentiert in SCRUM-365, Developer-Kommentar am 2026-08-25.)
     */
    public static final String CLOSED_STATUS = 'Closed';

    /**
     * Zählt für alle übergebenen Kontakte die offenen Fälle neu und aktualisiert genau
     * die Kontakte, deren Open_Cases_Count__c sich geändert hat.
     *
     * @param contactIds die betroffenen Contact-Ids (alter + neuer Kontakt beim Reassign)
     * @return Anzahl der tatsächlich aktualisierten Kontakte (0 = kein Wert geändert).
     *         SCRUM-367: Rückgabewert ist aufruf-kompatibel zum Trigger (der ignoriert
     *         ihn) und macht die Methode für den Batch-Rebuilder verwendbar.
     */
    public static Integer recompute(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return 0;
        }

        // 1 SOQL: exakte offene Fälle pro Kontakt.
        // Ein Kontakt ohne offene Fälle liefert KEINE Zeile → wir behandeln Fehlen als 0.
        Map<Id, Integer> openCounts = new Map<Id, Integer>();
        for (AggregateResult r : [
            SELECT ContactId, COUNT(Id) cnt
            FROM Case
            WHERE ContactId IN :contactIds AND Status != :CLOSED_STATUS
            GROUP BY ContactId
        ]) {
            openCounts.put((Id) r.get('ContactId'), (Integer) r.get('cnt'));
        }

        // Aktueller Zustand der betroffenen Kontakte (nur diese — kein Voll-Scan).
        Map<Id, Decimal> currentValues = new Map<Id, Decimal>();
        for (Contact ct : [
            SELECT Id, Open_Cases_Count__c
            FROM Contact
            WHERE Id IN :contactIds
        ]) {
            currentValues.put(ct.Id, ct.Open_Cases_Count__c == null ? 0 : ct.Open_Cases_Count__c);
        }

        // Nur Kontakte updaten, deren sich tatsächlich geändert hat.
        List<Contact> toUpdate = new List<Contact>();
        for (Id cid : contactIds) {
            Integer newCount = openCounts.get(cid);
            Integer actualCount = (newCount == null) ? 0 : newCount;
            Decimal currentValue = currentValues.get(cid);
            Integer priorValue = (currentValue == null) ? 0 : currentValue.intValue();
            if (actualCount != priorValue) {
                toUpdate.add(new Contact(Id = cid, Open_Cases_Count__c = actualCount));
            }
        }

        // 1 DML — nur wenn sich ein Wert geändert hat.
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }
}
