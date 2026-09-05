/**
 * SCRUM-388: Nächtlicher Reaktivierungs-Lauf über den kompletten Account-Stock.
 *
 * Rechnet einmal täglich (nächtlich) für JEDES Account zwei systemgepflegte
 * Felder neu — KEINE Sofortberechnung beim Speichern:
 *   - Last_Opportunity__c = CreatedDate der JÜNGSTEN Opportunity des Accounts
 *     (nie eine gehabt → bleibt null/leer, AC3)
 *   - Is_Inactive__c     = TRUE, wenn seit jenem Datum MEHR als 180 Tage liegen;
 *     ohne jemals eine Opportunity zählt die Schwelle ab dem Account's eigenen
 *     CreatedDate (AC4/AC6). Exakt 180 Tage = NOCH aktiv (AC5, striktes >).
 *
 * House-Pattern (QueryLocator, 200er-Chunks, ohne SELECT FOR UPDATE) aus
 * CaseOpenCountRebuilder (SCRUM-367), abgeleitet auf das hier passende:
 *   - QueryLocator über den VOLLSTÄNDIGEN Account-Stock (kein Filter), 200er-
 *     Chunks, kurze DML-Transaction je Chunk, KEIN SELECT FOR UPDATE
 *     → mehrere tausend Accounts ohne Timeout (AC7).
 *   - without sharing: muss ALLE Accounts/Opportunities sehen, unabhängig vom
 *     Sharing des Lauf-Users (AC7 „alle Accounts der Org“). ABER: without sharing
 *     umgeht nur REKORD-Sharing, NICHT Feld-Security (FLS) → der Lauf-User
 *     braucht Update-FLS auf beide Felder (→ SCRUM388_AccountReactivationWrite).
 *   - Bulk: pro Chunk 1 AGGREGATE-SOQL (MAX(CreatedDate) GROUP BY AccountId)
 *     + 1 konditionales DML (nur geänderte Records) → 0 SOQL/DML im Loop.
 *   - Idempotenz (AC8): aktueller Feldwert in der Query geholt + verglichen;
 *     ein Account wird nur aktualisiert, wenn ein Wert sich ändert → zweiter
 *     Lauf ohne Datenänderung toucht 0 Records. Die Zähler processed/corrected
 *     dienen der finish-Debug-Log (kein Run-Log-Objekt, PO-Scope „keine
 *     Historie“). Test-Strategie + Org-Besonderheit (kein Multi-Chunk-
 *     executeBatch; Direkt-Fahren über execute()): siehe Design-Doc ADR-4.
 *
 * @author developer-agent
 * @date 2026-09-05
 */
public without sharing class AccountReactivationBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    /** Schwelle in ganzen Tagen: MEHR als 180 → inaktiv (AC4), exakt 180 → aktiv (AC5). */
    public static final Integer INACTIVE_THRESHOLD_DAYS = 180;

    /** Standard-Batch-Größe (Accounts je Chunk). */
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    /** Referenz-Tag für die Tagesdifferenz. Production = System.today(). */
    private final Date asOf;
    /** Batch-Größe; Test-Konstruktor erlaubt kleine Chunks (AC7-Skalierung). */
    private final Integer batchSize;

    /** Verarbeitete Accounts (Stateful; summiert über alle Chunk-Grenzen). */
    private Integer processed;
    /** Tatsächlich geänderter Accounts (Stateful; summiert über alle Chunk-Grenzen). */
    private Integer corrected;

    /** Production: alle Accounts, Referenz = heutiger Tag. */
    public AccountReactivationBatch() {
        this(System.today(), DEFAULT_BATCH_SIZE);
    }

    /** Test-Konstruktor: fixierter Referenz-Tag + kleine Chunks (deterministisch). */
    @testVisible
    public AccountReactivationBatch(Date asOf, Integer batchSize) {
        this.asOf = asOf;
        this.batchSize = (batchSize == null) ? DEFAULT_BATCH_SIZE : batchSize;
        this.processed = 0;
        this.corrected = 0;
    }

    /** Zähler-Auslesung für direkte Ausführung im Apex-Test (siehe ADR-4). */
    @testVisible
    public Integer getProcessed() { return processed; }
    @testVisible
    public Integer getCorrected() { return corrected; }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // VOLLSTÄNDIGER Stock +aktueller Feldwert zum Idempotenz-Compare (AC8).
        return Database.getQueryLocator(
            'SELECT Id, CreatedDate, Last_Opportunity__c, Is_Inactive__c FROM Account');
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for (Account a : scope) {
            accountIds.add(a.Id);
        }

        // 1 AGGREGATE-SOQL je Chunk: jüngste CreatedDate pro Account. Nur Accounts
        // MIT Opportunity erscheinen; keine → nicht im Map → Fallback (AC3/AC6).
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
            Date ref   = newestByAccount.get(a.Id);     // null → nie eine Opportunity
            Date lastOpp;
            if (ref == null) {
                lastOpp = null;                          // AC3: Datum bleibt leer
                ref   = a.CreatedDate.date();            // AC6: Schwelle ab Account-Anlage
            } else {
                lastOpp = ref;                           // AC2/AC4: Datum der jüngsten Opp
            }

            Integer daysSince   = (asOf == null || ref == null) ? 0 : asOf.daysAfter(ref);
            Boolean newInactive = daysSince > INACTIVE_THRESHOLD_DAYS;   // AC5: striktes >

            if (a.Is_Inactive__c != newInactive || a.Last_Opportunity__c != lastOpp) {
                a.Last_Opportunity__c = lastOpp;
                a.Is_Inactive__c      = newInactive;
                toUpdate.add(a);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;                             // 1 DML je Chunk, nur geänderte (AC8)
        }
        corrected += toUpdate.size();
        processed += scope.size();
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('AccountReactivationBatch: processed=' + processed +
                     ' corrected=' + corrected);
    }
}
