/**
 * SCRUM-420: Testdaten-Factory nach Hausmuster (SCRUM365/370 TestDataFactory).
 *
 * Account zentral — eindeutiger Name, kein dedup-Drift in der Org.
 *
 * @author developer-agent
 * @date 2026-09-19
 */
@isTest
public class SCRUM420TestDataFactory {

    /**
     * Erzeugt einen Account mit eindeutigem Namen (kein dedup-Drift in der Org).
     */
    public static Id createAccount(String tag) {
        Account a = new Account(Name = 'Test-420-' + tag + '-' + String.valueOf(System.currentTimeMillis()));
        insert a;
        return a.Id;
    }
}
