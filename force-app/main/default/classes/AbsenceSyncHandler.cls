/**
 * SCRUM-457: Mirror of Absence__c onto the customer (Account.Absence_*).
 *
 * One record per account manager and absence lives on Absence__c; the customer
 * page and the team-lead overview read it from the Account, so the handler
 * copies it down. A formula field cannot traverse Account.Owner, hence Apex.
 *
 * AC7: OwnerId is NEVER written here — the handler only reads Owner to find
 * the Accounts. Do not confuse with CustomerTransferJob (SCRUM-410), which
 * exists precisely to change ownership and must not be reused.
 *
 * Governor limits (design §7): ONE Absence__c query and ONE Account query per
 * trigger event (WHERE Owner IN :users), not one per record; ONE bulk update.
 * No SOQL inside a loop, no per-record DML.
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
    private static boolean windowStillOpen(Date end) {
        return end != null && end >= Date.today();
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
        //    wins; ties go to the later record (Id as String: Id has no
        //    relational operator in Apex).
        Map<Id, Absence__c> winnerByUser = new Map<Id, Absence__c>();
        for (Absence__c rec : [
                SELECT Id, Absent_User__c, Start__c, End__c, Deputy__c
                FROM Absence__c
                WHERE Absent_User__c IN :touchedUsers
        ]) {
            if (!windowStillOpen(rec.End__c)) {
                continue;
            }
            Id u = rec.Absent_User__;
            Absence__c current = winnerByUser.get(u);
            if (current == null
                || rec.End__c > current.End__c
                || (rec.End__c == current.End__c
                    && String.valueOf(rec.Id) > String.valueOf(current.Id))) {
                winnerByUser.set(u, rec);
            }
        }

        // 2. The customers of every touched user — one query, not one per record.
        List<Account> accounts = [
            SELECT Id, Owner, Absence_Start__c, Absence_End__c, Absence_Deputy__c
            FROM Account
            WHERE Owner IN :touchedUsers
        ];

        List<Account> changed = new List<Account>();
        for (Account a : accounts) {
            Id ownerId = a.Owner;
            Absence__c rec = winnerByUser.get(ownerId);

            Date mirrorStart = null;
            Date mirrorEnd = null;
            String mirrorDeputy = null;
            if (rec != null) {
                mirrorStart = rec.Start__c;
                mirrorEnd = rec.End__c;
                if (rec.Deputy__c != null) {
                    String name = rec.Deputy__c.Name;
                    if (name != null && name.length() > 80) {
                        name = name.substring(0, 80); // Account.Absence_Deputy__c is Text(80)
                    }
                    mirrorDeputy = name;
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

    public static void handleAfterSave(Absence__c[] after) {
        Set<Id> touched = new Set<Id>();
        for (Absence__c rec : after) {
            if (rec != null && rec.Absent_User__c != null) {
                touched.add(rec.Absent_User__);
            }
        }
        syncFor(touched);
    }

    public static void handleAfterDelete(Absence__c[] before) {
        // A deleted record can only clear the mirror — but the user may still
        // hold another, still-open absence, which syncFor() re-reads.
        Set<Id> touched = new Set<Id>();
        for (Absence__c rec : before) {
            if (rec != null && rec.Absent_User__c != null) {
                touched.add(rec.Absent_User__);
            }
        }
        syncFor(touched);
    }
}
