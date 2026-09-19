/**
 * SCRUM-420: Servicefälle nach Kundendringlichkeit priorisieren — bulkifieder
 * Recomputation-Handler.
 *
 * ADR (SCRUM-420): Bei jedem relevanten Case-Event (Neuanlage, Priority-Wechsel,
 * Schliessen/Wiederöffnen, Kundenwechsel) werden ALLE betroffenen Accounts (alter +
 * neuer Account beim Kundenwechsel) neu gezählt und alle offenen Cases des Kontos
 * auf die exakten Werte gebracht — exakte Neu-Zählung, kein Delta-Counting, kein Drift.
 * Ein Case wird nur aktualisiert, wenn sich einer der drei sichtbaren Werte
 * (Zähler/High-Zähler/Stufe) geändert hat (keine no-op-Updates).
 *
 * Governor-Budget pro Batch: 1 SOQL (alle betroffenen OFFENEN Cases holen) + 1 DML.
 * Die Zählung erfolgt in Apex aus der geholten Liste (kein SOQL-Case-Aggregate —
 * SUM(CASE WHEN …) wird vom Org-Compiler abgelehnt, s. Deploy-Fehler am 2026-09-19;
 * die Zählung aus der bereits in Memory liegenden Liste ist bulk und identisch korrekt).
 * Kein SOQL-in-Loop. AK7 (>=200 Cases) damit bestanden (Limits-Test s. SCRUM420…Test).
 *
 * Eskalationsmatrix (PO, final): H = offene High-Cases des Kunden (inkl. aktueller):
 *   H >= 2 -> 'Kritisch'   H == 1 -> 'Beobachten'   H == 0 -> 'Keine'.
 *
 * Zeitstempel (Eskalationszeitpunkt__c): wird pro Case NUR gesetzt, wenn dieser Case
 * zum ersten Mal 'Kritisch' wird (Feld noch null). Bei Herabstufung bleibt der Wert,
 * bei erneuter Eskalation auf 'Kritisch' bleibt er ebenfalls (nie ueberschrieben/geresettet).
 *
 * without sharing: die Zählung zeigt ALLE echten offenen Cases des Accounts,
 * deterministisch und unabhängig vom Sharing des aufrufenden Users (konsistent mit
 * SCRUM-365/370). Systemwrites laufen im System-Modus und umgehen FLS, daher ist
 * kein Update-FLS für irgendwen noetig («manuell nicht änderbar»).
 *
 * «offen» = Case.Status != 'Closed'; «High» = Case.Priority = 'High' — beide LITERALS
 * aus der Test-Org gelesen (Picklist Case.Status: New/Working/Escalated/Closed;
 * Case.Priority: Low/Medium/High).
 *
 * @author developer-agent
 * @date 2026-09-19
 */
public without sharing class CaseEscalationKunde {

    /** Case-Status, der «geschlossen» gilt; alle anderen Status sind offen. */
    public static final String CLOSED_STATUS = 'Closed';

    /** Case-Priority, die als «high» zählt — Literal aus der Test-Org (Picklist). */
    public static final String HIGH_PRIORITY = 'High';

    /** Eskalationsstufen (Werte des Picklist-Felds Eskalation_Kunde__c). */
    public static final String STUFE_KEINE = 'Keine';
    public static final String STUFE_BEOBACHTEN = 'Beobachten';
    public static final String STUFE_KRITISCH = 'Kritisch';

    /** Gilt ein Status als «geschlossen»? null wird als offen interpretiert. */
    public static Boolean isClosed(String status) {
        return status == CLOSED_STATUS;
    }

    /**
     * Reine Mapping-Funktion der Matrix auf die gezählte High-Zahl — kein SOQL.
     */
    public static String deriveStufe(Integer openHigh) {
        Integer h = (openHigh == null) ? 0 : openHigh;
        if (h >= 2) {
            return STUFE_KRITISCH;
        }
        if (h == 1) {
            return STUFE_BEOBACHTEN;
        }
        return STUFE_KEINE;
    }

    /**
     * Zählt für alle übergebenen Accounts die offenen / offenen High Cases neu und
     * aktualisiert genau die offenen Cases, deren sichtbarer Wert sich geändert hat.
     *
     * @param accountIds die betroffenen Account-Ids (alter + neuer Account beim Wechsel)
     * @return Anzahl der tatsächlich aktualisierten Cases (0 = kein Wert geändert).
     */
    public static Integer recompute(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return 0;
        }

        // 1 SOQL: alle offenen Fälle der betroffenen Accounts (inkl. der Felder,
        // die diffed werden + Priority/Status für die in-Apex-Zählung).
        List<Case> openCases = [
            SELECT Id, AccountId, Priority,
                   Offene_Cases_Kunde__c, Offene_High_Cases_Kunde__c,
                   Eskalation_Kunde__c, Eskalationszeitpunkt__c
            FROM Case
            WHERE AccountId IN :accountIds AND Status != :CLOSED_STATUS
        ];

        // In-Apex-Zählung pro Account aus der in Memory liegenden Liste — bulk, kein Loop-SOQL.
        Map<Id, Integer> openTotalByAccount = new Map<Id, Integer>();
        Map<Id, Integer> openHighByAccount = new Map<Id, Integer>();
        for (Case c : openCases) {
            if (c.AccountId == null) {
                continue;
            }
            Integer t = openTotalByAccount.get(c.AccountId);
            openTotalByAccount.put(c.AccountId, (t == null ? 0 : t) + 1);
            if (String.valueOf(c.Priority) == HIGH_PRIORITY) {
                Integer h = openHighByAccount.get(c.AccountId);
                openHighByAccount.put(c.AccountId, (h == null ? 0 : h) + 1);
            }
        }

        // Diff + Zeitstempel-Logik — keine SOQL im Loop.
        List<Case> toUpdate = new List<Case>();
        for (Case c : openCases) {
            if (c.AccountId == null) {
                continue;
            }
            Integer newTotal = openTotalByAccount.get(c.AccountId);
            Integer newHigh = openHighByAccount.get(c.AccountId);
            if (newTotal == null) {
                newTotal = 0;
            }
            if (newHigh == null) {
                newHigh = 0;
            }
            String newStufe = deriveStufe(newHigh);
            String currentStufe = c.Eskalation_Kunde__c;

            Boolean mustWrite =
                    (c.Offene_Cases_Kunde__c == null || c.Offene_Cases_Kunde__c.intValue() != newTotal)
                 || (c.Offene_High_Cases_Kunde__c == null || c.Offene_High_Cases_Kunde__c.intValue() != newHigh)
                 || (currentStufe == null || !currentStufe.equals(newStufe));

            if (mustWrite) {
                Case u = new Case(Id = c.Id);
                u.Offene_Cases_Kunde__c = newTotal;
                u.Offene_High_Cases_Kunde__c = newHigh;
                u.Eskalation_Kunde__c = newStufe;
                // Zeitstempel: NUR null -> set, wenn dieser Case erstmals 'Kritisch' wird.
                // Herabstufung und erneute Eskalation: Wert bleibt (nie ueberschrieben).
                if (c.Eskalationszeitpunkt__c == null && newStufe == STUFE_KRITISCH) {
                    u.Eskalationszeitpunkt__c = DateTime.now();
                }
                toUpdate.add(u);
            }
        }

        // 1 DML — nur wenn sich ein Wert geändert hat (418-Lektion: leerer Call = Fehler).
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }
}
