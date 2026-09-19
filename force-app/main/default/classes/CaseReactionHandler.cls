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
 * Re-Entry (ADR-1, ergänzt SCRUM-419): der nach-Trigger `update Trigger.new`
 * feuert einen neuen after-update-Lauf. Früher unterdrückte das allein die
 * Status-Guard (n.Status == o.Status ⇒ kein Doppler). Beim externen
 * Single-Field-REST-/CLI-Update blieb genau dieser 2. Lauf aktiv → Doppler
 * (Reopen = 2). Es gibt daher jetzt zusätzlich ein explizites Re-Entry-Flag
 * (isRecomputing), das der Trigger um den recompute-Aufruf setzt: der
 * handler-verursachte Re-Entry wird in ALLEN Pfaden übersprungen.
 *
 * @author developer-agent
 * @date 2026-09-18
 * @date 2026-09-19 SCRUM-419: Re-Entry-Flag (isRecomputing) gegen Doppler im
 *        externen REST/CLI-Pfad
 */
public without sharing class CaseReactionHandler {

    /**
     * Der Case-Status, der als «geschlossen» gilt. Alle anderen Status gelten
     * als offen. Aus der Test-Org gelesen: Case.Status Picklist =
     * New / Working / Escalated / Closed. (1:1 SCRUM-365 CLOSED_STATUS.)
     */
    public static final String CLOSED_STATUS = 'Closed';

    /**
     * SCRUM-419: Re-Entry-Flag für den Trigger. Der Trigger setzt es um den
     * recompute-Aufruf (true → finally false), damit der VON RECOMPUTE SELBST
     * ausgelöste re-entrant after-update-Lauf (der nur die Custom-Felder
     * schreibt) nicht noch einmal zählt.
     *
     * Warum nötig (SCRUM-418-Bug): Der alte Re-Entry-Schutz hing ausschließlich
     * am Status-Guard (n.Status != o.Status). Der greift im in-Org-Apex- und
     * in-app-UI-Pfad korrekt, aber beim EXTERNEN Single-Field-REST-/CLI-Update
     * bleibt der re-entrant 2. Lauf aktiv und erhöht den Zähler ein zweites Mal
     * (Reopen = 2 statt 1, deterministisch reproduziert). Das Flag unterdrückt
     * den handler-verursachten Re-Entry für ALLE Pfade, unabhängig davon, wie
     * Trigger.old/new beim externen Update geladen werden. Transaction-scope:
     * das Flag wird pro recompute-Aufruf gesetzt und zurückgesetzt, daher
     * blockt es keine legitimen, separaten Reopens in derselben Transaktion.
     */
    public static Boolean isRecomputing = false;

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