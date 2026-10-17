/**
 * [SCRUM-449] OpportunityRiskHandler — Trigger-Handler for the risk assessment.
 *
 * Runs in BEFORE-insert / BEFORE-update: all six risk fields are written on the
 * records already in hand, so the values are saved with the record — no second
 * DML round-trip, no trigger recursion (house OpportunityOverdueResetHandler
 * needed the hasFired guard because it did DML; this one needs none).
 *
 * The anchor rule (PO): "an update = any change made by a USER. Changes written
 * by the risk mechanism itself never count as an update and never reset the
 * inactivity counter."
 *   - User transaction (UI, API, Quick Action, bulk import) that changes a field
 *     the user can edit -> before-update fires -> Last_User_Change__c = now.
 *   - Our own scheduler's rewrite: systemWriteInProgress is set by recomputeAll.
 *   - ANY OTHER mechanism's rewrite (SCRUM-319 Is_Overdue__c, SCRUM-445 approval
 *     fields, SCRUM-414 Loss_Reason__c): the flag is false, so userEditedRecord()
 *     diffs new vs old and finds no user-editable difference -> anchor untouched.
 *     This is the fix for the Architect's Blocking 1: 66 records carry
 *     Is_Overdue__c, and the SCRUM-319 job's `update` used to reset the counter.
 *
 * Bulk: the whole chunk arrives in Trigger.new; evaluate() is pure Apex over it
 * (0 SOQL, 0 DML) — AC11 (data import) is covered by the same code path.
 *
 * @author developer-agent
 * @date 2026-10-14
 */
public without sharing class OpportunityRiskHandler {

    public static void handleBeforeInsert(List<Opportunity> newRecords) {
        OpportunityRiskService.evaluate(newRecords);
    }

    public static void handleBeforeUpdate(List<Opportunity> newRecords,
                                          Map<Id, Opportunity> oldMap) {
        // PO rule: the anchor moves only for a change made by a USER. Two
        // mechanisms guard against the other kind of update:
        //   1. systemWriteInProgress — our own scheduler's recompute.
        //   2. userEditedRecord — every OTHER mechanism's update (SCRUM-319 sets
        //      Is_Overdue__c, SCRUM-445 the approval fields, SCRUM-414 the loss
        //      reason). Those fire this trigger with the flag false; the diff
        //      against Trigger.oldMap is what keeps them from resetting the
        //      counter. Review SCRUM-449 Blocking 1.
        // The foreign-field visibility map is refreshed ONCE per transaction
        // here — accessibility belongs to the acting user, and the acting user
        // differs between a UI save, an API call and the nightly scheduler.
        // Without this the service would refresh lazily on the first record;
        // refreshing here makes the cost explicit and independent of chunk size.
        OpportunityRiskService.refreshForeignVisibility();
        for (Opportunity o : newRecords) {
            Opportunity was = oldMap.get(o.Id);
            if (was == null) {
                continue;
            }
            if (!OpportunityRiskService.systemWriteInProgress
                && OpportunityRiskService.userEditedRecord(o, was)) {
                o.Last_User_Change__c = System.now();
            }
        }
        OpportunityRiskService.evaluate(newRecords);
    }
}
