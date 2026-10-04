/**
 * [SCRUM-438] Apex-Test — SLA-Eskalation (Service-Kernlogik + Trigger +
 * Batch). Haus-Pattern SCRUM436CaseReminderTest / SCRUM432.
 *
 * ORG-AGNOSTISCH (Memory-Lektion: nichts hartcoden): die Test-Org-BH-
 * Geometrie darf in keinem Test vorkommen. Deshalb wird `now` ueber
 * SLAService.estimateDeadline(basis, K) eingestimmt — deren Invers-
 * Eigenschaft (diff(basis, estimateDeadline(basis, K)) == K) wird in
 * ac2_deadline_isExactInverseOfDiff ALLEIN ueber die Org-diff gepinnt.
 *
 * ZEIT-SIMULATION: Case.CreatedDate/ClosedDate sind in dieser Org NICHT
 * createable/updateable (beschrieben: create=false, update=false). Man
 * kann also weder zurueckdatieren noch geschlossene Records bauen.
 * Stattdessen wird die arbeite-Uhr ueber das SETZBARE Custom-Feld
 * SLA_Last_Checked__c (der Anker L) verankert:
 *   fresh(..., basis)   -> L = basis, A = 0
 *   evaluate(c, now)    -> worked = A + diff(L, now) = diff(basis, now).
 *   evaluate(c, estimateDeadline(bh, basis, K))  ->  worked = K, exakt,
 *                                                  Geometrie-unabhaengig.
 *
 * AC-Coverage:
 *   AC2  estimateDeadline ist die INVERSE von diff (1s-Praezision).
 *   AC3  Status: Im Zeitplan / Gefaehrdet / Ueberschritten (worked vs Ziel).
 *   AC4  Eskalation Stufe 1 -> Stufe 2, MONOTON (nie rueckstaendig).
 *   AC7  Priority-Wechsel: Zielzeit neu, bereits-Arbeitetes gewahrt.
 *   AC8  Batch ueber Bestand, Closed-Filter (ISNULL(ClosedDate)).
 *   AC9  Reaktiver before-Trigger: initSLA bei insert + isRunning-Reentry.
 *   Config: Zielzeit-Tabelle (High/Med/Low x Premium) + Pause-Gate.
 *   FLS  => SCRUM438SLAFlsTest (separate Klasse, System.runAs-Modus).
 *
 * @author developer-agent
 * @date 2026-10-04
 */
@isTest
private class SCRUM438SLATest {

    private static Id bh() {
        return SLAService.bhId();
    }

    private static DateTime at(Integer y, Integer mo, Integer d,
                               Integer h, Integer mi) {
        return DateTime.newInstance(y, mo, d, (h == null ? 0 : h),
                                    (mi == null ? 0 : mi), 0);
    }

    /**
     * Frischer, NICHT-insertierter Case-Literal fuer PURE Service-Tests
     * (0 DML). Der Anker L = SLA_Last_Checked__c wird auf `basis` gesetzt,
     * die akkumulierte Uhr A=0; CreatedDate/ClosedDate sind in dieser Org
     * nicht setzbar und bleiben hier bewusst leer.
     */
    private static Case fresh(String priority, String kundenstatus,
                              DateTime basis) {
        return new Case(Subject = 'SCR438 unit', Origin = 'Phone',
                        Status = 'New',
                        Priority = priority,
                        Kundenstatus__c = kundenstatus,
                        SLA_Last_Checked__c = basis,
                        SLA_Akkumulierte_WorkingMins__c = 0);
    }

    /* ================================================================
     * AC2 — estimateDeadline ist die INVERSE von workedMins/diff:
     *   diff(basis, est(basis, K)) == K  (1s-Praezision, Binary-Search).
     * Zeigt, dass die ADR-3 add-defekt-Ausweichfunktion (Binary-Search ueber
     * diff) exakt K Werk-Min liefert — unabhaengig von der Org-Geometrie.
     * ================================================================ */
    @isTest
    static void ac2_deadline_isExactInverseOfDiff() {
        Id bh = bh();
        DateTime basis = at(2026, 10, 5, 9, 0);   // ein Montag
        Integer[] probed = new Integer[]{30, 240, 480, 2040};
        for (Integer k : probed) {
            DateTime d = SLAService.estimateDeadline(bh, basis, k);
            Decimal back = SLAService.workedMins(bh, basis, d);
            System.assert(back.doubleValue() >= (k - 1)
                          && back.doubleValue() <= (k + 1),
                'AC2: est(basis,' + k + ') -> ' + back
                + ' Werk-Min, erwartet ~' + k);
        }
    }

