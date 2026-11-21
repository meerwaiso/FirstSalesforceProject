/**
 * SCRUM-468 Lend Devices: one loan at a time, never on a written-off device (AC4,
 * AC9 negative half), and the device half of a lending (AC3, AC6 setup).
 * The phase test matters: Trigger.isInsert is true in BOTH the before-insert and
 * the after-insert event, so a handler that runs once per batch must be pinned to
 * its phase with isBefore / isAfter - otherwise the write-back runs in the before
 * phase and the second half of the batch then trips the one-loan check (measured
 * in Test-Org: 8/8 test failures with 'device ... is already on loan').
 * Handler: LoanRecordGuard.
 */
trigger LoanRecordGuard on Loan_Record__c (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        LoanRecordGuard.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        LoanRecordGuard.handleAfterInsert(Trigger.new);
    }
}
