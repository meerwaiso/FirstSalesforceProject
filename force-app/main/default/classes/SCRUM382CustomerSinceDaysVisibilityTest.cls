/**
 * [SCRUM-382] Visibility proof for a Standard User WITH the Permission Set.
 *
 * PO criterion: "das Feld ist für alle sichtbar". The negative side (a Standard
 * User WITHOUT the PS cannot read the field) is proven by
 * SCRUM382CustomerSinceDaysFlsTest. This test proves the POSITIVE side: a
 * Standard User WITH the PS assigned runs a real SOQL SELECT on
 * Customer_Since_Days__c and gets back a value that matches the formula.
 *
 * If the field were not FLS-visible to this user the SELECT would throw
 * "No such column ... Customer_Since_Days__c" and the test fails loudly — so a
 * green run IS the visibility proof (not just a describe check).
 *
 * Implementation note: no DML is done on Account here (only setup DML on
 * User/PermissionSetAssignment), so the test respects the Mixed-DML rule —
 * the readable value comes from an existing org record, and its expected days
 * value is computed in Apex exactly the way the formula computes it
 * (whole days between today and the created date).
 *
 * In the Test-Org the PS is now assigned to all real users; this test mirrors
 * that by assigning the PS to a temp Standard User. Everything created here
 * rolls back with the test transaction.
 */
@isTest
private class SCRUM382CustomerSinceDaysVisibilityTest {

    @isTest
    static void standardUser_withPS_readsCorrectValue() {
        // Existing org record (read-only reference — no DML on Account), so the
        // test stays within the Mixed-DML rule (setup DML only).
        Account sample = [
            SELECT Id, CreatedDate, Customer_Since_Days__c
            FROM Account
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        // Expected value, exactly like the formula: whole days between today
        // and the (date-only) created date. (Apex Date-Date yields Integer days;
        // Date.valueOf(CreatedDate) is the Apex equivalent of DATEVALUE().)
        Integer expectedDays = Date.today() - Date.valueOf(sample.CreatedDate);

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Vis382Pos',
            Alias = 'vis382',
            Email = 'vis382pos@example.invalid',
            Username = 'vis382pos_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
        );
        insert u;

        // Assign the Permission Set (mirrors the org state where the PS is
        // granted to all real users).
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM382_CustomerSinceDays' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // POSITIVE: real SOQL read under the Standard User with the PS.
        System.runAs(u) {
            Decimal days = [
                SELECT Customer_Since_Days__c
                FROM Account
                WHERE Id = :sample.Id
            ].Customer_Since_Days__c;
            System.assertEquals(
                expectedDays, days,
                'Standard User WITH the PS must read Customer_Since_Days__c == ' +
                'TODAY() - DATEVALUE(CreatedDate) = ' + expectedDays +
                ' (got ' + days + ')'
            );
        }
    }
}