    /* ================================================================
     * AC3 — Statusregeln, nur worked vs. Ziel (org-agnostik via est()):
     *   50 % uebrig -> Im Zeitplan
     *   15 % uebrig -> Gefaehrdet   (< 20 %)
     *   0  uebrig   -> Ueberschritten (+ Flag true)
     * ================================================================ */
    @isTest
    static void ac3_status_branches() {
        Id bh = bh();
        DateTime basis = at(2026, 10, 5, 9, 0);
        Integer target = SLAConfig.targetMinutes('High', false);   // 240

        // (a) worked = 120 (= 50 % von 240) -> 50 % uebrig -> Im Zeitplan.
        Case a = fresh('High', 'Standard', basis);
        SLAService.evaluate(a,
             SLAService.estimateDeadline(bh, basis, 120), bh);
        System.assertEquals('Im Zeitplan', a.SLA_Status__c,
                            'AC3a: 50% = Im Zeitplan');
        System.assertEquals(false, a.SLA_Ueberschritten__c, 'AC3a: Flag false');

        // (b) worked = 204 (= 85 % von 240) -> 15 % uebrig -> Gefaehrdet.
        Case b = fresh('High', 'Standard', basis);
        SLAService.evaluate(b, SLAService.estimateDeadline(bh, basis, 204), bh);
        System.assertEquals('Gefaehrdet', b.SLA_Status__c, 'AC3b: 15% = Gefaehrdet');
        System.assertEquals(false, b.SLA_Ueberschritten__c, 'AC3b: Flag noch false');

        // (c) worked = target (100 %) -> Ueberschritten + Flag true.
        Case cc = fresh('High', 'Standard', basis);
        SLAService.evaluate(cc,
             SLAService.estimateDeadline(bh, basis, target), bh);
        System.assertEquals('Ueberschritten', cc.SLA_Status__c,
                            'AC3c: 100% = Ueberschritten');
        System.assertEquals(true, cc.SLA_Ueberschritten__c, 'AC3c: Flag true');
    }

