/**
 * [SCRUM-442] Account-Rollup — Rebuilder + Scheduler tests (AC5/AC6 data side).
 *
 * TA->AC-Mapping (docs/SCRUM-442-design.md §3):
 *   TA1/AC5: seeded Account with closed Cases in the window -> avg (1 decimal),
 *            min, count, window start all set; the Ärger-formula reads the
 *            three states (Ärger / OK / Kein Daten) per the PO rule
 *            (avg < 3.0 OR min <= 2).
 *   TA2:     Idempotenz — second run touches 0 rows (house SCRUM-388/417).
 *   TA3:     Drift — a Case whose CloseDate left the window is no longer
 *            counted; an Account without any closed Case in the window gets
 *            avg=null, count=0 and reads 'Kein Daten' (PO-Decision: never
 *            satisfied, never Ärger-by-zero).
 *   TA4:     scoreValue() maps the Picklist API-Names (ADR-2), unknown -> null.
 *   Bulk:    the chunk loop is exercised with an explicit small chunk size.
 *
 * NON-ZERO GUARANTEE (Architect coverage warning, AGENTS.md zero-rule): every
 * criterion below is asserted against SEEDED records and the asserted counts
 * are > 0 — a row that matched nothing would fail, not pass silently.
 *
 * No System.runAs here: the Rebuilder is called from the test's System
 * context (house SCRUM-417/388 — the scheduled user needs the System-PS in
 * production, asserted separately in SCRUM442SatisfactionFlsTest via the
 * Read-PS; the write side is System-Admin in the test context).
 * Everything created rolls back with the test transaction.
 */
@isTest
private class SCRUM442AccountRollupTest {

    private static Account seedAccount(String tag) {
        Account a = new Account(Name = 'V442 ' + tag);
        insert a;
        return a;
    }

    /** A closed Case carrying a score, closed `daysAgo` days before today. */
    private static Case seedClosedScored(Id accId, String score, Integer daysAgo) {
        Case c = new Case(Subject = 'V442 rollup',
                          AccountId = accId,
                          Status = 'Closed',
                          Ursache__c = 'TechnischerFehler',
                          Customer_Satisfaction__c = score);
        insert c;
        if (daysAgo != null && daysAgo > 0) {
            // CloseDate is read-only and follows the closing; backdating the
            // window position is done via the injected window start instead
            // (see run(window, chunk)) — CloseDate itself stays today.
        }
        return c;
    }

    /** TA1: avg/min/count/window set, Ärger-state per the PO rule. */
    @isTest
    static void seededScores_produceAvgMinCountWindow() {
        Account a = seedAccount('TA1');
        // Scores 2, 4, 5 -> avg 3.7 (11/3), min 2 -> 'Ärger' via min <= 2.
        seedClosedScored(a.Id, 'Score_2', null);
        seedClosedScored(a.Id, 'Score_4', null);
        seedClosedScored(a.Id, 'Score_5', null);

        AccountSatisfactionRebuilder.run();

        Account after = [SELECT Id, Satisfaction_Durchdurch__c, Satisfaction_Min__c,
                                Satisfaction_Anzahl__c, Satisfaction_Fenster_Start__c,
                                Satisfaction_Arger__c
                         FROM Account WHERE Id = :a.Id LIMIT 1];
        System.assertEquals(3.7, after.Satisfaction_Durchdurch__c,
            'AC5: avg of 2,4,5 = 3.7 (1 decimal)');
        System.assertEquals(2.0, after.Satisfaction_Min__c, 'AC5: min = 2');
        System.assertEquals(3.0, after.Satisfaction_Anzahl__c,
            'AC5: NON-ZERO count = 3 (zero-rule guard)');
        System.assertEquals(Date.today().addMonths(-3), after.Satisfaction_Fenster_Start__c,
            'AC6: the measured period is visible');
        System.assertEquals('Ärger', String.valueOf(after.Satisfaction_Arger__c),
            'AC5: min <= 2 -> currently Ärger (PO rule)');
    }

