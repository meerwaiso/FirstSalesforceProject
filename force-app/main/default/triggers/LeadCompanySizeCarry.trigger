/**
 * [SCRUM-476] Lead-Trigger: the ONLY carry-over point. A conversion flips
 * Lead.IsConverted false -> true and names the customer by Lead.ConvertedAccountId —
 * an exact Id, no name matching, no ambiguity (user decision 2026-11-24, ADR-4 round 2).
 *
 * The Account-side trigger of the first round (AccountCompanySizeCarry) is deleted: it
 * keyed on Lead.Company, so ANY new Account whose Name matched a sized Lead got the band —
 * with 19 Name-groups carrying duplicates in Test-Org (up to 35 Accounts in one Name) that
 * wrote employee bands onto records nobody aimed at.
 *
 * after update only: Trigger.oldMap carries the pre-save IsConverted, which is what makes
 * a flip distinguishable from an edit of an already converted lead (AC12). House proof for
 * after update + oldMap: OpportunityFollowupMonitorTrigger, deployed green.
 * Coexists with LeadDuplicateGuard (before insert/update) — different phase, no ordering
 * dependency. Handler: CompanySizeCarryHandler.
 */
trigger LeadCompanySizeCarry on Lead (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        CompanySizeCarryHandler.carryConvertedLeads(Trigger.new, Trigger.oldMap);
    }
}
