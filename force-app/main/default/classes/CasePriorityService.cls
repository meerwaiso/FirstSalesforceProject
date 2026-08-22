/**
 * SCRUM-333: VIP case priority service (with Contact fallback).
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
public without sharing class CasePriorityService {

    private static final String VIP_CASE_MESSAGE =
        'VIP-Kunde \u2013 bitte innerhalb von 2 Stunden reagieren';

    public static void beforeInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }
        Set<Id> vipAccountIds = findVipAccountsForCases(newCases);
        if (vipAccountIds.isEmpty()) {
            return;
        }
        for (Case c : newCases) {
            Id linkedAcct = resolveCaseAccountId(c, newCases);
            if (linkedAcct != null && vipAccountIds.contains(linkedAcct)) {
                c.Priority = 'High';
            }
        }
    }

    public static void afterInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) {
            return;
        }
        Set<Id> vipAccountIds = findVipAccountsForCases(newCases);
        if (vipAccountIds.isEmpty()) {
            return;
        }
        List<Case> vipCases = new List<Case>();
        for (Case c : newCases) {
            Id linkedAcct = resolveCaseAccountId(c, newCases);
            if (c.Id != null && linkedAcct != null && vipAccountIds.contains(linkedAcct)) {
                vipCases.add(c);
            }
        }
        if (vipCases.isEmpty()) {
            return;
        }
        List<FeedItem> feedItems = new List<FeedItem>();
        List<CaseComment> fallbacks = new List<CaseComment>();
        for (Case c : vipCases) {
            feedItems.add(new FeedItem(
                ParentId = c.Id,
                Type = 'TextPost',
                Body = VIP_CASE_MESSAGE
            ));
            fallbacks.add(new CaseComment(
                ParentId = c.Id,
                CommentBody = VIP_CASE_MESSAGE
            ));
        }
        try {
            insert feedItems;
        } catch (Exception e) {
            insert fallbacks;
        }
    }

    private static Set<Id> findVipAccountsForCases(List<Case> cases) {
        Set<Id> accountIds = new Set<Id>();
        Map<Id, Id> caseIdToContact = new Map<Id, Id>();
        for (Case c : cases) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
            if (c.ContactId != null) {
                caseIdToContact.put(c.ContactId, c.ContactId);
            }
        }
        Set<Id> contactIds = new Set<Id>(caseIdToContact.keySet());
        if (!contactIds.isEmpty()) {
            for (Contact ct : [SELECT AccountId FROM Contact WHERE Id IN :contactIds]) {
                if (ct.AccountId != null) {
                    accountIds.add(ct.AccountId);
                }
            }
        }
        if (accountIds.isEmpty()) {
            return new Set<Id>();
        }
        Set<Id> vipIds = new Set<Id>();
        for (Account a : [
            SELECT Id
            FROM Account
            WHERE Id IN :accountIds AND VIP_Customer__c = true
        ]) {
            vipIds.add(a.Id);
        }
        return vipIds;
    }

    private static Id resolveCaseAccountId(Case c, List<Case> allCases) {
        if (c.AccountId != null) {
            return c.AccountId;
        }
        if (c.ContactId != null) {
            for (Contact ct : [SELECT AccountId FROM Contact WHERE Id = :c.ContactId LIMIT 1]) {
                if (ct.AccountId != null) {
                    return ct.AccountId;
                }
            }
        }
        return null;
    }
}