/**
 * [SCRUM-418] FLS negativ + positiv für Case.Reactivation_Count__c
 * + Case.Last_Reactivation__c (Reaktivierungszähler, systemmaintained).
 *
 * FLS-Modell (ADR-3, SCRUM-418): Beide Felder sind `updateable=false` (read-only)
 * und werden nur vom Trigger geschrieben (Systemwrites laufen im System-Modus
 * und umgehen FLS). „Wer Case-Lesezugriff hat, sieht die Felder; niemand kann
 * sie von Hand ändern."  Erreicht wird das Sichtbarkeit über das Permission
 * Set SCRUM418_Reactivation (readable=true, editable=false auf beiden Feldern).
 *
 * Ein brandneues Custom Field ist FLS-gated by default: ein User OHNE das PS
 * kann es NICHT lesen.  Dieser Test beweist beide Seiten gegen echtes Org-
 * Verhalten (1:1 Shape von SCRUM403LastCaseDateFlsTest):
 *   1. Temp-User auf Standard-User-Profil (keine FLS auf den neuen Feldern).
 *   2. PRECONDITION: Case object-level Zugang vorhanden — sonst wären die
 *      FLS-Assertions unten aus dem falschen Grund grün.
 *   3. NEGATIV: ohne PS → beide Felder NICHT lesbar, NICHT beschreibbar.
 *   4. Permission Set SCRUM418_Reactivation zuweisen.
 *   5. POSITIV: mit PS → beide Felder LESBAR; beide NICHT beschreibbar
 *      (updateable=false / editable=false → read-only).
 *
 * System.runAs() übt echte FLS aus (runAs umgeht FLS NICHT).
 * Alles, was hier erzeugt wird, rollt per Test-Transaktion zurück.
 */
@isTest
private class SCRUM418CaseReactionFlsTest {

    @isTest
    static void reactivationFields_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls418',
            Alias       = 'fls418',
            Email       = 'fls418neg@example.invalid',
            Username    = 'fls418neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',    // de_DE wird in dieser Org abgelehnt (erprobt)
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles' // UTC wird hier abgelehnt (erprobt)
        );
        insert u;

        // 2. Vorbedingung: Standard-User hat object-level Zugang zu Case,
        //    sonst wären die FLS-Assertions aus dem falschen Grund grün.
        Boolean caseReadable;
        System.runAs(u) {
            caseReadable = Case.SObjectType.getDescribe().isAccessible();
        }
        System.assert(
            caseReadable,
            'Vorbedingung fehlgeschlagen: Standard-User hat keinen Case-Zugriff — ' +
            'die FLS-Assertions unten würden aus dem falschen Grund grün.'
        );

        // 3. NEGATIV: ohne Permission Set → beide Felder unsichtbar.
        System.runAs(u) {
            System.assertEquals(
                false, Case.Reactivation_Count__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM418_Reactivation: Reactivation_Count__c darf NICHT lesbar sein');
            System.assertEquals(
                false, Case.Reactivation_Count__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM418_Reactivation: Reactivation_Count__c darf NICHT beschreibbar sein');
            System.assertEquals(
                false, Case.Last_Reactivation__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM418_Reactivation: Last_Reactivation__c darf NICHT lesbar sein');
            System.assertEquals(
                false, Case.Last_Reactivation__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM418_Reactivation: Last_Reactivation__c darf NICHT beschreibbar sein');
        }

        // 4. Permission Set zuweisen.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM418_Reactivation' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIV: mit PS → beide Felder lesbar; beide NICHT beschreibbar.
        System.runAs(u) {
            System.assertEquals(
                true, Case.Reactivation_Count__c.getDescribe().isAccessible(),
                'Mit PS SCRUM418_Reactivation: Reactivation_Count__c muss lesbar sein');
            System.assertEquals(
                false, Case.Reactivation_Count__c.getDescribe().isUpdateable(),
                'Mit PS: Reactivation_Count__c darf NICHT von Hand änderbar sein (read-only)');
            System.assertEquals(
                true, Case.Last_Reactivation__c.getDescribe().isAccessible(),
                'Mit PS SCRUM418_Reactivation: Last_Reactivation__c muss lesbar sein');
            System.assertEquals(
                false, Case.Last_Reactivation__c.getDescribe().isUpdateable(),
                'Mit PS: Last_Reactivation__c bleibt read-only (read-only Feld + editable=false)');
        }
    }
}
