/**
 * OpportunityLossReasonClearHandler — Trigger handler fur das automatische
 * Leeren des Verlustgrundes (Opportunity.Loss_Reason__c), SCRUM-381.
 *
 * Wird aus dem gemeinsamen Opportunity-Trigger (OpportunityOverdueReset,
 * before update) aufgerufen — ein Trigger pro Objekt, etabliertes Muster.
 *
 * Verhalten:
 *   Jede Opportunity, deren StageName sich VON 'Closed Lost' AUF eine andere
 *   Stage andert (Reopen, Closed Won, ...), bekommt Loss_Reason__c auf null
 *   gesetzt. Ein Verlustgrund ergibt fuer eine wiederaufgegriffene oder
 *   gewonnene Chance keinen Sinn mehr (AC4 / AC5).
 *
 * Warum einfache null-Zuweisung (kein Shadow-Field / Kein Space-Trick):
 *   Die Validierung LossReason_PflichtBeiClosedLost wird auf den ENDSTAND des
 *   Records in der Transaktion ausgewertet — also NACH dem Before-Update-Trigger.
 *   Wir leeren das Feld nur, wenn sich die Stage weg von 'Closed Lost' andert;
 *   in derselben Transaktion ist das Rule-Gate (StageName = 'Closed Lost') dann
 *   bereits FALSE, daher kann das Leeren nie zu einem falsch-positiven Block
 *   fuehren. Der einzige blockierte Fall bleibt der gewollte: Stage bleibt
 *   'Closed Lost' UND das Feld ist leer.
 *
 * Bulk / Governor-Limits:
 *   Ein Before-Update-Aufruf, 0 SOQL, eine Feld-Zuweisung pro geaendertem
 *   Record (Loop ueber Trigger.new / Trigger.oldMap). Rekursion: StageName wird
 *   von diesem Handler nie verandert -> die Clear-Logik feuert hoechstens 1x pro
 *   Record pro Transaktion; das eigene hasFired-Flag ist ein Safety-Net.
 */
public with sharing class OpportunityLossReasonClearHandler {
    // Statische Flag zum Schutz gegen Trigger-Rekursion (eigenes, unabhaengig
    // vom SCRUM-319-Handler).
    @testVisible
    private static Boolean hasFired = false;

    /**
     * Before-Update-Handler: leert Loss_Reason__c, wenn sich die Stage VON
     * 'Closed Lost' weg auf eine andere Stage andert.
     *
     * @param newRecords Liste der neuen Opportunity-Zustaende (Update)
     * @param oldMap     Map Id -> Opportunity alter Zustand
     */
    public static void handleBeforeUpdate(List<Opportunity> newRecords, Map<Id, Opportunity> oldMap) {
        if (hasFired) {
            return;
        }
        hasFired = true;

        for (Opportunity opp : newRecords) {
            Opportunity oldOpp = oldMap.get(opp.Id);

            // NUR leeren, wenn sich die Stage tatsaechlich AUS Closed Lost heraun
            // andert. Kein Clear bei Stage ohne Aenderung und kein Clear bei einem
            // bloessen Ueberschreiben von Closed Lost -> Closed Lost.
            if (oldOpp != null
                && oldOpp.StageName == 'Closed Lost'
                && opp.StageName != 'Closed Lost') {
                opp.Loss_Reason__c = null;
            }
        }
    }
}
