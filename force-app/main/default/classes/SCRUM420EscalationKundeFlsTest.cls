/**
 * [SCRUM-420] FLS negativ + positiv für die vier ESC-felder des Kunden
 * (Case.Eskalation_Kunde__c, Case.Offene_Cases_Kunde__c, Case.Offene_High_Cases_Kunde__c,
 * Case.Eskalationszeitpunkt__c).
 *
 * FLS-Modell (ADR, SCRUM-420): Alle vier Felder sind `updateable=false` (read-only)
 * und werden nur vom System geschrieben. Sichtbarkeit über das Permission Set
 * SCRUM420_EskalationKunde (readable=true, editable=false).
 *
 * Negativ-Test: ein User OHNE das PS kann die Felder NICHT lesen.
 * Positiv-Test: mit PS lesbar, aber NICHT beschreibbar.
 *
 * Vorlage: 1:1 Shape von SCRUM418CaseReactionFlsTest.
 */
@isTest
private class SCRUM420EscalationKundeFlsTest {

    @isTest
    static void escalationFields_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls420',
            Alias       = 'fls420',
            Email       = 'fls420neg@example.invalid',
            Username    = 'fls420neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;

        // Vorbedingung: Standard-User hat object-level Zugang zu Case
        Boolean caseReadable;
        System.runAs(u) {
            caseReadable = Case.SObjectType.getDescribe().isAccessible();
        }
        System.assert(
            caseReadable,
            'Vorbedingung fehlgeschlagen: Standard-User hat keinen Case-Zugriff.'
        );

        // NEGATIV: ohne PS → alle vier Felder unsichtbar
        System.runAs(u) {
            System.assertEquals(false, Case.Eskalation_Kunde__c.getDescribe().isAccessible(),
                'Ohne PS: Eskalation_Kunde__c darf NICHT lesbar sein');
            System.assertEquals(false, Case.Eskalation_Kunde__c.getDescribe().isUpdateable(),
                'Ohne PS: Eskalation_Kunde__c darf NICHT beschreibbar sein');

            System.assertEquals(false, Case.Offene_Cases_Kunde__c.getDescribe().isAccessible(),
                'Ohne PS: Offene_Cases_Kunde__c darf NICHT lesbar sein');
            System.assertEquals(false, Case.Offene_Cases_Kunde__c.getDescribe().isUpdateable(),
                'Ohne PS: Offene_Cases_Kunde__c darf NICHT beschreibbar sein');

            System.assertEquals(false, Case.Offene_High_Cases_Kunde__c.getDescribe().isAccessible(),
                'Ohne PS: Offene_High_Cases_Kunde__c darf NICHT lesbar sein');
            System.assertEquals(false, Case.Offene_High_Cases_Kunde__c.getDescribe().isUpdateable(),
                'Ohne PS: Offene_High_Cases_Kunde__c darf NICHT beschreibbar sein');

            System.assertEquals(false, Case.Eskalationszeitpunkt__c.getDescribe().isAccessible(),
                'Ohne PS: Eskalationszeitpunkt__c darf NICHT lesbar sein');
            System.assertEquals(false, Case.Eskalationszeitpunkt__c.getDescribe().isUpdateable(),
                'Ohne PS: Eskalationszeitpunkt__c darf NICHT beschreibbar sein');
        }

        // PS zuweisen
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM420_EskalationKunde' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // POSITIV: mit PS → alle vier Felder lesbar; alle vier NICHT beschreibbar
        System.runAs(u) {
            System.assertEquals(true, Case.Eskalation_Kunde__c.getDescribe().isAccessible(),
                'Mit PS: Eskalation_Kunde__c muss lesbar sein');
            System.assertEquals(false, Case.Eskalation_Kunde__c.getDescribe().isUpdateable(),
                'Mit PS: Eskalation_Kunde__c bleibt read-only');

            System.assertEquals(true, Case.Offene_Cases_Kunde__c.getDescribe().isAccessible(),
                'Mit PS: Offene_Cases_Kunde__c muss lesbar sein');
            System.assertEquals(false, Case.Offene_Cases_Kunde__c.getDescribe().isUpdateable(),
                'Mit PS: Offene_Cases_Kunde__c bleibt read-only');

            System.assertEquals(true, Case.Offene_High_Cases_Kunde__c.getDescribe().isAccessible(),
                'Mit PS: Offene_High_Cases_Kunde__c muss lesbar sein');
            System.assertEquals(false, Case.Offene_High_Cases_Kunde__c.getDescribe().isUpdateable(),
                'Mit PS: Offene_High_Cases_Kunde__c bleibt read-only');

            System.assertEquals(true, Case.Eskalationszeitpunkt__c.getDescribe().isAccessible(),
                'Mit PS: Eskalationszeitpunkt__c muss lesbar sein');
            System.assertEquals(false, Case.Eskalationszeitpunkt__c.getDescribe().isUpdateable(),
                'Mit PS: Eskalationszeitpunkt__c bleibt read-only');
        }
    }
}
