/**
 * CompanySizeCarryHandler — SCRUM-476: carries the employee-size band a colleague
 * recorded on a Lead onto the customer (Account), exactly ONCE, and never over a
 * value that is already there. Nothing computes the band, nothing backfills it.
 *
 * ADR-4, review round 2 (user decision, 2026-11-24): a lead conversion is NOT a change
 * of Lead.Company. It flips Lead.IsConverted false -> true and writes
 * Lead.ConvertedAccountId, and THAT ID names the customer exactly. So there is no name
 * matching anywhere and no ambiguity can exist:
 *
 *   one entry, one save event: carryConvertedLeads(List<Lead>, Map<Id,Lead>)
 *
 * Why the name-based path was deleted (measured, see docs/SCRUM-476-notizen.md): the old
 * Account-insert entry wrote the band onto ANY new Account whose Name matched a sized
 * Lead. Test-Org holds 268 Accounts under 106 distinct Names — 19 Name-groups carry
 * duplicates, up to 35 Accounts in one group — so that path put a wrong employee band on
 * records nobody aimed at, which violates "nothing else happens when a size is set".
 * The Account-side trigger AccountCompanySizeCarry is deleted with this change; the fill
 * now happens on the Lead side, keyed by ConvertedAccountId.
 *
 * Semantics (AC 4 / AC 5 / AC 12):
 *   - only a conversion counts: IsConverted false -> true, ConvertedAccountId != null.
 *     Editing an already converted lead afterwards changes nothing (AC 12).
 *   - never overwrite: the blank check is a SERVER-SIDE filter
 *     (WHERE ... Company_Size__c = null), so "an existing band wins" is a property of
 *     the query, not of a branch that could be reasoned away.
 *   - a refused write must never abort the conversion: the update is Savepoint-wrapped
 *     with the Database API, which EXISTS in this org — measured 2026-11-24
 *     (Database.setSavepoint() compiles; Database.Rollback(sp) undid an update and the
 *     probe script ran to completion). My earlier note about a missing rollback primitive
 *     probed the wrong shapes (the Savepoint type's set()/pop(), a SAVEPOINT STATEMENT),
 *     not this API.
 *
 * Governor limits: the entry returns BEFORE any query unless a Lead in this batch
 * actually flipped IsConverted, so an ordinary Lead save stays query-free; ONE SOQL per
 * trigger event keyed by a Set<Id>, ONE bulkified update.
 * Nothing on Contact, Opportunity, Case, or any Feed/EmailMessage/Task record (F-5).
 */
public without sharing class CompanySizeCarryHandler {

    public static void carryConvertedLeads(List<Lead> after, Map<Id, Lead> before) {
        // Account Id -> the Lead whose band wins for that customer. Several Leads in ONE
        // save can name the SAME customer (the UI attach path does; the Apex convertLead
        // path cannot — measured 2026-11-24: sameRecord=false, one new Account per
        // conversion, and Lead.ConvertedAccountId is "not writeable" on the wire). The
        // PO's accepted tie-break is "newest lead wins", so the winner is picked by Id —
        // Salesforce Ids increase with creation — and never by save order, which the
        // platform does not define. Deterministic by construction, not "last saved".
        Map<Id, Lead> winnerOfCustomer = new Map<Id, Lead>();
        for (Lead l : after) {
            if (!l.IsConverted
                || l.ConvertedAccountId == null
                || l.Company_Size__c == null) {
                continue; // nothing to carry: no band on the lead / not converted here
            }
            Lead was = before.get(l.Id);
            if (was == null || was.IsConverted) {
                // was == null: no pre-save record (defensive; updates always carry oldMap).
                // was.IsConverted: converted BEFORE this save -> not a flip -> AC 12, an
                // edit of an already converted lead never re-fills its customer.
                continue;
            }
            Lead held = winnerOfCustomer.get(l.ConvertedAccountId);
            if (held == null || l.Id > held.Id) {
                winnerOfCustomer.put(l.ConvertedAccountId, l); // newest Lead wins (AC 13 tie-break)
            }
        }
        if (winnerOfCustomer.isEmpty()) {
            return; // no conversion in this save: zero queries, zero writes
        }

        Set<Id> targets = winnerOfCustomer.keySet(); // Map.keySet() -> Set<Id> (measured)
        List<Account> blank = [
            SELECT Id, Company_Size__c
            FROM Account
            WHERE Id IN :targets AND Company_Size__c = null
        ];
        if (blank.isEmpty()) {
            return; // every target already carries a band: AC 4, nothing touched
        }

        // Fresh sObjects carrying Id + the written field only (house SCRUM-459): an update
        // of a queried record writes every field in its cache, and one of those may not be
        // writeable for reasons unrelated to this band.
        List<Account> write = new List<Account>();
        for (Account a : blank) {
            write.add(new Account(Id = a.Id, Company_Size__c = winnerOfCustomer.get(a.Id).Company_Size__c));
        }

        Savepoint carried = Database.setSavepoint();
        try {
            update write; // ONE bulkified statement
        } catch (Exception e) {
            // Ownership, FLS or a Validation Rule of another ticket refused the write:
            // roll the whole statement back, so no customer ends up half-written and the
            // Lead save — the conversion or the attach itself — continues (design F-2).
            Database.Rollback(carried);
        }
    }
}
