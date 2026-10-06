/**
 * [SCRUM-438] Zentrale Konfiguration fuer die automatische SLA-Eskalation.
 *
 * EIN EINZIGER ORT fuer alle PO-Konstanten + die Pause-Status-Menge, damit
 * jede PO-Drehung eine 1-Zeilen-Aenderung bleibt (house SCRUM-436
 * CaseReminderConfig-Shape).
 *
 * Zielzeit-Tabelle (PO-Tabelle, ADR-7): Basis-Werk-Minuten je Priority,
 * Premium (Case.Kundenstatus__c = 'Premium', ADR-6 Reuse) −25 %:
 *   High   240  | 180   | Medium  480  | 360   | Low  1440  | 1080
 *
 * Pause (ADR-4): konfigurierbare Statusliste. Der echte Picklist-Wert
 * "Warten auf Kunde" existiert aktuell NICHT in der Org (Case.Status =
 * New/Working/Escalated/Closed, verifiziert) -> DEFAULT leer, Org-Setup-Step
 * (DevOps) liefert den Wert, Developer traegt ihn hier ein. Robust: die
 * Pause-Flag-Feld-Logik laeuft auch ohne Statusliste (nur Ueberschritt).
 *
 * @author developer-agent
 * @date 2026-10-04
 */
public without sharing class SLAConfig {

    // PO-Tabelle: Basis-Werk-Minuten je Priority (ADR-3: Werkzeit via
    // BusinessHours.diff — hier nur die Ziel-GRÖSSE, keine Rechenmaschine).
    public static final Map<String,Integer> DEADLINE_MINUTES_BY_PRIORITY =
            new Map<String,Integer>{
                'High'   => 240,
                'Medium' => 480,
                'Low'    => 1440
            };

    // PO/ADR-7: Premium-Kunde (Case.Kundenstatus__c = 'Premium') −25 %.
    public static final Decimal PREMIUM_DISCOUNT = 0.25;

    // PO/ADR-8: Eskalation Stufe 1 -> Stufe 2 nach +4 Werkstunden Ueberschreitung.
    public static final Integer ESCALATION_LEVEL2_AFTER_MINUTES = 240;

    // PO/ADR-9: <20 % Zielzeit uebrig = "Gefaehrdet".
    public static final Decimal DANGER_THRESHOLD = 0.2;

    // PO/ADR-4: Pause-Statusliste. Echter Wert "Warten auf Kunde" fehlt in
    // der Org (Case.Status hat genau 4 Werte) -> leer bis Org-Setup-Step.
    // 1-Zeilen-Aenderung, sobald der PO/DevOps den Wert liefert.
    public static final Set<String> PAUSE_STATUSES = new Set<String>{
        // AC3/AC4 (SCRUM-438): Pause-Status(e), Uhr friert (ADR-4).
        'Warten auf Kunde'
    };

    private SLAConfig() {}

    /** Ist der Case im Pause-Status (Uhr gefroren)? */
    public static Boolean isPauseStatus(String status) {
        return status != null && PAUSE_STATUSES.contains(status);
    }

    /**
     * Ziel-Werk-Minuten fuer einen Case: Basis je Priority, Premium −25 %.
     * Unbekannte/leere Priority -> Medium (konservativer Default, PO-Default).
     */
    public static Integer targetMinutes(String priority, Boolean premium) {
        Integer base = DEADLINE_MINUTES_BY_PRIORITY.get(priority);
        if (base == null) {
            base = DEADLINE_MINUTES_BY_PRIORITY.get('Medium');
        }
        Double v = base;
        if (premium == true) {
            v = v * (1.0 - PREMIUM_DISCOUNT.doubleValue());
        }
        return (Integer) Math.round(v);
    }
}
