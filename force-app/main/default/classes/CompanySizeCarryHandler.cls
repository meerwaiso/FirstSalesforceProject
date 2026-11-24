/**
 * CompanySizeCarryHandler — SCRUM-476: carries the employee-size band a colleague
 * recorded on a Lead onto the customer (Account), exactly ONCE, and never over a
 * value that is already there. Nothing computes the band, nothing backfills it.
 *
 * ADR-4 / two entries, two save events:
 *   A) carryToNewAccounts  — a NEW customer is an Account INSERT. The band is looked
 *      up by name (Lead.Company is the name-based reference to Account.Name) and
 *      assigned IN PLACE in the after-save, so there is no second DML statement and
 *      no recursion.
 *   B) fillBlankCustomers  — ATTACHING a lead to an existing customer saves ONLY the
 *      Lead: the Account record is not part of that save, so no Account-side code can
 *      see the event. The fill is one bulkified update, SavePoint-wrapped, because the
 *      converter may not OWN that customer (design F-2): a CRUD/ownership refusal must
 *      never abort the lead save, otherwise the conversion itself would break.
 *
 * ADR-6: only a CHANGE of Lead.Company counts as an attach. Editing a sized lead
 * afterwards must not refill a customer (AC 12).
 * Both sides filter Company_Size__c = null, so the two paths are ordering-independent
 * and cannot double-write; `carried` is the per-transaction belt (the B-side update
 * re-fires the A-side trigger, which then sees a non-blank band anyway).
 *
 * Bulk: ONE SOQL per trigger event on each side, keyed by a Set of names; ONE bulk
 * update in B; ZERO queries when every customer already has a band or no Company
 * changed — Account is a hot object (imports, Data Cloud clean-ups).
 * Nothing on Contact, Opportunity, Case or any Feed/Email/Task record (design F-5).
 */
public without sharing class CompanySizeCarryHandler {

    // Accounts whose band this transaction already wrote. Never populated when a
    // write was rolled back, so a later attach attempt can still fill the record.
    @testVisible
    @testOnly
    private static Set<Id> carried = new Set<Id>();

    // ---------- A) new customer: the Account insert takes its lead's band ----------
    public static void carryToNewAccounts(List<Account> newAccounts) {
        List<Account> blank = new List<Account>();
        Set<String> names = new Set<String>();
        for (Account acct : newAccounts) {
            if (acct.Company_Size__c == null
                && acct.Name != null
                && !carried.contains(acct.Id)) {
                blank.add(acct);
                names.add(acct.Name.toLowerCase());
            }
        }
        if (blank.isEmpty()) {
            return; // band already set or nothing named: the save stays query-free
        }

        Map<String, String> band = bandsOfLeadsNamed(names);
        if (band.isEmpty()) {
            return; // no sized lead for these names: AC 2 — clean save, empty size
        }
        for (Account acct : blank) {
            String key = acct.Name.toLowerCase();
            if (!band.containsKey(key)) {
                continue;
            }
            // In-place on the after-save records: no extra DML, no re-entry.
            acct.Company_Size__c = band.get(key);
            carried.add(acct.Id);
        }
    }

    // ONE SOQL. ORDER BY Id ASC so the NEWEST lead wins for an ambiguous name
    // (open decision flagged to the PO: several sized leads, one new customer name).
    private static Map<String, String> bandsOfLeadsNamed(Set<String> names) {
        Map<String, String> band = new Map<String, String>();
        for (Lead lead : [
            SELECT Id, Company, Company_Size__c
            FROM Lead
            WHERE Company_Size__c != null AND Company IN :names
            ORDER BY Id ASC
        ]) {
            if (lead.Company != null) {
                band.put(lead.Company.toLowerCase(), lead.Company_Size__c);
            }
        }
        return band;
    }

    // ---------- B) attaching a lead: fill a BLANK existing customer only ----------
    public static void fillBlankCustomers(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        Map<String, String> band = new Map<String, String>();
        for (Lead lead : newLeads) {
            if (lead.Company_Size__c == null || lead.Company == null) {
                continue;
            }
            Lead old = oldMap == null ? null : oldMap.get(lead.Id);
            if (old == null) {
                continue; // not an update: no attach event to answer
            }
            String oldName = old.Company == null ? '' : old.Company.toLowerCase();
            String newName = lead.Company.toLowerCase();
            if (oldName == newName) {
                continue; // ADR-6 / AC 12: a lead edit is not an attach
            }
            band.put(newName, lead.Company_Size__c);
        }
        if (band.isEmpty()) {
            return;
        }

        List<String> names = band.keys();
        List<Account> write = new List<Account>();
        // The blank filter is server-side: a customer that already carries a band is
        // never even selected, so it can never be overwritten (AC 4).
        for (Account acct : [
            SELECT Id, Name, Company_Size__c
            FROM Account
            WHERE Company_Size__c = null AND Name IN :names
        ]) {
            if (acct.Name == null
                || carried.contains(acct.Id)
                || !band.containsKey(acct.Name.toLowerCase())) {
                continue;
            }
            acct.Company_Size__c = band.get(acct.Name.toLowerCase());
            write.add(acct);
        }
        if (write.isEmpty()) {
            return;
        }

        SavePoint guard;
        try {
            guard = SavePoint.set();
            update write; // ONE bulkified statement
            for (Account acct : write) {
                carried.add(acct.Id);
            }
        } catch (AccessException e) {
            SavePoint.release(guard);
            // F-2: the colleague who attaches the lead may not own that customer.
            // Refusing here must NOT abort the lead save — otherwise the conversion
            // or the attach itself would fail. The band simply stays for a reader
            // who may edit it, and `carried` stays empty so a later attach can fill.
        }
    }
}
