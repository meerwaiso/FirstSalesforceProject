/**
 * [SCRUM-416] Offene Chancen je Kunde — Apex-Funktionaltests.
 *
 * TA→AK-Mapping (docs/SCRUM-416-design.md):
 *   TA-1 ≙ AK1: 3 offen + 1 won + 2 lost → Count = 3, Value = Summe gerade der 3 Offenen.
 *   TA-2 ≙ AK2: offene Chance IsClosed → true (won UND lost) → fällt aus Count UND Summe.
 *   TA-3 ≙ AK3: offene Chance Amount X → Y → Summe weicht um Y − X; NEGATIV: won-Chance
 *                umwerten → Account-Werte bleiben unverändert.
 *   TA-4 ≙ AK4: offene Chance auf anderen Account umhängen → alter Count −1/Value −x,
 *                neuer +1/+x, beide korrekt.
 *   TA-5:    offene Chance mit leerem Amount → zählt in Count, 0 in Value.
 *   TA-6:    Bulk — 200 Opportunities in einem Batch über 10 Accounts → Governor Limits grün.
 *
 * «offen» = IsClosed = false (Single Source of Truth, ADR-3). Der Test verifiziert
 * das ERGEBNIS auf dem Account (aus Sicht des Users) — nicht die interne Mechanik.
 * Alles, was hier erzeugt wird, rollt mit der Test-Transaction zurück.
 */
@isTest
private class SCRUM416OpenOpportunityRollupTest {

    /** Erzeugt einen minimalen Account und gibt die Id zurück. */
    private static Id newAccount(String tag) {
        Account a = new Account(Name = 'V416 ' + tag);
        insert a;
        return a.Id;
    }

    /** Liest die beiden Account-Werte roh (kein Cast, kein ??-Default — Gate für Default 0). */
    private static Account values(Id accId) {
        return [SELECT Id, Open_Opportunity_Count__c, Open_Opportunity_Value__c
                FROM Account WHERE Id = :accId];
    }

    /**
     * TA-5-Auszug + Raw-Roh-Startwert: ein leerer Account zeigt 0/0 (Feld-Default 0,
     * nicht NULL) — das AC «Kunde ohne offene Chancen → 0/0» ist ein echtes Gate.
     */
    @isTest
    static void freshAccount_defaultsZeroZero() {
        Id a = newAccount('Zero');
        Account acc = values(a);
        System.assertEquals(Decimal.valueOf(0), acc.Open_Opportunity_Count__c,
            'Roh-Startwert Count muss 0 sein (Feld-Default), nicht NULL');
        System.assertEquals(Decimal.valueOf(0), acc.Open_Opportunity_Value__c,
            'Roh-Startwert Value muss 0 sein, nicht NULL');
    }

    /**
     * TA-1 ≙ AK1: 3 offene + 1 won + 2 lost → Count = 3, Value = Summe der 3 Offenen
     * (won/lost nicht enthalten, Beträge gewählt, dass Summen unterscheidbar sind).
     */
    @isTest
    static void mixedStages_countsAndSumsOpenOnly() {
        Id a = newAccount('Mixed');
        List<Opportunity> ops = new List<Opportunity>();
        // 3 offen: 100 + 200 + 300 = 600
        ops.add(new Opportunity(Name = 'V416 open-1', AccountId = a, StageName = 'Prospecting', Amount = 100));
        ops.add(new Opportunity(Name = 'V416 open-2', AccountId = a, StageName = 'Qualification', Amount = 200));
        ops.add(new Opportunity(Name = 'V416 open-3', AccountId = a, StageName = 'Proposed', Amount = 300));
        // 1 won: 999 (müsste 1600 ergeben, wenn won zählte)
        ops.add(new Opportunity(Name = 'V416 won', AccountId = a, StageName = 'Closed Won', Amount = 999));
        // 2 lost: 888 + 777 (müssten 3265 ergeben, wenn lost zählte)
        ops.add(new Opportunity(Name = 'V416 lost-1', AccountId = a, StageName = 'Closed Lost', Amount = 888));
        ops.add(new Opportunity(Name = 'V416 lost-2', AccountId = a, StageName = 'Closed Lost', Amount = 777));
        insert ops;

        Account acc = values(a);
        System.assertEquals(Decimal.valueOf(3), acc.Open_Opportunity_Count__c,
            'Nur die 3 offenen Chancen zählen, won/lost nicht');
        System.assertEquals(Decimal.valueOf(600), acc.Open_Opportunity_Value__c,
            'Summe enthält nur die 3 offenen Beträge (100+200+300), won/lost nicht');
    }

