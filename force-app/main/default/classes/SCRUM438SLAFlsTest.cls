/**
 * [SCRUM-438] FLS negativ + positiv fuer die sieben SLA-Felder am Case
 * (SLA_Zielzeit__c, SLA_Status__c, SLA_Eskalation__c, SLA_Ueberschritten__c,
 *  SLA_Last_Checked__c, SLA_Uhr_gestoppt__c, SLA_Akkumulierte_WorkingMins__c) —
 * read-only, systemgepfegt per Trigger/Batch (PO-AC10).
 *
 * 1:1 Shape von SCRUM436CaseReminderFlsTest / SCRUM390OverdueCaseFlsTest:
 *   1. Temp-User auf Standard-User-Profil (keine FLS auf den neuen Feldern).
 *   2. PRECONDITION: Case object-level Zugang vorhanden.
 *   3. NEGATIV (AC13): ohne PS -> alle 7 Felder NICHT lesbar/beschreibbar.
 *   4. SCRUM438_SLA_Read zuweisen.
 *   5. POSITIV (AC10): mit Read-PS -> alle 7 LESBAR; keins beschreibbar
 *      (Service-Mitarbeiter koein-editieren).
 *
 * System.runAs() uebt echte FLS aus (runAs umgeht FLS NICHT). Alles rollt per
 * Test-Transaktion zurueck.
 */
@isTest
private class SCRUM438SLAFlsTest {

    @isTest
    static void slaFields_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls438',
            Alias       = 'fls438',
            Email       = 'fls438@example.invalid',
            Username    = 'fls438_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',      // de_DE wird in dieser Org abgelehnt (erprobt)
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles' // UTC wird hier abgelehnt (erprobt)
        );
        insert u;

        // 2. Vorbedingung: Standard-User hat object-level Zugang zu Case.
        Boolean caseReadable;
        System.runAs(u) {
            caseReadable = Case.SObjectType.getDescribe().isAccessible();
        }
        System.assert(caseReadable,
            'Vorbedingung fehlgeschlagen: Standard-User hat keinen Case-Zugriff — ' +
            'die FLS-Assertions unten wuerden aus dem falschen Grund gruen.');

        List<Schema.SObjectField> all =
            new List<Schema.SObjectField>{
                Case.SLA_Zielzeit__c,
                Case.SLA_Status__c,
                Case.SLA_Eskalation__c,
                Case.SLA_Ueberschritten__c,
                Case.SLA_Last_Checked__c,
                Case.SLA_Uhr_gestoppt__c,
                Case.SLA_Akkumulierte_WorkingMins__c
            };

        // 3. NEGATIV (AC13): ohne Permission Set -> 7 Felder unsichtbar.
        System.runAs(u) {
            for (Schema.SObjectField f : all) {
                assertNotVisible('Ohne PS SCRUM438_SLA_Read', f);
            }
        }

        // 4. Read-Permission Set zuweisen.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM438_SLA_Read' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIV (AC10): mit Read-PS -> 7 lesbar; keins beschreibbar.
        System.runAs(u) {
            for (Schema.SObjectField f : all) {
                assertReadOnly('Mit PS SCRUM438_SLA_Read', f);
            }
        }
    }

    private static void assertNotVisible(String ctx, Schema.SObjectField f) {
        Schema.DescribeFieldResult d = f.getDescribe();
        System.assertEquals(false, d.isAccessible(),
            ctx + ': ' + d.getName() + ' darf NICHT lesbar sein');
        System.assertEquals(false, d.isUpdateable(),
            ctx + ': ' + d.getName() + ' darf NICHT beschreibbar sein');
    }

    private static void assertReadOnly(String ctx, Schema.SObjectField f) {
        Schema.DescribeFieldResult d = f.getDescribe();
        System.assertEquals(true, d.isAccessible(),
            ctx + ': ' + d.getName() + ' muss lesbar sein');
        System.assertEquals(false, d.isUpdateable(),
            ctx + ': ' + d.getName() + ' darf NICHT von Hand aenderbar sein (read-only)');
    }
}
