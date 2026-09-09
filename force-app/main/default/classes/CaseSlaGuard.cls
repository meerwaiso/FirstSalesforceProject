/**
 * SCRUM-404: CaseSlaGuard — vor-Update-Guard für die 3 systemgepflegten Felder.
 * ADR-5: stummer Revert auf Trigger.old für alle nicht-erlaubten Writes.
 *
 * Erlaubte Transitionen:
 *   Reaktionsfrist__c    : null → Wert, nur wenn WRITING_DEADLINE
 *   Erste_Rueckmeldung__c: null → Wert, nur wenn WRITING_RESPONSE
 *   Sla_Alert_Sent__c    : false → true, nur wenn WRITING_ALERT
 *
 * TEST_BYPASS: im Apex-Test erlaubt zusätzliche manuelle Changes im Trigger-Pfad
 * (AC 5: Frist in der Vergangenheit — Case wird mit gesetzter Frist via API/insert
 * erzeugt; danach TEST_BYPASS=false für die Mutagen-Tests).
 */
public without sharing class CaseSlaGuard {
    @testVisible public static Boolean WRITING_DEADLINE = false;
    @testVisible public static Boolean WRITING_RESPONSE = false;
    @testVisible public static Boolean WRITING_ALERT    = false;
    @testVisible public static Boolean TEST_BYPASS      = false;

    /**
     * Vor-Update: alle nicht-gestatteten Writes auf die 3 systemgepflegten Felder
     * werden stumm auf den Trigger.old-Wert revertiert.
     */
    public static void guardOnUpdate(List<Case> oldList, List<Case> newList) {
        if (oldList == null || newList == null) return;
        for (Integer i = 0; i < oldList.size(); i++) {
            Case o = oldList[i];
            Case n = newList[i];
            // Reaktionsfrist__c: nur null→Wert, nur wenn WRITING_DEADLINE.
            if (n.Reaktionsfrist__c != o.Reaktionsfrist__c) {
                if (WRITING_DEADLINE && o.Reaktionsfrist__c == null && n.Reaktionsfrist__c != null) {
                    // erlaubte Transition, behalten
                } else if (TEST_BYPASS) {
                    // Test-Bypass: erlauben
                } else {
                    n.Reaktionsfrist__c = o.Reaktionsfrist__c;
                }
            }
            // Erste_Rueckmeldung__c: nur null→Wert, nur wenn WRITING_RESPONSE.
            if (n.Erste_Rueckmeldung__c != o.Erste_Rueckmeldung__c) {
                if (WRITING_RESPONSE && o.Erste_Rueckmeldung__c == null && n.Erste_Rueckmeldung__c != null) {
                    // erlaubte Transition, behalten
                } else if (TEST_BYPASS) {
                    // Test-Bypass: erlauben
                } else {
                    n.Erste_Rueckmeldung__c = o.Erste_Rueckmeldung__c;
                }
            }
            // Sla_Alert_Sent__c: nur false→true, nur wenn WRITING_ALERT.
            if (n.Sla_Alert_Sent__c != o.Sla_Alert_Sent__c) {
                if (WRITING_ALERT && o.Sla_Alert_Sent__c == false && n.Sla_Alert_Sent__c == true) {
                    // erlaubte Transition, behalten
                } else if (TEST_BYPASS) {
                    // Test-Bypass: erlauben
                } else {
                    n.Sla_Alert_Sent__c = o.Sla_Alert_Sent__c;
                }
            }
        }
    }
}
