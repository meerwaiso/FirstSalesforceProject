/**
 * [SCRUM-438] Kern-Logik der SLA-Eskalation — EINE Quelle, von Batch UND
 * reaktivem before-Trigger aufgerufen (AC8: keine Logik-Duplikation).
 *
 * Pure static methods, KEINE DML (DML bleibt im Batch / before-Trigger-
 * Feldersetzung auf Trigger.new). `now` und `bh` (BusinessHours-Id) werden
 * als Parameter injiziert -> deterministische Tests (house SCRUM-436) und
 * EINE SOQL pro Trigger-/Batch-Lauf statt pro Row (Governor).
 *
 * ARBEITETE-UHR (gefroren bei Pause), geometry-unabhaengig (ADR-4):
 *   A = SLA_Akkumulierte_WorkingMins__c (gefrorene gearbeitet-Min)
 *   L = SLA_Last_Checked__c  (Anker, laeuft IMMER auf now, auch in Pause)
 *   Pause:   worked = A (gefroren); L := now  (Pause-Ende merken).
 *   no Pause: worked = A + diff(L, now); A := worked; L := now.
 * Pause-Korrektur ist damit exakt in MINUTEN (auch ueber Nacht/Wochenende),
 * weil nur BusinessHours.diff vorkommt und dasselbe Set beide Male liest.
 *
 * BELEGTES BH-VERHALTEN (Probe 2026-10-04, Test-Org):
 *  - diff(start,end) CLAMPT start auf das naechste Fenster (Case um 08:00
 *    zahlt ab 09:00, wie um 05:00/00:00) -> Deadline von CreatedDate aus
 *    korrekt, unabhaengig ob Creation im/ausserhalb des Fensters.
 *  - add(...) ist DEF EKT (liefert Fensterstart); NIEMALS verwenden.
 *  => Status/Eskalation brauchen KEINEN absoluten DateTime — nur
 *     worked-Min vs. Ziel-Min; Deadline = estimateDeadline (Binary-Search
 *     ueber diff, monoton, 1s-Praezision).
 *
 * Eskalation ist MONOTON (worked nie fallend, Pause friert): Stufe sinkt
 * nie -> PO-Regel "Eskalationsstufe bleibt bei Pause" konstruktiv.
 *
 * @author developer-agent
 * @date 2026-10-04
 */
