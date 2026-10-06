/**
 * [SCRUM-438] S3/S4 — Pause / Resume der SLA-Uhr (neu, dieser Zyklus).
 *
 * Testet die PAUSE-LOGIK in SLAService.evaluate() (pure, KEINE DML, bh
 * injiziert) mit dem Picklist-Wert 'Warten auf Kunde', der in diesem Zyklus
 * nach SLAConfig.PAUSE_STATUSES eingetragen wurde.
 *
 * WARUM Unit-Level (nicht End-to-End): Die Org haelt den Wert 'Warten auf
 * Kunde' in Case.Status (Standard-Picklist, custom=False) NICHT — es gibt
 * keinen Metadata-Pfad, ihn anzulegen (Org-Setup, DevOps). Ein realer Case kann
 * den Status deshalb in UI/SOQL nicht haben. Die Pause-Logik ist aber reine
 * Funktion des Status-Strings (SLAConfig.isPauseStatus) und laesst sich direkt
 * auf einem in-memory-Case belegen — before-insert-Semantik, keine Picklist-
 * Validierung. Damit ist die CODE-Logik von S3/S4 verifiziert; die End-to-End-
 * Abdeckung (realer Case im Status) ist am Org-Picklist-Setup gebunden.
 *
 * Belegte Eigenschaften:
 *   S3 (Pause):  A (SLA_Akkumulierte_WorkingMins__c) bleibt gefroren, selbst
 *                wenn echte Arbeitzeit seit dem letzten Anker vergangen ist;
 *                SLA_Uhr_gestoppt__c=true, Anker SLA_Last_Checked__c läuft auf now.
 *   S4 (Resume): Nach dem Verlassen der Pause läuft A weiter — aber nur um die
 *                Arbeitzeit ZWISCHEN Pause-Ende (Anker) und now. Die Pause wird
 *                NICHT gebucht.
 *   PO-Regel:    Erreichte Eskalationsstufe bleibt in der Pause bestehen (A ist
 *                gefroren, worked fällt nicht unter target -> kein Reset).
 *
 * @author tester-agent
 * @date 2026-10-06
 */
@IsTest
private class SCRUM438SLAPauseTest {

    /** 1 Query: Default-BusinessHours-Id der Org (deterministischer BH-Bezug). */
    private static Id bh() {
        return [SELECT Id FROM BusinessHours LIMIT 1].Id;
    }

    /** Basis-Case: A=60 min, Anker 3h zurück, High/Standard (target 240). */
    private static Case baseCase(String status, DateTime anchor) {
        return new Case(
            Status                        = status,
            Priority                      = 'High',
            Kundenstatus__c               = 'Standard',
            SLA_Akkumulierte_WorkingMins__c = 60,
            SLA_Last_Checked__c           = anchor,
            SLA_Zielzeit__c               = anchor.addHours(4),
            SLA_Eskalation__c             = 'Keine',
            SLA_Status__c                 = 'Im Zeitplan',
            SLA_Ueberschritten__c         = false,
            SLA_Uhr_gestoppt__c           = false
        );
    }

    /**
     * S3 — Die Uhr friert, solange der Case im Pause-Status liegt.
     * A bleibt 60, obwohl (an-)3h reale Zeit seit dem Anker vergangen sind.
     */
    @IsTest
    static void s3_pause_freezesClock() {
        Id b = bh();
        DateTime now   = DateTime.newInstance(2026, 10, 5, 14, 0, 0);  // Do 14:00 (Workzeit)
        DateTime anchor = now.addHours(-3);                              // Do 11:00

        Case c = baseCase('Warten auf Kunde', anchor);
        SLAService.evaluate(c, now, b);

        System.assertEquals(true,  c.SLA_Uhr_gestoppt__c,
            'S3: SLA_Uhr_gestoppt__c muss true sein im Pause-Status.');
        System.assertEquals(60, c.SLA_Akkumulierte_WorkingMins__c.doubleValue(),
            'S3: A muss GEFROREN bleiben (Pause bucht keine Zeit).');
        System.assertEquals(now.getTime(), c.SLA_Last_Checked__c.getTime(),
            'S3: Anker muss auf now laufen (Pause-Ende merken).');
        // worked = A = 60 < target 240 -> nicht ueberschritten, Im Zeitplan.
        System.assertEquals(false, c.SLA_Ueberschritten__c,
            'S3: 60 < 240 darf nicht ueberschritten sein.');
    }

