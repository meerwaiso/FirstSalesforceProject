/**
 * [SCRUM-436] Core-Logik der automatischen Wiedervorlage fuer offene Cases.
 *
 * Zwei Quellen setzen „Letzte Bearbeitung" (PO-Definition, ADR-3):
 *   1. Statuswechsel auf dem Case  -> CaseReminderTrigger (before update,
 *      schreibt DIREKT auf Trigger.new, 0 SOQL/0 DML, FLS-umgangen da before).
 *   2. Mitarbeiter-Kommentar/Antwort (CaseComment) -> markRelevantWork() hier:
 *      1 SOQL (Parent mit aktuellem Feld-Stand laden) + 1 DML (update) pro
 *      Aufruf, KEIN SOQL/DML im Loop, 200er-Chunk-sicher.
 *
 * Idempotenz / DB-Stand (house SCRUM-418/365): Der Zähler Reminder_Count__c
 * wird IMMER auf dem frisch geladenen DB-Stand inkrementiert (hier: SOQL),
 * nie auf einem moeglichst veralteten sObject. Im before-Trigger-Kontext
 * (Statuswechsel) ist Trigger.new bereits der vollstaendige DB-Stand, dort
 * ist die Addition ohne SOQL korrekt — s. CaseReminderTrigger.
 *
 * Re-Entry (house SCRUM-419, ADR-1): das `update toWrite` in
 * markRelevantWork() feuert den Case-Trigger RE-ENTRANT. isReceiving macht
 * genau diesen Re-Lauf inert — pfad-agnostisch (UI, REST/CLI, Batch).
 *
 * without sharing: die Logik ist deterministisch ueber den offenen Bestand
 * und unabhaengig vom Sharing des aufrufenden Users. Ueberwindet WITHOUT
 * SHARING NICHT FLS: der Batch-Executor braucht das Write-PS
 * SCRUM436_CaseReminderSystem (ADR-5), Endanwender das Read-PS
 * SCRUM436_CaseReminder.
 *
 * @author developer-agent
 * @date 2026-10-02
 */
