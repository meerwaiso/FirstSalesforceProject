/**
 * [SCRUM-398] FLS negative + positive proof for Case.Eskalationsstufe__c
 * („Eskalationsstufe“, read-only Picklist formula).
 *
 * The field ships with a read-only FLS Permission Set
 * SCRUM398_Eskalationsstufe. A brand-new custom field is FLS-gated by default:
 * a user WITHOUT the Permission Set cannot read it.
 *
 * 1:1 house shape: SCRUM396BetreuungsstufeFlsTest.cls
 *
 *   1. temp user on the „Standard User" profile (no FLS on the new field)
 *   2. Precondition: Standard User has Case object access
 *   3. NEGATIVE: without PS -> field not readable, not writable
 *   4. Grant the Permission Set.
 *   5. POSITIVE: with PS -> field readable; NOT writable (read-only Formula +
 *      PS editable=false)
 *
 * Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM398EskalationsstufeFlsTest {

    @isTest
    static void eskalationsstufe_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls398Neg',
            Alias = 'fls398',
            Email = 'fls398neg@example.invalid',
            Username = 'fls398neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE rejected in this org (verified, prior tests)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // 2. Precondition: Standard User has Case object access.
        System.runAs(u) {
            System.assert(
                Case.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Case object access'
            );
        }

        // 3. NEGATIVE: no Permission Set -> field is invisible.
        System.runAs(u) {
            System.assertEquals(
                false, Case.Eskalationsstufe__c.getDescribe().isAccessible(),
                'Without PS SCRUM398_Eskalationsstufe Eskalationsstufe__c must NOT be readable'
            );
            System.assertEquals(
                false, Case.Eskalationsstufe__c.getDescribe().isUpdateable(),
                'Without PS SCRUM398_Eskalationsstufe Eskalationsstufe__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM398_Eskalationsstufe' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set -> readable; stays read-only.
        System.runAs(u) {
            System.assertEquals(
                true, Case.Eskalationsstufe__c.getDescribe().isAccessible(),
                'With PS SCRUM398_Eskalationsstufe Eskalationsstufe__c must be readable'
            );
            // Read-only Formula + PS editable=false: even with the PS it is never writable.
            System.assertEquals(
                false, Case.Eskalationsstufe__c.getDescribe().isUpdateable(),
                'With PS SCRUM398_Eskalationsstufe Eskalationsstufe__c must remain read-only'
            );
        }
    }
}
