/**
 * SCRUM-333: VIP case priority service (with Contact fallback).
 *
 * Bulk-safe: 2 SOQL + 1 DML per batch (max).
 *
 * Case -> Account resolution:
 *   1. Direct: Case.AccountId
 *   2. Fallback: Case.ContactId -> Contact.AccountId (case linked to a Contact only)
 *
 * VIP flag: Account.VIP_Customer__c == true
 * Priority: 'High' on Before-INSERT
 * FeedItem: "VIP-Kunde – bitte innerhalb von 2 Stunden reagieren" on After-INSERT
 * Fallback to CaseComment if FeedItem insert fails (chatter-disabled org).
 *
 * @author developer-agent
 * @date 2026-08-21
 */
public without sharing class CasePriorityTrigger {

    private static final String VIP_CASE_MESSAGE =
        'VIP-Kunde \u2013 bitte innerhalb von 2 Stunden reagieren';

    public static void beforeInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }
        BatchData data = buildBatchData(newCases);
        if (data.vipAccountIds.isEmpty()) {
            return;
        }
        for (Case c : newCases) {
            Id linkedAcct = resolveCaseAccountId(c, data.contactIdToAccountId);
            if (linkedAcct != null && data.vipAccountIds.contains(linkedAcct)) {
                c.Priority = 'High';
            }
        }
    }

    public static void afterInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }
        BatchData data = buildBatchData(newCases);
        if (data.vipAccountIds.isEmpty()) {
            return;
        }
        List<Case> vipCases = new List<Case>();
        for (Case c : newCases) {
            Id linkedAcct = resolveCaseAccountId(c, data.contactIdToAccountId);
            if (c.Id != null && linkedAcct != null && data.vipAccountIds.contains(linkedAcct)) {
                vipCases.add(c);
            }
        }
        if (vipCases.isEmpty()) {
            return;
        }
        List<FeedItem> feedItems = new List<FeedItem>();
        for (Case c : vipCases) {
            feedItems.add(new FeedItem(
                ParentId = c.Id,
                Type = 'TextPost',
                Body = VIP_CASE_MESSAGE
            ));
        }
        try {
            insert feedItems;
        } catch (Exception e) {
            List<CaseComment> fallbacks = new List<CaseComment>();
            for (Case c : vipCases) {
                fallbacks.add(new CaseComment(
                    ParentId = c.Id,
                    CommentBody = VIP_CASE_MESSAGE
                ));
            }
            insert fallbacks;
        }
    }

    private class BatchData {
        public Set<Id> vipAccountIds;
        public Map<Id, Id> contactIdToAccountId;
    }

    private static BatchData buildBatchData(List<Case> cases) {
        BatchData data = new BatchData();
        data.contactIdToAccountId = new Map<Id, Id>();

        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Case c : cases) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
            if (c.ContactId != null) {
                contactIds.add(c.ContactId);
            }
        }

        // Bulk 1: Contact -> AccountId (fallback path)
        if (!contactIds.isEmpty()) {
            for (Contact ct : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds]) {
                if (ct.AccountId != null) {
                    data.contactIdToAccountId.put(ct.Id, ct.AccountId);
                    accountIds.add(ct.AccountId);
                }
            }
        }

        // Bulk 2: Account VIP filter
        if (!accountIds.isEmpty()) {
            data.vipAccountIds = new Set<Id>();
            for (Account a : [
                SELECT Id
                FROM Account
                WHERE Id IN :accountIds AND VIP_Customer__c = true
            ]) {
                data.vipAccountIds.add(a.Id);
            }
        } else {
            data.vipAccountIds = new Set<Id>();
        }

        return data;
    }

    private static Id resolveCaseAccountId(Case c, Map<Id, Id> contactIdToAccountId) {
        if (c.AccountId != null) {
            return c.AccountId;
        }
        if (c.ContactId != null && contactIdToAccountId != null) {
            return contactIdToAccountId.get(c.ContactId);
        }
        return null;
    }
}