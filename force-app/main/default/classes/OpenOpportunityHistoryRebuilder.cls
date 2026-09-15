/**
 * [SCRUM-417] Offener Chancen-Verlauf je Kunde — nächtlicher Vollrecompute.
 *
 * `run()` recompute idempotent für ALLE Monate seit Jahresanfang (Januar des
 * laufenden Jahres bis zum aktuellen Monat, Monatsende-Snapshot):
 *   1. je Monat M: 1 Aggregate-SOQL (COUNT offener, SUM offene Beträge)
 *      über alle Kontexte (Accounts mit Chancen); offene Menge je M laut
 *      Zähl-Definition (Single Source of Truth = IsClosed, ADR-1/3 aus 416).
 *   2. Kontext-Menge = Kontexte mit Aktivität seit Jahresanfang ∪ Kontexte mit
 *      bestehenden Zeilen (Kontinuität: ein Kunde, der seine Chancen kassiert,
 *      behält 0/0-Zeilen → der Einbruch bleibt sichtbar).
 *   3. Upsert 1 Zeile je (Kunde, Monat) auf Unique-Key History_Key__c in
 *      2000er-Chunks; fehlende (Kunde, Monat) = 0/0.
 *   4. Account.Open_Value_Drop_Last_Month__c = Wert(aktueller Monat) −
 *      Wert(Monat davor); negativ = Einbruch; null im Januar (kein Vormonat).
 *
 * Backfill = erster Produktionslauf (gleicher Code-Pfad — es gibt keinen
 * separaten Backfill-Job). Governor: ≤ 1 Aggregate-SOQL je Monat (nie im
 * Record-Loop) + 1 SELECT bestehender Zeilen + 1 SELECT Accounts + Chunk-DML.
 *
 * Design-Abweichung gegenüber docs/SCRUM-417-design.md (deploy-notwendig):
 *   - History_Key__c ist kein Formelfeld, sondern ein unique Text-Feld, das
 *     dieser Rebuilder pflegt. Grund: Salesforce verbietet <unique> auf
 *     Formelfeldern ("Can not specify unique for CustomFields that have a
 *     formula") und ein Formelfeld kann nie Upsert-Token sein. Unique Text
 *     bewahrt die 1:1-(Kunde,Monat)-Garantie in der DB + kollisionsfreien
 *     Upsert exakt wie vom Design intendiert.
 *   - MD-Feld heißt AccountId__c (kein nacktes „AccountId" = Standard-Field).
 *
 * without sharing (System-Schreiben, ADR-6): FLS ist nur bei DML des
 * Lauf-Users relevant; System-Admin-DML umgeht FLS.
 */
