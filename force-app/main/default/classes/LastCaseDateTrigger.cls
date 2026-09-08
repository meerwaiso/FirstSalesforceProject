/**
 * SCRUM-403: Datum des letzten Anliegens auf dem Kontakt — bulkified Recomputation.
 *
 * ADR-1 (Apex, SCRUM-365/367-Muster): Bei jedem relevanten Case-Event (Insert /
 * Delete / Umbuchung) rechnet der Handler für ALLE betroffenen Kontakte das
 * Datum des JÜNGSTEN zugeordneten Falls neu — aus den `MAX(CreatedDate)` aller
 * zugeordneten Cases (offen UND erledigt). Eine einzige GROUP-BY-Query, exakte
 * Neu-Berechnung statt Delta, kein Drift.
 *
 * ADR-3 (Zeitbasis = CreatedDate): Anliegen = der Fall wurde ANGELEGT.
 *   - CreatedDate wird beim Insert gesetzt und ist bei Update unveränderlich
 *     → ein Status-Wechsel einer alten Notiz zählt NICHT als neues Anliegen.
 *   - Deshalb ist die Relevanzprüfung beim Update `ContactId`-Änderung NUR
 *     (anders als der CaseOpenCountTrigger, der zusätzlich den Status prüft).
 *
 * ADR-4 (NULL-Semantik, exakt getrennt von SCRUM-365):
 *   `Last_Case_Date__c = null` bedeutet «kein Case je vorhanden» (Kontakt ohne
 *   Fälle bleibt dauerhaft leer — kein «heute», keine 0).
 *   mustWrite pro Contact = `currentDate == null ? (newDate != null) : (newDate != currentDate)`
 *     → NULL → Wert: schreiben | Wert → Wert: nur bei Änderung | NULL → NULL: no-op.
 *
 * Governor (Bulk 200): 1 Aggregate-SOQL + 1 SOQL (aktueller Zustand) + 1 DML
 * (update contacts) pro Batch, unabhängig von der Anzahl der Fälle. Kein SOQL-in-Loop.
 *
 * without sharing: das Datum zeigt ALLE echten Fälle des Kontakts — deterministisch,
 * unabhängig vom Sharing des aufrufenden Users. Systemwrites laufen im System-Modus
 * und umgehen FLS, daher braucht keine Person Update-FLS auf `Last_Case_Date__c`
 * («manuell nicht änderbar»).
 *
 * @author developer-agent
 * @date 2026-09-09
 */
public without sharing class LastCaseDateTrigger {

    /**
     * Rechnet für alle übergebenen Kontakte das Datum des jüngsten Falls neu und
     * aktualisiert genau die Kontakte, deren `Last_Case_Date__c` sich geändert hat
     * (oder die von NULL auf ein Datum aufspringen — die Bestandslage aus ADR-4).
     *
     * @param contactIds die betroffenen Contact-Ids (bei Umbuchung: alter UND neuer Kontakt)
     * @return Anzahl der tatsächlich aktualisierten Kontakte (0 = kein Wert geändert).
     *         SCRUM-367-kompatibel: Rückgabewert ist aufruf-kompatibel zum Trigger
     *         (der ignoriert ihn) und macht die Methode für den Batch-Rebuilder verwendbar.
     */
    public static Integer recompute(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return 0;
        }

        // 1 AGGREGATE-SOQL: jüngstes CreatedDate pro Kontakt (offen UND erledigt).
        // MAX(CreatedDate) liefert ein Datetime; wir brauchen nur das Datum.
        // Ein Kontakt OHNE Fälle liefert KEINE Zeile → Fehlen = null (= ADR-4: «kein Fall»).
        Map<Id, Datetime> latestCase = new Map<Id, Datetime>();
        for (AggregateResult r : [
            SELECT ContactId, MAX(CreatedDate) latest
            FROM Case
            WHERE ContactId IN :contactIds
            GROUP BY ContactId
        ]) {
            Object v = r.get('latest');
            latestCase.put((Id) r.get('ContactId'), (v == null) ? null : (Datetime) v);
        }

        // 2 SOQL: aktueller Zustand der betroffenen Kontakte (nur diese — kein Voll-Scan).
        // Wichtig: null bleibt `kein Fall je` (ADR-4) und wird NICHT normalisiert.
        Map<Id, Date> currentValues = new Map<Id, Date>();
        for (Contact ct : [
            SELECT Id, Last_Case_Date__c
            FROM Contact
            WHERE Id IN :contactIds
        ]) {
            currentValues.put(ct.Id, ct.Last_Case_Date__c);
        }

        // Nur Kontakte updaten, deren Wert sich tatsächlich geändert hat.
        // NULL → Wert: schreiben · Wert → Wert: nur bei Änderung · NULL → NULL: no-op.
        List<Contact> toUpdate = new List<Contact>();
        for (Id cid : contactIds) {
            Datetime latest = latestCase.get(cid);
            Date newDate = (latest == null) ? null : latest.date();
            Date currentDate = currentValues.get(cid);

            Boolean mustWrite = (currentDate == null)
                ? (newDate != null)
                : (newDate != currentDate);

            if (mustWrite) {
                toUpdate.add(new Contact(Id = cid, Last_Case_Date__c = newDate));
            }
        }

        // 1 DML — nur wenn sich ein Wert geändert hat.
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }
}