    /* ================================================================
     * AC4 — Eskalation: Stufe 1 bei Ueberschreitung, Stufe 2 nach +4h,
     * MONOTON: erreichte Stufe sinkt NICHT wieder (Pause-Fall konstruktiv).
     * ================================================================ */
    @isTest
    static void ac4_escalation_monotonic() {
        Id bh = bh();
        DateTime basis = at(2026, 10, 5, 9, 0);
        Integer target = SLAConfig.targetMinutes('High', false);   // 240

        // unter Ziel (K=120) -> Keine.
        Case a = fresh('High', 'Standard', basis);
        SLAService.evaluate(a, SLAService.estimateDeadline(bh, basis, 120), bh);
        System.assertEquals('Keine', a.SLA_Eskalation__c,
                            'AC4a: unter Ziel = Keine');

        // auf Ziel (K=240) -> Stufe 1.
        Case b = fresh('High', 'Standard', basis);
        SLAService.evaluate(b,
             SLAService.estimateDeadline(bh, basis, target), bh);
        System.assertEquals('Stufe 1', b.SLA_Eskalation__c,
                            'AC4b: auf Ziel = Stufe 1');

        // Ziel + 240 -> Stufe 2.
        Case cc = fresh('High', 'Standard', basis);
        SLAService.evaluate(cc,
             SLAService.estimateDeadline(bh, basis,
                 target + SLAConfig.ESCALATION_LEVEL2_AFTER_MINUTES), bh);
        System.assertEquals('Stufe 2', cc.SLA_Eskalation__c,
                            'AC4c: +4h = Stufe 2');

        // MONOTONITÄT: erreichte Stufe 1, neu bewertet mit frueherer Clock
        // (worked = 120 < Ziel 240) -> darf NICHT auf "Keine" fallen.
        Case m = fresh('High', 'Standard', basis);
        m.SLA_Eskalation__c = 'Stufe 1';
        SLAService.evaluate(m, SLAService.estimateDeadline(bh, basis, 120), bh);
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
        DateTime basis = at(2026, 10, 5, 9, 0);

        // Phase 1: High, K=120 Werk-Min (t120).
        Case c = fresh('High', 'Standard', basis);
        DateTime t120 = SLAService.estimateDeadline(bh, basis, 120);
        SLAService.evaluate(c, t120, bh);
        System.assertEquals(120, c.SLA_Akkumulierte_WorkingMins__c.intValue(),
            'AC7 pre: High, 120 min gearbeitet');

        // Phase 2: auf Low (Ziel 1440) wechseln, +60 min (t180).
        c.Priority = 'Low';
        DateTime t180 = SLAService.estimateDeadline(bh, t120, 60);
        SLAService.onPriorityChange(c, t180, bh);
        System.assertEquals(180, c.SLA_Akkumulierte_WorkingMins__c.intValue(),
            'AC7: 120 + 60 = 180 min bleibt gewahrt');

        // Neue Zielzeit = rest = 1440 - 180 = 1260 ab t180. Inverse ueber
        // Org-diff pruefen (org-agnostisch):
        Integer newTarget = SLAConfig.targetMinutes('Low', false);       // 1440
        Decimal remaining = SLAService.workedMins(bh, t180, c.SLA_Zielzeit__c);
        System.assertEquals(newTarget - 180, (Integer)remaining,
            'AC7: neue Zielzeit deckt rest ' + (newTarget - 180)
            + ' Werk-Min ab t180');
        System.assertEquals('Im Zeitplan', c.SLA_Status__c,
            'AC7: mit ' + (newTarget - 180) + ' min Puffer = Im Zeitplan');
    }

    /* ================================================================
     * Config — Zielzeit-Tabelle (PO/ADR-7) + Premium −25 % + Pause-Gate.
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
        System.assertEquals(480,  SLAConfig.targetMinutes(null,     false), 'null -> Medium Default');
        System.assertEquals(480,  SLAConfig.targetMinutes('Bogus',  false), 'Bogus -> Medium Default');

        // Pause-Gate (ADR-4): leer -> nichts gepauset; null safe.
        System.assertEquals(false, SLAConfig.isPauseStatus('New'),     'New nicht Pause');
        System.assertEquals(false, SLAConfig.isPauseStatus('Working'), 'Working nicht Pause');
        System.assertEquals(false, SLAConfig.isPauseStatus(null),      'null nicht Pause');
    }

    /* ================================================================
     * AC9 — Reaktiver before-Trigger: neue offene Cases bekommen beim
     * insert Zielzeit + Status + Eskalation(Keine) + Letzter_Lauf;
     * Uhr_gestoppt initial false. (Real CreatedDate=now -> worked~0.)
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
        System.assertNotEquals(null, r.SLA_Zielzeit__c,
            'AC9: Zielzeit beim insert gesetzt');
        System.assertNotEquals(null, r.SLA_Last_Checked__c,
            'AC9: Letzter Lauf gesetzt');
        System.assertEquals('Keine', r.SLA_Eskalation__c,
            'AC9: Eskalation initial Keine');
        System.assertEquals(false, r.SLA_Ueberschritten__c,
            'AC9: Ueberschritten initial false');
        System.assertEquals(false, r.SLA_Uhr_gestoppt__c,
            'AC9: Uhr_gestoppt initial false');
        System.assert(r.SLA_Zielzeit__c > r.CreatedDate,
            'AC9: Zielzeit liegt NACH Creation (Zukunft)');
    }

    /* ================================================================
     * AC9 — Re-Entry-Guard: waehrend Batch-DML (isRunning=true) faellt der
     * Trigger inert aus -> der re-entrant `update` aendert KEIN SLA-Feld.
     * ================================================================ */
    @isTest
    static void ac9_reentry_guard() {
        Case c = new Case(Subject='SCR438 reentry', Origin='Phone',
                          Status='New', Priority='Medium');
        insert c;
        DateTime before = [SELECT SLA_Last_Checked__c FROM Case
                            WHERE Id=:c.Id LIMIT 1][0].SLA_Last_Checked__c;
        SLAService.isRunning = true;
        try {
            update new Case(Id = c.Id, Status = 'Working');   // feuert Trigger
        } finally {
            SLAService.isRunning = false;
        }
        DateTime after = [SELECT SLA_Last_Checked__c FROM Case
                           WHERE Id=:c.Id LIMIT 1][0].SLA_Last_Checked__c;
        System.assertEquals(before.getTime(), after.getTime(),
            'AC9: Re-Entry-Lauf (isRunning=true) aendert SLA-Felder NICHT');
    }

