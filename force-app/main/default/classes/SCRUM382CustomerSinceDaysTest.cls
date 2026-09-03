/**
 * [SCRUM-382] Functional test for the new formula field
 * Account.Customer_Since_Days__c ("Kunde seit (Tage)").
 *
 * Covers the deterministic core of the requirement (ADR-3):
 *   TODAY() - DATEVALUE(CreatedDate) => an account created TODAY shows 0.
 * DATEVALUE strips the time part, so a today-created account is 0 regardless of
 * the hour it was created (07:00 or 23:00) — this is exactly the PO acceptance criterion.
 *
 * CreatedDate is not settable via DML, so the only assertable value in a test
 * transaction is the today case: any freshly inserted Account must read 0, and
 * the field must be a read-only, system-calculated Formula.
 *
 * Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM382CustomerSinceDaysTest {

    @isTest
    static void todayCreatedAccount_showsZeroDays_andFieldIsReadOnlyFormula() {
        // Fresh account created in this test transaction -> CreatedDate = today.
        Account acc = new Account(Name = '[SCRUM-382-Test]Value');
        insert acc;

        // Formula fields are NOT populated on the in-memory sObject after DML —
        // query the record back so Customer_Since_Days__c is computed.
        Account fresh = [SELECT Customer_Since_Days__c FROM Account WHERE Id = :acc.Id];

        // AC "heute -> 0": deterministic via DATEVALUE (no time fraction).
        System.assertEquals(
            0, fresh.Customer_Since_Days__c,
            'A today-created Account must show 0 full days (TODAY() - DATEVALUE(CreatedDate))'
        );

        // Field must be a system-calculated Formelfeld (ADR-1), never user-updatable.
        Schema.DescribeFieldResult f = Account.Customer_Since_Days__c.getDescribe();
        System.assertEquals(
            true, f.isCalculated(),
            'Customer_Since_Days__c must be a calculated (formula) field'
        );
        System.assertEquals(
            false, f.isUpdateable(),
            'Customer_Since_Days__c must be read-only (formula, no user edit)'
        );

        // Number(10,0): precise, no scale.
        System.assertEquals(
            0, f.getScale(),
            'Customer_Since_Days__c must be Number(10,0) — scale 0'
        );
    }
}
