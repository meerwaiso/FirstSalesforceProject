/**
 * [SCRUM-436] FLS negativ + positiv fuer die vier Wiedervorlage-Felder am
 * Case (Last_Relevant_Update__c, Reminder_Due_Date__c, Reminder_Required__c,
 * Reminder_Count__c) — read-only, systemgepflegt.
 *
 * FLS-Modell (ADR-5): Alle vier Felder haben im Read-PS
 * SCRUM436_CaseReminder `editable=false, readable=true`. Ein brandneues
 * Custom Field ist FLS-gated by default: ein User OHNE das PS kann es NICHT
 * lesen.  Dieser Test beweist beide Seiten gegen echtes Org-Verhalten
 * (1:1 Shape von SCRUM418CaseReactionFlsTest):
 *   1. Temp-User auf Standard-User-Profil (keine FLS auf den neuen Feldern).
 *   2. PRECONDITION: Case object-level Zugang vorhanden.
 *   3. NEGATIV: ohne PS -> alle 4 Felder NICHT lesbar, NICHT beschreibbar.
 *   4. Permission Set SCRUM436_CaseReminder zuweisen.
 *   5. POSITIV: mit PS -> alle 4 LESBAR; alle 4 NICHT beschreibbar (read-only).
 *
 * System.runAs() uebt echte FLS aus (runAs umgeht FLS NICHT).
 * Alles, was hier erzeugt wird, rollt per Test-Transaktion zurueck.
 */
@isTest
private class SCRUM436CaseReminderFlsTest {

    @isTest
    static void reminderFields_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls436',
            Alias       = 'fls436',
            Email       = 'fls436neg@example.invalid',
            Username    = 'fls436neg_' + DateTime.now().getTime() + '@example.invalid',
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
        System.assert(
            caseReadable,
            'Vorbedingung fehlgeschlagen: Standard-User hat keinen Case-Zugriff — ' +
            'die FLS-Assertions unten wuerden aus dem falschen Grund gruen.'
        );

        // 3. NEGATIV: ohne Permission Set -> 4 Felder unsichtbar.
        System.runAs(u) {
            assertNotVisible('Ohne PS SCRUM436_CaseReminder',
                    Case.Last_Relevant_Update__c);
            assertNotVisible('Ohne PS SCRUM436_CaseReminder',
                    Case.Reminder_Due_Date__c);
            assertNotVisible('Ohne PS SCRUM436_CaseReminder',
                    Case.Reminder_Required__c);
            assertNotVisible('Ohne PS SCRUM436_CaseReminder',
                    Case.Reminder_Count__c);
        }

        // 4. Permission Set zuweisen.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM436_CaseReminder' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIV: mit PS -> 4 Felder lesbar; 4 NICHT beschreibbar.
        System.runAs(u) {
            assertReadOnly('Mit PS SCRUM436_CaseReminder',
                    Case.Last_Relevant_Update__c);
            assertReadOnly('Mit PS SCRUM436_CaseReminder',
                    Case.Reminder_Due_Date__c);
            assertReadOnly('Mit PS SCRUM436_CaseReminder',
                    Case.Reminder_Required__c);
            assertReadOnly('Mit PS SCRUM436_CaseReminder',
                    Case.Reminder_Count__c);
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
