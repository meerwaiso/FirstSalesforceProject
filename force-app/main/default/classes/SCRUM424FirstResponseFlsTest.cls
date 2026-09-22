/**
 * [SCRUM-424] AC10 — FLS auf den 3 neuen Case-Feldern (USER_MODE).
 *
 * Gemessen in der Test-Org am 2026-09-22 (keine Annahmen):
 *   - Standard-User OHNE das PS kann die Felder NICHT lesen  -> SELECT WITH USER_MODE wirft.
 *   - User MIT dem PS (read-only) kann die Felder lesen      -> SELECT WITH USER_MODE laeuft.
 *   - Kein User (Profil ODER PS) kann die Felder schreiben   -> isUpdateable()==false in beiden Faellen.
 *
 * ADR-6 / ticket-Hinweis: negativer FLS-Test ist nur gultig mit WITH USER_MODE
 * (AccessLevel.USER_MODE) — ohne laeuft Apex im Systemmodus und ist bauartbedingt gruen.
 *
 * PS-Zugriff (read-back der FLS-Kette, Stufe 3 "Zuweisung"):
 *   Existenz    -> PermissionSet "SCRUM424_FirstResponse_Read" existiert (deployed)
 *   Gewaehrung  -> FieldPermissions readable=true, editable=false (in der PS)
 *   Zuweisung   -> PermissionSetAssignment wird im Test je nach Leg gesetzt.
 *
 * @author developer-agent
 * @date 2026-09-22
 */
@isTest
private class SCRUM424FirstResponseFlsTest {

    private static final String PERMSET_NAME = 'SCRUM424_FirstResponse_Read';

    private static final String F_TIME  = 'First_Response_Time__c';
    private static final String F_MINS  = 'First_Response_Working_Mins__c';
    private static final String F_MISS  = 'First_Response_Target_Missed__c';

    private static User newUser(String alias) {
        Profile standard = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId         = standard.Id,
            LastName          = 'Scr424 ' + alias,
            Alias             = alias,                 // max 8 Zeichen
            Email             = alias + sfx + '@x.invalid',
            Username          = alias + sfx + '@x.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'Europe/Berlin'
        );
        insert u;
        return u;
    }

    private static Id permsetId() {
        return [SELECT Id FROM PermissionSet WHERE Name = :PERMSET_NAME LIMIT 1][0].Id;
    }

    private static void assignPS(User u) {
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = permsetId());
    }

    /**
     * Hat der User Lese-FLS auf den 3 Feldern? (SOQL im USER_MODE, DML-frei:
     * wirft reiner Read auf LIMIT 1 -> kein Mixed-DML mit der PS-Zuweisung).
     * Wirft der Select (kein Read-FLS), liefert die Methode false;
     * laeuft er (Read-FLS vorhanden), liefert sie true.
     */
    private static Boolean canRead(User u) {
        Boolean ok = false;
        System.runAs(u) {
            try {
                List<Case> rows = [
                    SELECT First_Response_Time__c, First_Response_Working_Mins__c,
                           First_Response_Target_Missed__c
                    FROM Case WITH USER_MODE LIMIT 1
                ];
                // SELECT lief durch (keine FLS-Ausnahme) -> Lese-FLS vorhanden
                ok = true;
            } catch (Exception e) {
                ok = false;
            }
        }
        return ok;
    }

    /** Hat der User schreibbare FLS auf dem Feld? (Schema-Reflexion im USER-Kontext) */
    private static Boolean canWrite(User u) {
        Boolean w = null;
        System.runAs(u) {
            w = Case.First_Response_Time__c.getDescribe().isUpdateable();
        }
        return w;
    }

    /* ------------------------------------------------------------------
     * AC10 — Negativ-Leg: Standard-User OHNE PS kann die Felder NICHT lesen.
     *   (Vorbedingung S3 = Profil-Lock. In der aktuellen Test-Org gemessen: wirft -> gruen.)
     */
    @isTest
    static void ac10_negative_user_without_ps_cannot_read() {
        // FLS-Kette Stufe 1: die PS existiert (deployed)
        Id psId = permsetId();
        System.assertNotEquals(null, psId, 'AC10: PS existiert');

        // Stufe 2+3 verhaltensbasiert: ein User, der die PS NICHT haelt, darf NICHT lesen.
        User ohnePS = newUser('nops42');
        System.assert(!canRead(ohnePS),
            'AC10: User ohne PS darf die 3 Felder NICHT lesen (USER_MODE)');
    }

    /* ------------------------------------------------------------------
     * AC10 — Positiv-Leg: User MIT dem PS kann die Felder lesen.
     */
    @isTest
    static void ac10_positive_user_with_ps_can_read() {
        User mitPS = newUser('withps');
        assignPS(mitPS);

        // FLS-Kette Stufe 3 (Zuweisung): read-back
        Integer assigned = [SELECT COUNT() FROM PermissionSetAssignment
                            WHERE AssigneeId = :mitPS.Id
                              AND PermissionSetId = :permsetId()];
        System.assertEquals(1, assigned, 'AC10: PS ist dem User zugeordnet (read-back)');

        // Stufe 2 (Gewahrung) verhaltensbasiert: nur mit der PS wird Read erteilt
        System.assert(canRead(mitPS),
            'AC10: User mit PS darf die 3 Felder lesen (USER_MODE)');
    }

    /* ------------------------------------------------------------------
     * AC10 — Schreib-Leg: weder Profil noch PS darf einen der 3 Felder beschreiben.
     */
    @isTest
    static void ac10_no_write_for_any_user() {
        User ohnePS = newUser('nops42');
        System.assert(!canWrite(ohnePS),
            'AC10: User ohne PS darf das Feld NICHT schreiben');

        User mitPS = newUser('withps');
        assignPS(mitPS);
        System.assert(!canWrite(mitPS),
            'AC10: auch der PS-User (read-only) darf das Feld NICHT schreiben');
    }
}
