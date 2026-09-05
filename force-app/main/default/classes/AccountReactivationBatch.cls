/**
 * SCRUM-388: Naechtiger Reaktivierungs-Lauf ueber den kompletten Account-Stock.
 *
 * Rechnet einmal taeglich (naechtlich) fuer JEDEN Account zwei
 * systemgepflegte Felder neu, KEINE Sofortberechnung beim Speichern:
 *   - Last_Opportunity__c = CreatedDate der JUENGSTEN Opportunity des
 *     Accounts (nie eine gehabt -> null/leer, AC3)
 *   - Is_Inactive__c      = TRUE, wenn seit jenem Datum MEHR als 180 Tage
 *     liegen; ohne jemals eine Opportunity zaehlt die Schwelle ab dem
 *     eigenen CreatedDate (AC4/AC6). Exakt 180 Tage = NOCH aktiv (AC5, >).
 *
 * House-Pattern (QueryLocator, 200er-Chunks) aus CaseOpenCountRebuilder
 * (SCRUM-367): QueryLocator ueber den VOLLSTAENDIGEN Account-Stock, 200er-
 * Chunks, kurze DML-Transaction je Chunk, KEIN SELECT FOR UPDATE -> mehrere
 * tausend Accounts ohne Timeout (AC7). without sharing sieht ALLE Records,
 * aber umgeht NICHT FLS -> Lauf-User braucht Update-FLS auf beide Felder
 * (-> SCRUM388_AccountReactivationWrite). Pro Chunk 1 AGGREGATE-SOQL + 1
 * konditionales DML (nur geaenderte Records) -> 0 SOQL/DML im Loop.
 * Idempotenz (AC8): aktueller Feldwert in Query geholt + verglichen; zweiter
 * Lauf ohne Datenaeanderung toucht 0 Records. Zaedler processed/corrected
 * dienen der finish-Debug-Log.
 *
 * @author developer-agent
 * @date 2026-09-05
 */
public without sharing class AccountReactivationBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer INACTIVE_THRESHOLD_DAYS = 180;
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private final Date asOf;
    private final Integer batchSize;
    private Integer processed;
    private Integer corrected;

    public AccountReactivationBatch() {
        this(System.today(), DEFAULT_BATCH_SIZE);
    }

    @testVisible
    public AccountReactivationBatch(Date asOf, Integer batchSize) {
        this.asOf = asOf;
        this.batchSize = (batchSize == null) ? DEFAULT_BATCH_SIZE : batchSize;
        this.processed = 0;
        this.corrected = 0;
    }

    @testVisible
    public Integer getProcessed() { return processed; }
    @testVisible
    public Integer getCorrected() { return corrected; }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator(
            'SELECT Id, CreatedDate, Last_Opportunity__c, Is_Inactive__c FROM Account');
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for (Account a : scope) {
            accountIds.add(a.Id);
        }

        Map<Id, Date> newestByAccount = new Map<Id, Date>();
        for (AggregateResult ar :
                [SELECT AccountId, MAX(CreatedDate) newCreated
                 FROM Opportunity
                 WHERE AccountId IN :accountIds
                 GROUP BY AccountId]) {
            Object newest = ar.get('newCreated');
            if (newest == null) {
                continue;
            }
            Date newestDate = (newest instanceof DateTime)
                    ? ((DateTime) newest).date()
                    : (Date) newest;
            newestByAccount.put((Id) ar.get('AccountId'), newestDate);
        }

        List<Account> toUpdate = new List<Account>();
        for (Account a : scope) {
            Date ref   = newestByAccount.get(a.Id);    // null -> nie eine Opportunity
            Date lastOpp;
            if (ref == null) {
                lastOpp = null;                          // AC3: leer
                ref     = a.CreatedDate.date();          // AC6: ab Account-Anlage
            } else {
                lastOpp = ref;                           // AC2/AC4
            }

            Integer daysSince   = wholeDaysBetween(ref, asOf);
            Boolean newInactive = daysSince > INACTIVE_THRESHOLD_DAYS; // AC5: >

            if (a.Is_Inactive__c != newInactive || a.Last_Opportunity__c != lastOpp) {
                a.Last_Opportunity__c = lastOpp;
                a.Is_Inactive__c      = newInactive;
                toUpdate.add(a);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        corrected += toUpdate.size();
        processed += scope.size();
    }

    private static Integer wholeDaysBetween(Date fromDate, Date toDate) {
        if (fromDate == null || toDate == null) {
            return 0;
        }
        return fromDate.daysBetween(toDate);
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('AccountReactivationBatch: processed=' + processed +
                     ' corrected=' + corrected);
    }
}
