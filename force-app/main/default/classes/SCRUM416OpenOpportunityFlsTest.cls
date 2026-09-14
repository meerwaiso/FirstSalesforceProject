/**
 * [SCRUM-416] FLS negative + positive proof for
 * Account.Open_Opportunity_Count__c and Account.Open_Opportunity_Value__c
 * (read-only, systemmaintained).
 *
 * Ein brandneues Custom Field ist per Default FLS-gated: ein User OHNE das
 * Permission Set SCRUM416_OpenOpportunities kann beide Felder weder lesen
 * noch schreiben. Mit dem PS sind sie LESBAR, aber für niemanden editierbar
 * (ADR-5, Kein Edit für niemanden — Systemwrites laufen im System-Kontext).
 *
 * Test-Org trägt zwei Lizenzen (beide System Admin), daher System.runAs()
 * mit einem lizenzfreien Test-User auf dem "Standard User"-Profil —
 * runAs greift nicht durch FLS (Vorgang: SCRUM-382, 1:1-Pattern).
 * Alles created hier rollt mit der Test-Transaction zurück.
 */
@isTest
private class SCRUM416OpenOpportunityFlsTest {

    @isTest
    static void openOpportunityFields_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls416Neg',
            Alias = 'fls416',
            Email = 'fls416neg@example.invalid',
            Username = 'fls416neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC rejected here (verified)
        );
        insert u;

        // 2. Precondition: Standard User has Account object access.
        System.runAs(u) {
            System.assert(
                Account.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Account object access — ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 3. NEGATIVE: no Permission Set → both fields invisible.
        System.runAs(u) {
            System.assertEquals(
                false,
                Account.Open_Opportunity_Count__c.getDescribe().isAccessible(),
                'Without PS SCRUM416_OpenOpportunities Open_Opportunity_Count__c must NOT be readable'
            );
            System.assertEquals(
                false,
                Account.Open_Opportunity_Count__c.getDescribe().isUpdateable(),
                'Without PS Open_Opportunity_Count__c must NOT be writable'
            );
            System.assertEquals(
                false,
                Account.Open_Opportunity_Value__c.getDescribe().isAccessible(),
                'Without PS SCRUM416_OpenOpportunities Open_Opportunity_Value__c must NOT be readable'
            );
            System.assertEquals(
                false,
                Account.Open_Opportunity_Value__c.getDescribe().isUpdateable(),
                'Without PS Open_Opportunity_Value__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM416_OpenOpportunities' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set → readable; stays read-only.
        System.runAs(u) {
            System.assertEquals(
                true,
                Account.Open_Opportunity_Count__c.getDescribe().isAccessible(),
                'With PS SCRUM416_OpenOpportunities Open_Opportunity_Count__c must be readable'
            );
            System.assertEquals(
                true,
                Account.Open_Opportunity_Value__c.getDescribe().isAccessible(),
                'With PS SCRUM416_OpenOpportunities Open_Opportunity_Value__c must be readable'
            );
            // Read-only per ADR-5 (PS editable=false): mit PS NICHT schreibbar.
            System.assertEquals(
                false,
                Account.Open_Opportunity_Count__c.getDescribe().isUpdateable(),
                'With PS Open_Opportunity_Count__c must remain read-only (editable=false)'
            );
            System.assertEquals(
                false,
                Account.Open_Opportunity_Value__c.getDescribe().isUpdateable(),
                'With PS Open_Opportunity_Value__c must remain read-only (editable=false)'
            );
        }
    }
}
