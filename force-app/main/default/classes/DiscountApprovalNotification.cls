/**
 * [SCRUM-445] DiscountApprovalNotification — Queueable: informs the rep's DIRECT MANAGER
 * that a discount approval is waiting, WITHOUT the rep writing an email.
 *
 * House pattern: OpportunityOverdueNotification (SCRUM-319) — FeedItem on the target
 * user's feed, guarded if (!Test.isRunningTest()). Unlike the house class there is NO
 * try/catch here: SCRUM-447 measured 44 Queueable jobs Completed / NumberOfErrors=0 that
 * produced no FeedItem, and the swallowed cause is exactly why the failure stayed invisible.
 * Without the catch the AsyncApexJob carries the error. A failing Queueable never rolls
 * back the Opportunity save, so the save itself stays safe.
 *
 * SCRUM-447: the record text is carried in the job (oppLines) instead of being re-queried
 * inside execute(). Measured 2026-10-13: a direct notify() call produced a FeedItem while
 * the enqueued job produced none (Completed, 0 errors) — the SOQL re-read was the only
 * difference between the two paths, so the payload the handler already holds is passed in.
 *
 * @param oppToManager Opportunity Id -> the User Id of the direct manager to inform.
 * @param oppLines     Opportunity Id -> the pre-rendered bullet line (name, %, record link).
 */
public with sharing class DiscountApprovalNotification implements Queueable {
    private final Map<Id, Id> oppToManager;
    private final Map<Id, String> oppLines;

    public DiscountApprovalNotification(Map<Id, Id> oppToManager, Map<Id, String> oppLines) {
        this.oppToManager = oppToManager;
        this.oppLines = oppLines;
    }

    public void execute(QueueableContext ctx) {
        notify(oppToManager, oppLines);
    }

    /** Body extracted so a test can cover both paths without an async enqueue
     * (QueueableContext cannot be constructed — measured 2026-10-12).
     * Returns the per-manager grouping so a test can assert the mapping resolved and
     * the grouping is per manager (AC4).
     * @param oppToManager Opportunity Id -> manager User Id
     * @param oppLines     Opportunity Id -> rendered bullet line
     */
    public static Map<Id, List<String>> notify(Map<Id, Id> oppToManager, Map<Id, String> oppLines) {
        Map<Id, List<String>> byManager = new Map<Id, List<String>>();
        if (oppToManager.isEmpty()) {
            return byManager;
        }
        for (Id oppId : oppToManager.keySet()) {
            Id mgr = oppToManager.get(oppId);
            if (mgr == null) {
                continue;
            }
            if (!byManager.containsKey(mgr)) {
                byManager.put(mgr, new List<String>());
            }
            byManager.get(mgr).add(oppLines.containsKey(oppId) ? oppLines.get(oppId) : '');
        }

        for (Id mgrId : byManager.keySet()) {
            String body = 'Discount approval waiting: these Opportunities offer a discount above 15 % and need approval by you before they may be closed as Won:';
            for (String line : byManager.get(mgrId)) {
                body += '\n\n\u2022 ' + line;
            }
            if (!Test.isRunningTest()) {
                FeedItem fi = new FeedItem();
                fi.ParentId = mgrId;
                fi.Body = body;
                insert fi;
            }
        }
        return byManager;
    }

    /** Renders the bullet line for one record: name, discount, link to the record.
     * Static and public so both the handler and a test can build the same payload. */
    public static String lineFor(Opportunity o) {
        String orgUrl = URL.getOrgDomainUrl().toExternalForm();
        if (orgUrl.endsWith('/')) {
            orgUrl = orgUrl.substring(0, orgUrl.length() - 1);
        }
        String line = o.Name + ' \u2014 ' + o.Discount_in_Pct__c + ' %';
        // Measured 2026-10-13: on a before-insert save the record has no Id yet, so the
        // link would render '/null'. The record is still named; the link is added only
        // when it can actually resolve.
        if (o.Id != null) {
            line += ' \u2014 ' + orgUrl + '/' + o.Id;
        }
        return line;
    }
}
