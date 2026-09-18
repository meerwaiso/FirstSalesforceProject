/**
 * SCRUM-418: Wiedereröffnungen eines Cases zählen — bulkifieder Handler.
 *
 * ADR (SCRUM-418): „Wiederaufmachen" = Statuswechsel aus 'Closed' in einen
 * offenen Status (New/Working/Escalated). Jeder solche Wechsel erhöht
 * Reactivation_Count__c um genau 1 und setzt Last_Reactivation__c auf jetzt.
 *
 * Delta-Inkrement statt Voll-Recompute (ADR-2): Der Status-Wechsel zählt
 * exakt eine Wiederaufmachung; das Feld trägt den Zähler direkt. 1 SOQL
 * (aktuelle Zähler der betroffenen Cases) + 1 DML (update) pro Batch —
 * unabhängig von der Anzahl der Fälle. Kein SOQL-in-Loop, Bulk-200-sicher.
 *
 * WICHTIG (Trigger.new-Pitfall): In after update trägt Trigger.new für ein
 * Custom-Feld, das im User-DML NICHT gesetzt wurde, den Wert null IM SPEICHER
 * (der DB-Wert wird nicht nachgeladen). Man liest daher die aktuellen
 * Zähler aktiv per SOQL und inkrementiert auf dem DB-Stand — sonst würde
 * ein zweiter Reopen den Zähler auf 1 statt auf 4 setzen (Datenverlust).
 *
 * without sharing: die Zählung ist deterministisch und unabhängig vom
 * Sharing des aufrufenden Users (1:1 SCRUM-365/403). Systemwrites laufen im
 * System-Modus und umgehen FLS → „manuell nicht änderbar", kein Update-FLS
 * für irgendwen nötig.
 *
 * Re-Entry (ADR-1): der nach-Trigger `update Trigger.new` feuert einen neuen
 * after-update-Lauf; dort ist old.Status bereits offen ⇒ Guard=false ⇒ kein
 * zweites Inkrement, keine Rekursion, kein Governor-Loop.
 *
 * @author developer-agent
 * @date 2026-09-18
 */
public without sharing class CaseReactionHandler {

    /**
     * Der Case-Status, der als «geschlossen» gilt. Alle anderen Status gelten
     * als offen. Aus der Test-Org gelesen: Case.Status Picklist =
     * New / Working / Escalated / Closed. (1:1 SCRUM-365 CLOSED_STATUS.)
     */
    public static final String CLOSED_STATUS = 'Closed';

    /**
     * Erhöht für alle übergebenen (bereits wiederaufgemachten) Cases die
     * Reaktivierungszahl um 1 und setzt das Datum der letzten Reaktivierung
     * auf jetzt. Inkrementiert auf dem aktuellen DB-Wert (Trigger.new-Pitfall).
     *
     * @param reopens die Cases, deren Status gerade Closed→offen gewechselt ist
     *        (aus Trigger.new, Index-gepaart zum Guard im Trigger)
     * @return Anzahl der tatsächlich aktualisierten Cases (0 = keine Eingabe)
     */
    public static Integer recompute(List<Case> reopens) {
        if (reopens == null || reopens.isEmpty()) {
            return 0;
        }

        // 1 SOQL: aktuelle Zähler der betroffenen Cases (DB-Stand). Trigger.new
        // ist hier NICHT tragfähig — s. Pitfall oben.
        Set<Id> caseIds = new Set<Id>();
        for (Case c : reopens) {
            caseIds.add(c.Id);
        }
        Map<Id, Integer> currentCounts = new Map<Id, Integer>();
        for (Case c : [
            SELECT Id, Reactivation_Count__c
            FROM Case
            WHERE Id IN :caseIds
        ]) {
            // Custom Number-Feld ist in Apex immer Decimal (auch scale=0).
            Decimal stored = c.Reactivation_Count__c;
            currentCounts.put(c.Id, stored == null ? 0 : stored.intValue());
        }

        // Inkrement auf dem DB-Stand + Zeitpunkt der letzten Reaktivierung.
        //
        // WICHTIG (DML-Pitfall): Trigger.new[i] ist in after update gegen DML
        // READ-ONLY — ein `update Trigger.new` (oder update auf einer Sub-Liste
        // davon) schlägt mit "Record is read-only" fehl. Wir bauen daher frische
        // Instances mit Id + den neuen Werten. Der Re-Entry (neuer after-update
        // Lauf) läuft dann über dieselbe Guard-Logik: n.Status == o.Status (nur
        // die Custom-Felder ändern sich, nicht der Status) ⇒ Guard=false ⇒
        // kein Doppler, keine Rekursion.
        DateTime now = System.now();
        List<Case> toWrite = new List<Case>();
        for (Case n : reopens) {
            Integer oldCount = currentCounts.get(n.Id);
            Integer newCount = (oldCount == null ? 0 : oldCount) + 1;
            toWrite.add(new Case(
                Id = n.Id,
                Reactivation_Count__c = newCount,
                Last_Reactivation__c = now
            ));
        }

        // 1 DML pro Batch (nach-Trigger-Re-Entry, s. ADR-1).
        if (!toWrite.isEmpty()) {
            update toWrite;
        }
        return toWrite.size();
    }
}
