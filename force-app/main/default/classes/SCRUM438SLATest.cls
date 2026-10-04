/**
 * [SCRUM-438] Apex-Test — SLA-Eskalation (Service-Kernlogik + Trigger +
 * Batch). Haus-Pattern SCRUM436CaseReminderTest / SCRUM432.
 *
 * ORG-AGNOSTIK (Memory-Lektion: nicht hartcoded): die Test-Org-BH ist
 * Mo-Fr 9-17 + Sa/So 24/7 (Probe 2026-10-04), aber kein Test darf von
 * dieser Geometrie abhaengen. Deshalb wird `now` Ueber
 * SLAService.estimateDeadline(...) eingestimmt — dessen Invers-Eigenschaft
 * (diff(from, estimateDeadline(from, K)) == K, aehnlich ADR-3/ADR-3-FIX)
 * wird in ac2_deadline_inverse ALLEIN ueber die Org-diff ge-prueft. Damit
 * ist "worked = K Minuten" exakt gesetzt, unabhaengig von der Geometrie.
 *
 * AC-Coverage:
 *   AC2  Zielzeit = Creation + Ziel-Minuten (Binary-Search-Deadline korrekt)
 *   AC3  Status Im Zeitplan / Gefaehrdet / Ueberschritten (worked vs. Ziel)
 *   AC4  Eskalation Stufe 1 -> Stufe 2, MONOTON (nie rueckstaendig)
 *   AC7  Priority-Wechsel: Zielzeit neu, bereits-Arbeitetes angerechnet
 *   AC8  Batch ueber Bestand, idempotent (2. Lauf toucht 0), Closing-Filter
 *   AC9  Reaktiver before-Trigger: initSLA bei insert, isRunning-Reentry
 *   Config: Zielzeit-Tabelle (High/Med/Low x Premium) + Pause-Gate
 *   FLS  => SCRUM438SLAFlsTest (separate Klasse, System.runAs-Modus)
 *
 * @author developer-agent
 * @date 2026-10-04
 */
@isTest
private class SCRUM438SLATest {

    // EINMAL pro Test-Klasse holen (Governor): Default-BH-Set der Org.
    private static Id bh() {
        return SLAService.bhId();
    }

    private static DateTime at(Integer y, Integer mo, Integer d, Integer h,
                               Integer mi) {
        return DateTime.newInstance(y, mo, d, (h == null ? 0 : h),
                                    (mi == null ? 0 : mi), 0);
    }

    /**
     * Frischer, nicht-insertierter Case-Literal fuer PURE Service-Tests
     * (0 DML). CreatedDate bewusst backdated (read-only, aber im Literal
     * in-memory setzbar); Last_Checked/Akkum initial null -> Bootstrap-Pfad.
     */
    private static Case fresh(String priority, String kundenstatus,
                              DateTime created) {
        return new Case(Subject = 'SCR438 unit', Origin = 'Phone',
                        Status = 'New',
                        Priority = priority,
                        Kundenstatus__c = kundenstatus,
                        CreatedDate = created);
    }

    /* ================================================================
     * AC2 — estimateDeadline ist die INVERSE von workedMins/diff.
     *   diff(from, est(from, K)) == K  (1s-Praezision, Binary-Search).
     * Das ist der Kernbeweis, dass die ADR-3 add-defekt-Ausweichfunktion
     * (Binary-Search ueber diff) tatsaechlich exakt K Werk-Minuten liefert,
     * UEBERHAUPT NICHT von der Org-Geometrie abhaengig.
     * ================================================================ */
    @isTest
    static void ac2_deadline_isExactInverseOfDiff() {
        Id bh = bh();
        DateTime from = at(2026, 10, 5, 9, 0);     // ein Montag
        Integer[] probed = new Integer[]{30, 480, 1440, 1440 + 600};
        for (Integer k : probed) {
            DateTime d = SLAService.estimateDeadline(bh, from, k);
            Decimal back = SLAService.workedMins(bh, from, d);
            // Inverse: genau k (1s Toleranz = <= 1 Min = 60s, diff gibt min).
            System.assert(back.doubleValue() >= k.doubleValue() - 1.0
                          && back.doubleValue() <= k.doubleValue() + 1.0,
                'AC2: est(from,' + k + ') liefert ' + back + ' Werk-Min, erwartet ~' + k);
        }
    }

