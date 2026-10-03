/**
 * SCRUM-437: Wiedererkennende Servicefälle (Problemkategorie + Problemserie) —
 * bulkified Recomputation-Handler.
 *
 * ADR-1/2/3: Bei jedem relevanten Case-Event (insert/update/delete) werden alle
 * betroffenen (AccountId, Problemkategorie)-Gruppen mit einer einzigen IN-Query
 * neu berechnet — exakte Neu-Berechnung, kein Delta, kein Drift. Ein Fall wird
 * nur aktualisiert, wenn sich mindestens eines der 4 Berechnungsfelder
 * tatsächlich geändert hat (no-op-skip, verhindert After-Update-Zyklen).
 *
 * Governance (Bulk 200): 1 SOQL (IN-Query) + max. 1 DML (update) pro Batch,
 * unabhängig von der Fallzahl. Kein SOQL-in-Loop, keine DML-in-Loop.
 *
 * Pool-Definition (§4):
 *   Pool(c) = alle p ≠ c in derselben (AccountId, Problemkategorie)-Gruppe,
 *   die im Zeitfenste r sind: offen ODER (Status=Closed AND ClosedDate >=
 *   today - WINDOW_DAYS). Offene Fälle zählen immer; geschlossene nur im
 *   30-Tage-Fenster.
 *
 * Felder je Fall c:
 *   Wiederkehrendes_Problem__c     = |Pool(c)| >= 2
 *   Anzahl_aehnlicher_offener_Cases__c = |{p in Pool(c): Status offen}|
 *   Letzter_aehnlicher_Case__c    = Id des p in Pool(c) mit max CreatedDate
 *                                   (Tie: max Id); leeres Pool → null
 *   Problemserie__c               = gemeinsamer deterministischer String je
 *                                   (AccountId, Problemkategorie), gesetzt auf
 *                                   ALLE Fälle der Gruppe, wenn bereits begründet
 *                                   ODER Schwelle erstmals überschritten (≥3 im
 *                                   Fenster). Sonst null. (ADR-2: persistiert.)
 *
 * Serienkennzeichen (§4.3, Abweichung vom Design):
 *   AccountId + '_' + Problemkategorie-API-Value (nicht Label, weil SOQL
 *   API-Value liefert und Label-Änderung die Kennzeichen nicht brechen soll).
 *   Längster API-Value 'TechnischerDefekt' = 17 Zeichen → 18+1+17 = 36 ≤ 40.
 *
 * @author developer-agent
 * @date 2026-10-03
 */