    /**
     * TA-2 ≙ AK2: eine offene Chance fällt aus Count UND Summe, wenn sie geschlossen
     * wird — geprüft für gewonnen UND verloren.
     */
    @isTest
    static void closingOpenOpp_removesFromCountAndSum() {
        Id a = newAccount('Close');
        Opportunity open = new Opportunity(
            Name = 'V416 close-target', AccountId = a, StageName = 'Prospecting', Amount = 500);
        insert open;
        Account acc0 = values(a);
        System.assertEquals(Decimal.valueOf(1), acc0.Open_Opportunity_Count__c);
        System.assertEquals(Decimal.valueOf(500), acc0.Open_Opportunity_Value__c);

        // Als gewonnen markieren
        open.StageName = 'Closed Won';
        update open;
        Account acc1 = values(a);
        System.assertEquals(Decimal.valueOf(0), acc1.Open_Opportunity_Count__c,
            'Gewonnene Chance zählt nicht mehr in Count');
        System.assertEquals(Decimal.valueOf(0), acc1.Open_Opportunity_Value__c,
            'Gewonnener Betrag fällt aus Summe');

        // Wiederaufmachen → zählt wieder
        open.StageName = 'Prospecting';
        update open;
        Account acc2 = values(a);
        System.assertEquals(Decimal.valueOf(1), acc2.Open_Opportunity_Count__c,
            'Reopen zählt wieder in Count');
        System.assertEquals(Decimal.valueOf(500), acc2.Open_Opportunity_Value__c,
            'Reopens betrag zählt wieder in Summe');
    }

    @isTest
    static void lostAlsoDrops() {
        Id a = newAccount('Lost');
        Opportunity open = new Opportunity(
            Name = 'V416 lost-target', AccountId = a, StageName = 'Prospecting', Amount = 350);
        insert open;
        open.StageName = 'Closed Lost';
        update open;

        Account acc = values(a);
        System.assertEquals(Decimal.valueOf(0), acc.Open_Opportunity_Count__c,
            'Verlorene Chance zählt nicht mehr in Count');
        System.assertEquals(Decimal.valueOf(0), acc.Open_Opportunity_Value__c,
            'Verlorener Betrag fällt aus Summe');
    }

    /**
     * TA-3 ≙ AK3: offene Chance umwerten X → Y, Summe weicht um Y − X.
     * NEGATIV: won-Chance umwerten → Account-Werte bleiben unverändert.
     */
    @isTest
    static void reopeningMovesSum_deltaOfDifference() {
        Id a = newAccount('Reval');
        Opportunity open = new Opportunity(
            Name = 'V416 reval', AccountId = a, StageName = 'Prospecting', Amount = 100);
        insert open;
        open.Amount = 250;
        update open;

        Account acc = values(a);
        System.assertEquals(Decimal.valueOf(1), acc.Open_Opportunity_Count__c,
            'Count bleibt 1 bei reiner Betragänderung');
        System.assertEquals(Decimal.valueOf(250), acc.Open_Opportunity_Value__c,
            'Summe weicht um Y − X (250 − 100 = 150)');
    }

    @isTest
    static void revaluingClosedOpp_doesNotTouchValues() {
        Id a = newAccount('RevalClosed');
        Opportunity won = new Opportunity(
            Name = 'V416 won-reval', AccountId = a, StageName = 'Closed Won', Amount = 100);
        insert won;
        Account acc0 = values(a);
        System.assertEquals(Decimal.valueOf(0), acc0.Open_Opportunity_Count__c);
        System.assertEquals(Decimal.valueOf(0), acc0.Open_Opportunity_Value__c);

        won.Amount = 9999;
        update won;
        Account acc1 = values(a);
        System.assertEquals(Decimal.valueOf(0), acc1.Open_Opportunity_Count__c,
            'Umwertung einer won-Chance bewegt Count nicht');
        System.assertEquals(Decimal.valueOf(0), acc1.Open_Opportunity_Value__c,
            'Umwertung einer won-Chance bewegt Summe nicht');
    }

    /**
     * TA-4 ≙ AK4: offene Chance auf einen anderen Account umhängen →
     * alter Count −1/Value −x, neuer +1/+x; BEIDE Kunden zeigen danach
     * korrekte Werte (alter Client hat nebenher eine eigene offene Chance).
     */
    @isTest
    static void reassigningMovesBothAccounts() {
        Id oldAcc = newAccount('Old');
        Id newAcc = newAccount('New');
        // Alter Kunde hat zusätzlich eine eigene offene Chance (200),
        // damit sich das −1/−x vom restlichen Bestand abhebt.
        Opportunity other = new Opportunity(
            Name = 'V416 stay', AccountId = oldAcc, StageName = 'Prospecting', Amount = 200);
        Opportunity mover = new Opportunity(
            Name = 'V416 mover', AccountId = oldAcc, StageName = 'Prospecting', Amount = 400);
        insert other;
        insert mover;

        Account old0 = values(oldAcc);
        System.assertEquals(Decimal.valueOf(2), old0.Open_Opportunity_Count__c);
        System.assertEquals(600, old0.Open_Opportunity_Value__c);

        mover.AccountId = newAcc;
        update mover;

        Account old1 = values(oldAcc);
        System.assertEquals(Decimal.valueOf(1), old1.Open_Opportunity_Count__c,
            'Alter Kunde: Count −1 nach Umhängen');
        System.assertEquals(200, old1.Open_Opportunity_Value__c,
            'Alter Kunde: Value −400 nach Umhängen');

        Account new1 = values(newAcc);
        System.assertEquals(Decimal.valueOf(1), new1.Open_Opportunity_Count__c,
            'Neuer Kunde: Count +1 nach Umhängen');
        System.assertEquals(400, new1.Open_Opportunity_Value__c,
            'Neuer Kunde: Value +400 nach Umhängen');
    }

