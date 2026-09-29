/**
 * [SCRUM-434] Gemeinsamer Test-Hilfsblock: Standard User mit dem
 * SCRUM-434_Ursache-Permission-Set (Read+Edit FLS auf Case.Ursache__c).
 *
 * Warum diese Klasse: Das frische Feld Case.Ursache__c ist in Prod-Org noch
 * nicht freigegeben. Liefert ein @isTest-Fixture den Cause-Wert im
 * System-Kontext, fehlt dem ausfuehrenden Validierungs-User in der Prod-
 * check-only-Validierung genau das FLS dieses neuen Feldes — DML meldet
 * "fields being inaccessible on Sobject Case", SOQL "No such column". Luecke C
 * des FLS-Gates verlangt genau diesen Fall: das fachliche DML/SOQL auf das neue
 * Feld laeuft unter System.runAs(ein User mit dem gewaehrenden PS).
 *
 * Idiom (Hausmuster SCRUM370 / SCRUM424 / SCRUM432): User UND
 * PermissionSetAssignment entstehen im System-Kontext (ein User kann sich kein
 * PSA geben, und Setup+DML in einer Transaktion vermeiden MIXED_DML), danach laeuft
 * das Ursache__c-bearing DML/SOQL in System.runAs(u).
 *
 * @author developer-agent
 * @date 2026-09-29
 */
@isTest
private class SCRUM434TestFixtures {

    // Unique username within one test class run (multiple methods, one tx each).
    private static Integer n = 0;

    /**
     * Legt einen Standard User an, waehlt ihm das SCRUM434_Ursache-PS und
     * liefert ihn rueck. NUR fuer den Lauf des fachlichen DML/SOQL auf
     * Case.Ursache__c unter System.runAs.
     */
    public static User ursacheUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(System.now().getTime());
        String t = (tag == null || tag == '') ? 'x' : tag.replace(' ', '').replace('-', '');
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr434F',
            Alias = 'scr434',
            Email = 'scr434fix_' + t + '_' + stamp + '_' + (n++) + '@example.invalid',
            Username = 'scr434fix_' + t + '_' + stamp + '_' + (n++) + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM434_Ursache' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }
}
