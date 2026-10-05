/**
 * [SCRUM-438] Apex-Test — SLA-Eskalation (Service-Kernlogik + Trigger +
 * Batch). Haus-Pattern SCRUM436CaseReminderTest / SCRUM432 / SCRUM424.
 *
 * ORG-AGNOSTISCH: die Test-Org-BH-Geometrie darf in keinem Test vorkommen.
 * Deshalb wird `now` ueber SLAService.estimateDeadline(basis, K) eingestimmt
 * — deren Inverse-Eigenschaft (diff(basis, estimateDeadline(basis, K)) == K)
 * wird in ac2_deadline_isExactInverseOfDiff ALLEIN ueber die Org-diff gepinnt.
 *
 * ZEIT-SIMULATION: Case.CreatedDate/ClosedDate sind in dieser Org NICHT
 * createable/updateable. Die Arbeitet-Uhr wird ueber das SETZBARE Custom-Feld
 * SLA_Last_Checked__c (Anker L) verankert:
 *   fresh(..., basis)  -> L = basis, A = 0
 *   evaluate(c, now)   -> worked = A + diff(L, now).
 *
 * FLS-DRUCK (Hard-Gate fls-gate Luecke C, SCRUM-432): alle funktionalen
 * DML/SOQL laufen unter System.runAs(u). u = Standard-User mit
 * SCRUM438_SLA_System (7/7 editierbares FLS) + SLA_System + SLA_Read.
 * Setup (User + PSA) ist AUSSERHALB vom runAs-Block (ein User kann sich
 * kein PSA selbst geben -> MIXED_DML). Der Batch (SLAJobBatch) laeuft
 * INNERHALB runAs — sein DML braucht das editierbare SLA-FLS.
 *
 * AC-Coverage:
 *   AC2  estimateDeadline ist die INVERSE von diff (1s-Praezision).
 *   AC3  Status: Im Zeitplan / Gefaehrdet / Ueberschritten (worked vs Ziel).
 *   AC4  Eskalation Stufe 1 -> Stufe 2, MONOTON (nie rueckstaendig).
 *   AC7  Priority-Wechsel: Zielzeit neu, bereits-Arbeitetes gewahrt.
 *   AC8  Batch ueber Bestand, Closed-Filter (ClosedDate = null).
 *   AC9  Reaktiver before-Trigger: initSLA bei insert + isRunning-Reentry.
 *   Config: Zielzeit-Tabelle (High/Med/Low x Premium) + Pause-Gate.
 *
 * @author developer-agent
 * @date 2026-10-04
 */
@isTest
private class SCRUM438SLATest {

    private static final String PS_SYSTEM = 'SCRUM438_SLA_System';
    private static final String PS_READ   = 'SCRUM438_SLA_Read';

    private static Id bh() {
        return SLAService.bhId();
    }

    // ============================ Test-Fabrik (FLS-Druck) ================= //

