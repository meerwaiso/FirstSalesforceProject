/**
 * [SCRUM-405] FLS negative + positive proof for Contact.Firmen_Telefonnummer__c
 * (Telefon Firma, read-only Text-Formel = Account.Phone, Lookup-Cross-Reference).
 *
 * PO-AC "Service kann das Feld sehen, niemand ändert es von Hand" wird in der
 * Org über das Permission Set SCRUM405_FirmenTelefonnummer erreicht
 * (readable=true, editable=false). Aber ein brandneues Custom Field ist
 * FLS-gated by default: ein Standard-User OHNE das PS kann es NICHT lesen.
 * Dieser Test beweist beide Seiten gegen echtes Org-Verhalten:
 *   1. temp user auf Standard-User-Profil (keine FLS auf dem neuen Feld)
 *   2. PRECONDITION: Contact object-level access vorhanden (sonst wären die
 *      FLS-Assertions aus dem falschen Grund grün)
 *   3. NEGATIV: ohne PS -> Feld NICHT lesbar, NICHT beschreibbar
 *   4. PS SCRUM405_FirmenTelefonnummer zuweisen
 *   5. POSITIV: mit PS -> Feld LESBAR; NICHT beschreibbar (read-only Formel)
 *
 * System.runAs() erzeugt einen lizenzlosen Test-User und übt echte FLS aus
 * (runAs umgeht FLS NICHT). Alles hier erzeugt wird, rollt per Test-Transaktion
 * zurück. Vorbild 1:1 SCRUM-403 / SCRUM-382 / SCRUM-365 (erprobt).
 */
@isTest
private class SCRUM405FirmenTelefonnummerFlsTest {

    @isTest
    static void firmenTelefonnummer_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls405',
            Alias = 'fls405',
            Email = 'fls405neg@example.invalid',
            Username = 'fls405neg_' + DateTime.now().getTime() + '@example.invalid',
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

        // 3. NEGATIV: ohne Permission Set -> Feld unsichtbar.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.Firmen_Telefonnummer__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM405_FirmenTelefonnummer: Firmen_Telefonnummer__c darf NICHT lesbar sein');
            System.assertEquals(
                false, Contact.Firmen_Telefonnummer__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM405_FirmenTelefonnummer: Firmen_Telefonnummer__c darf NICHT beschreibbar sein');
        }

        // 4. Permission Set zuweisen (wie im Release für die Service-Freigabe).
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM405_FirmenTelefonnummer' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIV: mit Permission Set -> lesbar; NICHT beschreibbar.
        System.runAs(u) {
            System.assertEquals(
                true, Contact.Firmen_Telefonnummer__c.getDescribe().isAccessible(),
                'Mit PS SCRUM405_FirmenTelefonnummer: Firmen_Telefonnummer__c muss lesbar sein');
            System.assertEquals(
                false, Contact.Firmen_Telefonnummer__c.getDescribe().isUpdateable(),
                'Mit PS: Firmen_Telefonnummer__c bleibt read-only (Formel + editable=false)');
        }
    }
}
