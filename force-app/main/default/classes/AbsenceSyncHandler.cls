/**
 * SCRUM-457: Mirror of Absence__c onto the customer (Account.Absence_*).
 *
 * One record per account manager and absence lives on Absence__c; the customer
 * page and the team-lead overview read it from the Account, so the handler
 * copies it down. A formula field cannot traverse the owner, hence Apex.
 *
 * AC7: the owner is NEVER written here — the handler only reads OwnerId to
 * find the Accounts. Do not confuse with CustomerTransferJob (SCRUM-410),
 * which exists precisely to change ownership and must not be reused.
 *
 * Governor limits (design §7): ONE Absence__c query, ONE User query (deputy
 * display names) and ONE Account query per trigger event, not one per record;
 * ONE bulk update. No SOQL inside a loop, no per-record DML.
 *
 * Recomputation is stateless: for every user touched by the event we re-read
 * the Absence__c records that still exist for that user and take the one with
 * the latest End__c that has not ended yet. That makes change (AC6), cancel
 * (delete) and "one of several absences cancelled" all follow immediately,
 * without a second write and without a nightly job.
 */
public class AbsenceSyncHandler {

    // A record only mirrors while it has not ended yet: End__c >= today
    // (PO assumption 1: absent through End__c inclusive). A record with a
    // blank End__c is an incomplete absence and shows nothing on the customer
    // (AC3: outside the absence the page must look exactly as today).
    private static boolean windowStillOpen(Date untilWhen) {
        return untilWhen != null && untilWhen >= Date.today();
    }

    /**
     * @param touchedUsers Users named by the records of the current event
     *                    (Absence__c.Absent_User__c).
     */
    public static void syncFor(Set<Id> touchedUsers) {
        if (touchedUsers == null || touchedUsers.isEmpty()) {
            return;
        }

        // 1. What absence is still open for each touched user? Latest End__c
        //    wins; ties go to the later record (Id has no relational operator
        //    in Apex, so compare it as String). The winner is kept as plain
        //    values, not as an Absence__c: a Map<Id, Absence__c> is refused by
        //    the compiler here ("no set(Id, Absence__c) on Map<Id,Absence__c>").
        Map<Id, Date> bestEnd = new Map<Id, Date>();
        Map<Id, Date> bestStart = new Map<Id, Date>();
        Map<Id, Id> bestDeputy = new Map<Id, Id>();
        Map<Id, Id> bestRecord = new Map<Id, Id>();
        Set<Id> deputyIds = new Set<Id>();

        for (Absence__c rec : [
                SELECT Id, Absent_User__c, Start__c, End__c, Deputy__c
                FROM Absence__c
                WHERE Absent_User__c IN :touchedUsers
        ]) {
            if (!windowStillOpen(rec.End__c)) {
                continue;
            }
            Id manager = rec.Absent_User__c;
            Id deputyId = rec.Deputy__c;
            Id previous = bestRecord.get(manager);
            if (previous == null
                || rec.End__c > bestEnd.get(manager)
                || (rec.End__c == bestEnd.get(manager)
                    && String.valueOf(rec.Id) > String.valueOf(previous))) {
                bestRecord.put(manager, rec.Id);
                bestEnd.put(manager, rec.End__c);
                bestStart.put(manager, rec.Start__c);
                bestDeputy.put(manager, deputyId);
                if (deputyId != null) {
                    deputyIds.add(deputyId);
                }
            }
        }

        // 2. Display names of the deputies. Measured: "rec.Deputy__c.Name" is
        //    refused by the compiler ("A non foreign key field cannot be
        //    referenced in a path expression"), so the names come from one
        //    User query instead of a path expression.
        Map<Id, String> deputyNameById = new Map<Id, String>();
        if (!deputyIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :deputyIds]) {
                Id uid = u.Id;
                deputyNameById.put(uid, u.Name);
            }
        }

        // 3. The customers of every touched user — one query, not one per record.
        //    Measured: the SOQL column for the Account owner is OwnerId
        //    ("No such column 'Owner' on entity 'Account'"); "Owner" is only
        //    the relationship alias used by report tokens (USERS.NAME).
        List<Account> accounts = [
            SELECT Id, OwnerId, Absence_Start__c, Absence_End__c, Absence_Deputy__c
            FROM Account
            WHERE OwnerId IN :touchedUsers
        ];

        List<Account> changed = new List<Account>();
        for (Account a : accounts) {
            Id managerId = a.OwnerId;
            boolean openAbsence = bestRecord.containsKey(managerId);

            Date mirrorStart = null;
            Date mirrorEnd = null;
            String mirrorDeputy = null;
            if (openAbsence) {
                mirrorStart = bestStart.get(managerId);
                mirrorEnd = bestEnd.get(managerId);
                Id deputyId = bestDeputy.get(managerId);
                if (deputyId != null) {
                    String deputyName = deputyNameById.get(deputyId);
                    if (deputyName != null && deputyName.length() > 80) {
                        deputyName = deputyName.substring(0, 80); // Account.Absence_Deputy__c is Text(80)
                    }
                    mirrorDeputy = deputyName;
                }
            }

            if (a.Absence_Start__c == mirrorStart
                && a.Absence_End__c == mirrorEnd
                && a.Absence_Deputy__c == mirrorDeputy) {
                continue; // nothing to write — keeps the update batch minimal
            }
            a.Absence_Start__c = mirrorStart;
            a.Absence_End__c = mirrorEnd;
            a.Absence_Deputy__c = mirrorDeputy;
            // OwnerId deliberately untouched (AC7).
            changed.add(a);
        }

        if (!changed.isEmpty()) {
            update changed; // house bulk idiom (CustomerTransferJob), minus the ownership change
        }
    }

    // One trigger block for the whole object (house pattern: "after insert,
    // after update, after delete" — "after save" is not an Apex event token).
    // Trigger.new / Trigger.oldMap are SObject, so the loop variable is SObject
    // and the record is cast ("expected SObject was Absence__c").
    public static void handleAfter() {
        Set<Id> touched = new Set<Id>();
        // Measured: on after insert Trigger.oldMap is NULL (not an empty map),
        // and on after delete Trigger.new is null — an unguarded .values() on
        // either throws NullPointerException and rolls the whole insert back.
        if (Trigger.new != null) {
            for (SObject so : Trigger.new) {
                Absence__c rec = (Absence__c) so;
                if (rec != null && rec.Absent_User__c != null) {
                    touched.add(rec.Absent_User__c);
                }
            }
        }
        // On a delete Trigger.new is empty and the cancelled records are in
        // oldMap; on an update oldMap holds the record before the change, so a
        // moved Absent_User__c clears the mirror of the previous manager too.
        if (Trigger.oldMap != null) {
            for (SObject so : Trigger.oldMap.values()) {
                Absence__c rec = (Absence__c) so;
                if (rec != null && rec.Absent_User__c != null) {
                    touched.add(rec.Absent_User__c);
                }
            }
        }
        syncFor(touched);
    }
}
