/**
 * [SCRUM-453] SCRUM453ContactLeftHandler — Trigger handler for the "contact person
 * has left the customer's company" mark on Contact (ADR-2/ADR-4, docs/SCRUM-453-design.md).
 *
 * Three responsibilities, one Contact batch each:
 *   1. guardUndo      AC-6: clearing Has_Left_Company__c is refused unless the RUNNING
 *                     user holds SCRUM453_ContactLeft_Undo. FLS cannot do this (ADR-2):
 *                     setting and clearing edit the SAME Checkbox, so FLS is per field,
 *                     not per direction. Team lead = holder of that Permission Set
 *                     (ADR-3), resolved via UserInfo.getUserId() + a PermissionSetAssignment
 *                     query — both verified compiling in Test-Org (the Architect's probe
 *                     2026-10-22); $User/$Profile do NOT compile, do not plan on them.
 *   2. defaultLeftDate AC-2: mark set without a date -> date = today. Editable later.
 *   3. recompute      AC-8: full recompute of the three system-maintained Account
 *                     aggregates (SCRUM-416 handler pattern, not a declarative Rollup —
 *                     this repo has zero Rollup fields). Idempotent, drift-free, heals
 *                     re-parenting; write only on actual change.
 *
 * AC-9 (ADR-7): NOTHING automatic beyond the mark and its aggregates — no Mail, no
 * EmailMessage, no Task, no SetStatus, no FeedItem anywhere in this class or its
 * trigger. The newsletter consent fields NewsletterConsent__c / ConsentDate__c are
 * never read and never written here (AC-5).
 *
 * without sharing (house: OpportunityLockedAccountGuard): the undo gate is a security
 * gate; with sharing it would become profilable-dependent and could silently pass.
 *
 * Governor limits: per batch at most 1 PermissionSet + 1 PermissionSetAssignment
 * query (only when a clearing is present) and 2 aggregate SOQL + 1 Account SELECT
 * + 1 update (only when an Account actually changed). No SOQL inside a loop.
 * The Account update fires no Contact trigger -> no recursion.
 */
