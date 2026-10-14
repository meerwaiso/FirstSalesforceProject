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
 *   - User transaction (UI, API, Quick Action, bulk import): before-update fires
 *     -> Last_User_Change__c = System.now().
 *   - The nightly scheduler's own `update` (OpportunityRiskService.recomputeAll)
 *     sets systemWriteInProgress while it runs; the handler then leaves the
 *     anchor untouched.
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
        if (OpportunityRiskService.systemWriteInProgress) {
            // The scheduler's own rewrite — not a user change, anchor untouched.
            return;
        }
        for (Opportunity o : newRecords) {
            o.Last_User_Change__c = System.now();
        }
        OpportunityRiskService.evaluate(newRecords);
    }
}