public without sharing class CaseReminderService {

    /**
     * SCRUM-419-Shape: Re-Entry-Flag. Der Case-Trigger fuehrt es ueber seine
     * Update-Logik, der CaseComment-Trigger ueber markRelevantWork(). Der
     * vom `update toWrite` ausgeloesste re-entrant Case-Trigger-Lauf sieht
     * isReceiving=true und faellt aus. Pfad-agnostisch (auch gegen die
     * mehrfachen EXECUTION_CONTEXTS externer Single-Field-Updates,
     * SCRUM-419-Lektion).
     */
    public static Boolean isReceiving = false;

    private CaseReminderService() {}

    /**
     * Setzt „Letzte Bearbeitung" auf den betroffenen Parent-Cases, wenn ein
     * STAFF-Kommentar (CreatedById != Case.CreatedById, SCRUM-424-Guard)
     * eingefuegt wurde. Kundeneigene Kommentare (CreatedById ==
     * Case.CreatedById) sind KEINE relevante Bearbeitung (PO) und aendern
     * nichts.
     *
     * Konditionaler Reset (PO-Regel 8, AC8): nur wenn Reminder_Required__c
     * aktuell true ist (DB-Stand aus frischem SOQL) wird das Flag auf false
     * gesetzt und Reminder_Count__c um 1 erhoht. Reminder_Due_Date__c wird
     * BEIBEHALTEN (PO-Offenpunkt #5 Default: letzter Ausloese-Zeitpunkt
     * bleibt lesbar).
     *
     * Governor: exakt 1 SOQL + 1 DML, 0 im Loop.
     *
     * @param newComments CaseComments aus Trigger.new (after insert)
     * @return Anzahl der aktualisiert Parent-Cases
     */
    public static Integer markRelevantWork(List<CaseComment> newComments) {
        if (newComments == null || newComments.isEmpty()) {
            return 0;
        }

        Set<Id> caseIds = new Set<Id>();
        for (CaseComment cc : newComments) {
            if (cc.ParentId != null) {
                caseIds.add(cc.ParentId);
            }
        }
        if (caseIds.isEmpty()) {
            return 0;
        }

        // 1 SOQL: aktueller Stand der Parent-Cases inkl. der 3 Zähler-/
        // Flag-Felder (Trigger.new ist im after insert-Kontext NICHT der
        // Parent-Stand — das hier ist die einzige Quelle).
        Map<Id, Case> caseMap = new Map<Id, Case>([
            SELECT Id, CreatedById, Last_Relevant_Update__c,
                   Reminder_Required__c, Reminder_Count__c
            FROM Case
            WHERE Id IN :caseIds
        ]);

        // Nur StAFF-Kommentare zaehlen (PO + ADR-3, 1:1 SCRUM-424-Guard).
        // Mehrere Kommentare auf denselben Case in einem Batch = 1 Update.
        Set<Id> staffTouched = new Set<Id>();
        for (CaseComment cc : newComments) {
            Case c = caseMap.get(cc.ParentId);
            if (c == null) continue;                       // orphan comment
            if (cc.CreatedById == c.CreatedById) continue; // Kundenkommentar
            staffTouched.add(cc.ParentId);
        }
        if (staffTouched.isEmpty()) {
            return 0;
        }

        DateTime now = System.now();
        List<Case> toWrite = new List<Case>();
        for (Id cid : staffTouched) {
            Case c = caseMap.get(cid);
            Boolean wasFlagged = (c.Reminder_Required__c == true);
            // Custom Number ist in Apex immer Decimal (house Pitfall).
            Integer currentCount = (c.Reminder_Count__c == null)
                    ? 0 : c.Reminder_Count__c.intValue();
            toWrite.add(new Case(
                Id                       = cid,
                Last_Relevant_Update__c  = now,
                Reminder_Required__c     = wasFlagged ? false : c.Reminder_Required__c,
                Reminder_Count__c        = currentCount + (wasFlagged ? 1 : 0)
                // Reminder_Due_Date__c bewusst NICHT gesetzt -> bleibt
                // (PO-Offenpunkt #5 Default, Audit).
            ));
        }

        // 1 DML pro Batch. Feuert den Case-Trigger re-entrant — der
        // faellt dort ueber isReceiving aus (oben), und der Status-Guard
        // ist ohnehin false (Status wird hier nicht geaendert).
        update toWrite;
        return toWrite.size();
    }

    /**
     * ADR-2: Werktag-Arithmetik Mo-Fr, KEIN Feiertag, KEIN BusinessHours-
     * Objekt. Zaehlt die Kalendertage im OFFENEN Intervall (from, to] auf
     * Tages-Ebene: der Tag von `from` zaehlt NICHT mit, der Tag von `to`
     * ja. Reine CPU-Arithmetik ueber DayOfWeek, TZ-agnostisch (nur das
     * Kalendertag-Zeichen zahlt, nicht die Uhrzeit), kein Governor-Risiko.
     *
     * Beispiel: from = Mo 09:00, to = Fr 01:00 -> (Mo, Fr] = Di, Mi, Do, Fr
     * = 4 Werktage.
     *
     * @param from letzte relevante Bearbeitung (oder null -> 0)
     * @param to   Pruefzeitpunkt (Batch-System.now() bzw. test-injiziert)
     * @return Anzahl Werktage im Intervall (>= 0)
     */
    public static Integer workingDaysBetween(DateTime from, DateTime to) {
        if (from == null || to == null || to.getTime() <= from.getTime()) {
            return 0;
        }
        Date start = from.date(); // org-TZ, auf Tag-Ebene
        Date end   = to.date();
        Integer count = 0;
        Date d = start + 1;       // erster Tag NACH from
        while (d <= end) {
            if (isWorkingDay(d)) {
                count++;
            }
            d = d.addDays(1);
        }
        return count;
    }

    /** Date.dayOfWeek(): 1=So .. 7=Sa -> 2..6 = Mo-Fr. */
    private static Boolean isWorkingDay(Date d) {
        Integer dow = Integer.valueOf(d.dayOfWeek());
        return dow >= 2 && dow <= 6;
    }
}
