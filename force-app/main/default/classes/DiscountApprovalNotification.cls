/**
 * [SCRUM-445] DiscountApprovalNotification — Queueable: informs the rep's DIRECT MANAGER
 * that a discount approval is waiting, WITHOUT the rep writing an email.
 *
 * House pattern: OpportunityOverdueNotification (SCRUM-319) — FeedItem on the target
 * user's feed, guarded if (!Test.isRunningTest()), try/catch so a Chatter problem never
 * breaks the save.
 *
 * @param oppToManager Opportunity Id -> the User Id of the direct manager to inform.
 */
public with sharing class DiscountApprovalNotification implements Queueable {
    private final Map<Id, Id> oppToManager;

    public DiscountApprovalNotification(Map<Id, Id> oppToManager) {
        this.oppToManager = oppToManager;
    }

    public void execute(QueueableContext ctx) {
        notify(oppToManager);
    }

    /** Body extracted so a test can cover both paths without an async enqueue
     * (QueueableContext cannot be constructed — measured 2026-10-12).
     * Returns the per-manager grouping so a test can assert the mapping resolved and
     * the grouping is per manager (AC4); the FeedItem itself is test-guarded and is
     * proven by the Playwright E2E spec. */
    public static Map<Id, List<Opportunity>> notify(Map<Id, Id> oppToManager) {
        Map<Id, List<Opportunity>> byManager = new Map<Id, List<Opportunity>>();
        if (oppToManager.isEmpty()) {
            return byManager;
        }
        Set<Id> oppIds = new Set<Id>();
        for (Id k : oppToManager.keySet()) {
            oppIds.add(k);
        }
        List<Opportunity> opps = [
            SELECT Id, Name, Discount_in_Pct__c FROM Opportunity WHERE Id IN :oppIds
        ];

        for (Opportunity o : opps) {
            Id mgr = oppToManager.get(o.Id);
            if (mgr == null) {
                continue;
            }
            if (!byManager.containsKey(mgr)) {
                byManager.put(mgr, new List<Opportunity>());
            }
            byManager.get(mgr).add(o);
        }

        String orgUrl = URL.getOrgDomainUrl().toExternalForm();
        if (orgUrl.endsWith('/')) {
            orgUrl = orgUrl.substring(0, orgUrl.length() - 1);
        }

        for (Id mgrId : byManager.keySet()) {
            String body = 'Discount approval waiting: these Opportunities offer a discount above 15 % and need approval by you before they may be closed as Won:';
            for (Opportunity o : byManager.get(mgrId)) {
                body += '\n\n\u2022 ' + o.Name + ' \u2014 ' + o.Discount_in_Pct__c + ' % \u2014 ' + orgUrl + '/' + o.Id;
            }
            if (!Test.isRunningTest()) {
                try {
                    FeedItem fi = new FeedItem();
                    fi.ParentId = mgrId;
                    fi.Body = body;
                    insert fi;
                } catch (Exception e) {
                    System.debug('DiscountApprovalNotification: no feed item for manager ' + mgrId + ': ' + e.getMessage());
                }
            }
        }
        return byManager;
    }
}
