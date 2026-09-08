/**
 * [SCRUM-403] FLS negative + positive proof for Contact.Last_Case_Date__c
 * (Letztes Anliegen, Date, systemmaintained) + Contact.Time_Since_Last_Case__c
 * (Wie lange her, read-only Text-Formel).
 *
 * PO-AC "Service kann das Feld sehen, niemand ändert es von Hand" wird in der
 * Org über das Permission Set SCRUM403_LastCaseDate erreicht (readable=true,
 * editable=false auf beiden Feldern). Aber ein brandneues Custom Field ist
 * FLS-gated by default: ein Standard-User OHNE das PS kann es NICHT lesen.
 * Dieser Test beweist beide Seiten gegen echtes Org-Verhalten:
 *   1. temp user auf Standard-User-Profil (keine FLS auf den neuen Feldern)
 *   2. PRECONDITION: Contact object-level access vorhanden (sonst wären die
 *      FLS-Assertions aus dem falschen Grund grün)
 *   3. NEGATIV: ohne PS → beide Felder NICHT lesbar, NICHT beschreibbar
 *   4. PS SCRUM403_LastCaseDate zuweisen
 *   5. POSITIV: mit PS → beide Felder LESBAR; beides NICHT beschreibbar
 *      (Date = systemmaintained editable=false; Text = Formel read-only)
 *
 * System.runAs() erzeugt einen lizenzlosen Test-User und übt echte FLS aus
 * (runAs umgeht FLS NICHT). Alles hier erzeugt wird, rollt per Test-Transaktion
 * zurück. Vorbild 1:1 SCRUM-382 / SCRUM-365 (erprobt).
 */
@isTest
private class SCRUM403LastCaseDateFlsTest {

    @isTest
    static void lastCaseDate_andDuration_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls403',
            Alias = 'fls403',
            Email = 'fls403neg@example.invalid',
            Username = 'fls403neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', // de_DE wird in dieser Org abgelehnt (erprobt)
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles' // UTC wird hier abgelehnt (erprobt)
        );
        insert u;

        // 2. Vorbedingung: Standard-User hat object-level Zugang zu Contact,
        //    sonst wären die FLS-Assertions unten aus dem falschen Grund grün.
        System.runAs(u) {
            System.assert(
                Contact.SObjectType.getDescribe().isAccessible(),
                'Vorbedingung fehlgeschlagen: Standard-User hat keinen Contact-Zugriff — ' +
                    'die FLS-Assertions unten würden aus dem falschen Grund grün.'
            );
        }

        // 3. NEGATIV: ohne Permission Set → beide Felder unsichtbar.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.Last_Case_Date__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM403_LastCaseDate: Last_Case_Date__c darf NICHT lesbar sein');
            System.assertEquals(
                false, Contact.Last_Case_Date__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM403_LastCaseDate: Last_Case_Date__c darf NICHT beschreibbar sein');
            System.assertEquals(
                false, Contact.Time_Since_Last_Case__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM403_LastCaseDate: Time_Since_Last_Case__c darf NICHT lesbar sein');
            System.assertEquals(
                false, Contact.Time_Since_Last_Case__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM403_LastCaseDate: Time_Since_Last_Case__c darf NICHT beschreibbar sein');
        }

        // 4. Permission Set zuweisen (wie im Release für die Service-Freigabe).
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM403_LastCaseDate' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIV: mit Permission Set → beide lesbar; beide NICHT beschreibbar.
        System.runAs(u) {
            System.assertEquals(
                true, Contact.Last_Case_Date__c.getDescribe().isAccessible(),
                'Mit PS SCRUM403_LastCaseDate: Last_Case_Date__c muss lesbar sein');
            System.assertEquals(
                false, Contact.Last_Case_Date__c.getDescribe().isUpdateable(),
                'Mit PS: Last_Case_Date__c darf NICHT von Hand änderbar sein (systemmaintained, editable=false)');
            System.assertEquals(
                true, Contact.Time_Since_Last_Case__c.getDescribe().isAccessible(),
                'Mit PS SCRUM403_LastCaseDate: Time_Since_Last_Case__c muss lesbar sein');
            System.assertEquals(
                false, Contact.Time_Since_Last_Case__c.getDescribe().isUpdateable(),
                'Mit PS: Time_Since_Last_Case__c bleibt read-only (read-only Formel + editable=false)');
        }
    }
}