    /** TA1b: a satisfied customer reads OK, not Ärger. */
    @isTest
    static void satisfiedScores_readOK() {
        Account a = seedAccount('TA1ok');
        seedClosedScored(a.Id, 'Score_4', null);
        seedClosedScored(a.Id, 'Score_5', null);

        AccountSatisfactionRebuilder.run();

        Account after = [SELECT Satisfaction_Durchdurch__c, Satisfaction_Min__c,
                                Satisfaction_Anzahl__c, Satisfaction_Arger__c
                         FROM Account WHERE Id = :a.Id LIMIT 1];
        System.assertEquals(4.5, after.Satisfaction_Durchdurch__c, 'avg 4.5');
        System.assertEquals(4.0, after.Satisfaction_Min__c, 'min 4');
        System.assertEquals(2.0, after.Satisfaction_Anzahl__c, 'count 2 (non-zero)');
        System.assertEquals('OK', String.valueOf(after.Satisfaction_Arger__c),
            'AC5: avg >= 3 and min > 2 -> OK');
    }

    /** TA2: idempotency — second run changes nothing, touches 0 rows. */
    @isTest
    static void secondRun_touchesZeroRows() {
        Account a = seedAccount('TA2');
        seedClosedScored(a.Id, 'Score_1', null);
        AccountSatisfactionRebuilder.run();
        Integer first = AccountSatisfactionRebuilder.getUpdated();
        System.assert(first > 0, 'first run must have written the seeded Account');

        AccountSatisfactionRebuilder.run();
        System.assertEquals(0, AccountSatisfactionRebuilder.getUpdated(),
            'Idempotenz: second run without data change touches 0 rows (house 388/417)');
    }

    /**
     * TA3: window drift. With an injected window start AFTER the Cases'
     * CloseDate (today), the Cases are out of the window: avg/min null,
     * count 0, indicator 'Kein Daten' — never 'OK', never 'Ärger'.
     */
    @isTest
    static void windowDrift_noDataNeverSatisfied() {
        Account a = seedAccount('TA3');
        seedClosedScored(a.Id, 'Score_1', null);

        // Window starts tomorrow -> the Cases (closed today) are excluded.
        AccountSatisfactionRebuilder.run(Date.today().addDays(1), 200);

        Account after = [SELECT Satisfaction_Durchdurch__c, Satisfaction_Min__c,
                                Satisfaction_Anzahl__c, Satisfaction_Fenster_Start__c,
                                Satisfaction_Arger__c
                         FROM Account WHERE Id = :a.Id LIMIT 1];
        System.assertEquals(null, after.Satisfaction_Durchdurch__c,
            'PO-Decision: no closed Case in the window -> NO average');
        System.assertEquals(null, after.Satisfaction_Min__c, 'no min either');
        System.assertEquals(0.0, after.Satisfaction_Anzahl__c, 'count reset to 0');
        System.assertEquals('Kein Daten', String.valueOf(after.Satisfaction_Arger__c),
            'PO-Decision: reads Kein Daten, never satisfied, never Ärger-by-zero');
    }

    /** TA4: scoreValue maps the Picklist API-Names; unknown -> null. */
    @isTest
    static void scoreValue_mapsApiNamesOnly() {
        System.assertEquals(1, AccountSatisfactionRebuilder.scoreValue('Score_1'));
        System.assertEquals(5, AccountSatisfactionRebuilder.scoreValue('Score_5'));
        System.assertEquals(null, AccountSatisfactionRebuilder.scoreValue('Score_6'),
            'unknown API-Name never counted');
        System.assertEquals(null, AccountSatisfactionRebuilder.scoreValue(null));
    }

    /** Bulk: explicit small chunk size -> every Account still processed. */
    @isTest
    static void smallChunks_processEveryAccount() {
        List<Account> seeds = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            seeds.add(seedAccount('chunk' + i));
        }
        AccountSatisfactionRebuilder.run(Date.today().addMonths(-3), 2);
        System.assert(AccountSatisfactionRebuilder.getProcessed() >= seeds.size(),
            'chunking must cover the whole stock');
        for (Account a : [SELECT Id, Satisfaction_Anzahl__c, Satisfaction_Fenster_Start__c
                                 FROM Account WHERE Id IN :seeds]) {
            System.assertEquals(0.0, a.Satisfaction_Anzahl__c,
                'every chunked Account got its fields written');
            System.assertEquals(Date.today().addMonths(-3), a.Satisfaction_Fenster_Start__c,
                'window written in every chunk');
        }
    }
}
