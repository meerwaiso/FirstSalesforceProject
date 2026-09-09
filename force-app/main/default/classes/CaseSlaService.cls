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
     * basierend auf der BusinessHours-Config der Org.
     *
     * Algorithmus:
     * 1. Start bei `from` (abgerundet auf die nächste volle Stunde).
     * 2. Stunde für Stunde: wenn die Stunde im Business-Hours-Raster liegt,
     *    wird sie "verbraucht" (remaining--). Sonst übersprungen.
     * 3. Ende: letzte verbrauchte Stunde = Deadline (exklusiv).
     *
     * `BusinessHours.isBusiness(Date, Time)` prüft, ob ein (Datum, Uhrzeit)-Paar
     * innerhalb der konfigurierten Arbeitszeiten liegt → respektiert Feiertage,
     * Wochenenden und alle Business-Hours-Windowen der Org.
     */
    @testVisible
    public static DateTime addBusinessHours(DateTime from, Integer totalHours) {
        // Start auf die nächste volle Stunde runden.
        DateTime cursor = DateTime.newInstance(
            from.year(), from.month(), from.day(),
            from.hour(), 0, 0
        );

        // Wenn `cursor` selbst keine Business-Stunde ist, starten wir trotzdem dort —
        // der Algorithmus überspringt einfach nicht-gültige Stunden.

        Integer remaining = totalHours;
        Integer guard = 0; // Safety-Guard gegen Endlosschleife (max. 30 Tage)
        DateTime lastBusinessHour = null;

        while (remaining > 0 && guard < 720) {
            guard++;

            // Prüfen: ist `cursor` eine Business-Stunde?
            // isBusiness(Date, Time) → true wenn within business hours.
            // Time-Objekt aus dem Hour+Minute von cursor erstellen.
            Time t = Time.newInstance(
                cursor.hour(), cursor.minute(), cursor.second(), 0
            );
            if (BusinessHours.isBusiness(cursor.date(), t)) {
                // This hour is a business hour — consume it.
                remaining--;
                lastBusinessHour = cursor;
            }

            // Move to next hour.
            cursor = DateTime.newInstance(
                cursor.year(), cursor.month(), cursor.day(),
                cursor.hour() + 1, 0, 0
            );
        }

        // Deadline = Ende der letzten verbrauchten Business-Stunde = anfang + 1h.
        if (lastBusinessHour == null) {
            // No business hours found within 30 days — return null.
            return null;
        }
        return lastBusinessHour.addHours(1);
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
