/**
 * [SCRUM-402] Functional test for the formula field Opportunity.Value_Tier__c
 * („Wertstufe“, read-only Text formula — the live computation from Amount).
 *
 * Covers AC1 deterministically (declarative formula, no Apex/Flow):
 *   „Unbekannt“ when Amount is null      <-- RE-REGRESSION GUARD against
 *                                            formulaTreatBlanksAs=BlankAsZero,
 *                                            the deployed defect from SCRUM-401
 *   „Gering“    when Amount < 50.000
 *   „Mittel“    when 50.000 <= Amount <= 99.999.99 (lower bound inclusive)
 *   „Hoch“      when Amount >= 100.000        (lower bound inclusive)
 *
 * And AC1 „die Wertstufe folgt dem aktuellen Betrag“: a change to Amount flips
 * the Wertstufe in the same read, without any manual upkeep (formula recomputes
 * on every read).
 *
 * House shape: SCRUM396BetreuungsstufeTest.cls (query back after DML — formula
 * fields are not populated on the in-memory sObject). An Opportunity is created
 * with no Account (Amount is the only value-bearing input of the formula).
 */
@isTest
private class SCRUM402WertstufeTest {

    private static Opportunity makeOpp(String tag, Decimal amount) {
        Opportunity o = new Opportunity(
            Name = tag,
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1),
            Amount = amount
        );
        insert o;
        return o;
    }

    private static String readValue(String oppId) {
        return [SELECT Value_Tier__c FROM Opportunity WHERE Id = :oppId].Value_Tier__c;
    }

    // ---- AC1 value matrix ------------------------------------------------

    @isTest
    static void nullAmount_showsUnbekannt_reRegressionGuard() {
        // The SCRUM-401 defect deployed formulaTreatBlanksAs=BlankAsZero, which
        // coerced a blank Amount to 0 and rendered „Gering“. With ErrorIfAnyBlank
        // + ISBLANK first, a blank Amount must yield the sentinel „Unbekannt“.
        Opportunity o = makeOpp('TEST-SCRUM-402-NULL', null);
        System.assertEquals(
            'Unbekannt', readValue(o.Id),
            'null Amount -> „Unbekannt“ (AC1; re-regression guard against BlankAsZero)'
        );
    }

    @isTest
    static void amountBelow50k_showsGering() {
        Opportunity o = makeOpp('TEST-SCRUM-402-15K', 15000);
        System.assertEquals('Gering', readValue(o.Id), '15.000 -> „Gering“ (AC1)');
    }

    @isTest
    static void amountExactly50k_showsMittel_lowerBoundInclusive() {
        Opportunity o = makeOpp('TEST-SCRUM-402-50K', 50000);
        System.assertEquals(
            'Mittel', readValue(o.Id),
            '50.000 -> „Mittel“ (AC1; untere Grenze inclusive)'
        );
    }

    @isTest
    static void amountJustBelow100k_showsMittel() {
        Opportunity o = makeOpp('TEST-SCRUM-402-99999', 99999.99);
        System.assertEquals(
            'Mittel', readValue(o.Id),
            '99.999,99 -> „Mittel“ (AC1; oberhalb 50.000, unter 100.000)'
        );
    }

    @isTest
    static void amountExactly100k_showsHoch_lowerBoundInclusive() {
        Opportunity o = makeOpp('TEST-SCRUM-402-100K', 100000);
        System.assertEquals(
            'Hoch', readValue(o.Id),
            '100.000 -> „Hoch“ (AC1; untere Grenze inclusive)'
        );
    }

    @isTest
    static void amountAbove100k_showsHoch() {
        Opportunity o = makeOpp('TEST-SCRUM-402-250K', 250000);
        System.assertEquals('Hoch', readValue(o.Id), '250.000 -> „Hoch“ (AC1)');
    }

    @isTest
    static void valueFollowsCurrentAmount_notPersistedStale() {
        // AC1: „Ändert sich Amount, ändert sich die Wertstufe, ohne dass
        // jemand etwas nachträgt.“ A formula (not a trigger-maintained field)
        // recomputes on every read, so a change to Amount flips the result in
        // the same transaction — including crossing into and out of the null
        // branch (the BlankAsZero-relevant transition).
        Opportunity o = makeOpp('TEST-SCRUM-402-FLIP', null);
        System.assertEquals('Unbekannt', readValue(o.Id), 'Precondition: null -> „Unbekannt“');

        o.Amount = 15000;
        update o;
        System.assertEquals('Gering', readValue(o.Id), 'After 15.000 the value flips to „Gering“');

        o.Amount = 100000;
        update o;
        System.assertEquals('Hoch', readValue(o.Id), 'After 100.000 the value flips to „Hoch“');

        o.Amount = null;
        update o;
        System.assertEquals(
            'Unbekannt', readValue(o.Id),
            'After back to null the value must flip back to „Unbekannt“, not stick at „Gering“ (BlankAsZero regression)'
        );
    }

    // ---- Schema asserts (field definition) --------------------------------

    @isTest
    static void fieldIsReadOnlyCalculatedStringFormula() {
        Schema.DescribeFieldResult f = Opportunity.Value_Tier__c.getDescribe();
        System.assertEquals(
            true, f.isCalculated(),
            'Value_Tier__c must be a calculated (formula) field (ADR-1)'
        );
        System.assertEquals(
            false, f.isUpdateable(),
            'Value_Tier__c must be read-only (formula, no user edit)'
        );
        System.assert(
            f.getType() == Schema.DisplayType.STRING,
            'Value_Tier__c must be a Text field (PO wants the word values Hoch/Mittel/Gering/Unbekannt)'
        );
        System.assertEquals(
            0, f.getPicklistValues().size(),
            'Value_Tier__c must have NO Picklist values — the four literals are inside the formula, not a controlled vocabulary'
        );
    }
}
