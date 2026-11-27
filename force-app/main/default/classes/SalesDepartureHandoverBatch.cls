/**
 * [SCRUM-483] The ownership move: Owner + the 3 provenance fields, nothing else.
 *
 * AC6 / ADR-6 (Construct-by-Construction): only Owner and the provenance fields
 * are ever submitted, and NEVER from the record cache that was read in — every
 * save uses a FRESH sObject carrying Id plus the written fields (house pitfall
 * SCRUM-459: `update` writes every field of the cached record, and one of them
 * may not be writeable). That is also why the before-update guards of the existing
 * handlers (FollowupMonitoringHandler.assertNoUserTypedValues, OpportunityRiskTrigger)
 * cannot propose a different value on our save.
 *
 * ADR-3 (house SCRUM-410 ADR-2): the normal path is ONE Queueable job in ONE
 * transaction — SalesDepartureHandoverJob. This class holds the chunked DML both
 * paths share, and is itself Database.Batchable (house shape AccountReactivationBatch
 * SCRUM-388: QueryLocator, 200er-Chunks, no SELECT FOR UPDATE) as the documented
 * fallback for a person above ~5.000 child records — there atomicity is gone and
 * the Failed trail row is the compensation (ADR-4 tier 2). Measured Test-Org
 * volume: 268 Accounts / 89 open Opportunities, so the Queueable path runs today.
 *
 * OpportunityRiskService.systemWriteInProgress is set for the duration of the
 * Opportunity saves (house system-write flag, SCRUM-449): the risk trigger stays
 * inert on a pure ownership change.
 *
 * @author developer-agent
 * @date 2026-11-27
 */
public without sharing class SalesDepartureHandoverBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE = 200;

    private final Id fromUser;
    private final Id toUser;
    private final Id runRowId;
    private Integer movedAccounts;
    private Integer movedOpportunities;

    public SalesDepartureHandoverBatch(Id fromUserId, Id toUserId, Id trailRowId) {
        this.fromUser = fromUserId;
        this.toUser = toUserId;
        this.runRowId = trailRowId;
        this.movedAccounts = 0;
        this.movedOpportunities = 0;
    }

    @testVisible
    public Integer getMovedAccounts() {
        return movedAccounts;
    }

    @testVisible
    public Integer getMovedOpportunities() {
        return movedOpportunities;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        String sql = 'SELECT Id, OwnerId FROM Account WHERE OwnerId = \''
            + String.valueOf(fromUser) + '\'';
        return Database.getQueryLocator(sql);
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        List<Id> ids = new List<Id>();
        for (Account a : scope) {
            ids.add(a.Id);
        }
        movedAccounts += moveAccountsChunk(ids, fromUser, toUser, runRowId);
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('SCRUM-483 Batchable fallback: movedAccounts='
            + String.valueOf(movedAccounts));
    }

    /**
     * Moves one chunk of Accounts: fresh record, Owner + provenance only (AC1/AC7).
     * @return how many records were saved
     */
    public static Integer moveAccountsChunk(List<Id> recordIds, Id previousOwner,
                                            Id newOwner, Id trailRow) {
        if (recordIds == null || recordIds.isEmpty()) {
            return 0;
        }
        DateTime when = System.now();
        List<Account> moves = new List<Account>();
        for (Id recId : recordIds) {
            Account m = new Account(Id = recId);
            m.OwnerId = newOwner;
            m.Handed_Over_From__c = previousOwner;
            m.Handed_Over_On__c = when;
            m.Handover_Run__c = trailRow;
            moves.add(m);
        }
        update moves;
        return moves.size();
    }

    /**
     * Moves the OPEN Opportunities of a chunk (AC1). Closed, Won and Lost
     * records are never loaded here, therefore they keep their owner (AC5).
     * @return how many records were saved
     */
    public static Integer moveOpenOpportunitiesChunk(List<Id> recordIds, Id previousOwner,
                                                     Id newOwner, Id trailRow) {
        if (recordIds == null || recordIds.isEmpty()) {
            return 0;
        }
        DateTime when = System.now();
        List<Opportunity> moves = new List<Opportunity>();
        for (Id recId : recordIds) {
            Opportunity m = new Opportunity(Id = recId);
            m.OwnerId = newOwner;
            m.Handed_Over_From__c = previousOwner;
            m.Handed_Over_On__c = when;
            m.Handover_Run__c = trailRow;
            moves.add(m);
        }
        OpportunityRiskService.systemWriteInProgress = true;
        try {
            update moves;
        } finally {
            OpportunityRiskService.systemWriteInProgress = false;
        }
        return moves.size();
    }

    /**
     * ADR-4 tier 2: a caught DmlException does NOT roll back what an earlier
     * statement already saved, so the revert is an explicit save. Fresh records
     * again: Owner restored, provenance cleared, nothing else touched (AC6).
     * @return how many records were reverted
     */
    public static Integer revertAccountsChunk(List<Id> recordIds, Id previousOwner) {
        if (recordIds == null || recordIds.isEmpty()) {
            return 0;
        }
        List<Account> back = new List<Account>();
        for (Id recId : recordIds) {
            Account r = new Account(Id = recId);
            r.OwnerId = previousOwner;
            r.Handed_Over_From__c = null;
            r.Handed_Over_On__c = null;
            r.Handover_Run__c = null;
            back.add(r);
        }
        update back;
        return back.size();
    }

    public static Integer revertOpenOpportunitiesChunk(List<Id> recordIds,
                                                       Id previousOwner) {
        if (recordIds == null || recordIds.isEmpty()) {
            return 0;
        }
        List<Opportunity> back = new List<Opportunity>();
        for (Id recId : recordIds) {
            Opportunity r = new Opportunity(Id = recId);
            r.OwnerId = previousOwner;
            r.Handed_Over_From__c = null;
            r.Handed_Over_On__c = null;
            r.Handover_Run__c = null;
            back.add(r);
        }
        OpportunityRiskService.systemWriteInProgress = true;
        try {
            update back;
        } finally {
            OpportunityRiskService.systemWriteInProgress = false;
        }
        return back.size();
    }
}
