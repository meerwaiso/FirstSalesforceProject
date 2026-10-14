/**
 * [SCRUM-449] OpportunityRiskScheduler — Schedulable for the nightly recompute.
 *
 * C1 (inactivity) and C3 (close date passed) are time-based: they change with
 * the calendar, not with a record edit. The trigger covers edits; this job
 * covers the clock. House pattern: OpenOpportunityHistoryScheduler (SCRUM-417)
 * / AccountReactivationScheduler (SCRUM-388) — the scheduler starts the service,
 * it holds no logic of its own.
 *
 * CRON proposal: 0 0 4 * * ?  (daily 04:00).
 * Measured in Test-Org on 2026-10-14: `SELECT ... FROM ScheduledJob` (Tooling
 * API) returned 0 jobs — the slot collides with nothing today. Existing house
 * slots: 02:00 SCRUM-388, 03:00 SCRUM-417, 06:00 SCRUM-319/414.
 *
 * IMPORTANT — Scheduled Jobs are RUNTIME objects, not metadata: the CRON entry
 * is NOT created by a deploy. The org step (DevOps, not CI):
 *
 *   System.schedule('SCRUM-449 Risk Evaluation', '0 0 4 * * ?',
 *                   new OpportunityRiskScheduler());
 *
 * Without that step the code is deployed but never runs.
 *
 * @author developer-agent
 * @date 2026-10-14
 */
global class OpportunityRiskScheduler implements Schedulable {

    global void execute(SchedulableContext ctx) {
        Integer saved = OpportunityRiskService.recomputeAll();
        System.debug('OpportunityRiskScheduler: ' + saved + ' Opportunities re-evaluated');
    }
}
