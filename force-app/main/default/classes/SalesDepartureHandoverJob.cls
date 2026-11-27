/**
 * [SCRUM-483] One handover = ONE Queueable job = ONE transaction (ADR-3, house
 * SCRUM-410 ADR-2): the audit row, the Owner change and the provenance fields are
 * all-or-nothing, no partial result can "lie" in the org.
 *
 * ADR-4 · the three failure tiers, and why the deactivation cannot fail:
 *   1. Blocked  — pre-flight in SalesDepartureHandoverService, NO DML at all
 *                 (no manager and no fallback = AC4, no mapping row = AC12).
 *   2. Failed   — a caught DmlException: an explicit compensating save restores
 *                 the old Owner and clears the provenance fields, because a
 *                 caught Apex exception does NOT roll back what an earlier
 *                 statement already saved. Then Status__c=Failed + the German
 *                 message in Error_Detail__c (AC11 "shown, not hidden").
 *   3. Escalated— the compensation itself is refused: the row stays Failed and
 *                 the job aborts with a named exception, so the Tester sees it.
 *
 * The job NEVER writes a User field. That is what makes AC11 structural: IT
 * deactivates the person in Setup, this job only moves records — a failing move
 * can therefore not undo the deactivation.
 *
 * Governor: 3 bulk SELECTs + max. 4 bulk DML statements + 1 INSERT per person,
 * no query in a loop. Measured Test-Org volume for the largest owner: 255
 * Accounts, 89 open Opportunities org-wide — inside the Queueable limits; above
 * ~5.000 child records per person the Batchable path (SalesDepartureHandoverBatch)
 * takes over (ADR-3).
 *
 * Tests: SalesDepartureHandoverTest (behaviour, incl. the AC11 failure fixture).
 *
 * @author developer-agent
 * @date 2026-11-27
 */
public without sharing class SalesDepartureHandoverJob implements Queueable {

    private final Id fromUserId;
    private final Id toUserId;
    private final String rule;
    private final String evidence;

    public SalesDepartureHandoverJob(Id fromUserId, Id toUserId, String ruleValue,
                                     String evidenceValue) {
        this.fromUserId = fromUserId;
        this.toUserId = toUserId;
        this.rule = ruleValue;
        this.evidence = evidenceValue;
    }

    public void execute(QueueableContext ctx) {
        // 3× bulk SELECT. Closed/Won/Lost deals are read for the COUNT only -
        // they are never saved, so they keep their owner (AC5).
        List<Account> accounts = [
            SELECT Id, OwnerId FROM Account WHERE OwnerId = :fromUserId
        ];
        List<Opportunity> openDeals = [
            SELECT Id, OwnerId FROM Opportunity
            WHERE OwnerId = :fromUserId AND IsClosed = false
        ];
        List<Opportunity> closedDeals = [
            SELECT Id FROM Opportunity
            WHERE OwnerId = :fromUserId AND IsClosed = true
        ];

        List<Id> accountIds = collectIds(accounts);
        List<Id> openDealIds = collectIds(openDeals);

        // ADR-6 (house SCRUM-449 flag, set by OpportunityRiskService.recomputeAll at
        // lines 373/403): every handler that stamps `Last_User_Change__c` on a user
        // edit compares now.OwnerId != was.OwnerId — and an ownership move changes
        // exactly that field. Without the flag SCRUM-319 `Inactive_Days__c` /
        // `Is_Overdue__c` and SCRUM-414 `Is_Close_Date_Overdue__c` are silently
        // re-anchored on every moved deal, which destroys the "deal went cold" signal
        // (AC6: nothing besides the owner changes). The flag covers the WHOLE handover
        // transaction — trail insert, both ownership saves and the compensation — and
        // is reset in `finally`, so a failing save cannot leave it stuck true.
        OpportunityRiskService.systemWriteInProgress = true;
        try {
            // The trail row comes FIRST so the provenance on every moved record can
            // point at it (AC8/AC9). Its Id is needed before the save.
            Id trailRowId = SalesDepartureHandoverService.logRow(
                fromUserId, toUserId, rule, evidence,
                SalesDepartureHandoverService.ST_DONE, null, null
            );

            try {
                Integer movedAccounts = SalesDepartureHandoverBatch.moveAccountsChunk(
                    accountIds, fromUserId, toUserId, trailRowId);
                Integer movedDeals = SalesDepartureHandoverBatch.moveOpenOpportunitiesChunk(
                    openDealIds, fromUserId, toUserId, trailRowId);
                updateTrailCounts(trailRowId, movedAccounts, movedDeals, closedDeals.size());
            } catch (DmlException moveError) {
                // Tier 2: explicit compensation, then the row says Failed in German.
                handleMoveFailure(trailRowId, accountIds, openDealIds, fromUserId,
                                  moveError.getMessage());
            }
        } finally {
            OpportunityRiskService.systemWriteInProgress = false;
        }
    }

    private static List<Id> collectIds(List<SObject> records) {
        List<Id> ids = new List<Id>();
        for (SObject rec : records) {
            ids.add(rec.Id);
        }
        return ids;
    }

    /** Counts of the run on the trail row (fresh sObject, SCRUM-459 pitfall). */
    private static void updateTrailCounts(Id rowId, Integer accounts, Integer deals,
                                          Integer closedKept) {
        SalesDepartureHandover__c row = new SalesDepartureHandover__c(Id = rowId);
        row.Accounts_Handed_Over__c = accounts;
        row.Open_Opportunities_Handed_Over__c = deals;
        row.Closed_Opportunities_Kept__c = closedKept;
        update row;
    }

    private static void handleMoveFailure(Id rowId, List<Id> accountIds,
                                          List<Id> openDealIds, Id previousOwner,
                                          String germanReason) {
        // The verdict is written BEFORE the compensation is attempted: when the
        // revert is refused as well (tier 3), the row still has to say Failed —
        // otherwise the half-moved state would be invisible (AC11).
        markFailed(rowId, germanReason);
        try {
            SalesDepartureHandoverBatch.revertAccountsChunk(accountIds, previousOwner);
            SalesDepartureHandoverBatch.revertOpenOpportunitiesChunk(openDealIds,
                                                                      previousOwner);
        } catch (DmlException compensationError) {
            // Tier 3 escalation: the move AND the revert are refused. The row
            // below still says Failed, and the caller is told with a named
            // exception - a silent half-moved state is not possible here.
            throw new SalesDepartureHandoverException(
                'SCRUM-483: the ownership move and its compensation both failed: '
                + germanReason + ' / ' + compensationError.getMessage()
            );
        }
    }

    /** AC11: the failure is visible, not hidden in a system log. */
    private static void markFailed(Id rowId, String reason) {
        SalesDepartureHandover__c row = new SalesDepartureHandover__c(Id = rowId);
        row.Status__c = SalesDepartureHandoverService.ST_FAILED;
        row.Error_Detail__c = SalesDepartureHandoverService.trim255(reason);
        update row;
    }
}

