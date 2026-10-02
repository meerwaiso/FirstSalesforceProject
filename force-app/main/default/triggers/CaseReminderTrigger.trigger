/**
 * [SCRUM-436] Case-Trigger — „Letzte Bearbeitung" bei Eroeffnung und bei
 * Statuswechsel.
 *
 * before insert:  Uhr startet bei Eroeffnung (PO-Regel 1, AC1).
 *                 Last_Relevant_Update__c = System.now(), ausserdem
 *                 falls noch null (Testbarkeit: backdated Wiedervorlage-
 *                 Felder werden vom Trigger nicht ueberschrieben; in der
 *                 Praxis kann es niemand setzen — Feld ist read-only).
 *
 * before update:  relevante Bearbeitung = Statuswechsel (PO-Definition,
 *                 ADR-3). Setzt:
 *                   - Last_Relevant_Update__c = System.now()
 *                   - falls Reminder_Required__c = true: Flag auf false UND
 *                     Reminder_Count__c += 1 (PO-Regel 8, AC8).
 *                     Idempotenz: im before-Kontext IST Trigger.new[i] der
 *                     vollstaendige DB-Stand (vor DML) -> die Zähler-
 *                     Addition ist hier ohne SOQL korrekt. (Im after-
 *                     Kontext waere das das house SCRUM-418-Pitfall, daher
 *                     laeuft das hier bewusst in before.)
 *                     Reminder_Due_Date__c bleibt (PO-Offenpunkt #5 Default).
 *
 *     NICHT relevante Bearbeitung (nur Name, Kommentarfeld, etc.) aendert
 *     NICHTS — PO: nur Statuswechsel + Mitarbeiter-Kommentar (ADR-3).
 *
 * Re-Entry (house SCRUM-419): der vom CaseComment-Pfad (Service
 * update toWrite) oder vom Batch (update toFlag) ausgeloesste re-entrant
 * Lauf faellt ueber CaseReminderService.isReceiving AUS. Im Batch-/Service-
 * Pfad aendert sich der Status ohnehin nicht, der Guard waere doppelt
 * sicher — das Flag ist der pfad-agnostische Schutz (SCRUM-419-Lektion:
 * externe Single-Field-REST/CLI-Updates laufen in mehreren
 * EXECUTION_CONTEXTS und umgehen Status-Guards).
 *
 * Governor: 0 SOQL, 0 DML im Trigger — alle Felder werden DIREKT auf
 * Trigger.new[i] gesetzt (before-Trigger = noch veränderlich).
 *
 * @author developer-agent
 * @date 2026-10-02
 */
trigger CaseReminderTrigger on Case (before insert, before update) {

    if (Trigger.isInsert) {
        for (Case c : Trigger.new) {
            // PO-Regel 1 / AC1: neue Cases starten die Uhr bei Eroeffnung.
            // Null-Check: in der Praxis immer null (read-only Feld), in
            // Tests koennen Wiedervorlage-Felder backdated werden.
            if (c.Last_Relevant_Update__c == null) {
                c.Last_Relevant_Update__c = System.now();
            }
        }
        return;
    }

    // Re-Entry ueberspringen (house SCRUM-419): der CaseComment-Service
    // oder der Batch feuert diesen Trigger re-entrant (deren `update`
    // aendert nur Reminder-Felder, nie den Status).
    if (CaseReminderService.isReceiving) {
        return;
    }

    if (!Trigger.isUpdate) {
        return;
    }

    DateTime now = System.now();
    for (Integer i = 0; i < Trigger.new.size(); i++) {
        Case n = Trigger.new[i];
        Case o = Trigger.old[i];
        // Trigger.old ist der DB-Stand (before-Kontext, 0 SOQL). Trigger.new[ ]
        // enthaelt nur die gesetzten Felder eines partiellen Updates -> der
        // aktuelle Flag-/Zaehler-Zustand kommt AUS o, nicht aus n.
        Boolean wasFlagged   = (o.Reminder_Required__c == true);
        Decimal  oldCount    = (o.Reminder_Count__c == null)
                ? 0 : o.Reminder_Count__c;

        // Relevante Bearbeitung = Statuswechsel (PO + ADR-3). null-Checks:
        // partielle Updates ohne Status-Feld (Admin-Flag, Batch-Update,
        // re-entrant Lauf) haben n.Status == null -> kein Wechsel, kein Reset.
        if (n.Status != null && o.Status != null && n.Status != o.Status) {
            n.Last_Relevant_Update__c = now;

            // Konditionaler Reset (PO-Regel 8, AC8): nur wenn aktuell
            // geflaggt — Zustand aus DB-Stand o (house SCRUM-418/365:
            // Zähler-Werte NIE aus einem moeglichst unvollstaendigen
            // Trigger.new[i], sondern aus dem DB-Stand).
            if (wasFlagged) {
                n.Reminder_Required__c = false;
                n.Reminder_Count__c    = oldCount + 1;
                // Reminder_Due_Date__c bewusst NICHT gesetzt -> bleibt (PO).
            }
        }
    }
}
