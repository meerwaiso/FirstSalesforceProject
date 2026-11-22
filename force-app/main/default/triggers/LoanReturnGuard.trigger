/**
 * SCRUM-468 Lend Devices: recording a return puts the device back to Available
 * and clears its current-lending fields (AC6, AC7 history stays in Loan_Record__c).
 * Fires only when Loan_Return_Datum__c goes from blank to filled.
 * Handler: LoanReturnGuard.
 */
trigger LoanReturnGuard on Loan_Record__c (before update) {
    if (Trigger.isUpdate) {
        LoanReturnGuard.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
