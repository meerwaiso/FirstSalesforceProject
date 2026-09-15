/**
 * [SCRUM-417] FLS negative + positive proof für OpenOpportunityHistory__c
 * (Snapshot_Month__c, Open_Count__c, Open_Value__c) und
 * Account.Open_Value_Drop_Last_Month__c (read-only, systemmaintained) plus
 * Objekt-View auf OpenOpportunityHistory__c (kein UI-Write).
 *
 * Ein brandneues Custom Object ist per Default FLS-gated: ein User OHNE das
 * Permission Set SCRUM417_OpenOpportunityHistory kann das Objekt weder sehen
 * noch seine Felder lesen. Mit dem PS ist alles LESBAR, aber für niemanden
 * editierbar (ViewOnly, kein Create/Edit/Delete — Systemwrites laufen im
 * System-Kontext).
 *
 * Haus-Pattern 1:1 von SCRUM416OpenOpportunityFlsTest: System.runAs() mit einem
 * lizenzfreien Test-User auf dem "Standard User"-Profil (runAs greift nicht
 * durch FLS). Alles created hier rollt mit der Test-Transaction zurück.
 */
@isTest
private class SCRUM417OpenOpportunityHistoryFlsTest {

    @isTest
    static void historyInvisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls417Neg',
            Alias = 'fls417',
            Email = 'fls417neg@example.invalid',
            Username = 'fls417neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // NEGATIVE: ohne PS → Objekt unsichtbar, Felder nicht lesbar.
        System.runAs(u) {
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.SObjectType.getDescribe().isAccessible(),
                'Ohne PS SCRUM417_OpenOpportunityHistory: Objekt nicht sichtbar');
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.Snapshot_Month__c.getDescribe().isAccessible(),
                'Ohne PS: Snapshot_Month__c nicht lesbar');
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.Open_Count__c.getDescribe().isAccessible(),
                'Ohne PS: Open_Count__c nicht lesbar');
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.Open_Value__c.getDescribe().isAccessible(),
                'Ohne PS: Open_Value__c nicht lesbar');
            System.assertEquals(
                false,
                Account.Open_Value_Drop_Last_Month__c.getDescribe().isAccessible(),
                'Ohne PS: Account.Open_Value_Drop_Last_Month__c nicht lesbar');
        }

        // Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM417_OpenOpportunityHistory' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // POSITIVE: mit PS → Objekt lesbar, Felder lesbar, alles read-only.
        System.runAs(u) {
            System.assertEquals(
                true,
                OpenOpportunityHistory__c.SObjectType.getDescribe().isAccessible(),
                'Mit PS: Objekt lesbar (ViewOnly)');
            System.assertEquals(
                true,
                OpenOpportunityHistory__c.Snapshot_Month__c.getDescribe().isAccessible(),
                'Mit PS: Snapshot_Month__c lesbar');
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.Snapshot_Month__c.getDescribe().isUpdateable(),
                'Mit PS: Snapshot_Month__c read-only');
            System.assertEquals(
                true,
                OpenOpportunityHistory__c.Open_Count__c.getDescribe().isAccessible(),
                'Mit PS: Open_Count__c lesbar');
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.Open_Count__c.getDescribe().isUpdateable(),
                'Mit PS: Open_Count__c read-only');
            System.assertEquals(
                true,
                OpenOpportunityHistory__c.Open_Value__c.getDescribe().isAccessible(),
                'Mit PS: Open_Value__c lesbar');
            System.assertEquals(
                false,
                OpenOpportunityHistory__c.Open_Value__c.getDescribe().isUpdateable(),
                'Mit PS: Open_Value__c read-only');
            System.assertEquals(
                true,
                Account.Open_Value_Drop_Last_Month__c.getDescribe().isAccessible(),
                'Mit PS: Account.Open_Value_Drop_Last_Month__c lesbar');
            System.assertEquals(
                false,
                Account.Open_Value_Drop_Last_Month__c.getDescribe().isUpdateable(),
                'Mit PS: Drop-Feld read-only');
        }
    }
}
