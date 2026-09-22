/**
 * SCRUM-424 First-Response FLS Test (negative test)
 * 
 * Verifies that a user without the SCRUM424_FirstResponse_Read permission set
 * cannot read the three First-Response tracking fields on Case.
 * 
 * Strategy: 
 * 1. Insert a Case, then update the fields via a known-working admin user flow
 * 2. Switch to a user WITHOUT the PS via Test.setUser()
 * 3. Try to query the fields — expect FieldException because FLS denies read
 * 4. Grant the PS to that user, then retry — should succeed
 * 
 * This proves both negative (no PS = no read) and positive (PS = read).
 */
@isTest
private class SCRUM424FirstResponseFlsTest {

    private static Final String PERMSET_NAME = 'SCRUM424_FirstResponse_Read';
    private static Final Set<String> FIELDS_TO_TEST = new Set<String>{
        'First_Response_Time__c',
        'First_Response_Working_Mins__c',
        'First_Response_Target_Missed__c'
    };

    /**
     * Create and assign the PS if needed; return its Id.
     */
    @TestSetup
    private static void setupPermissionSet() {
        // Verify or create the permission set that grants read access
        List<PermissionSet> existing = [
            SELECT Id FROM PermissionSet WHERE Name = :PERMSET_NAME
        ];

        if (existing.isEmpty()) {
            PermissionSet ps = new PermissionSet(
                Name = PERMSET_NAME,
                Label = 'SCRUM-424 First Response Read',
                Description = 'Grants read access to First-Response metrics fields on Case.'
            );
            insert ps;

            // Add case field read perms
            List<FieldPermissions> fps = new List<FieldPermissions>();
            for (String field : FIELDS_TO_TEST) {
                fps.add(new FieldPermissions(
                    ParentId = ps.Id,
                    Field = field,
                    ParentObject = 'Case',
                    Readable = true,
                    Editable = false
                ));
            }
            insert fps;
        }
    }

    @isTest
    static void negative_user_cannot_read_fields() {
        // Insert a Case with all three fields populated
        Case c = new Case(
            Contact_email__c = 'test@example.com',
            Subject = 'FLS negative test'
        );
        insert c;

        Case upd = [SELECT Id FROM Case WHERE Id = :c.Id];
        upd.First_Response_Time__c = System.now();
        upd.First_Response_Working_Mins__c = 12.5;
        upd.First_Response_Target_Missed__c = true;
        update upd;

        // Query via admin user — should succeed
        Case adminRead = [
            SELECT First_Response_Time__c,
                   First_Response_Working_Mins__c,
                   First_Response_Target_Missed__c
            FROM Case
            WHERE Id = :c.Id
        ];
        System.assertNotEquals(null, adminRead.First_Response_Time__c);

        // Now switch to a user that does NOT have the permission set
        // Find or create a user for testing
        Id userWithoutPS = findOrCreateTestUser(false);
        Test.setUser(userWithoutPS);

        // Try querying the FLS-protected fields — should throw FieldException
        // because the user lacks the 'SCRUM424_FirstResponse_Read' permission set
        List<Case> results;
        try {
            results = [
                SELECT First_Response_Time__c,
                       First_Response_Working_Mins__c,
                       First_Response_Target_Missed__c
                FROM Case
                WHERE Id = :c.Id
            ];
            // If we get here, the field is accessible — unexpected!
            System.fail('Expected FieldException was not thrown. User without ' +
                        'permission set can read First-Response fields.');
        } catch (FieldException fex) {
            // Expected — FLS prevents reading these fields
            System.debug('FLS correctly blocked read: ' + fex.getMessage());
        }
    }

    @isTest
    static void positive_user_with_ps_can_read_fields() {
        // Insert a Case with all three fields populated
        Case c = new Case(
            Contact_email__c = 'test@example.com',
            Subject = 'FLS positive test'
        );
        insert c;

        Case upd = [SELECT Id FROM Case WHERE Id = :c.Id];
        upd.First_Response_Time__c = System.now();
        upd.First_Response_Working_Mins__c = 8.3;
        upd.First_Response_Target_Missed__c = false;
        update upd;

        // Switch to a user that HAS the permission set
        Id userWithPS = findOrCreateTestUser(true);
        Test.setUser(userWithPS);

        // Now the same query should succeed
        List<Case> results = [
            SELECT First_Response_Time__c,
                   First_Response_Working_Mins__c,
                   First_Response_Target_Missed__c
            FROM Case
            WHERE Id = :c.Id
        ];
        System.assertEquals(1, results.size());

        Case read = results[0];
        System.assertNotEquals(null, read.First_Response_Time__c);
        System.assertNotEquals(null, read.First_Response_Working_Mins__c);
        System.assertNotEquals(null, read.First_Response_Target_Missed__c);
        System.debug('FLS correctly allowed read for user with PS');
    }

    /**
     * Find or create a test user, optionally assigning the permission set.
     * Returns the user's Id.
     */
    private static Id findOrCreateTestUser(Boolean hasPermissionSet) {
        String username = 'scr424test' + (hasPermissionSet ? 'withps' : 'nops') + 
                          '.' + DateTime.now().getTime() + '@example.com';

        // Check if user already exists
        List<User> existing = [SELECT Id FROM User WHERE Username = :username];
        if (!existing.isEmpty()) {
            if (hasPermissionSet) {
                assignPS(existing[0].Id);
            }
            return existing[0].Id;
        }

        // Create the user
        Profile prof = [
            SELECT Id FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User u = new User(
            Username = username,
            Email = username,
            LastName = 'Scr424Test',
            FirstName = 'User',
            ProfileId = prof.Id,
            Alias = 'scr424',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        if (hasPermissionSet) {
            assignPS(u.Id);
        }

        return u.Id;
    }

    private static void assignPS(Id userId) {
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = :PERMSET_NAME
        ];

        PermissionSetAssignment psa = new PermissionSetAssignment(
            PermissionSetId = ps.Id,
            AssigneeId = userId
        );
        insert psa;
    }
}