public without sharing class SCRUM453ContactLeftHandler {

    private static final String UNDO_PS_NAME = 'SCRUM453_ContactLeft_Undo';

    // @testVisible counters prove the bulkification in SCRUM453ContactLeftTest.
    @testVisible public static Integer undoPsSoqlCount = 0;
    @testVisible public static Integer recomputeSoqlCount = 0;

    // ---------- 1. AC-6: undo gate ----------
    public static void guardUndo(List<Contact> newRecords, Map<Id, Contact> oldMap) {
        List<Contact> clearing = new List<Contact>();
        for (Contact c : newRecords) {
            Contact old = oldMap.get(c.Id);
            if (old != null && old.Has_Left_Company__c && !c.Has_Left_Company__c) {
                clearing.add(c);
            }
        }
        if (clearing.isEmpty()) {
            return;
        }
        if (runningUserHoldsUndoPs()) {
            return;
        }
        for (Contact c : clearing) {
            c.addError('Undo blockiert: only a team lead (Permission Set '
                      + UNDO_PS_NAME + ') may clear the Austritt mark. The mark and its '
                      + 'date stay as they are.');
        }
    }

    /** 1 PermissionSet + 1 PermissionSetAssignment query, cached per call. */
    private static Boolean runningUserHoldsUndoPs() {
        Id me = UserInfo.getUserId();
        if (me == null) {
            return false;
        }
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet
                                    WHERE Name = :UNDO_PS_NAME LIMIT 1];
        undoPsSoqlCount++;
        if (sets.isEmpty()) {
            return false;
        }
        List<PermissionSetAssignment> mine = [SELECT Id FROM PermissionSetAssignment
                                              WHERE AssigneeId = :me
                                              AND PermissionSetId = :sets[0].Id
                                              LIMIT 1];
        return !mine.isEmpty();
    }

    // ---------- 2. AC-2: date defaults to the day of marking ----------
    public static void defaultLeftDate(List<Contact> newRecords) {
        for (Contact c : newRecords) {
            if (c.Has_Left_Company__c && c.Left_Company_Date__c == null) {
                c.Left_Company_Date__c = Date.today();
            }
        }
    }

    // ---------- touched Accounts of a batch ----------
    public static Set<Id> accountIds(List<Contact> recs) {
        Set<Id> ids = new Set<Id>();
        for (Contact c : recs) {
            if (c.AccountId != null) {
                ids.add(c.AccountId);
            }
        }
        return ids;
    }

    /** Update: only a mark/date change or a re-parenting changes an aggregate;
     * on re-parenting BOTH the old and the new Account are recomputed (SCRUM-416 AK4). */
    public static Set<Id> accountIdsChanged(List<Contact> newRecs, Map<Id, Contact> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Contact c : newRecs) {
            Contact old = oldMap.get(c.Id);
            if (old == null) {
                if (c.AccountId != null) {
                    ids.add(c.AccountId);
                }
                continue;
            }
            if (c.AccountId != old.AccountId
                    || c.Has_Left_Company__c != old.Has_Left_Company__c
                    || c.Left_Company_Date__c != old.Left_Company_Date__c) {
                if (c.AccountId != null) {
                    ids.add(c.AccountId);
                }
                if (old.AccountId != null) {
                    ids.add(old.AccountId);
                }
            }
        }
        return ids;
    }

    // ---------- 3. AC-8: full recompute of the Account aggregates ----------
    public static void recompute(Set<Id> accountIds) {
        if (accountIds.isEmpty()) {
            return;
        }
        Map<Id, Account> current = new Map<Id, Account>(
            [SELECT Id, Contacts_Without_Mark__c, Contacts_Left_Count__c, Last_Contact_Left_Date__c
             FROM Account WHERE Id IN :accountIds]);

        Map<Id, Integer> leftCnt = new Map<Id, Integer>();
        Map<Id, Integer> unmarkedCnt = new Map<Id, Integer>();
        Map<Id, Date> lastLeft = new Map<Id, Date>();

        // Marked: count + newest known leaving date.
        for (AggregateResult r : [SELECT AccountId, COUNT(Id) cnt, MAX(Left_Company_Date__c) newest
                                  FROM Contact
                                  WHERE AccountId IN :accountIds
                                  AND Has_Left_Company__c = true
                                  GROUP BY AccountId]) {
            Id accId = (Id) r.get('AccountId');
            leftCnt.put(accId, (Integer) r.get('cnt'));
            if (r.get('newest') != null) {
                lastLeft.put(accId, (Date) r.get('newest'));
            }
        }
        // Not marked: still there, so the customer keeps a contact person.
        for (AggregateResult r : [SELECT AccountId, COUNT(Id) cnt
                                  FROM Contact
                                  WHERE AccountId IN :accountIds
                                  AND Has_Left_Company__c = false
                                  GROUP BY AccountId]) {
            Id accId = (Id) r.get('AccountId');
            unmarkedCnt.put(accId, (Integer) r.get('cnt'));
        }
        recomputeSoqlCount += 2;

        List<Account> toUpdate = new List<Account>();
        for (Id accId : accountIds) {
            Account acc = current.get(accId);
            if (acc == null) {
                continue;
            }
            Integer newLeft = leftCnt.containsKey(accId) ? leftCnt.get(accId) : 0;
            Integer newWithout = unmarkedCnt.containsKey(accId) ? unmarkedCnt.get(accId) : 0;
            Date newLast = lastLeft.containsKey(accId) ? lastLeft.get(accId) : null;
            if (acc.Contacts_Left_Count__c != newLeft
                    || acc.Contacts_Without_Mark__c != newWithout
                    || acc.Last_Contact_Left_Date__c != newLast) {
                acc.Contacts_Left_Count__c = newLeft;
                acc.Contacts_Without_Mark__c = newWithout;
                acc.Last_Contact_Left_Date__c = newLast;
                toUpdate.add(acc);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
