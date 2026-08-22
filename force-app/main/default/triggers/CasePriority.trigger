/**
 * SCRUM-333: VIP case priority trigger (with Contact fallback).
 *
 * Before-Insert: auto-set Priority = 'High' when the linked Account is VIP.
 *   Resolution: direct Case.AccountId first; fallback via first related Contact if
 *   Case.AccountId is null (case was created against a Contact on a non-VIP
 *   default, or the Case was linked to a Contact whose AccountId differs).
 * After-Insert: post a FeedItem "VIP-Kunde – bitte innerhalb von 2 Stunden reagieren"
 *   on the case (Fallback CaseComment if FeedItem insert fails in the org).
 *
 * @author developer-agent
 * @date 2026-08-21
 */
trigger CasePriorityTrigger on Case (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        CasePriorityService.beforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        CasePriorityService.afterInsert(Trigger.new);
    }
}