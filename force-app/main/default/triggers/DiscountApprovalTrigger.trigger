/**
 * [SCRUM-445] DiscountApprovalTrigger — wires DiscountApprovalHandler on Opportunity.
 *
 * before update: (a) discount raised above 15 % without a covering approval ->
 *   Discount_Approval__c = Pending + Approval_Requested_On__c = now + manager notified;
 *   (b) the manager's Approved/Rejected decision -> Approved_Discount_Value__c +
 *   decision fields (Approval_Decided_By__c / Approval_Decided_On__c).
 * before insert: a new Opportunity already above the threshold gets its request at once.
 *
 * The hard cap (25 %) and the blocked Closed Won are ValidationRules
 * (Discount_Hard_Cap_25, No_Won_Without_Approval) — declarative, not Apex.
 */
trigger DiscountApprovalTrigger on Opportunity (before insert, before update) {
    if (Trigger.isInsert) {
        DiscountApprovalHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        DiscountApprovalHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
