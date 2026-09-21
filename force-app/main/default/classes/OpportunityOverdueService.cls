/**
 * OpportunityOverdueService — Core logic for detecting and marking inactive opportunities
 * 
 * - Finds opportunities that are overdue (open stage + no update for >14 days)
 * - Sets Is_Overdue__c = true on overdue opportunities
 * - Returns list of newly marked opportunity IDs for notification
 */
public with sharing class OpportunityOverdueService {

    @testVisible private static Integer OVERDUE_DAYS_THRESHOLD = 14;

    /**
     * Finds all overdue opportunities and marks them with Is_Overdue__c = true.
     * Returns the list of opportunity IDs that were newly marked (were false, now true).
     *
     * @return List of Ids of newly marked overdue opportunities
     */
    public static List<Id> findAndMarkOverdueOpportunities() {
        // DateTime gegen DateTime vergleichen, nicht Date gegen DateTime.
        //
        // Die frühere Fassung rechnete Date.today().addDays(-threshold + 1) und
        // verglich das mit LastModifiedDate. Date.today() liefert das Datum in der
        // Zeitzone des laufenden Benutzers, ein Date im Vergleich mit einem
        // DateTime-Feld verankert aber an GMT-Mitternacht. Damit hing das Ergebnis
        // davon ab, in welcher Zeitzone der Benutzer steht und zu welcher Stunde
        // gelaufen wurde: in einer Org mit America/Los_Angeles (GMT-7) fiel der
        // Stichtag zwischen 00:00 und 07:00 UTC in die Vergangenheit, und gerade
        // angelegte Datensätze fielen aus dem Filter. Der Prod-Org Drift Gate war
        // dadurch in diesem Fenster rot und danach grün, bei identischem Code.
        //
        // now() - threshold ist zeitzonenunabhängig und sagt genau, was gemeint ist:
        // seit N Tagen nicht mehr angefasst. Das +1 entfällt, weil es nur die
        // Date/DateTime-Grenze umgehen sollte.
        //
        // <= statt <: Salesforce stempelt DML-Zeitstempel mit der Transaktionszeit,
        // und System.now() liefert innerhalb derselben Transaktion genau diesen Wert.
        // Ein im Test gerade angelegter Datensatz liegt damit nicht VOR dem Stichtag,
        // sondern exakt AUF ihm. Fachlich identisch ("seit N Tagen nicht angefasst"),
        // für threshold=0 aber der Unterschied zwischen prüfbar und nicht prüfbar.
        DateTime thresholdTime = DateTime.now().addDays(-OVERDUE_DAYS_THRESHOLD);

        // Find open opportunities that are older than the threshold and not already marked
        List<Opportunity> overdueOpportunities = [
            SELECT Id, OwnerId, Name, StageName, LastModifiedDate, Is_Overdue__c
            FROM Opportunity
            WHERE StageName != 'Closed Won'
              AND StageName != 'Closed Lost'
              AND LastModifiedDate <= :thresholdTime
              AND Is_Overdue__c = false
        ];

        if (overdueOpportunities.isEmpty()) {
            return new List<Id>();
        }

        // Mark all overdue opportunities in a single bulk DML
        List<Id> newlyMarkedIds = new List<Id>();
        for (Opportunity opp : overdueOpportunities) {
            opp.Is_Overdue__c = true;
            newlyMarkedIds.add(opp.Id);
        }
        update overdueOpportunities;

        System.debug('OpportunityOverdueService: ' + newlyMarkedIds.size() + ' overdue opportunities marked.');
        return newlyMarkedIds;
    }
}