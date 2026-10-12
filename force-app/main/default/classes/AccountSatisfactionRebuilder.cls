/**
 * AccountSatisfactionRebuilder — SCRUM-442: nächtlicher Vollrecompute of the
 * four system-maintained Account.Satisfaction_* fields over the whole Account
 * stock (ADR-3, house SCRUM-417 OpenOpportunityHistoryRebuilder / SCRUM-388
 * AccountReactivationBatch).
 *
 * Why a nightly full recompute and not an immediate trigger: the 3-month
 * window is ROLLING (today minus 3 calendar months) — it drifts every day
 * without any data change. An immediate recompute at the closing would freeze
 * the window. Consequence stated to the PO: the customer-side average can lag
 * one day; the follow-up Task (AC3) is created immediately in the Case
 * trigger, so the obligation is never late.
 *
 * Per Account:
 *   Satisfaction_Fenster_Start__c = today.addMonths(-3)   (AC6: the period
 *                                                       must be visible)
 *   Satisfaction_Anzahl__c    = # closed Cases with a score, CloseDate >= window
 *   Satisfaction_Durchdurch__c  = average of the scores (1 decimal), null =
 *                               NO closed Case in the window (PO-Decision:
 *                               must not read as satisfied)
 *   Satisfaction_Min__c       = minimum score in the window, null = no data
 *   Satisfaction_Arger__c     is the platform formula field — never written
 *                               here (formula fields take no write FLS).
 *
 * Idempotency (house SCRUM-388/365/417): only rows whose values actually
 * changed are updated -> a second run without data change touches 0 rows.
 * Drift-healing: an Account whose Cases left the window gets its fields reset
 * to null/count 0 — the average never stays stale.
 *
 * Governor (ADR-7): QueryLocator over the FULL Account stock, 200er-Chunks,
 * per Chunk exactly 1 SOQL (the Cases of that chunk's Accounts in the window)
 * + 1 conditional bulk update, 0 SOQL in loops.
 *
 * avg/min/count are computed in Apex from the fetched rows, NOT as SOQL
 * aggregates: AVG()/MIN() over a Picklist field is not an aggregate-able
 * column (ADR-2 chose Picklist over Number for the score), and the Org
 * compiler rejects the conditional aggregate forms (SCRUM-420 lesson).
 *
 * Date-bind caveat (SCRUM-417): a Date bind is cast to midnight of that day —
 * fine here (day-granularity window), the window start is computed ONCE per
 * run, never per record.
 *
 * without sharing (ADR-5): deterministic over the whole stock, independent of
 * the scheduled user's sharing. WITHOUT SHARING DOES NOT BYPASS FLS -> the
 * scheduled user needs the System-PS SCRUM442_Satisfaction_System.
 *
 * @author developer-agent
 * @date 2026-10-10
 */
