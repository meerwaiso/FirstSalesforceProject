/**
 * [SCRUM-424] Handler fuer erste Mitarbeiter-Reaktion auf Case via CaseComment.
 *
 * Nach ADR-4: 2 gekoppelte SOQLs, 1 DML pro Batch, Write-once (First_Response_Time__c = null).
 * BusinessHours.diff fuer Arbeitsminuten (wenn BH aktiv, sonst Kalender).
 * Target: Premium=60min, Standard/leer=240min.
 *
 * @author developer-agent
 * @date 2026-09-22
 */
public without sharing class CaseCommentFirstResponse {

    // PO-Konfiguration: Zielwerte in Arbeitssminuten
    private static final Integer PREMIUM_TARGET_MINUTES = 60;
    private static final Integer STANDARD_TARGET_MINUTES = 240;

    private CaseCommentFirstResponse() {}

    /**
     * After-insert handling for CaseComment.
     * Identifies first staff response per case and computes SLA fields.
     */
    public static void afterInsert(List<CaseComment> newComments) {
        processFirstResponses(newComments);
    }

    /** Wrapper for trigger — old name kept for compatibility. */
    public static void processFirstResponses(List<CaseComment> newComments) {
        if (newComments == null || newComments.isEmpty()) return;

        // Gather parent Case IDs
        Set<Id> caseIds = new Set<Id>();
        for (CaseComment cc : newComments) {
            if (cc.ParentId != null) caseIds.add(cc.ParentId);
        }
        if (caseIds.isEmpty()) return;

        // SOQL 1: Only cases where first response isn't already recorded (Write-once).
        // CreatedDate is SELECTED — BUGFIX SCRUM-424: it was missing before, so the
        // working-minutes delta dereferenced a null and every qualifying comment threw
        // a NullPointerException (root cause of the 3/15 verdict).
        List<Case> cases = [
            SELECT Id, CreatedById, CreatedDate, Kundenstatus__c, First_Response_Time__c
            FROM Case
            WHERE Id IN :caseIds
            AND First_Response_Time__c = null
        ];
        Map<Id, Case> caseMap = new Map<Id, Case>(cases);

        // BusinessHours is looked up ONCE, not per comment — BUGFIX SCRUM-424: the old
        // code ran a BusinessHours SOQL inside the loop, i.e. up to N SOQLs per batch
        // (governor-limit risk on the AC8 200-comment bulk case).
        Id bhId = getDefaultBusinessHoursId();

        // Identify qualifying comments: first by creator != case creator
        // We process in insert order; for cases with multiple new comments,
        // only the first qualifying one matters (others skipped via caseMap removal)
        List<Case> toUpdate = new List<Case>();
        for (CaseComment cc : newComments) {
            Case c = caseMap.remove(cc.ParentId);
            if (c == null) continue;                  // already handled (write-once)
            if (cc.CreatedById == c.CreatedById) continue; // customer's own comment (ADR-4)

            Integer targetMinutes = resolveTargetMinutes(c.Kundenstatus__c);

            // Working minutes via BusinessHours.diff (calendar fallback when no BH)
            Long workingMs = computeBusinessMinutes(bhId, c.CreatedDate, cc.CreatedDate);
            Integer workingMins = (Integer)(workingMs / 60000);

            c.First_Response_Time__c = cc.CreatedDate;
            c.First_Response_Working_Mins__c = workingMins;
            c.First_Response_Target_Missed__c = (workingMins > targetMinutes);
            toUpdate.add(c);
        }

        // SOQL 2: Single DML for all updated cases
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * Resolve SLA target from customer status (PO spec: Premium=60, others/blank=240).
     */
    private static Integer resolveTargetMinutes(String status) {
        if ('Premium'.equalsIgnoreCase(status)) {
            return PREMIUM_TARGET_MINUTES;
        }
        return STANDARD_TARGET_MINUTES;
    }

    /**
     * Default BusinessHours Id, or null if none is configured.
     */
    private static Id getDefaultBusinessHoursId() {
        List<BusinessHours> bhs = [
            SELECT Id
            FROM BusinessHours
            WHERE IsDefault = true
            LIMIT 1
        ];
        return bhs.isEmpty() ? null : bhs[0].Id;
    }

    /**
     * Working minutes via BusinessHours.diff when a default BH exists, else calendar
     * duration (current Test-Org BH is 24/7, so calendar == business minutes here).
     */
    private static Long computeBusinessMinutes(Id bhId, Datetime caseCreated, Datetime commentCreated) {
        if (bhId != null) {
            try {
                Long result = BusinessHours.diff(bhId, caseCreated, commentCreated);
                if (result != null && result >= 0) {
                    return result;
                }
            } catch (Exception e) {
                // fall through to calendar
            }
        }
        Long ms = commentCreated.getTime() - caseCreated.getTime();
        return (ms < 0) ? 0 : ms;
    }
}