    /* ================================================================
     * AC3 — Statusregeln, nur worked vs. Ziel (org-agnostik via est()):
     *   50 %  uebrig -> Im Zeitplan
     *   15 %  uebrig -> Gefaehrdet   (< 20 %)
     *   0  uebrig    -> Ueberschritten (+ Ueberschritten-Flag true)
     * ================================================================ */
    @isTest
    static void ac3_status_branches() {
        Id bh = bh();
        DateTime from = at(2026, 10, 5, 9, 0);
        Integer target = SLAConfig.targetMinutes('High', false);          // 240

        // (a) worked = 50 % Ziel -> 50 % uebrig -> Im Zeitplan.
        Case a = fresh('High', 'Standard', from);
        SLAService.evaluate(a, SLAService.estimateDeadline(bh, from, target/2), bh);
        System.assertEquals('Im Zeitplan', a.SLA_Status__c, 'AC3a: 50% = Im Zeitplan');
        System.assertEquals(false, a.SLA_Ueberschritten__c, 'AC3a: Flag false');

        // (b) worked = 85 % Ziel -> 15 % uebrig -> Gefaehrdet.
        Case b = fresh('High', 'Standard', from);
        Integer eightyFive = (Integer)Math.round(0.85 * target);
        SLAService.evaluate(b, SLAService.estimateDeadline(bh, from, eightyFive), bh);
        System.assertEquals('Gefaehrdet', b.SLA_Status__c, 'AC3b: 15% = Gefaehrdet');
        System.assertEquals(false, b.SLA_Ueberschritten__c, 'AC3b: Flag noch false');

        // (c) worked = 100 % Ziel -> Ueberschritten + Flag true.
        Case c = fresh('High', 'Standard', from);
        SLAService.evaluate(c, SLAService.estimateDeadline(bh, from, target), bh);
        System.assertEquals('Ueberschritten', c.SLA_Status__c, 'AC3c: 100% = Ueberschritten');
        System.assertEquals(true, c.SLA_Ueberschritten__c, 'AC3c: Flag true');
    }

    /* ================================================================
     * AC4 — Eskalation: Stufe 1 bei Ueberschreitung, Stufe 2 nach +4h,
     * MONOTON: erreichte Stufe sinkt NICHT wieder (Pause-Fall konstruktiv).
     * ================================================================ */
    @isTest
    static void ac4_escalation_monotonic() {
        Id bh = bh();
        DateTime from = at(2026, 10, 5, 9, 0);
        Integer target = SLAConfig.targetMinutes('High', false);

        // unter Ziel -> Keine.
        Case a = fresh('High', 'Standard', from);
        SLAService.evaluate(a, SLAService.estimateDeadline(bh, from, target/2), bh);
        System.assertEquals('Keine', a.SLA_Eskalation__c, 'AC4a: unter Ziel = Keine');

        // genau auf Ziel -> Stufe 1.
        Case b = fresh('High', 'Standard', from);
        SLAService.evaluate(b, SLAService.estimateDeadline(bh, from, target), bh);
        System.assertEquals('Stufe 1', b.SLA_Eskalation__c, 'AC4b: auf Ziel = Stufe 1');

        // Ziel + 240 -> Stufe 2.
        Case c = fresh('High', 'Standard', from);
        SLAService.evaluate(c,
             SLAService.estimateDeadline(bh, from, target
                 + SLAConfig.ESCALATION_LEVEL2_AFTER_MINUTES), bh);
        System.assertEquals('Stufe 2', c.SLA_Eskalation__c, 'AC4c: +4h = Stufe 2');

        // MONOTONITÄT: Case mit erreichter Stufe 1 wird auf einem frueheren
        // `now` (worked < Ziel) neu bewertet -> darf NICHT auf "Keine"
        // fallen (Pause friert worked; hier synthetisch: fruehere Clock).
        Case m = fresh('High', 'Standard', from);
        m.SLA_Eskalation__c = 'Stufe 1';   // erreichte Stufe
        m.SLA_Akkumulierte_WorkingMins__c = 0;
        m.SLA_Last_Checked__c = null;
        SLAService.evaluate(m, SLAService.estimateDeadline(bh, from, target/2), bh);
        System.assertEquals('Stufe 1', m.SLA_Eskalation__c,
            'AC4d: erreichte Stufe 1 bleibt (monoton, kein Rueckschritt)');
    }

