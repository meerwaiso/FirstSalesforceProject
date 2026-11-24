/**
 * [SCRUM-476] Account-Trigger: a NEW customer takes the employee-size band of the
 * lead that carries its name (AC1, AC2, AC6). Only the insert branch acts — a new
 * customer is an Account INSERT, and an ordinary customer save therefore costs
 * zero queries (Account is a hot object: imports, Data Cloud clean-ups).
 *
 * M4: AccountLockGuard is the only other Account trigger and runs before update,
 * so ordering with it is irrelevant. Handler: CompanySizeCarryHandler (ADR-4).
 */
trigger AccountCompanySizeCarry on Account (after insert, after update) {
    if (Trigger.isInsert) {
        CompanySizeCarryHandler.carryToNewAccounts(Trigger.new);
    }
}