public without sharing class AccountSatisfactionRebuilder {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    @testVisible
    public static Integer getUpdated() { return updatedCount; }

    @testVisible
    public static Integer getProcessed() { return processedCount; }

    private static Integer updatedCount = 0;
    private static Integer processedCount = 0;

    /** Window start of the current run: today minus 3 calendar months (PO). */
    public static Date windowStart() {
        return Date.today().addMonths(-3);
    }

    public static void run() {
        run(windowStart(), DEFAULT_BATCH_SIZE);
    }

    /** @testVisible entry: injectable window start + chunk size. */
    @testVisible
    public static void run(Date windowStartParam, Integer batchSize) {
        updatedCount = 0;
        processedCount = 0;
        Date window = (windowStartParam == null) ? windowStart() : windowStartParam;
        Integer size = (batchSize == null || batchSize <= 0) ? DEFAULT_BATCH_SIZE : batchSize;

        // QueryLocator over the FULL Account stock (house SCRUM-388/417) —
        // every Account is re-evaluated, so drift out of the window heals too.
        // Chunking verified against the org (probe 2026-10-10): the
        // Database.QueryLocator result iterates as Iterable<SObject> of single
        // records; the chunk loop below groups them into `size`-sized chunks.
        List<Account> buffer = new List<Account>();
        for (SObject so : (Iterable<SObject>) Database.getQueryLocator([
                SELECT Id, Satisfaction_Durchdurch__c, Satisfaction_Min__c,
                       Satisfaction_Anzahl__c, Satisfaction_Fenster_Start__c
                       FROM Account
            ])) {
            buffer.add((Account) so);
            if (buffer.size() >= size) {
                processChunk(window, buffer);
                buffer = new List<Account>();
            }
        }
        if (!buffer.isEmpty()) {
            processChunk(window, buffer);
        }
    }

    /** One chunk = 1 SOQL (the window's Cases of these Accounts) + 1 bulk update. */
    private static void processChunk(Date window, List<Account> chunk) {
        Set<Id> accIds = new Set<Id>();
        for (Account a : chunk) {
            accIds.add(a.Id);
        }
        processedCount += chunk.size();

        // 1 SOQL per chunk. Filter = the PO's window: closed Cases with a score
        // whose CloseDate is at/after the window start. No Date-literal
        // concatenation: the bind keeps the midnight-cast caveat visible
        // (SCRUM-417 lesson).
        // Parallel maps — the org compiler rejects inner types ("Inner types
        // are not allowed to have inner types", probe 2026-10-10), so the
        // per-Account stats live in three Maps, not a helper class.
        Map<Id, Integer> sumMap = new Map<Id, Integer>();
        Map<Id, Integer> countMap = new Map<Id, Integer>();
        Map<Id, Integer> minMap = new Map<Id, Integer>();
        for (Case c : [SELECT Id, AccountId, Customer_Satisfaction__c
                       FROM Case
                       WHERE AccountId IN :accIds
                         AND IsClosed = true
                         AND ClosedDate >= :window
                         AND Customer_Satisfaction__c != null]) {
            Integer score = scoreValue(String.valueOf(c.Customer_Satisfaction__c));
            if (score == null || c.AccountId == null) {
                continue;
            }
            Integer sum = sumMap.get(c.AccountId);
            Integer cnt = countMap.get(c.AccountId);
            Integer min = minMap.get(c.AccountId);
            sumMap.put(c.AccountId, (sum == null) ? score : sum + score);
            countMap.put(c.AccountId, (cnt == null) ? 1 : cnt + 1);
            minMap.put(c.AccountId, (min == null) ? score : Math.min(min, score));
        }

        List<Account> toUpdate = new List<Account>();
        for (Account a : chunk) {
            Integer cnt = countMap.get(a.Id);
            Decimal avg = null;
            Decimal min = null;
            Decimal countDec = Decimal.valueOf(0);
            if (cnt != null) {
                // 1 decimal, HALF_UP — setScale(1) verified against the org
                // (probe 2026-10-10: 13/4 -> 3.2).
                avg = Decimal.valueOf(sumMap.get(a.Id)) / Decimal.valueOf(cnt);
                avg = avg.setScale(1);
                min = Decimal.valueOf(minMap.get(a.Id));
                countDec = Decimal.valueOf(cnt);
            }

            // Conditional write: only rows that actually changed (idempotency).
            Boolean changed = false;
            if (a.Satisfaction_Fenster_Start__c != window) {
                a.Satisfaction_Fenster_Start__c = window;
                changed = true;
            }
            if (a.Satisfaction_Anzahl__c != countDec) {
                a.Satisfaction_Anzahl__c = countDec;
                changed = true;
            }
            if (a.Satisfaction_Durchdurch__c != avg) {
                a.Satisfaction_Durchdurch__c = avg;
                changed = true;
            }
            if (a.Satisfaction_Min__c != min) {
                a.Satisfaction_Min__c = min;
                changed = true;
            }
            if (changed) {
                toUpdate.add(a);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            updatedCount += toUpdate.size();
        }
    }

    /**
     * Score-API-Name -> value. The Picklist API-Names are the fixed set
     * Score_1..Score_5 (ADR-2); labels carry an en-dash and are locale-prone,
     * the API-Names are not. Unknown value -> null (never counted).
     */
    @testVisible
    public static Integer scoreValue(String apiName) {
        if (apiName == null) {
            return null;
        }
        if (apiName == 'Score_1') return 1;
        if (apiName == 'Score_2') return 2;
        if (apiName == 'Score_3') return 3;
        if (apiName == 'Score_4') return 4;
        if (apiName == 'Score_5') return 5;
        return null;
    }

}
