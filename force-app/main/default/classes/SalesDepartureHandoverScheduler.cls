/**
 * [SCRUM-483] Schedulable entry point of the Sales-Austritt-Uebergabe.
 *
 * ADR-2 · WHY A SCHEDULED JOB AND NOT A TRIGGER: no hook exists on a user
 * deactivation — no Apex trigger, Validation Rule or Flow can observe "a User
 * stopped being active" (the repo holds 28 triggers, none on User), and every
 * org-wide state scan in this repo is a Scheduler (AccountReactivationBatch
 * SCRUM-388, CaseReminderBatch SCRUM-436, AccountSatisfactionBatch SCRUM-442,
 * OpenOpportunityHistoryScheduler SCRUM-417). Candidates are therefore derived
 * from the record, never from an event:
 *
 *     candidate  <=>  the owning User record is missing   OR   IsActive = false
 *
 * The second branch is the reason that IT switched the person off; the first
 * covers IT deleting the user instead (Deactivation_Evidence__c says which).
 *
 * CADENCE: hourly, minute 5 — suggested CRON `0 5 * * * ?`. Free slot:
 * 01:00 SCRUM-436, 02:00 SCRUM-388, 03:00 SCRUM-417, 04:00 SCRUM-442, 06:00
 * SCRUM-319/414. AC1 and AC7 therefore hold WITHIN ONE HOUR of the deactivation
 * (PO accepted this window, comment 23891) — the release note has to say that in
 * plain words, and the Tester measures the real delay instead of assuming it.
 *
 * WICHTIG: Scheduled Jobs are LAUFTIME-Objects, KEINE Metadata — the CRON entry
 * is NOT created by a deploy and must be set in the Org (house pitfall SCRUM-442
 * / SCRUM-436 / SCRUM-442). WITHOUT this org step the code is deployed but runs
 * NIE:
 *
 *   System.schedule('SCRUM-483 Departure Handover', '0 5 * * * ?',
 *                   new SalesDepartureHandoverScheduler());
 *
 * -> @devops-agent: Test-Org on deploy, Prod-Org on release. Read the existing
 * schedule list back before taking the slot (collision check).
 *
 * The scheduled user needs SCRUM483_Handover_System (class access + editable
 * provenance FLS + Create on the trail object): DML checks FLS even in
 * without-sharing classes, and a missing grant shows up as `No such column`,
 * which reads like a missing field and is not one.
 *
 * @author developer-agent
 * @date 2026-11-27
 */
public class SalesDepartureHandoverScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        SalesDepartureHandoverService.loadRunCaches();
        Map<Id, String> candidates = SalesDepartureHandoverService.findDeactivatedOwners();

        Integer handedOver = 0;
        Integer blocked = 0;
        for (Id ownerId : candidates.keySet()) {
            String evidence = candidates.get(ownerId);
            if (SalesDepartureHandoverService.alreadyLogged(ownerId, evidence)) {
                // idempotency (house SCRUM-388/417): a second run touches 0 rows
                continue;
            }
            Id target = SalesDepartureHandoverService.resolveTarget(ownerId);
            if (target == null) {
                // Tier 1 Blocked: no DML at all, but the situation is visible
                // (AC4 no manager / no fallback, AC12 forgotten in the mapping).
                SalesDepartureHandoverService.logRow(
                    ownerId, null, SalesDepartureHandoverService.targetRule(),
                    evidence, SalesDepartureHandoverService.ST_BLOCKED,
                    SalesDepartureHandoverService.blockInfo(), null
                );
                blocked++;
                continue;
            }
            // The move runs as its own Queueable job: one person's failure can
            // never undo another person's deactivation, and never aborts the run.
            SalesDepartureHandoverJob job = new SalesDepartureHandoverJob(
                ownerId, target, SalesDepartureHandoverService.targetRule(), evidence
            );
            enqueue job;
            handedOver++;
        }
        System.debug('SCRUM-483 DepartureHandover: candidates='
            + String.valueOf(candidates.size())
            + ' queued=' + String.valueOf(handedOver)
            + ' blocked=' + String.valueOf(blocked));
    }
}
