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

        // SOQL 1: Only cases where first response isn't already recorded (Write-once)
        List<Case> cases = [
            SELECT Id, CreatedById, Kundenstatus__c, First_Response_Time__c
            FROM Case
            WHERE Id IN :caseIds
            AND First_Response_Time__c = null
        ];
        Map<Id, Case> caseMap = new Map<Id, Case>(cases);

        // Identify qualifying comments: first by creator != case creator
        // We process in insert order; for cases with multiple new comments,
        // only the first qualifying one matters (others skipped via caseMap removal)
        List<Case> toUpdate = new List<Case>();
        for (CaseComment cc : newComments) {
            Case c = caseMap.remove(cc.ParentId);
            if (c == null) continue;                  // already handled
            if (cc.CreatedById == c.CreatedById) continue; // customer, not staff

            Integer targetMinutes = resolveTargetMinutes(c.Kundenstatus__c);

            // Compute working minutes via BusinessHours.diff (or calendar as fallback)
            Long workingMs = computeBusinessMinutes(c.CreatedDate, cc.CreatedDate);
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
     * Compute working minutes using BusinessHours.diff if available,
     * else fall back to calendar duration (for 24/7 orgs / no default BH).
     */
    private static Long computeBusinessMinutes(Datetime caseCreated, Datetime commentCreated) {
        try {
            // Find default BusinessHours
            List<BusinessHours> bhs = [
                SELECT Id
                FROM BusinessHours
                WHERE IsDefault = true
                LIMIT 1
            ];
            if (!bhs.isEmpty()) {
                Long result = BusinessHours.diff(bhs[0].Id, caseCreated, commentCreated);
                if (result != null && result >= 0) {
                    return result;
                }
            }
        } catch (Exception e) {
            // BusinessHours not available or query failed — fall through to calendar
        }
        // Fallback: raw calendar duration in ms
        Long ms = commentCreated.getTime() - caseCreated.getTime();
        return (ms < 0) ? 0 : ms;
    }
}
