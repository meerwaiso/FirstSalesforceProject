/**
 * [SCRUM-421] Trigger-Wrapper fuer CaseQueueAssignment (Queue-Zuordnung).
 *
 * Bulk wie das 420-House-Pattern: alle Cases in Trigger.new/Trigger.old in einem
 * O(n) Loop sammeln, exakt EIN Handler-Call pro Operation (route(new, old)).
 * Rekursions-Schutz, 2 Ebenen:
 *   (1) Update-Filter im Handler: nur bei Servicebereich-/Kundenstatus-Wechsel —
 *       der Handler schreibt OwnerId + 2 Systemfelder, die NICHT im Filter liegen.
 *   (2) isRunning-Guard (try/finally): der Handler-eigene Owner-`update` feuert
 *       denselben Trigger erneut, der Guard bricht ihn sofort ab.
 *
 * NUR after-Phasen: nach dem Commit stehen die neuen Werte; vor der Persistenz
 * waere der Readback unsauber (Haus-Folge 420/365).
 * without sharing: konsistent mit CaseEscalationKundeTrigger — der Handler laeuft
 * im System-Modus und schreibt OwnerId + eigene Felder; der Wrapper muss nur
 * Standard-Felder (OwnerId/CreatedById) + die 2 eigenen Pickliste aus trigger.old/new
 * lesen, was sharing-unabhaengig ist.
 *
 * @author developer-agent
 * @date 2026-09-20
 */
public without sharing class CaseQueueAssignmentTrigger {

    /** Reentry-Schutz gegen Handler-eigene Case-DML (2. Rekursions-Ebene). */
    private static Boolean isRunning = false;

    public static void afterInsert() {
        if (isRunning) {
            return;
        }
        isRunning = true;
        try {
            // Neuanlage: nur greifen, wenn Owner = erstellender User (neu, nicht
            // weitergeleitet). Alle anderen => nicht eligibel (AK4); leerer SB => AK7.
            CaseQueueAssignment.route((List<Case>) System.trigger.new, null);
        } finally {
            isRunning = false;
        }
    }

    public static void afterUpdate() {
        if (isRunning) {
            return;
        }
        isRunning = true;
        try {
            // Der Handler selbst filtert SB/KS-Wechsel (1. Rekursions-Ebene);
            // hier wird alles an ihn gegeben, damit der Filter zentral bleibt.
            CaseQueueAssignment.route(
                    (List<Case>) System.trigger.new,
                    (List<Case>) System.trigger.old);
        } finally {
            isRunning = false;
        }
    }
}