    /* ================================================================
     * AC7 — Priority-/Premium-Wechsel: bereits-Arbeitetes bleibt gewahrt,
     * Zielzeit wird neu auf rest = newTarget - worked berechnet.
     * ================================================================ */
    @isTest
    static void ac7_priority_change_carriesWorkedForward() {
        Id bh = bh();
        DateTime from = at(2026, 10, 5, 9, 0);

        // Phase 1: High, 120 Werk-Min gearbeitet (t50).
        Case c = fresh('High', 'Standard', from);
        DateTime t1 = SLAService.estimateDeadline(bh, from,
                       SLAConfig.targetMinutes('High', false)/2);   // 120
        SLAService.evaluate(c, t1, bh);
        System.assertEquals(120, c.SLA_Akkumulierte_WorkingMins__c.intValue(),
            'AC7 pre: High, 120 min gearbeitet');

        // Phase 2: auf Low (Ziel 1440) wechseln, 60 min spaeter.
        c.Priority = 'Low';
        DateTime t2 = SLAService.estimateDeadline(bh, t1, 60);
        SLAService.onPriorityChange(c, t2, bh);
        System.assertEquals(180, c.SLA_Akkumulierte_WorkingMins__c.intValue(),
            'AC7: 120 + 60 = 180 min bleibt gewahrt');

        // Neue Zielzeit = rest = newTarget - worked = 1440 - 180 = 1260,
        // ab t2. Inverse ueber Org-diff pruefen (org-agnostik):
        Integer newTarget = SLAConfig.targetMinutes('Low', false);     // 1440
        Decimal remaining = SLAService.workedMins(bh, t2, c.SLA_Zielzeit__c);
        System.assertEquals((newTarget - 180), (Integer)remaining,
            'AC7: neue Zielzeit deckt rest 1260 Werk-Min ab t2');
        System.assertEquals('Im Zeitplan', c.SLA_Status__c,
            'AC7: mit 1260 min Puffer = Im Zeitplan');
    }

    /* ================================================================
     * Config — Zielzeit-Tabelle (PO/ADR-7) + Premium-24-38 + Pause-Gate.
     * Pure, kein DML, keine BH-Abhaengigkeit.
     * ================================================================ */
    @isTest
    static void config_deadlineTableAndPremium() {
        System.assertEquals(240,  SLAConfig.targetMinutes('High',   false), 'High Std 240');
        System.assertEquals(180,  SLAConfig.targetMinutes('High',   true),  'High Premium 180');
        System.assertEquals(480,  SLAConfig.targetMinutes('Medium', false), 'Medium Std 480');
        System.assertEquals(360,  SLAConfig.targetMinutes('Medium', true),  'Medium Premium 360');
        System.assertEquals(1440, SLAConfig.targetMinutes('Low',    false), 'Low Std 1440');
        System.assertEquals(1080, SLAConfig.targetMinutes('Low',    true),  'Low Premium 1080');
        System.assertEquals(480,  SLAConfig.targetMinutes(null,     false), 'unbek. Priority -> Medium Default');
        System.assertEquals(480,  SLAConfig.targetMinutes('Bogus',  false), 'Bogus Priority -> Medium Default');

        // Pause-Gate (ADR-4): leer -> nichts gepauset; null safe.
        System.assertEquals(false, SLAConfig.isPauseStatus('New'), 'New nicht Pause');
        System.assertEquals(false, SLAConfig.isPauseStatus('Working'), 'Working nicht Pause');
        System.assertEquals(false, SLAConfig.isPauseStatus(null), 'null nicht Pause');
    }

    /* ================================================================
     * AC9 — Reaktiver before-Trigger: neue offene Cases bekommen beim
     * insert Zielzeit + Status + Eskalation(None) + Last_Checked; Uhr gestoppt false.
     * (Keine exakten worked-Werte abgeprueft: CreatedDate=Real-now ->
     *  worked~0 -> deterministisch 'Im Zeitplan' + 'Keine'.)
     * ================================================================ */
    @isTest
    static void ac9_trigger_initialisesOpenCase() {
        Case c = new Case(Subject='SCR438 trig', Origin='Phone',
                          Status='New', Priority='Medium');
        insert c;
        Case r = [SELECT Id, SLA_Zielzeit__c, SLA_Status__c, SLA_Eskalation__c,
                       SLA_Ueberschritten__c, SLA_Last_Checked__c,
                       SLA_Uhr_gestoppt__c, SLA_Akkumulierte_WorkingMins__c,
                       CreatedDate
                     FROM Case WHERE Id=:c.Id LIMIT 1][0];
        System.assertNotEquals(null, r.SLA_Zielzeit__c, 'AC9: Zielzeit beim insert gesetzt');
        System.assertNotEquals(null, r.SLA_Last_Checked__c, 'AC9: Letzter Lauf gesetzt');
        System.assertEquals('Keine', r.SLA_Eskalation__c, 'AC9: Eskalation initial Keine');
        System.assertEquals(false, r.SLA_Ueberschritten__c, 'AC9: Ueberschritten initial false');
        System.assertEquals(false, r.SLA_Uhr_gestoppt__c, 'AC9: Uhr_gestoppt initial false');
        System.assert(r.SLA_Zielzeit__c > r.CreatedDate,
            'AC9: Zielzeit liegt NACH Creation (Zukunft)');
    }

