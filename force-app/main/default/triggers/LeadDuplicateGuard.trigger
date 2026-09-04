/**
 * Lead-Trigger (SCRUM-386): Dubletten-Markierung per E-Mail.
 * before insert: neue Leads gegen DB + Batch pruefen (AC2, AC5).
 * before update: nur bei veraenderter Email neu bewerten (AC3, AC3b, AC4).
 * Konvertierte Leads: nie markiert, nie Referenz (ADR-6).
 */
trigger LeadDuplicateGuard on Lead (before insert, before update) {
    if (Trigger.isInsert) {
        LeadDuplicateGuard.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isUpdate) {
        LeadDuplicateGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