public without sharing class CaseProblemSerieHandler {

    /** Der Case-Status, der als «geschlossen» gilt. Alle anderen sind offen. */
    public static final String CLOSED_STATUS = 'Closed';

    /** 30-Tage-Fenster für «kürzlich geschlossen». */
    public static final Integer WINDOW_DAYS = 30;

    /**
     * Rechnet die 4 Berechnungsfelder für alle Fälle der übergebenen Accounts
     * neu und aktualisiert nur die geänderten.
     *
     * @param accountIds die betroffenen Account-Ids (aus Trigger.new/.old;
     *                   bei Kategorie-Änderung auch alte und neue Gruppe)
     * @return Anzahl der tatsächlich aktualisierten Cases (0 = kein Wert geändert).
     */
    public static Integer recompute(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return 0;
        }

        // Fensterbeginn als Datetime um Mitternacht (Case.ClosedDate ist in
        // dieser Org ein Datetime, nicht Date — sobject describe).
        Date windowStartDate = Date.today().addDays(-WINDOW_DAYS);
        Datetime windowStart = Datetime.newInstanceGmt(
            windowStartDate.year(), windowStartDate.month(), windowStartDate.day(),
            0, 0, 0);

        // 1 SOQL: alle Fälle der betroffenen Accounts (auch ohne Kategorie).
        // Wir laden alle, weil eine Kategorie-Änderung einen Fall aus einer
        // Gruppe heraus und in eine andere verschiebt — beides muss stimmen.
        List<Case> allCases = [
            SELECT Id, AccountId, Problemkategorie__c, Status, ClosedDate,
                   CreatedDate,
                   Wiederkehrendes_Problem__c,
                   Anzahl_aehnlicher_offener_Cases__c,
                   Letzter_aehnlicher_Case__c,
                   Problemserie__c
            FROM Case
            WHERE AccountId IN :accountIds AND AccountId != null
        ];

        // Partitioniere nach (AccountId, Problemkategorie).
        // null-Kategorie ist eine eigene "Gruppe" (kein Serien-System).
        Map<String, List<Case>> groups = new Map<String, List<Case>>();
        for (Case c : allCases) {
            String key = c.AccountId + '|' +
                         (c.Problemkategorie__c == null ? 'NULL' : c.Problemkategorie__c);
            if (!groups.containsKey(key)) {
                groups.put(key, new List<Case>());
            }
            groups.get(key).add(c);
        }

        List<Case> toUpdate = new List<Case>();

        for (List<Case> groupCases : groups.values()) {
            Case firstCase = groupCases.get(0);
            String category = firstCase.Problemkategorie__c;
            Boolean hasCategory = (category != null);

            // Serienkennzeichen (deterministisch je Gruppe, unabhängig vom Zustand).
            String seriesKey = hasCategory ? buildSeriesKey(firstCase.AccountId, category) : null;

            // Serie bereits begründet? Nur wenn ≥1 Fall der Gruppe DIE KORREKT
            // ABGELEITETE Serienkennung dieser Gruppe trägt (deterministisch je
            // (AccountId, Kategorie)). Ein veralteter Wert aus einer früheren
            // Kategorie (Kategorie-Änderung, AC6) taucht hier auf und darf die
            // neue Gruppe NICHT als "bereits begründet" markieren → nur exakte
            // Übereinstimmung mit seriesKey zählt.
            Boolean hasEstablished = false;
            if (hasCategory) {
                for (Case gc : groupCases) {
                    if (gc.Problemserie__c == seriesKey) {
                        hasEstablished = true;
                        break;
                    }
                }
            }

            // Serie auf alle Fälle der Gruppe setzen?
            //   Ja, wenn bereits begründet (persistiert) ODER Schwelle ≥3 im Fenster.
            //   Nein, wenn unter Schwelle und nicht begründet.
            Integer windowCount = 0;
            for (Case gc : groupCases) {
                if (isInWindow(gc.Status, gc.ClosedDate, windowStart)) {
                    windowCount++;
                }
            }
            Boolean shouldSetSeries = hasCategory && (hasEstablished || windowCount >= 3);

            // Je Fall in der Gruppe: Pool berechnen, Felder setzen, mustWrite prüfen.
            for (Case c : groupCases) {
                // Pool(c): alle p ≠ c in der Gruppe, die im Fenster sind.
                Integer poolSize = 0;
                Integer openPoolSize = 0;
                Case lastSimilar = null; // max CreatedDate (Tie: max Id)
                for (Case p : groupCases) {
                    if (p.Id == c.Id) continue;
                    if (!isInWindow(p.Status, p.ClosedDate, windowStart)) continue;
                    poolSize++;
                    if (p.Status != CLOSED_STATUS) {
                        openPoolSize++;
                    }
                    if (lastSimilar == null
                        || p.CreatedDate > lastSimilar.CreatedDate
                        || (p.CreatedDate == lastSimilar.CreatedDate && p.Id > lastSimilar.Id)) {
                        lastSimilar = p;
                    }
                }

                Boolean newRecurring  = (hasCategory && poolSize >= 2);
                Integer newOpenCount  = hasCategory ? openPoolSize : 0;
                Id    newLastSimilar  = (hasCategory && lastSimilar != null) ? lastSimilar.Id : null;
                String newSeries      = shouldSetSeries ? seriesKey : null;

                // mustWrite: nur wenn ein Wert sich geändert hat.
                Boolean curRecurring = (c.Wiederkehrendes_Problem__c == null)
                                       ? false : c.Wiederkehrendes_Problem__c;
                Boolean recurringChanged = (c.Wiederkehrendes_Problem__c != newRecurring)
                                      || (c.Wiederkehrendes_Problem__c == null && newRecurring);
                Boolean countChanged = (c.Anzahl_aehnlicher_offener_Cases__c == null)
                               || (c.Anzahl_aehnlicher_offener_Cases__c.intValue() != newOpenCount);
                Boolean lastChanged  = (c.Letzter_aehnlicher_Case__c != newLastSimilar);
                Boolean seriesChanged= (c.Problemserie__c != newSeries);

                if (recurringChanged || countChanged || lastChanged || seriesChanged) {
                    c.Wiederkehrendes_Problem__c     = newRecurring;
                    c.Anzahl_aehnlicher_offener_Cases__c = newOpenCount;
                    c.Letzter_aehnlicher_Case__c     = newLastSimilar;
                    c.Problemserie__c                = newSeries;
                    toUpdate.add(c);
                }
            }
        }

        // 1 DML — nur wenn sich ein Wert geändert hat.
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }

    /**
     * Ist der Case im 30-Tage-Zeitfenster? Offene Fälle zählen immer;
     * geschlossene Fälle nur, wenn ClosedDate >= windowStart.
     * (Case.ClosedDate ist in dieser Org ein Datetime — sobject describe.)
     */
    private static Boolean isInWindow(String status, Datetime closedDate, Datetime windowStart) {
        if (status != CLOSED_STATUS) {
            return true; // offen
        }
        return (closedDate != null && closedDate >= windowStart);
    }

    /**
     * Serienschlüssel: deterministisch je (AccountId, Problemkategorie-API-Value).
     * AccountId (15/18 Zeichen) + '_' + API-Value (z.B. 'LoginZugang').
     * Längster API-Value 'TechnischerDefekt' = 17 Zeichen → 18+1+17 = 36 ≤ 40.
     */
    public static String buildSeriesKey(Id accountId, String problemKategorieApiValue) {
        return accountId + '_' + problemKategorieApiValue;
    }
}
