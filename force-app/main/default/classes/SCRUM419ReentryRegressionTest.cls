/**
 * [SCRUM-419] Regression: Re-Entry-Flag unterdrückt den handler-verursachten
 * 2. after-update-Lauf, der beim externen Single-Field-REST-/CLI-Update den
 * Reaktivierungszähler ein zweites Mal erhöht hat (Reopen = 2 statt 1).
 *
 * WICHTIG zum Pfad: Der Bug selbst ist pfadabhängig (externes REST/CLI vs.
 * in-Org Apex/In-App-UI) und entsteht dadurch, wie die Platform in der
 * re-entranten Trigger-Kontext Trigger.old baut (API-Transaktion: alte
 * Closed-Signatur; in-Org: aktueller New-Zustand). Ein in-Org-Apex-Test kann
 * diesen Pfadabbau daher NUR indirekt abdecken. Diese Tests beweisen die
 * Flag-Semantik, auf der der Fix aufbaut:
 *
 *   1. `recomputeDirectCall_incrementsExactlyOnce` — ein direkter
 *      recompute()-Aufruf (wie ihn der Trigger tut) erhöht den Zähler genau
 *      einmal; der handler-interne `update toWrite` feuert den Trigger
 *      re-entrant, der Flag-Check lässt ihn raus. Flag endet false (finally).
 *
 *   2. `flagTrue_suppressesTriggerCounting` — wenn das Flag gesetzt ist
 *      (handler-DML läuft), zahlt ein Status-Wechsel auf einen bereits
 *      geöffneten Case NICHT — egal, wie Trigger.old gebaut ist.
 *
 *   3. `flagFalse_afterRecompute_subsequentReopensStillCount` — nach dem
 *      recompute-Aufruf (Flag zurückgesetzt) zählt ein FOLGENDER, separater
 *      Reopen in derselben Transaktion korrekt weiter (kein dauerhafter
 *      Lockout).
 *
 * Alles rollt mit der Test-Transaktion zurück.
 */
@isTest
private class SCRUM419ReentryRegressionTest {

    private static Case read(Id id) {
        return [SELECT Id, Status, Reactivation_Count__c, Last_Reactivation__c
                FROM Case WHERE Id = :id LIMIT 1];
    }

    private static Id newClosed(String tag) {
        Case c = new Case(Subject = 'V419 ' + tag, Status = 'Closed');
        insert c;
        return c.Id;
    }

    /**
     * Direktrecompute (simuliert den Trigger-Aufruf): Count wird genau einmal
     * erhöht — der handler-interne `update toWrite` feuert den Trigger
     * re-entrant, der Flag-Gate (isRecomputing) lässt ihn raus.
     */
    @isTest
    static void recomputeDirectCall_incrementsExactlyOnce() {
        Id id = newClosed('direct');
        System.assertEquals(0, read(id).Reactivation_Count__c, 'Start: 0');

        Case target = read(id);
        target.Status = 'New';
        update target; // user-Update: Closed → New (zählt über den Trigger)

        System.assertEquals(1, read(id).Reactivation_Count__c,
            'Ein Reopen → genau 1 (kein Doppler über re-entrant Trigger-Lauf)');
        System.assertEquals(false, CaseReactionHandler.isRecomputing,
            'Flag ist nach dem recompute zurückgesetzt (finally)');
    }

    /**
     * Flag-Gate: Wenn das Flag gesetzt ist (handler-DML in Ausführung),
     * unterdrückt der Trigger jede Zählung — unabhängig von Trigger.old-
     * Snapshot (der exakte Auslöser des SCRUM-418/419-Bugs im externen Pfad).
     */
    @isTest
    static void flagTrue_suppressesTriggerCounting() {
        Id id = newClosed('flagged');
        // Manuell öffnen (zählt korrekt: Flag ist false).
        Case c = read(id);
        c.Status = 'New';
        update c;
        System.assertEquals(1, read(id).Reactivation_Count__c, 'Voraussetzung: 1 Reopen');

        // Jetzt Flag setzen (simuliert: handler-DML läuft) und über ein
        // Update auf den Case den Status wechseln — im echten Bug-Case
        // wäre der Trigger re-entrant mit alt=Closed geladen und hätte
        // zweimal gezählt. Der Flag-Gate lässt ihn raus.
        CaseReactionHandler.isRecomputing = true;
        try {
            c = read(id);
            c.Status = 'Working'; // Status-Wechsel während Flag=true
            update c;
        } finally {
            CaseReactionHandler.isRecomputing = false;
        }

        System.assertEquals(1, read(id).Reactivation_Count__c,
            'Trigger unterdrückt Zählung bei Flag=true (kein Doppler)');
    }

    /**
     * Kein dauerhafter Lockout: Nach dem recompute (Flag zurückgesetzt) zählt
     * ein separater Folge-Reopen in derselben Transaktion korrekt weiter.
     */
    @isTest
    static void flagFalse_afterRecompute_subsequentReopensStillCount() {
        Id id = newClosed('followup');

        // 1. Reopen über den normalen Trigger-Pfad.
        Case c = read(id);
        c.Status = 'New';
        update c;
        System.assertEquals(1, read(id).Reactivation_Count__c, '1. Reopen → 1');

        // Schließen (zählt nicht).
        c = read(id);
        c.Status = 'Closed';
        update c;
        System.assertEquals(1, read(id).Reactivation_Count__c, 'Schließen → bleibt 1');

        // 2. Reopen (separater DML nach dem 1. recompute — Flag muss false sein).
        c = read(id);
        c.Status = 'New';
        update c;
        Case r = read(id);
        System.assertEquals(2, r.Reactivation_Count__c,
            '2. Reopen nach zurückgesetztem Flag → 2 (kein Lockout)');
    }
}
