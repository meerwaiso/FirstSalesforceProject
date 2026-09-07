/**
 * [SCRUM-396] Functional test for the new formula field
 * Contact.Betreuungsstufe__c („Betreuungsstufe“, read-only Text formula).
 *
 * Covers AC1 deterministically (ADR-1 — declarative formula, no Apex/Flow):
 *   „keine“  when Open_Cases_Count__c = 0
 *   „normal“ when Open_Cases_Count__c = 1 or 2
 *   „hoch“   when Open_Cases_Count__c >= 3
 *   Evaluated at view time from the CURRENT value of
 *   Open_Cases_Count__c (AC: „aktualisiert sich, wenn sich die Anzahl
 *   offener Fälle ändert“).
 *
 * ORG CONSTRAINT (verified, SCRUM-396 header):
 *   Open_Cases_Count__c is a Number field with Default 0 maintained by
 *   CaseOpenCountTrigger (SCRUM-365). The trigger is NOT part of this ticket
 *   (Out-of-Scope: „keine Änderung an Open_Cases_Count__c oder den Triggern“),
 *   so the value is set directly via DML in the test to probe each formula
 *   branch in isolation. The field is also NOT part of the Contact required
 *   field set, so all branches are DML-reachable (unlike Lead.Company in
 *   SCRUM-394, which had a required-field guard).
 *
 * House shape: SCRUM394DataQualityTest.cls (query back after DML —
 * formula fields are not populated on the in-memory sObject).
 */
@isTest
private class SCRUM396BetreuungsstufeTest {

    private static Contact makeContact(String tag, Integer openCases) {
        Contact c = new Contact(
            LastName = tag,
            Open_Cases_Count__c = openCases
        );
        insert c;
        return c;
    }

    private static String readValue(String contactId) {
        return [SELECT Betreuungsstufe__c FROM Contact WHERE Id = :contactId].Betreuungsstufe__c;
    }

    // ---- AC1 value matrix ------------------------------------------------

    @isTest
    static void zeroOpenCases_showsKeine() {
        Contact c = makeContact('TEST-SCRUM-396-ZERO', 0);
        System.assertEquals(
            'keine', readValue(c.Id),
            '0 offene Fälle -> „keine“ (AC1)'
        );
    }

    @isTest
    static void oneOpenCase_showsNormal() {
        Contact c = makeContact('TEST-SCRUM-396-ONE', 1);
        System.assertEquals(
            'normal', readValue(c.Id),
            '1 offener Fall -> „normal“ (AC1)'
        );
    }

    @isTest
    static void twoOpenCases_showsNormal() {
        Contact c = makeContact('TEST-SCRUM-396-TWO', 2);
        System.assertEquals(
            'normal', readValue(c.Id),
            '2 offene Fälle -> „normal“ (AC1)'
        );
    }

    @isTest
    static void threeOpenCases_showsHoch() {
        Contact c = makeContact('TEST-SCRUM-396-THREE', 3);
        System.assertEquals(
            'hoch', readValue(c.Id),
            '3 offene Fälle -> „hoch“ (AC1)'
        );
    }

    @isTest
    static void fourOpenCases_showsHoch() {
        Contact c = makeContact('TEST-SCRUM-396-FOUR', 4);
        System.assertEquals(
            'hoch', readValue(c.Id),
            '4 offene Fälle -> „hoch“ (AC1)'
        );
    }

    @isTest
    static void valueFollowsCurrentState_notPersistedStale() {
        // AC1: the value must reflect the CURRENT value of
        // Open_Cases_Count__c at the moment of viewing. A formula (not a
        // trigger-maintained field) recomputes on every read, so a change to
        // the count must immediately flip the result in the same transaction.
        Contact c = makeContact('TEST-SCRUM-396-FLIP', 0);
        System.assertEquals('keine', readValue(c.Id), 'Precondition: 0 -> keine');

        c.Open_Cases_Count__c = 1;
        update c;
        System.assertEquals(
            'normal', readValue(c.Id),
            'After 1 the value must flip to „normal“ (AC1: current state, not stale)'
        );

        c.Open_Cases_Count__c = 3;
        update c;
        System.assertEquals(
            'hoch', readValue(c.Id),
            'After 3 the value must flip to „hoch“ (AC1: current state, not stale)'
        );

        c.Open_Cases_Count__c = 0;
        update c;
        System.assertEquals(
            'keine', readValue(c.Id),
            'After back to 0 the value must flip back to „keine“'
        );
    }

    // ---- Schema asserts (field definition) --------------------------------

    @isTest
    static void fieldIsReadOnlyCalculatedStringFormula() {
        Schema.DescribeFieldResult f = Contact.Betreuungsstufe__c.getDescribe();
        System.assertEquals(
            true, f.isCalculated(),
            'Betreuungsstufe__c must be a calculated (formula) field (ADR-1)'
        );
        System.assertEquals(
            false, f.isUpdateable(),
            'Betreuungsstufe__c must be read-only (formula, no user edit)'
        );
        System.assert(
            f.getType() == Schema.DisplayType.STRING,
            'Betreuungsstufe__c must be a Text field (PO wants the word values keine/normal/hoch)'
        );
        System.assertEquals(
            0, f.getPicklistValues().size(),
            'Betreuungsstufe__c must have NO Picklist values — the three literals are inside the formula, not a controlled vocabulary'
        );
    }
}
