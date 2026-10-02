/**
 * [SCRUM-436] Zentrale Konfiguration fuer die automatische Wiedervorlage.
 *
 * EIN EINZIGER ORT, in dem die Case-Status-Mengen definiert sind. So bleibt
 * die PO-Entscheidung (ADR-4, Offene-Punkt #1) eine 1-Zeilen-Aenderung:
 * der PO liefert/zaehlt den echten Status „Warten auf Kunde" (der aktuell in
 * der Test-Org/Prod-Org NICHT existiert — Case.Status hat genau 4 Werte:
 * New/Working/Escalated/Closed), dann traegt er ihn in SUSPENDED_STATUSES
 * ein und die AC5/AC6-Logik greift unveraendert.
 *
 * Semantik (PO-Regeln + ADR-4):
 *   - MONITORED_STATUSES  = Uhr laeuft: Case wird naechtlich geprueft.
 *   - SUSPENDED_STATUSES  = Uhr pausiert: keine Wiedervorlage (PO-Status
 *                           „Warten auf Kunde" — Wert fehlt noch, Platzhalter).
 *   - „Closed" = nie monitored (wird im Batch-SOQL zudem explizit gefiltert).
 *
 * @author developer-agent
 * @date 2026-10-02
 */
public without sharing class CaseReminderConfig {

    // PO-Offenpunkt #1 — DEFAULT-Werte, bis der PO die reale Status-Menge
    // festlegt (ADR-4, Option 1 empfohlen: „Warten auf Kunde" als neuen
    // Picklist-Wert anlegen). Monitored = New + Working + Escalated (Default:
    // ein unarbeiteter neuer Fall oder Eskalierte muessen ebenfalls erinnern),
    // Closed = nie.
    public static final Set<String> MONITORED_STATUSES = new Set<String> {
        'New', 'Working', 'Escalated'
    };

    // PO-Offenpunkt #1 — SUSPENDED. Der echte Wert (PO: „Warten auf Kunde")
    // existiert in der Org noch nicht -> Platzhalter bleibt leer. Sobald der
    // PO den Wert anlegt (@devops) und hier eintraegt, wird ein Case in
    // diesem Status naechtlich NICHT geprueft (AC5) und die Ueberwachung
    // beginnt neu, wenn er zurueck in einen MONITORED-Status wechselt (AC6).
    public static final Set<String> SUSPENDED_STATUSES = new Set<String> {
        // 'Warten auf Kunde' — PO muss Wert liefern/anzulegen (ADR-4).
    };

    // PO-Werktag-Schwellen (PO: „länger als 3 Werktage" Standard,
    // „bereits nach 1 Werktag" bei High). ADR-2: reine Mo-Fr-Kalendertags-
    // Arithmetik, KEIN BusinessHours-Objekt, KEIN Feiertag.
    public static final Integer DEFAULT_THRESHOLD_WORKING_DAYS = 3;
    public static final Integer HIGH_THRESHOLD_WORKING_DAYS    = 1;

    private CaseReminderConfig() {}

    /** True, wenn der naechtliche Batch den Case im Status ueberwachen soll. */
    public static Boolean isMonitoredStatus(String status) {
        return status != null && MONITORED_STATUSES.contains(status);
    }
}
