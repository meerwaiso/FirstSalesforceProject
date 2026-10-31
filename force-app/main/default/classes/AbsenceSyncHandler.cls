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
 * Governor limits (design §7): FIVE SOQL queries per trigger event (Q1–Q5
 * below), constant in the number of records; ONE bulk update. No SOQL inside a
 * loop, no per-record DML.
 *
 * The recompute is BIDIRECTIONAL (AC10): an event on the deputy's own absence
 * must re-flag every customer whose manager names that deputy, so the touched
 * users are widened with the managers that name them as deputy (Q1).
 *
 * Recomputation is stateless: for every user in play we re-read the Absence__c
 * records that still exist for that user and take the one with the latest
 * End__c that has not ended yet. Change (AC6), cancel (delete) and "one of
 * several absences cancelled" therefore follow immediately, without a second
 * write and without a nightly job.
 */
public class AbsenceSyncHandler {

    // A record only mirrors while it has not ended yet: End__c >= today
    // (PO assumption 1: absent through End__c inclusive). A record with a
    // blank End__c is an incomplete absence and shows nothing on the customer
    // (AC3: outside the absence the page must look exactly as today).
    private static boolean windowStillOpen(Date untilWhen) {
        return untilWhen != null && untilWhen >= Date.today();
    }

    // Winner per user over a set of Absence__c records: latest End__c, ties to
    // the later Id as String (Id has no relational operator in Apex).
    private static void consider(
        Map<Id, Id> winnerRec,
        Map<Id, Date> startByUser,
        Map<Id, Date> endByUser,
        Map<Id, Id> deputyByUser,
        Absence__c rec
    ) {
        Id user = rec.Absent_User__c;
        Id previous = winnerRec.get(user);
        if (previous == null
            || rec.End__c > endByUser.get(user)
            || (rec.End__c == endByUser.get(user)
                && String.valueOf(rec.Id) > String.valueOf(previous))) {
            winnerRec.put(user, rec.Id);
            startByUser.put(user, rec.Start__c);
            endByUser.put(user, rec.End__c);
            deputyByUser.put(user, rec.Deputy__c);
        }
    }

