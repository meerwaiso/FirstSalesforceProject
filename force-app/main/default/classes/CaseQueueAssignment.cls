/**
 * [SCRUM-421] Queue-Zuordnung: neue/änderte Cases automatisch dem passenden
 * Bearbeitungs-Queue zuweisen (Servicebereich + Kundenstatus).
 *
 * ADR 1 (Apex statt Flow): 300-Bulk ohne N+1 — genau 1 Group-SOQL (statischer
 * Cache, nur bei Cache-miss) + 1 DML pro Batch, keine Case-SOQL (der Handler
 * liest ausschliesslich Trigger.new/Trigger.old-Felder).
 *
 * Routing (PO-final, Matrix B + ADR-2 "leer => nie zuordnen"):
 *   Servicebereich null          -> NICHT zuweisen (AK7)
 *   Standard (beliebiger nicht-leerer SB) -> 'First Level Support'        (AK2)
 *   Premium: Technik/Vertrag/Rechnung/Allgemein -> techn. Support/
 *     Vertragsservice/Billing/FLS; sonstiges -> FLS                        (AK1)
 *   Ziel-Queue existiert nicht   -> Fallback 'First Level Support'; FLS
 *     fehlt ebenfalls -> nicht zuweisbar                                   (AK3)
 *
 * Eligibility (ADR-4, "nie manuelle Entscheidungen ueberschreiben"):
 *   OwnerId == CreatedById  (neu, nicht weitergeleitet)
 *   ODER  OwnerId einer unserer 4 Queues (vorher automatisch zugeordnet)
 *   Ein User als Owner (Mensch uebernommen) => NICHT mehr greifen (AK6).
 *
 * Rekursions-Schutz: (1) Update-Filter nur SB/KS-Wechsel (Handler schreibt
 * OwnerId/-Systemfelder, liegen NICHT im Filter); (2) isRunning-Guard im Wrapper.
 *
 * System-Modus (without sharing): schreibt OwnerId + eigene 2 Systemfelder ohne
 * Write-FLS (Haus-Pattern SCRUM-420/398: read-only FLS-PS, Trigger schreibt trotzdem).
 *
 * @author developer-agent
 * @date 2026-09-20
 */