public without sharing class OpenOpportunityHistoryRebuilder {

    /** Idempotenter Vollrecompute aller Monate seit Jahresanfang bis heute. */
    public static void run() {
        Date asOf = Date.today();
        List<String> months = monthKeys(asOf);
        Integer year = asOf.year();

        // 1) Kontexte mit bestehenden Zeilen (Kontinuität).
        Set<Id> contexts = new Set<Id>();
        for (OpenOpportunityHistory__c h : [SELECT AccountId__c FROM OpenOpportunityHistory__c]) {
            contexts.add(h.AccountId__c);
        }

        // 2) je Monat M: 1 Aggregate-SOQL → Count/Value je Kontext.
        Map<String, Map<Id, Integer>> countByMonth = new Map<String, Map<Id, Integer>>();
        Map<String, Map<Id, Decimal>> valueByMonth = new Map<String, Map<Id, Decimal>>();
        for (Integer i = 0; i < months.size(); i++) {
            String mk = months.get(i);
            Date endM = monthEnd(year, Integer.valueOf(mk.substring(5)));
            Boolean current = isCurrentMonth(mk, asOf);
            // Bind-Variablen einzeln benennen (SOQL erlaubt je Named-Bind ein Mal).
            Date createdMax = endM;
            Date closeMin = endM;
            String where = current
                ? 'IsClosed = false'
                : '(IsClosed = false OR (IsClosed = true AND (ClosedDate > :closeMin OR ClosedDate = null)))';
            String soql = 'SELECT AccountId, COUNT(Id) cnt, SUM(Amount) amt FROM Opportunity '
                + 'WHERE AccountId != null AND CreatedDate <= :createdMax AND ' + where + ' GROUP BY AccountId';
            Map<Id, Integer> cBy = new Map<Id, Integer>();
            Map<Id, Decimal> vBy = new Map<Id, Decimal>();
            List<AggregateResult> agg = Database.query(soql);
            for (AggregateResult r : agg) {
                Id accId = (Id) r.get('AccountId');
                cBy.put(accId, (Integer) r.get('cnt'));
                Decimal amt = r.get('amt') == null ? 0 : (Decimal) r.get('amt');
                vBy.put(accId, amt);
            }
            countByMonth.put(mk, cBy);
            valueByMonth.put(mk, vBy);
            for (Id id : cBy.keySet()) {
                contexts.add(id);
            }
        }

        // 3) 1 Zeile je (Kontext, Monat); fehlende = 0/0; Upsert auf Unique-Key.
        List<OpenOpportunityHistory__c> rows = new List<OpenOpportunityHistory__c>();
        for (Id c : contexts) {
            for (String mk : months) {
                Map<Id, Integer> cBy = countByMonth.get(mk);
                Map<Id, Decimal> vBy = valueByMonth.get(mk);
                rows.add(new OpenOpportunityHistory__c(
                    AccountId__c = c,
                    Snapshot_Month__c = mk,
                    Open_Count__c = (cBy != null && cBy.containsKey(c)) ? cBy.get(c) : 0,
                    Open_Value__c = (vBy != null && vBy.containsKey(c)) ? vBy.get(c) : 0,
                    History_Key__c = c + '-' + mk
                ));
            }
        }
        for (Integer i = 0; i < rows.size(); i += 2000) {
            Integer end = Math.min(i + 2000, rows.size());
            Database.upsert(rows.sublist(i, end), OpenOpportunityHistory__c.History_Key__c);
        }

        // 4) Drop-Feld je Kontext: Wert(aktueller Monat) − Wert(Monat davor).
        if (!contexts.isEmpty()) {
            Integer lastIdx = months.size() - 1;
            String lastMk = months.get(lastIdx);
            Boolean hasPrev = lastIdx >= 1;
            String prevMk = hasPrev ? months.get(lastIdx - 1) : null;
            List<Account> accounts = [SELECT Id, Open_Value_Drop_Last_Month__c FROM Account WHERE Id IN :contexts];
            List<Account> toUpdate = new List<Account>();
            Map<Id, Decimal> curVal = valueByMonth.get(lastMk);
            Map<Id, Decimal> prevVal = (hasPrev && valueByMonth.get(prevMk) != null) ? valueByMonth.get(prevMk) : null;
            for (Account acc : accounts) {
                Decimal cur = (curVal != null) ? curVal.get(acc.Id) : null;
                Decimal prev = (prevVal != null) ? prevVal.get(acc.Id) : null;
                Decimal drop = dropValue(cur, prev, hasPrev);
                if (drop != acc.Open_Value_Drop_Last_Month__c) {
                    acc.Open_Value_Drop_Last_Month__c = drop;
                    toUpdate.add(acc);
                }
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        }
    }

    /**
     * Zähl-Definition pro Monat, pure Funktion (einheitliche Quelle, ADR-1/3):
     *  aktueller Monat (Kontext asOf): offen = IsClosed = false (exakt die
     *    Menge des SCRUM-416-Live-Feldes → AK4 erfüllt konstruktiv).
     *  vergangene Monate M: offen am Monatsende M = IsClosed = false (ist noch
     *    offen) ODER (war am Monatsende M offen und schloss erst danach:
     *    IsClosed = true AND (ClosedDate > MonatsEnde ODER ClosedDate null)).
     * (Vorausgesetzt: die Kandidaten sind bereits gefiltert auf
     *  AccountId != null AND CreatedDate <= MonatsEnde(M).)
     */
    public static Boolean isCountedInMonth(Opportunity o, Date monthEnd, Date asOf) {
        if (isCurrentMonth(monthKey(monthEnd), asOf)) {
            return o.IsClosed == false;
        }
        if (o.IsClosed == false) {
            return true;
        }
        return (o.ClosedDate != null && o.ClosedDate > monthEnd) || o.ClosedDate == null;
    }

    /** Drop = Wert(aktueller Monat) − Wert(Vormonat); null ohne Vormonat (Januar). */
    public static Decimal dropValue(Decimal currentValue, Decimal previousValue, Boolean hasPreviousMonth) {
        if (!hasPreviousMonth) {
            return null;
        }
        if (currentValue == null) {
            currentValue = 0;
        }
        if (previousValue == null) {
            previousValue = 0;
        }
        return currentValue - previousValue;
    }

    /** Drop-Feld auf Account = Wert(aktueller Monat) − Wert(Vormonat); null im Januar. */
    public static Decimal accountDrop(Decimal currentValue, Decimal previousValue, Boolean hasPreviousMonth) {
        return dropValue(currentValue, previousValue, hasPreviousMonth);
    }

    /** Keys 'yyyy-MM' für Januar bis (inkl.) den Monat von asOf. */
    public static List<String> monthKeys(Date asOf) {
        List<String> keys = new List<String>();
        for (Integer m = 1; m <= asOf.month(); m++) {
            keys.add(monthKey(asOf.year(), m));
        }
        return keys;
    }

    /** Monats-Ende (letzter Tag des Monats) als Date. */
    public static Date monthEnd(Integer year, Integer month) {
        Date firstNext = (month == 12)
            ? Date.newInstance(year + 1, 1, 1)
            : Date.newInstance(year, month + 1, 1);
        return firstNext.addDays(-1);
    }

    private static Boolean isCurrentMonth(String mk, Date asOf) {
        return Integer.valueOf(mk.substring(0, 4)) == asOf.year()
            && Integer.valueOf(mk.substring(5, 7)) == asOf.month();
    }

    private static String monthKey(Integer year, Integer month) {
        String mm = (month < 10 ? '0' : '') + String.valueOf(month);
        return String.valueOf(year) + '-' + mm;
    }

    private static String monthKey(Date d) {
        return monthKey(d.year(), d.month());
    }
}
