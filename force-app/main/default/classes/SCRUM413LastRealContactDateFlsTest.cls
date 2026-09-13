/**
 * [SCRUM-413] FLS negative + positive proof for Contact.Last_Real_Contact_Date__c
 * (Letzter echter Kontakt, Date, systemmaintained).
 *
 * PO-AC "Sales kann das Feld sehen, niemand ändert es von Hand" wird über das
 * Permission Set SCRUM413_LastRealContactDate erreicht (readable=true, editable=false).
 * Aber ein brandneues Custom Field ist FLS-gated by default: ein Standard-User OHNE
 * das PS kann es NICHT lesen.
 *
 * Dieser Test beweist beide Seiten gegen echtes Org-Verhalten:
 *   1. temp user auf Standard-User-Profil (keine FLS auf dem neuen Feld)
 *   2. PRECONDITION: Contact object-level access vorhanden
 *   3. NEGATIV: ohne PS → Feld NICHT lesbar, NICHT beschreibbar
 *   4. PS SCRUM413_LastRealContactDate zuweisen
 *   5. POSITIV: mit PS → LESBAR; NICHT beschreibbar
 *
 * System.runAs() erzeugt einen lizenzlosen Test-User und übt echte FLS aus
 * (runAs umgeht FLS NICHT). Alles hier erzeugte wird per Test-Transaktion zurückgesetzt.
 * Vorbild 1:1 SCRUM-382 / SCRUM-403.
 *
 * @author developer-agent
 * @date 2026-09-13
 */
@isTest
private class SCRUM413LastRealContactDateFlsTest {

    @isTest
    static void lastRealContactDate_invisibleWithoutPS_readOnlyWithPS() {
        Profile standardUser = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = standardUser.Id,
            LastName = 'Fls413',
            Alias = 'fls413',
            Email = 'fls413neg_' + DateTime.now().getTime() + '@example.invalid',
            Username = 'fls413neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // Vorbedingung: Standard-User hat object-level Zugang zu Contact.
        System.runAs(u) {
            System.assert(
                Contact.SObjectType.getDescribe().isAccessible(),
                'Vorbedingung fehlgeschlagen: Standard-User hat keinen Contact-Zugriff — ' +
                    'die FLS-Assertions unten würden aus dem falschen Grund grün.'
            );
        }

        // NEGATIV: ohne Permission Set → Feld nicht lesbar.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.Last_Real_Contact_Date__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM413_LastRealContactDate: Last_Real_Contact_Date__c darf NICHT lesbar sein');
            System.assertEquals(
                false, Contact.Last_Real_Contact_Date__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM413_LastRealContactDate: Last_Real_Contact_Date__c darf NICHT beschreibbar sein');
        }

        // Permission Set zuweisen.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM413_LastRealContactDate' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // POSITIV: mit Permission Set → lesbar; nicht beschreibbar.
        System.runAs(u) {
            System.assertEquals(
                true, Contact.Last_Real_Contact_Date__c.getDescribe().isAccessible(),
                'Mit PS SCRUM413_LastRealContactDate: Last_Real_Contact_Date__c muss lesbar sein');
            System.assertEquals(
                false, Contact.Last_Real_Contact_Date__c.getDescribe().isUpdateable(),
                'Mit PS: Last_Real_Contact_Date__c darf NICHT von Hand änderbar sein (systemmaintained, editable=false)');
        }
    }
}