public without sharing class CaseQueueAssignment {

    /** Fallback-Queue: Standard-Kunden, Allgemein, fehlendes Ziel-Queue. */
    public static final String QUEUE_FLS = 'First Level Support';
    public static final String QUEUE_TECHNIK = 'Technischer Support';
    public static final String QUEUE_VERTRAG = 'Vertragsservice';
    public static final String QUEUE_RECHNUNG = 'Billing';

    /** Kundenstatus-Werte (Picklist Case.Kundenstatus__c) — Literals aus der Org. */
    public static final String STATUS_PREMIUM = 'Premium';

    /** Servicebereich-Werte (Picklist Case.Servicebereich__c) — Literals aus der Org. */
    public static final String SB_TECHNIK = 'Technik';
    public static final String SB_VERTRAG = 'Vertrag';
    public static final String SB_RECHNUNG = 'Rechnung';

    /** Die 4 Ziel-Queue-Names (statisch; Ids sind org-spezifisch, deshalb Cache). */
    private static final Set<String> QUEUE_NAMES = new Set<String>(new List<String>{
        QUEUE_TECHNIK, QUEUE_VERTRAG, QUEUE_RECHNUNG, QUEUE_FLS
    });

    /** Statischer Cache Name -> Queue-Id, einmal pro Transaction (ADR 3: keine Query/Case). */
    private static Map<String, Id> queueIdByName;

    /**
     * Reine Mapping-Funktion: Ziel-Queue-NAME aus Kundenstatus + Servicebereich.
     * null (Servicebereich) => null (AK7: nie zuordnen). Kein SOQL.
     */
    public static String resolveTargetName(String status, String servicebereich) {
        if (servicebereich == null) {
            return null; // AK7: leer => nie zuordnen
        }
        if (status == STATUS_PREMIUM) {
            if (servicebereich == SB_TECHNIK) {
                return QUEUE_TECHNIK;
            }
            if (servicebereich == SB_VERTRAG) {
                return QUEUE_VERTRAG;
            }
            if (servicebereich == SB_RECHNUNG) {
                return QUEUE_RECHNUNG;
            }
            // 'Allgemein' + jeder andere/unerwartete Value = "sonstiges"
            return QUEUE_FLS;
        }
        // 'Standard' (und jeder unerwartete Status) -> immer FLS (AK2)
        return QUEUE_FLS;
    }

    /**
     * Fallback-Kette (AK3): Ziel-Name fehlt in der Org => 'First Level Support';
     * fehlt FLS ebenfalls => null (nicht zuweisbar, wie AK7).
     */
    public static Id resolveQueueId(String targetName, Map<String, Id> queues) {
        if (targetName == null) {
            return null;
        }
        Id id = queues.get(targetName);
        if (id != null) {
            return id;
        }
        if (targetName != QUEUE_FLS) {
            // Ziel existiert nicht -> Fallback FLS
            return queues.get(QUEUE_FLS); // null, falls FLS ebenfalls fehlt
        }
        return null; // FLS selbst fehlt -> nicht zuweisbar
    }

    /**
     * Wendet die Zuordnung auf alle übergebenen Cases an. Liest ausschliesslich
     * Trigger.new/Trigger.old-Felder, 1 Group-SOQL (nur Cache-miss) + 1 DML.
     *
     * @param newCases Trigger.new (aktuelle Werte: OwnerId, CreatedById, SB, KS)
     * @param oldCases Trigger.old (null bei Insert); nur zum SB/KS-Änderungs-Filter
     * @return Anzahl tatsächlich aktualisierter Cases (0 = kein Wert geändert)
     */
    public static Integer route(List<Case> newCases, List<Case> oldCases) {
        if (newCases == null || newCases.isEmpty()) {
            return 0;
        }
        Map<String, Id> queues = loadQueues();
        List<Case> toUpdate = new List<Case>();

        for (Integer i = 0; i < newCases.size(); i++) {
            Case c = newCases[i];
            Case o = (oldCases != null && oldCases.size() > i) ? oldCases[i] : null;

            // Rekursions-/Änderungs-Filter: bei Update nur wenn sich SB oder KS
            // geändert hat (Handler-eigene OwnerId-/Systemfeld-Write greifen hier nicht).
            if (o != null && c.Servicebereich__c == o.Servicebereich__c
                    && c.Kundenstatus__c == o.Kundenstatus__c) {
                continue;
            }

            if (!isEligible(c, queues)) {
                continue; // (AK4/6) neu zugeordnet oder manuell weitergegeben
            }

            Id targetId = resolveQueueId(resolveTargetName(c.Kundenstatus__c, c.Servicebereich__c), queues);
            Boolean willRoute = (targetId != null);
            Boolean newCheckbox = willRoute;
            Boolean ownerChanges = willRoute && c.OwnerId != targetId;
            Boolean checkboxChanges = (c.Automatische_Zuordnung__c != newCheckbox);

            if (ownerChanges || checkboxChanges) {
                Case u = new Case(Id = c.Id);
                if (willRoute) {
                    u.OwnerId = targetId;
                    u.Automatische_Zuordnung__c = true;
                    u.Zuordnungszeitpunkt__c = DateTime.now();
                } else {
                    // nicht zuweisbar (leer/fehlend): Checkbox=false, Owner + Ts bleiben
                    u.Automatische_Zuordnung__c = false;
                }
                toUpdate.add(u);
            }
        }

        // 1 DML — nur wenn sich ein Wert geändert hat (418-Lektion: leerer Call = Fehler).
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }

    /**
     * Reines Predikat ohne SOQL: Owner = Ersteller (neu) ODER eines unserer 4 Queues.
     * Owner = beliebiger User (Mensch uebernommen) => ineligibel (AK6-Hebel).
     */
    private static Boolean isEligible(Case c, Map<String, Id> queues) {
        if (c.OwnerId == null) {
            return true;
        }
        if (c.CreatedById != null && c.OwnerId == c.CreatedById) {
            return true;
        }
        return queues.values().contains(c.OwnerId);
    }

    /** 1× Group-SOQL, nur beim ersten Call pro Transaction (statischer Cache). */
    private static Map<String, Id> loadQueues() {
        if (queueIdByName == null) {
            queueIdByName = new Map<String, Id>();
            for (Group g : [
                SELECT Id, Name
                FROM Group
                WHERE Type = 'Queue' AND Name IN :QUEUE_NAMES
            ]) {
                queueIdByName.put(g.Name, g.Id);
            }
        }
        return queueIdByName;
    }
}