    /**
     * S4 — Nach Resume läuft die Uhr; die Pause-Zeit wird NICHT gebucht.
     * A nach Resume = 60 + Arbeitzeit(Pause-Ende .. now2), NICHT
     * 60 + Arbeitzeit(ursprünglicher Anker .. now2).
     */
    @IsTest
    static void s3s4_pauseThenResume_frozenTimeNotBilled() {
        Id b  = bh();
        DateTime pauseStart = DateTime.newInstance(2026, 10, 5, 10, 0, 0); // Do 10:00
        DateTime pauseEnd   = DateTime.newInstance(2026, 10, 5, 12, 0, 0); // Do 12:00
        DateTime resumeNow  = DateTime.newInstance(2026, 10, 5, 14, 0, 0); // Do 14:00

        // Phase 1: Pause (10:00 -> 12:00, 2h Arbeitzeit liegen DAZWISCHEN).
        Case c = baseCase('Warten auf Kunde', pauseStart);
        SLAService.evaluate(c, pauseEnd, b);
        System.assertEquals(60, c.SLA_Akkumulierte_WorkingMins__c.doubleValue(),
            'S3: A gefroren während Pause (10:00-12:00 nicht gebucht).');

        // Phase 2: Resume (Status Working), Bewertung bei 14:00.
        c.Status = 'Working';
        SLAService.evaluate(c, resumeNow, b);

        // Erwarteter Zuwachs: NUR 12:00 -> 14:00 (2h Work), NICHT 10:00 -> 14:00.
        Decimal expectIncrement = SLAService.workedMins(b, pauseEnd, resumeNow);
        Decimal expectA = 60 + expectIncrement;

        System.assertEquals(false, c.SLA_Uhr_gestoppt__c,
            'S4: Uhr läuft wieder nach Resume.');
        System.assertEquals(expectA.doubleValue(),
            (c.SLA_Akkumulierte_WorkingMins__c).doubleValue(),
            'S4: A = 60 + Arbeitzeit(Pause-Ende..now); Pause-Zeit nicht gebucht.');
        System.assertEquals(resumeNow.getTime(), c.SLA_Last_Checked__c.getTime(),
            'S4: Anker auf now (Resume-Bewertung).');
    }

    /**
     * PO-Regel — Erreichte Eskalationsstufe bleibt in der Pause bestehen.
     * Case bereits auf Stufe 1 (worked >= target) -> in der Pause nicht auf 'Keine'.
     */
    @IsTest
    static void s3_escalationPreservedDuringPause() {
        Id b  = bh();
        DateTime now   = DateTime.newInstance(2026, 10, 5, 15, 0, 0);
        DateTime anchor = now.addHours(-2);

        // A = target (240) -> Stufe 1 erreicht.
        Case c = baseCase('Working', anchor);
        c.SLA_Akkumulierte_WorkingMins__c = 240;
        c.SLA_Eskalation__c = 'Stufe 1';
        SLAService.evaluate(c, now, b);   // normale Bewertung -> bleibt Stufe 1.
        System.assertEquals('Stufe 1', c.SLA_Eskalation__c, 'Vor-Pause Vorbedingung Stufe 1.');

        // Jetzt Pause: A bleibt 240 (>= target) -> Eskalation darf nicht fallen.
        c.Status = 'Warten auf Kunde';
        DateTime pauseNow = now.addHours(2);
        SLAService.evaluate(c, pauseNow, b);

        System.assertEquals('Stufe 1', c.SLA_Eskalation__c,
            'PO-Regel: erreichte Stufe 1 bleibt in der Pause bestehen (kein Reset).');
        System.assertEquals(true, c.SLA_Uhr_gestoppt__c, 'Pause wirksam.');
    }
}