    /** Legt einen Standard-User an und weist ihm beide SLA-PS zu (Setup,
     *  AUSSE HALB vom runAs-Block — ein User kann sich kein PSA geben). */
    private static User slaUser(String alias) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(System.now().getTime()).substring(0, 8);
        User u = new User(
            ProfileId         = standard.Id,
            LastName          = 'Scr438 ' + alias,
            Alias             = alias.substring(0, Math.min(alias.length(), 8)),
            Email             = alias + sfx + '@scr438.invalid',
            Username          = alias + sfx + '@scr438.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'Europe/Berlin'
        );
        insert u;
        List<Id> psIds = new List<Id>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('SCRUM438_SLA_System','SCRUM438_SLA_Read')]) {
            psIds.add(ps.Id);
        }
        for (Id psId : psIds) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
        }
        return u;
    }

    private static DateTime at(Integer y, Integer mo, Integer d,
                               Integer h, Integer mi) {
        return DateTime.newInstance(y, mo, d, (h == null ? 0 : h),
                                    (mi == null ? 0 : mi), 0);
    }

    /**
     * Frischer, NICHT-insertierter Case-Literal fuer PURE Service-Tests
     * (0 DML, laeuft im System-Modus — kein Feld ist im Kontext).
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
     * Pure-Service-Test (0 DML, 0 SOQL) -> System-Modus, kein runAs noetig.
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
     * AC3 — Statusregeln, nur worked vs. Ziel (org-agnostisch via est()).
     * Pure-Service (0 DML) -> System-Modus.
     * ================================================================ */
    @isTest
    static void ac3_status_branches() {
        Id bh = bh();
        DateTime basis = at(2026, 10, 5, 9, 0);
        Integer target = SLAConfig.targetMinutes('High', false);   // 240

        Case a = fresh('High', 'Standard', basis);
        SLAService.evaluate(a,
             SLAService.estimateDeadline(bh, basis, 120), bh);
        System.assertEquals('Im Zeitplan', a.SLA_Status__c,
                            'AC3a: 50% = Im Zeitplan');
        System.assertEquals(false, a.SLA_Ueberschritten__c, 'AC3a: Flag false');

        Case b = fresh('High', 'Standard', basis);
        SLAService.evaluate(b, SLAService.estimateDeadline(bh, basis, 204), bh);
        System.assertEquals('Gefaehrdet', b.SLA_Status__c,
                            'AC3b: 15% = Gefaehrdet');
        System.assertEquals(false, b.SLA_Ueberschritten__c, 'AC3b: Flag noch false');

        Case cc = fresh('High', 'Standard', basis);
        SLAService.evaluate(cc,
             SLAService.estimateDeadline(bh, basis, target), bh);
        System.assertEquals('Ueberschritten', cc.SLA_Status__c,
                            'AC3c: 100% = Ueberschritten');
        System.assertEquals(true, cc.SLA_Ueberschritten__c, 'AC3c: Flag true');
    }

    /* ================================================================
     * AC4 — Eskalation: Stufe 1 bei Ueberschreitung, Stufe 2 nach +4h,
     * MONOTON. Pure-Service (0 DML) -> System-Modus.
     * ================================================================ */
    @isTest
    static void ac4_escalation_monotonic() {
        Id bh = bh();
        DateTime basis = at(2026, 10, 5, 9, 0);
        Integer target = SLAConfig.targetMinutes('High', false);   // 240

        Case a = fresh('High', 'Standard', basis);
        SLAService.evaluate(a, SLAService.estimateDeadline(bh, basis, 120), bh);
        System.assertEquals('Keine', a.SLA_Eskalation__c,
                            'AC4a: unter Ziel = Keine');

        Case b = fresh('High', 'Standard', basis);
        SLAService.evaluate(b,
             SLAService.estimateDeadline(bh, basis, target), bh);
        System.assertEquals('Stufe 1', b.SLA_Eskalation__c,
                            'AC4b: auf Ziel = Stufe 1');

        Case cc = fresh('High', 'Standard', basis);
        SLAService.evaluate(cc,
             SLAService.estimateDeadline(bh, basis,
                 target + SLAConfig.ESCALATION_LEVEL2_AFTER_MINUTES), bh);
        System.assertEquals('Stufe 2', cc.SLA_Eskalation__c,
                            'AC4c: +4h = Stufe 2');

        Case m = fresh('High', 'Standard', basis);
        m.SLA_Eskalation__c = 'Stufe 1';
        SLAService.evaluate(m, SLAService.estimateDeadline(bh, basis, 120), bh);
        System.assertEquals('Stufe 1', m.SLA_Eskalation__c,
            'AC4d: erreichte Stufe 1 bleibt (monoton, kein Rueckschritt)');
    }

    /* ================================================================
     * AC7 — Priority-Wechsel: Zielzeit neu, Arbeitetes gewahrt.
     * Pure-Service (0 DML) -> System-Modus.
     * ================================================================ */
    @isTest
    static void ac7_priority_change_carriesWorkedForward() {
        Id bh = bh();
        DateTime basis = at(2026, 10, 5, 9, 0);

        Case c = fresh('High', 'Standard', basis);
        DateTime t120 = SLAService.estimateDeadline(bh, basis, 120);
        SLAService.evaluate(c, t120, bh);
        System.assertEquals(120, c.SLA_Akkumulierte_WorkingMins__c.intValue(),
            'AC7 pre: High, 120 min gearbeit et');

        c.Priority = 'Low';
        DateTime t180 = SLAService.estimateDeadline(bh, t120, 60);
        SLAService.onPriorityChange(c, t180, bh);
        System.assertEquals(180, c.SLA_Akkumulierte_WorkingMins__c.intValue(),
            'AC7: 120 + 60 = 180 min bleibt gewahrt');

        Integer newTarget = SLAConfig.targetMinutes('Low', false);       // 1440
        Decimal remaining = SLAService.workedMins(bh, t180, c.SLA_Zielzeit__c);
        System.assertEquals(newTarget - 180, (Integer)remaining,
            'AC7: neue Zielzeit deckt rest ' + (newTarget - 180)
            + ' Werk-Min ab t180');
        System.assertEquals('Im Zeitplan', c.SLA_Status__c,
            'AC7: mit ' + (newTarget - 180) + ' min Puffer = Im Zeitplan');
    }

    /* ================================================================
     * Config — Zielzeit-Tabelle + Premium −25% + Pause-Gate. Pure (0 DML).
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

        System.assertEquals(false, SLAConfig.isPauseStatus('New'),     'New nicht Pause');
        System.assertEquals(false, SLAConfig.isPauseStatus('Working'), 'Working nicht Pause');
        System.assertEquals(false, SLAConfig.isPauseStatus(null),      'null nicht Pause');
    }

    /* ================================================================
     * AC9 — Reaktiver before-Trigger: neue offene Cases bekommen beim
     * insert Zielzeit + Status + Eskalation(Keine) + Letzter_Lauf.
     * Case-DML unter System.runAs(slaUser) — der trigger schreib t die
     * 7 SLA-Felder, der User muss editierbares FLS halten.
     * ================================================================ */
    @isTest
    static void ac9_trigger_initialisesOpenCase() {
        User u = slaUser('ac9init');
        System.runAs(u) {
            Case c = new Case(Subject = 'SCR438 trig', Origin = 'Phone',
                              Status = 'New', Priority = 'Medium');
            insert c;
            Case r = [SELECT Id, SLA_Zielzeit__c, SLA_Status__c,
                           SLA_Eskalation__c, SLA_Ueberschritten__c,
                           SLA_Last_Checked__c, SLA_Uhr_gestoppt__c,
                           SLA_Akkumulierte_WorkingMins__c, CreatedDate
                        FROM Case WHERE Id = :c.Id LIMIT 1][0];
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
    }

    /* ================================================================
     * AC9 — Re-Entry-Guard: waehrend Batch-DML (isRunning=true) faellt der
     * Trigger inert aus. Alle Case-DML unter runAs.
     * ================================================================ */
    @isTest
    static void ac9_reentry_guard() {
        User u = slaUser('ac9reent');
        Id caseId;
        DateTime before, after;

        System.runAs(u) {
            Case c = new Case(Subject = 'SCR438 reentry', Origin = 'Phone',
                              Status = 'New', Priority = 'Medium');
            insert c;
            caseId = c.Id;
            before = [SELECT SLA_Last_Checked__c FROM Case
                       WHERE Id = :caseId LIMIT 1][0].SLA_Last_Checked__c;
        }

        SLAService.isRunning = true;
        try {
            System.runAs(u) {
                update new Case(Id = caseId, Status = 'Working');
            }
        } finally {
            SLAService.isRunning = false;
        }

        System.runAs(u) {
            after = [SELECT SLA_Last_Checked__c FROM Case
                      WHERE Id = :caseId LIMIT 1][0].SLA_Last_Checked__c;
        }
        System.assertEquals(before.getTime(), after.getTime(),
            'AC9: Re-Entry-Lauf (isRunning=true) aendert SLA-Felder NICHT');
    }

    /* ================================================================
     * AC8 — Batch ueber Bestand: offene Cases werden getrackt,
     * geschlossene bleiben unberuehrt (Batch-Filter: ClosedDate = null).
     * Geschlossene Cases: Status='Closed' (ClosedDate wird auto-gesetzt,
     * ist NICHT setzbar — create/update=false, verifiziert via Probe).
     * Bulk-Test: 30 offen + 2 geschlossen.
     *
     * SLA-Status-Field (Default 'Im Zeitplan', field-meta.xml <default>)
     * fuet JEDEN insert — es ist KEIN Taugliches Kriterium fuer
     * "Engine-inaktiv". "Nicht getrackt" heisst: die von der ENGINE
     * verwalteten Felder (Zielzeit, Letzter_Lauf, Akkumulierte) sind NULL.
     * ================================================================ */
    @isTest
    static void ac8_batch_runsAndIgnoresClosed() {
        // SYSTEM-MODUS (SCRUM-436-Hausmuster, s. SCRUM436CaseReminderTest
        // Zeilen 60-68 + plantCase): das Batch ist ein Scheduled-Job und
        // laeuft unter dem Scheduler (volle FLS). `without sharing` im
        // Batch-SELECT umgeht NUR Sharing, NICHT FLS — der Scheduler haelt
        // die 7 SLA-Felder + Kundenstatus__c. Der runAs-FLS-Druck lebt in
        // AC9 (Trigger-Pfad). Deshalb hier: beide Inserts + Batch in
        // System-Modus (kein runAs-User — der haette weder Kundenstatus-FLS
        // fuers Batch-SELECT noch Ursache-FLS, das SCRUM-434-ValRule-Feld).
        String[] prs = new String[]{'High','Medium','Low'};
        List<Case> open = new List<Case>();
        for (Integer i = 0; i < 30; i++) {
            open.add(new Case(Subject = 'SCR438 batch ' + i, Origin = 'Phone',
                              Status = 'New', Priority = prs[Math.mod(i, 3)]));
        }
        List<Case> closed = new List<Case>();
        for (Integer i = 0; i < 2; i++) {
            // Ursache__c PFLICHT bei geschlossenen Faellen (SCRUM-434
            // UrsachepflichtBeiGeschlossen, hart: ohne Ursache kein Insert —
            // FIELD_CUSTOM_VALIDATION_EXCEPTION). Wert = picklist-valid,
            // wie im urspruenglichen 9/9-Run (9e5abe0).
            closed.add(new Case(
                Subject  = 'SCR438 closed ' + i,
                Origin   = 'Phone',
                Priority = 'High',
                Status   = 'Closed',
                Ursache__c = 'HowToAnfrage'));
        }

        insert open;
        insert closed;

        Test.startTest();
        Database.executeBatch(new SLAJobBatch());
        Test.stopTest();

        Integer openValid = 0;
        for (Case c : open) {
            Case r = [SELECT SLA_Last_Checked__c, SLA_Status__c
                       FROM Case WHERE Id = :c.Id LIMIT 1][0];
            System.assert(r.SLA_Status__c == 'Im Zeitplan'
                         || r.SLA_Status__c == 'Gefaehrdet'
                         || r.SLA_Status__c == 'Ueberschritten',
                'AC8: offener Case hat valides SLA_Status__c: ' + r.SLA_Status__c);
            if (r.SLA_Last_Checked__c != null) { openValid++; }
        }
        System.assertEquals(30, openValid,
            'AC8: alle 30 offenen Cases getrackt');

        for (Case c : closed) {
            Case r = [SELECT SLA_Zielzeit__c, SLA_Last_Checked__c,
                               SLA_Akkumulierte_WorkingMins__c
                       FROM Case WHERE Id = :c.Id LIMIT 1][0];
            System.assertEquals(null, r.SLA_Zielzeit__c,
                'AC8: geschlossener Case hat KEINE Zielzeit (Engine inaktiv)');
            System.assertEquals(null, r.SLA_Last_Checked__c,
                'AC8: geschlossener Case hat KEINEN Letzter_Lauf (Engine inaktiv)');
        }
    }
}