    /* ================================================================
     * AC8 — Batch ueber Bestand: offene Cases werden getackt (valides
     * SLA_Status__c + Letzter_Lauf), geschlossene bleiben unberuehrt
     * (Batch-Filter: WHERE ISNULL(ClosedDate) = "Offen"). Geschlossen via
     * Status='Closed' + Ursache__c; ClosedDate wird dabei auto-gesetzt und
     * ist NICHT setzbar (create/update=false) -> Batch-Filter ISNULL(ClosedDate)
     * slaesst sie aus. Bulk-Safe ueber 30+2 Cases.
     * ================================================================ */
    @isTest
    static void ac8_batch_runsAndIgnoresClosed() {
        String[] prs = new String[]{'High','Medium','Low'};
        List<Case> open = new List<Case>();
        for (Integer i = 0; i < 30; i++) {
            open.add(new Case(Subject='SCR438 batch ' + i, Origin='Phone',
                              Status='New', Priority=prs[Math.mod(i, 3)]));
        }
        insert open;

        // 2 geschlossene: Status='Closed' + Ursache (SCRUM-418-Hausmuster).
        // ClosedDate wird dabei auto-gesetzt -> Batch-Filter ISNULL(ClosedDate)
        // slaesst sie aus.
        List<Case> closed = new List<Case>();
        for (Integer i = 0; i < 2; i++) {
            Case c = new Case(Subject='SCR438 closed ' + i, Origin='Phone',
                              Priority='High',
                              Status='Closed',
                              Ursache__c='HowToAnfrage');
            closed.add(c);
        }
        insert closed;

        Test.startTest();
        Database.executeBatch(new SLAJobBatch());   // 1. Lauf (now=System.now())
        Test.stopTest();

        Integer openValid = 0;
        for (Case c : open) {
            Case r = [SELECT SLA_Last_Checked__c, SLA_Status__c
                        FROM Case WHERE Id=:c.Id LIMIT 1][0];
            System.assert(r.SLA_Status__c == 'Im Zeitplan'
                         || r.SLA_Status__c == 'Gefaehrdet'
                         || r.SLA_Status__c == 'Ueberschritten',
                'AC8: offener Case hat valides SLA_Status__c: ' + r.SLA_Status__c);
            if (r.SLA_Last_Checked__c != null) { openValid++; }
        }
        System.assertEquals(30, openValid, 'AC8: alle 30 offenen Cases getackt');
        // Geschlossene Cases: der ENGINE-Kern hat sie NICHT angefasst.
        // ACHTUNG: SLA_Status__c tragt einen Picklist-Default ('Im Zeitplan',
        // field-meta.xml <default>true) -> wird bei JEDEM insert gefuellt,
        // unabhaengig von der Engine. "Nicht getackert" heisst deshalb:
        // die von der Engine verwalteten Felder (Zielzeit, Letzter_Lauf)
        // sind NULL. SLA_Status allein ist KEIN Taugliches Kriterium hier.
        for (Case c : closed) {
            Case r = [SELECT SLA_Zielzeit__c, SLA_Last_Checked__c,
                           SLA_Akkumulierte_WorkingMins__c
                       FROM Case WHERE Id=:c.Id LIMIT 1][0];
            System.assertEquals(null, r.SLA_Zielzeit__c,
                'AC8: geschlossener Case hat KEINE Zielzeit (Engine inaktiv)');
            System.assertEquals(null, r.SLA_Last_Checked__c,
                'AC8: geschlossener Case hat KEINEN Letzter_Lauf (Engine inaktiv)');
        }
    }
}
