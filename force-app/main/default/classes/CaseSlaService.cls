/**
 * SCRUM-404: CaseSlaService — SLA-Fristen für neue Cases (Business-Hours-berechnet).
 *
 * ADR-2: CreatedDate ist im before insert null (Systemfeld, erst beim Commit gesetzt)
 *  -> die Deadline wird aus NOW_OVERRIDE (null → DateTime.now()) berechnet.
 * ADR-5: Pre-Fills von Erste_Rueckmeldung__c / Sla_Alert_Sent__c werden hart entfernt
 *  (beim Insert darf nur die Deadline gesetzt werden; die setzt derselbe Trigger).
 */
public without sharing class CaseSlaService {
    @testVisible public static DateTime NOW_OVERRIDE = null;

    /**
     * Liest die SLA-Konfiguration (Custom Metadata) und liefert die
     * Priorität → Business-Stunden-Map. Global-Zeile (Prioritaet leer) liefert
     * den Optionalen Fallback. 1 MDT-Query pro Trigger-Lauf.
     */
    public static Map<String, Integer> slaHoursByPriority() {
        Map<String, Integer> m = new Map<String, Integer>();
        for (Sla_Konfiguration__mdt rec : [
            SELECT Prioritaet__c, Sla_Std__c FROM Sla_Konfiguration__mdt WHERE Prioritaet__c != null
        ]) {
            if (rec.Prioritaet__c != null && rec.Sla_Std__c != null) {
                m.put(rec.Prioritaet__c, rec.Sla_Std__c.intValue());
            }
        }
        return m;
    }

    /**
     * Vor-insert: setzt Reaktionsfrist__c je Case aus Priorität und konfigurierten
     * Business-Stunden und entfernt Pre-Fills von Erste_Rueckmeldung__c /
     * Sla_Alert_Sent__c (ADR-5).
     */
    public static void setDeadlinesForNewCases(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) return;
        Map<String, Integer> sla = slaHoursByPriority();
        DateTime now = NOW_OVERRIDE != null ? NOW_OVERRIDE : DateTime.now();
        for (Case c : newCases) {
            // Pre-Fills hart entfernen — vor-insert darf nur Deadline.
            c.Erste_Rueckmeldung__c = null;
            c.Sla_Alert_Sent__c = false;
            Integer hours = sla.get(c.Priority);
            if (hours == null || hours <= 0) {
                System.debug(LoggingLevel.WARN,
                    'CaseSlaService: keine SLA-Stunden für ' + c.Priority
                    + ' — Deadline bleibt leer (Case ' + c.Id + ').');
                continue;
            }
            c.Reaktionsfrist__c = addBusinessHours(now, hours);
        }
    }

    /**
     * Liefert den DateTime, der `totalHours` Business-Stunden nach `from` liegt,
     * basierend auf dem Default-BusinessHours-Record der Org.
     *
     * Primtivist: BusinessHours.add(null, DateTime, Long ms) — natives
     * Business-Time-Primtivist, respektiert Business-Hours-Konfiguration
     * und Feiertage automatisch. (Architekten-Findung, 2026-09-09: ADR-2 Pivot.)
     *
     * WICHTIG: Wenn der Default-BH-Record unkonfiguriert ist, fällt add()
     * auf Kalenderzeit zurück — §8.1 (BH Mo–Fr 08:00–17:00 setzen) ist
     * Release-Voraussetzung, kein Nice-to-have.
     */
    @testVisible
    public static DateTime addBusinessHours(DateTime from, Integer totalHours) {
        Long ms = (Long) totalHours * 3600L * 1000L;
        return BusinessHours.add(null, from, ms);
    }

    /**
     * Liest die globale MDT-Zeile (Prioritaet leer) und liefert Teamlead-User-ID
     * und Alert-Kanal. Leer = kein Alert (ADR-6, §8.5).
     */
    public static Sla_Konfiguration__mdt globalConfig() {
        List<Sla_Konfiguration__mdt> recs = [
            SELECT Teamlead__c, Alert_Kanal__c FROM Sla_Konfiguration__mdt WHERE Prioritaet__c = null LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }
}