    /**
     * @param touchedUsers Users named by the records of the current event
     *                    (Absence__c.Absent_User__c) — in both directions.
     */
    public static void syncFor(Set<Id> touchedUsers) {
        if (touchedUsers == null || touchedUsers.isEmpty()) {
            return;
        }

        // Direction 2 (AC10): the customers of a manager whose deputy is one of
        // the touched users must be re-flagged as well.
        Set<Id> managers = new Set<Id>(touchedUsers);
        // Q1
        for (Absence__c rec : [
                SELECT Id, Absent_User__c
                FROM Absence__c
                WHERE Deputy__c IN :touchedUsers AND Absent_User__c != null
        ]) {
            managers.add(rec.Absent_User__c);
        }
        if (managers.isEmpty()) {
            return;
        }

        // Q2 — the manager's own open absences.
        Map<Id, Id> bestRecord = new Map<Id, Id>();
        Map<Id, Date> bestStart = new Map<Id, Date>();
        Map<Id, Date> bestEnd = new Map<Id, Date>();
        Map<Id, Id> bestDeputy = new Map<Id, Id>();
        Set<Id> deputyIds = new Set<Id>();

        for (Absence__c rec : [
                SELECT Id, Absent_User__c, Start__c, End__c, Deputy__c
                FROM Absence__c
                WHERE Absent_User__c IN :managers
        ]) {
            if (!windowStillOpen(rec.End__c)) {
                continue;
            }
            consider(bestRecord, bestStart, bestEnd, bestDeputy, rec);
        }
        for (Id managerId : bestDeputy.keySet()) {
            Id deputyId = bestDeputy.get(managerId);
            if (deputyId != null) {
                deputyIds.add(deputyId);
            }
        }

        // Q3 — the deputy's OWN open absence window (AC10). Mirrored as two
        // dates, not as a boolean: a boolean written at save time is wrong the
        // day the deputy's absence ends, and a nightly refresh is automation the
        // user ruled out (AC9).
        Map<Id, Id> depRecord = new Map<Id, Id>();
        Map<Id, Date> depStart = new Map<Id, Date>();
        Map<Id, Date> depEnd = new Map<Id, Date>();
        Map<Id, Id> depUnused = new Map<Id, Id>();
        // Measured: the Apex SOQL parser refuses TODAY() inside a query that
        // also binds a set ("Expecting ']' but was: '('"), so the boundary is a
        // bound Date variable, not a literal function.
        Date today = Date.today();
        if (!deputyIds.isEmpty()) {
            for (Absence__c rec : [
                    SELECT Id, Absent_User__c, Start__c, End__c
                    FROM Absence__c
                    WHERE Absent_User__c IN :deputyIds AND End__c >= :today
            ]) {
                consider(depRecord, depStart, depEnd, depUnused, rec);
            }
        }

        // Q4 — display names. Measured: "rec.Deputy__c.Name" is refused by the
        // compiler ("A non foreign key field cannot be referenced in a path
        // expression"), so the names come from one User query.
        Map<Id, String> deputyNameById = new Map<Id, String>();
        if (!deputyIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :deputyIds]) {
                Id uid = u.Id;
                deputyNameById.put(uid, u.Name);
            }
        }

        // Q5 — the customers of every manager in play, one query.
        List<Account> accounts = [
            SELECT Id, OwnerId, Absence_Start__c, Absence_End__c, Absence_Deputy__c,
                   Absence_Deputy_Start__c, Absence_Deputy_End__c
            FROM Account
            WHERE OwnerId IN :managers
        ];

        List<Account> changed = new List<Account>();
        for (Account a : accounts) {
            Id managerId = a.OwnerId;
            boolean openAbsence = bestRecord.containsKey(managerId);

            Date mirrorStart = null;
            Date mirrorEnd = null;
            String mirrorDeputy = null;
            Date mirrorDepStart = null;
            Date mirrorDepEnd = null;
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
                    mirrorDepStart = depStart.get(deputyId);
                    mirrorDepEnd = depEnd.get(deputyId);
                }
            }

            if (a.Absence_Start__c == mirrorStart
                && a.Absence_End__c == mirrorEnd
                && a.Absence_Deputy__c == mirrorDeputy
                && a.Absence_Deputy_Start__c == mirrorDepStart
                && a.Absence_Deputy_End__c == mirrorDepEnd) {
                continue; // nothing to write — keeps the update batch minimal
            }
            a.Absence_Start__c = mirrorStart;
            a.Absence_End__c = mirrorEnd;
            a.Absence_Deputy__c = mirrorDeputy;
            a.Absence_Deputy_Start__c = mirrorDepStart;
            a.Absence_Deputy_End__c = mirrorDepEnd;
            // OwnerId deliberately untouched (AC7).
            changed.add(a);
        }

        if (!changed.isEmpty()) {
            update changed; // house bulk idiom (CustomerTransferJob), minus the ownership change
        }
    }

    // AC1 clause: an account manager can never be their own deputy. The check
    // lives here, the exception is thrown in the trigger body — the Apex
    // compiler refuses SavePointError inside a class ("Invalid type: SavePointError",
    // measured on this deploy), and the house exception type is AuraHandledException.
    public static boolean ownDeputyViolation() {
        if (Trigger.new == null) {
            return false; // after delete
        }
        for (SObject so : Trigger.new) {
            Absence__c rec = (Absence__c) so;
            if (rec != null
                && rec.Deputy__c != null
                && rec.Deputy__c == rec.Absent_User__c) {
                return true;
            }
        }
        return false;
    }

    // One trigger block for the whole object (house pattern: "after insert,
    // after update, after delete" — "after save" is not an Apex event token,
    // measured: "Unexpected token 'save'").
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