public without sharing class SLAService {

    // Re-Entry-Guard (house SCRUM-436/419): um einen `update` (Batch) oder
    // eine Trigger-Modifikation gesetzt -> der re-entrant Trigger-Lauf faellt
    // aus. Pfad-agnostisch.
    @testVisible
    public static Boolean isRunning = false;

    private SLAService() {}

    // ===================== Wrappers (1 SOQL bhId-Call) =================== //


    /** Batch-Pfad: bhId einmal im Batch holen wird empfohlen; hier Fallback. */
    public static void evaluate(Case c, DateTime now) {
        evaluate(c, now, bhId());
    }

    public static void onPriorityChange(Case c, DateTime now) {
        onPriorityChange(c, now, bhId());
    }

    public static void initSLA(Case c, DateTime now) {
        initSLA(c, now, bhId());
    }

    // ======================= Kern-Methoden (bh injiziert) ================ //

    /**
     * Vollstaendige Bewertung EINES offenen Cases. Setzt: Akkumulierte_
     * WorkingMins, Last_Checked, Uhr_gestoppt, Status, Eskalation,
     * Ueberschritten (Zielzeit bleibt stabil, ausser Legacy-Nachbestueck).
     * Monoton.
     */
    public static void evaluate(Case c, DateTime now, Id bh) {
        if (c == null || now == null) { return; }
        Boolean inPause = SLAConfig.isPauseStatus(c.Status);
        c.SLA_Uhr_gestoppt__c = inPause;

        Integer  target = SLAConfig.targetMinutes(c.Priority,
                                    c.Kundenstatus__c == 'Premium');
        Decimal  A  = (c.SLA_Akkumulierte_WorkingMins__c == null)
                               ? 0 : c.SLA_Akkumulierte_WorkingMins__c;
        DateTime L    = c.SLA_Last_Checked__c;
        DateTime from = (c.CreatedDate == null) ? now : c.CreatedDate;

        Decimal worked;
        if (L == null) {
            // Bootstrap (Legacy ohne Anker): ganze Zeit seit Creation.
            worked = inPause ? A : workedMins(bh, from, now);
            c.SLA_Akkumulierte_WorkingMins__c = worked;
            c.SLA_Last_Checked__c             = now;
            if (c.SLA_Zielzeit__c == null) {
                c.SLA_Zielzeit__c = estimateDeadline(bh, from, target);
            }
        } else if (inPause) {
            // Pause: gefroren, Anker laeuft auf jetzt; Zielzeit STABIL.
            c.SLA_Akkumulierte_WorkingMins__c = A;
            c.SLA_Last_Checked__c             = now;
            worked = A;
        } else {
            // Normal: Anker vorwaerts, gearbeitet = A + diff(L, now).
            worked = A + workedMins(bh, L, now);
            c.SLA_Akkumulierte_WorkingMins__c = worked;
            c.SLA_Last_Checked__c = now;
            // Zielzeit bleibt stabil; nur Legacy mit Anker aber ohne
            // Zielzeit nachbestuecken.
            if (c.SLA_Zielzeit__c == null) {
                Integer rem = (Integer)Math.floor(target.doubleValue()
                                          - worked.doubleValue());
                if (rem < 0) { rem = 0; }
                c.SLA_Zielzeit__c = estimateDeadline(bh, L, rem);
            }
        }

        setStatus(c, target, worked);
        setEscalation(c, target, worked);
    }

    /**
     * Priority- / Kundenstatus-Wechsel (AC7): neue Ziel-Minuten gelten,
     * BEREITS ARBEITETE bleiben gewahrt -> Zielzeit = estimate(now, rest).
     */
    public static void onPriorityChange(Case c, DateTime now, Id bh) {
        if (c == null || now == null) { return; }
        Integer newTarget = SLAConfig.targetMinutes(c.Priority,
                                    c.Kundenstatus__c == 'Premium');
        Decimal  A  = (c.SLA_Akkumulierte_WorkingMins__c == null)
                               ? 0 : c.SLA_Akkumulierte_WorkingMins__c;
        DateTime L    = c.SLA_Last_Checked__c;
        DateTime from = (c.CreatedDate == null) ? now : c.CreatedDate;

        Decimal worked;
        if (L == null) {
            worked = workedMins(bh, from, now);
            c.SLA_Akkumulierte_WorkingMins__c = worked;
            c.SLA_Last_Checked__c = now;
        } else {
            worked = A + workedMins(bh, L, now);
            c.SLA_Akkumulierte_WorkingMins__c = worked;
            c.SLA_Last_Checked__c = now;
        }
        c.SLA_Uhr_gestoppt__c = SLAConfig.isPauseStatus(c.Status);

        Integer remaining = newTarget - (Integer)Math.floor(worked.doubleValue());
        if (remaining < 0) { remaining = 0; }
        c.SLA_Zielzeit__c = estimateDeadline(bh, now, remaining);
        setStatus(c, newTarget, worked);
        setEscalation(c, newTarget, worked);
    }

    /**
     * Vor dem Insert (before-insert, 0 DML): Zielzeit + Status + Anker
     * auf dem neuen Record setzen; der Insert traegt sie dann mit.
     */
    public static void initSLA(Case c, DateTime now, Id bh) {
        if (c == null || now == null) { return; }
        Integer target = SLAConfig.targetMinutes(c.Priority,
                                c.Kundenstatus__c == 'Premium');
        DateTime from = (c.CreatedDate == null) ? now : c.CreatedDate;
        c.SLA_Akkumulierte_WorkingMins__c = 0;
        c.SLA_Last_Checked__c             = now;
        c.SLA_Uhr_gestoppt__c             = SLAConfig.isPauseStatus(c.Status);
        c.SLA_Zielzeit__c                 = estimateDeadline(bh, from, target);
        setStatus(c, target, 0);
        setEscalation(c, target, 0);
    }

    // ================ Statusregeln (PO-AC3/AC4), nur worked vs total ===== //

    private static void setStatus(Case c, Integer target, Decimal worked) {
        if (worked >= target.doubleValue()) {
            c.SLA_Status__c = 'Ueberschritten';
            c.SLA_Ueberschritten__c = true;
            return;
        }
        c.SLA_Ueberschritten__c = false;
        if (target > 0) {
            Decimal remaining = target.doubleValue() - worked.doubleValue();
            if (remaining / target.doubleValue() < SLAConfig.DANGER_THRESHOLD) {
                c.SLA_Status__c = 'Gefaehrdet';
                return;
            }
        }
        c.SLA_Status__c = 'Im Zeitplan';
    }

    private static void setEscalation(Case c, Integer target, Decimal worked) {
        Double w = worked.doubleValue();
        if (w >= target + SLAConfig.ESCALATION_LEVEL2_AFTER_MINUTES) {
            c.SLA_Eskalation__c = 'Stufe 2';
        } else if (w >= target) {
            c.SLA_Eskalation__c = 'Stufe 1';
        } else if (c.SLA_Eskalation__c == null
                   || c.SLA_Eskalation__c == 'Keine') {
            c.SLA_Eskalation__c = 'Keine';
            // Monoton: erreichte Stufe 1/2 wird NICHT zurueckgesetzt.
        }
    }

    // ======================== BusinessHours-Utilities ===================== //

    /**
     * Werk-Minuten start..end via BusinessHours.diff (MS -> Decimal-Min).
     * diff CLAMPT start auf das naechste Fenster (verifiziert), damit ist
     * die Uhr korrekt auch fuer Cases, die auesserhalb des Fensters
     * angelegt wurden.
     */
    public static Decimal workedMins(Id bh, DateTime start, DateTime end) {
        if (bh == null || start == null || end == null) { return 0; }
        return Decimal.valueOf(BusinessHours.diff(bh, start, end)) / 60000.0;
    }

    /** Default-BusinessHours-Id (1 Query). Im Trigger/Batch EINMAL holen. */
    @testVisible
    public static Id bhId() {
        return [SELECT Id FROM BusinessHours LIMIT 1].Id;
    }

    /**
     * deadline = from + exactly `workMinsMin` worked-Min per BusinessHours,
     * via Binary-Search ueber diff (BusinessHours.add defekt). 1s-Praezision.
     * Sucht das ERSTE T mit diff(from,T) >= workMinsMin (monotone Funktion
     * von T). Obergrenze wird iterativ verdraengt, bis sie genug worked-Min
     * deckt.
     */
    public static DateTime estimateDeadline(Id bh, DateTime from,
                                            Integer workMinsMin) {
        if (from == null) { return null; }
        if (workMinsMin == null || workMinsMin <= 0) { return from; }

        Double need = workMinsMin.doubleValue();
        DateTime hi = from.addMinutes(workMinsMin * 3);
        // Obergrenze aufstocken, bis sie >= need worked-Min deckt (Wochen-
        // enden/Non-BH-Zonen brauchen mehr Kalendertage).
        for (Integer i = 0; i < 30
             && BusinessHours.diff(bh, from, hi) / 60000.0 < need; i++) {
            hi = from.addMinutes((hi.getTime() - from.getTime()) / 60000L * 3);
        }

        Long loMs = from.getTime();
        Long hiMs = hi.getTime();
        for (Integer it = 0; it < 60 && (hiMs - loMs) > 1000; it++) {
            Long mid = loMs + (hiMs - loMs) / 2;
            if (BusinessHours.diff(bh, from, DateTime.newInstance(mid))
                       / 60000.0 >= need) {
                hiMs = mid;
            } else {
                loMs = mid;
            }
        }
        return DateTime.newInstance(hiMs);
    }
}
