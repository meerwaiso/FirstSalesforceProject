/**
 * [SCRUM-476] Lead-Trigger: attaching a lead to an EXISTING customer fills that
 * customer only while it is still blank (AC4, AC5, AC12). The attach saves ONLY the
 * Lead — the Account record is not part of that save — so no Account-side code can
 * see the event and the fill has to live here (design ADR-4).
 *
 * ADR-6: the attach is a CHANGE of Lead.Company, not every lead save. Editing a
 * sized lead afterwards must never refill a customer (AC12).
 * after update only: Trigger.oldMap holds the pre-save Company (house proof:
 * OpportunityFollowupMonitorTrigger, after update + oldMap, deployed green).
 * Coexists with LeadDuplicateGuard (before insert/update) — different phase, no
 * ordering dependency. Handler: CompanySizeCarryHandler.
 */
trigger LeadCompanySizeCarry on Lead (before update, after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        CompanySizeCarryHandler.fillBlankCustomers(Trigger.new, Trigger.oldMap);
    }
}
