/**
 * OpportunityOverdueScheduler — Scheduled Apex for daily overdue opportunity check
 * 
 * Runs daily at 06:00 and marks inactive opportunities (open stage + >14 days since last update).
 * Cron expression: 0 0 6 * * ? (daily at 06:00)
 */
global class OpportunityOverdueScheduler implements Schedulable {

    /**
     * Executes the daily overdue opportunity check
     */
    global void execute(SchedulableContext ctx) {
        List<Id> newlyMarkedIds = OpportunityOverdueService.findAndMarkOverdueOpportunities();

        // Send in-app notifications for newly marked opportunities
        if (!newlyMarkedIds.isEmpty()) {
            System.enqueueJob(new OpportunityOverdueNotification(newlyMarkedIds));
        }

        System.debug('OpportunityOverdueScheduler: ' + newlyMarkedIds.size() + ' overdue opportunities marked and notified.');
    }
}