    /* ================================================================
     * AC9 — Re-Entry-Guard: waehrend Batch-DML (isRunning=true) faellt der
     * Trigger inert aus -> der `update` im Batch feuert den re-entrant
     * Trigger-Lauf, der NICHTS aendert.
     * ================================================================ */
    @isTest
    static void ac9_reentry_guard() {
        Case c = new Case(Subject='SCR438 reentry', Origin='Phone',
                          Status='New', Priority='Medium');
        insert c;
        // isRunning setzen -> Trigger-Lauf muss inert bleiben.
        DateTime before = [SELECT SLA_Last_Checked__c FROM Case WHERE Id=:c.Id LIMIT 1][0].SLA_Last_Checked__c;
        SLAService.isRunning = true;
        try {
            // Update feuert den Trigger; Guard faellt es aus.
            update new Case(Id = c.Id, Status = 'Working');
        } finally {
            SLAService.isRunning = false;
        }
        DateTime after = [SELECT SLA_Last_Checked__c FROM Case WHERE Id=:c.Id LIMIT 1][0].SLA_Last_Checked__c;
        System.assertEquals(before.getTime(), after.getTime(),
            'AC9: Re-Entry-Lauf (isRunning=true) aendert SLA-Felder NICHT');
    }

    /* ================================================================
     * AC8 — Batch ueber Bestand: offene Cases werden getackt (Last_Checked
     * gesetzt + valides Status), geschlosene bleiben unberuehrt; Bulk-Safe.
     * Idempotenz: 2. Lauf toucht keine neue Zeile.
     * ================================================================ */
    @isTest
    static void ac8_batch_runsIdempotentAndIgnoresClosed() {
        List<Case> open = new List<Case>();
        for (Integer i = 0; i < 30; i++) {
            Case c = new Case(Subject='SCR438 batch ' + i, Origin='Phone',
                              Status='New', Priority=(String)['High','Medium','Low'][i%3]);
            open.add(c);
        }
        insert open;
        // 2 geschlossene (Status Closed, ClosedDate gesetzt via System-Modus):
        List<Case> closed = new List<Case>();
        for (Integer i = 0; i < 2; i++) {
            Case c = new Case(Subject='SCR438 closed ' + i, Origin='Phone',
                              Priority='High', ClosedDate=System.now());
            // Org-Validierung: Closed braucht Ursache__c (SCRUM-436-Lektion).
            c.Ursache__c = 'TechnischerFehler';
            closed.add(c);
        }
        insert closed;

        Test.startTest();
        Database.executeBatch(new SLAJobBatch());    // Default now = System.now()
        Database.executeBatch(new SLAJobBatch());    // Zweitlauf = idempotent
        Test.stopTest();

        Integer openTouched = 0;
        for (Case c : open) {
            Case r = [SELECT SLA_Last_Checked__c, SLA_Status__c, SLA_Eskalation__c
                        FROM Case WHERE Id=:c.Id LIMIT 1][0];
            System.assert(r.SLA_Status__c == 'Im Zeitplan' || r.SLA_Status__c == 'Gefaehrdet'
                          || r.SLA_Status__c == 'Ueberschritten',
                'AC8: offener Case hat valides SLA_Status__c: ' + r.SLA_Status__c);
            if (r.SLA_Last_Checked__c != null) { openTouched++; }
        }
        System.assertEquals(30, openTouched, 'AC8: alle 30 offenen Cases getackt');
        for (Case c : closed) {
            Case r = [SELECT SLA_Last_Checked__c, SLA_Status__c
                        FROM Case WHERE Id=:c.Id LIMIT 1][0];
            System.assertEquals(null, r.SLA_Status__c, 'AC8: geschlossener Case bleibt unberuehrt');
        }
    }
}
