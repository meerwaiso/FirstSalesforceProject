/**
 * [SCRUM-437] FLS negativ + positiv fuer die funf Problemserie-Felder am Case
 * (Wiederkehrendes_Problem__c, Anzahl_aehnlicher_offener_Cases__c,
 *  Letzter_aehnlicher_Case__c, Problemserie__c  = 4 systemgepflegt read-only,
 *  Problemkategorie__c = einziges manuelles Feld, im Read-PS editierbar).
 *
 * FLS-Modell (ADR-4): Die vier Berechnungsfelder haben im Read-PS
 * SCRUM437_ProblemSerie_Read `editable=false, readable=true`;
 * Problemkategorie__c hat `editable=true, readable=true`. Ein brandneues
 * Custom Field ist FLS-gated by default: ein User OHNE das PS kann NICHTS
 * davon sehen. Dieser Test beweist beide Seiten gegen echtes Org-Verhalten
 * (1:1 Shape von SCRUM436CaseReminderFlsTest):
 *   1. Temp-User auf Standard-User-Profil (keine FLS auf den neuen Feldern).
 *   2. PRECONDITION: Case object-level Zugang vorhanden.
 *   3. NEGATIV: ohne PS -> alle 5 Felder NICHT lesbar, NICHT beschreibbar.
 *   4. Permission Set SCRUM437_ProblemSerie_Read zuweisen.
 *   5. POSITIV: mit PS -> alle 4 Berechnungsfelder LESBAR, NICHT beschreibbar
 *      (read-only); Problemkategorie__c LESBAR und BESCHREIBBAR.
 *
 * System.runAs() uebt echte FLS aus (runAs umgeht FLS NICHT).
 * Alles, was hier erzeugt wird, rollt per Test-Transaktion zurueck.
 */
@isTest
private class SCRUM437ProblemSerieFlsTest {

    @isTest
    static void problemSerieFields_invisibleWithoutPS_readOnlyWithPS() {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId          = p.Id,
            LastName           = 'Fls437',
            Alias              = 'fls437',
            Email              = 'fls437neg@example.invalid',
            Username           = 'fls437neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey   = 'UTF-8',
            LanguageLocaleKey  = 'en_US',      // de_DE wird in dieser Org abgelehnt (erprobt)
            LocaleSidKey       = 'en_US',
            TimeZoneSidKey     = 'America/Los_Angeles' // UTC wird hier abgelehnt (erprobt)
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

        // 3. NEGATIV: ohne Permission Set -> 5 Felder unsichtbar.
        System.runAs(u) {
            assertNotVisible('Ohne PS SCRUM437_ProblemSerie_Read', Case.Wiederkehrendes_Problem__c);
            assertNotVisible('Ohne PS SCRUM437_ProblemSerie_Read', Case.Anzahl_aehnlicher_offener_Cases__c);
            assertNotVisible('Ohne PS SCRUM437_ProblemSerie_Read', Case.Letzter_aehnlicher_Case__c);
            assertNotVisible('Ohne PS SCRUM437_ProblemSerie_Read', Case.Problemserie__c);
            assertNotVisible('Ohne PS SCRUM437_ProblemSerie_Read', Case.Problemkategorie__c);
        }

        // 4. Permission Set zuweisen.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM437_ProblemSerie_Read' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIV: mit PS -> 4 Berechnungsfelder read-only, Kategorie editierbar.
        System.runAs(u) {
            assertReadOnly('Mit PS SCRUM437_ProblemSerie_Read', Case.Wiederkehrendes_Problem__c);
            assertReadOnly('Mit PS SCRUM437_ProblemSerie_Read', Case.Anzahl_aehnlicher_offener_Cases__c);
            assertReadOnly('Mit PS SCRUM437_ProblemSerie_Read', Case.Letzter_aehnlicher_Case__c);
            assertReadOnly('Mit PS SCRUM437_ProblemSerie_Read', Case.Problemserie__c);
            assertEditable('Mit PS SCRUM437_ProblemSerie_Read', Case.Problemkategorie__c);
        }
    }

    private static void assertNotVisible(String ctx, Schema.SObjectField f) {
        Schema.DescribeFieldResult d = f.getDescribe();
        System.assertEquals(false, d.isAccessible(),
            ctx + ': ' + d.getName() + ' darf NICHT lesbar sein');
        System.assertEquals(false, d.isUpdateable(),
            ctx + ': ' + d.getName() + ' darf NICHT beschreibbar sein');
    }

    /** Systemfeld: lesbar, aber NICHT von Hand aenderbar. */
    private static void assertReadOnly(String ctx, Schema.SObjectField f) {
        Schema.DescribeFieldResult d = f.getDescribe();
        System.assertEquals(true, d.isAccessible(),
            ctx + ': ' + d.getName() + ' muss lesbar sein');
        System.assertEquals(false, d.isUpdateable(),
            ctx + ': ' + d.getName() + ' darf NICHT von Hand aenderbar sein (read-only)');
    }

    /** Manuelles Feld (Kategorie): lesbar UND von Hand aenderbar. */
    private static void assertEditable(String ctx, Schema.SObjectField f) {
        Schema.DescribeFieldResult d = f.getDescribe();
        System.assertEquals(true, d.isAccessible(),
            ctx + ': ' + d.getName() + ' muss lesbar sein');
        System.assertEquals(true, d.isUpdateable(),
            ctx + ': ' + d.getName() + ' muss von Hand aenderbar sein (einziges manuelles Feld)');
    }
}
