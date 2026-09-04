/**
 * Lead-Dubletten-Markierung per E-Mail (SCRUM-386): Lead gegen Lead, case-insensitive.
 *
 * ADR-3 one-pass: dbMap (1 SOQL, oldest non-converted lead per normalized email)
 * + batchFirst (first candidate of the run per normalized email).
 * ref = dbMap[norm] else batchFirst[norm] else unique.
 * before insert: AC2, AC5. before update: only on effective email change (AC3, AC3b, ADR-4).
 * Converted leads: never marked, never reference (ADR-6). without sharing (ADR-5).
 * Bulk: 1 SOQL per trigger invocation, 0 DML, 0 SOQL in loop, O(batch) memory.
 */
public without sharing class LeadDuplicateGuard {

    public static void handleBeforeInsert(List<Lead> newLeads) {
        resolveCore(newLeads, null, new Set<Id>(), false);
    }

    public static void handleBeforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        // Own records of this run must not serve as DB references (no self-match).
        Set<Id> excludeIds = new Set<Id>();
        for (Lead lead : newLeads) {
            if (lead.Id != null) {
                excludeIds.add(lead.Id);
            }
        }
        resolveCore(newLeads, oldMap, excludeIds, true);
    }

    private static void resolveCore(
        List<Lead> candidates,
        Map<Id, Lead> oldMap,
        Set<Id> excludeIds,
        Boolean isUpdate
    ) {
        List<Lead> targets = new List<Lead>();
        Set<String> normSet = new Set<String>();

        for (Lead lead : candidates) {
            // Carry Email_Norm__c on every lead (ADR-2 / backfill hygiene).
            lead.Email_Norm__c = normOf(lead.Email);
            if (!lead.IsConverted) {
                if (lead.Email_Norm__c == null) {
                    // AC4 / AC3b: a non-converted lead without email is never marked.
                    // On update this also clears a previously set flag + reference
                    // (email changed to blank must clear, symmetric to unique email).
                    if (isUpdate) {
                        lead.Likely_Duplicate__c = false;
                        lead.Duplicate_Of__c = null;
                    }
                } else {
                    if (isUpdate) {
                        Lead oldLead = oldMap == null ? null : oldMap.get(lead.Id);
                        String oldNorm = normOf(oldLead == null ? null : oldLead.Email);
                        if (lead.Email_Norm__c != oldNorm) {
                            targets.add(lead);
                            normSet.add(lead.Email_Norm__c);
                        }
                    } else {
                        targets.add(lead);
                        normSet.add(lead.Email_Norm__c);
                    }
                }
            }
        }

        if (targets.isEmpty()) {
            return;
        }

        // dbMap: 1 SOQL, oldest non-converted lead per normalized email.
        Map<String, Lead> dbMap = new Map<String, Lead>();
        for (Lead existing : [
            SELECT Id, Name, CreatedDate, Email_Norm__c
            FROM Lead
            WHERE IsConverted = false AND Email_Norm__c IN :normSet
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (
                (excludeIds == null || !excludeIds.contains(existing.Id))
                && !dbMap.containsKey(existing.Email_Norm__c)
            ) {
                dbMap.put(existing.Email_Norm__c, existing);
            }
        }

        Map<String, Lead> batchFirst = new Map<String, Lead>();
        for (Lead lead : targets) {
            String norm = lead.Email_Norm__c;
            Lead ref = dbMap.get(norm);
            if (ref == null) {
                ref = batchFirst.get(norm);
            }
            if (ref != null) {
                lead.Likely_Duplicate__c = true;
                lead.Duplicate_Of__c = displayName(ref);
            } else if (isUpdate) {
                lead.Likely_Duplicate__c = false;
                lead.Duplicate_Of__c = null;
            }
            if (!batchFirst.containsKey(norm)) {
                batchFirst.put(norm, lead);
            }
        }
    }

    @testVisible
    private static String normOf(String email) {
        if (email == null) {
            return null;
        }
        String t = email.trim();
        if (t == '') {
            return null;
        }
        return t.toLowerCase();
    }

    private static String displayName(Lead ref) {
        String name = ref.Name;
        if (name == null || name == '') {
            name = ref.Email_Norm__c;
        }
        return name;
    }
}