    /**
     * TA-5: offene Chance mit leerem Amount → zählt in Count, 0 in Value.
     */
    @isTest
    static void blankAmount_countsButZeroValue() {
        Id a = newAccount('Blank');
        Opportunity open = new Opportunity(
            Name = 'V416 blank', AccountId = a, StageName = 'Prospecting', Amount = null);
        insert open;

        Account acc = values(a);
        System.assertEquals(Decimal.valueOf(1), acc.Open_Opportunity_Count__c,
            'Offene ohne Betrag zählt in Count');
        System.assertEquals(Decimal.valueOf(0), acc.Open_Opportunity_Value__c,
            'Fehlender Betrag zählt als 0 in Summe');
    }

    /**
     * TA-5 (Ergänzung, Delete): offene Chance löschen → fällt aus Count UND Summe.
     */
    @isTest
    static void deletingOpenOpp_dropsCountAndSum() {
        Id a = newAccount('Del');
        Opportunity open = new Opportunity(
            Name = 'V416 del', AccountId = a, StageName = 'Prospecting', Amount = 750);
        insert open;
        Account acc0 = values(a);
        System.assertEquals(Decimal.valueOf(1), acc0.Open_Opportunity_Count__c);
        System.assertEquals(Decimal.valueOf(750), acc0.Open_Opportunity_Value__c);

        delete open;
        Account acc1 = values(a);
        System.assertEquals(Decimal.valueOf(0), acc1.Open_Opportunity_Count__c,
            'Gelöschte offene Chance zählt nicht mehr in Count');
        System.assertEquals(Decimal.valueOf(0), acc1.Open_Opportunity_Value__c,
            'Gelöschter Betrag fällt aus Summe');
    }

    /**
     * TA-6: Bulk — 200 offene Opportunities in EINEM insert-Batch über 10 Accounts
     * → jeweils Count 20; Summe = Beträge der je 20 Chancen dieses Accounts.
     * Governor-Limits grün: 2 SOQL-Reads + 1 update pro Batch (kein SOQL in Loop).
     */
    @isTest
    static void bulkTwoHundredOverTenAccounts() {
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            accs.add(new Account(Name = 'V416 Bulk ' + i));
        }
        insert accs;

        // Erwartungswerte PRO-Account VOR dem Batch aufbauen (kein SOQL in Loop):
        // Bucket k (k = 0..9) erhält die Chancen i mit i % 10 == k (i = 0..199),
        // d. h. i = k, k+10, ..., k+190 → 20 Chancen mit Amount 10+i.
        Map<Id, Integer> expectedCount = new Map<Id, Integer>();
        Map<Id, Decimal> expectedValue = new Map<Id, Decimal>();
        for (Account ac : accs) {
            expectedCount.put(ac.Id, 0);
            expectedValue.put(ac.Id, 0);
        }
        for (Integer i = 0; i < 200; i++) {
            Id accId = accs[i % 10].Id;
            expectedCount.put(accId, expectedCount.get(accId) + 1);
            expectedValue.put(accId, expectedValue.get(accId) + (10 + i));
        }

        List<Opportunity> ops = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            ops.add(new Opportunity(
                Name = 'V416 bulk-' + i,
                AccountId = accs[i % 10].Id,
                StageName = 'Prospecting',
                Amount = 10 + i));
        }
        insert ops;

        // Ein einziger Account-Read: alle 10 müssen exakt stimmen.
        List<Id> accIds = new List<Id>();
        for (Account a : accs) {
            accIds.add(a.Id);
        }
        Integer checked = 0;
        for (Account acc : [SELECT Id, Open_Opportunity_Count__c, Open_Opportunity_Value__c
                            FROM Account WHERE Id IN :accIds]) {
            System.assertEquals(
                Decimal.valueOf(expectedCount.get(acc.Id)),
                acc.Open_Opportunity_Count__c,
                'Count des Accounts weicht ab (erwartet ' + expectedCount.get(acc.Id) + ')');
            System.assertEquals(
                expectedValue.get(acc.Id),
                acc.Open_Opportunity_Value__c,
                'Summe des Accounts weicht ab (erwartet ' + expectedValue.get(acc.Id) + ')');
            checked++;
        }
        System.assertEquals(10, checked, 'Alle 10 Accounts müssen gecheckt sein');
    }
}
