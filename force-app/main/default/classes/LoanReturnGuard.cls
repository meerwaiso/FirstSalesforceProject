/**
 * SCRUM-468 Lend Devices: recording a return makes the device Available again and
 * clears the current-lending fields on it (AC6).
 *
 * Fires only on the null -> filled transition of Loan_Return_Datum__c, so a plain
 * edit of an already returned loan touches nothing. A device that has been written
 * off keeps Written_Off: write-off is terminal, a late return of a lost device must
 * not undo it (PO decision + AC9). One bulk update of fresh sObjects.
 *
 * @author developer-agent
 * @date 2026-11-21
 */
public class LoanReturnGuard {

    public static void handleBeforeUpdate(List<Loan_Record__c> newRecords, Map<Id, Loan_Record__c> oldMap) {
        Set<Id> deviceIds = new Set<Id>();
        for (Loan_Record__c loan : newRecords) {
            Loan_Record__c before = oldMap.get(loan.Id);
            Date oldReturn = (before == null) ? null : before.Loan_Return_Datum__c;
            // SCRUM-468 round 4 (Architect AC7 shape): the history facts column carries
            // the actual return date and the duration in days. Written in beforeUpdate on
            // the record being saved - no extra DML, and only on the null -> filled
            // transition so a plain edit of a returned loan rewrites nothing.
            if (loan.Loan_Return_Datum__c != null && oldReturn == null) {
                String facts = 'returned ' + historyDate(loan.Loan_Return_Datum__c);
                if (loan.Loan_Duration_Days__c != null) {
                    // The duration comes from the existing formula field, read only: the
                    // Apex Date-minus-Date expression is rejected by this org's compiler
                    // ("Date expressions must use Integer or Long", validate 2026-11-22),
                    // while the formula field already carries the value as a Number.
                    facts = facts + ' / ' + loan.Loan_Duration_Days__c + ' Tage';
                }
                loan.Loan_History_Facts__c = facts;
            }
            if (loan.Loan_Return_Datum__c != null && oldReturn == null && loan.Loan_Devic__c != null) {
                deviceIds.add(loan.Loan_Devic__c);
            }
        }
        if (deviceIds.isEmpty()) {
            return;
        }
        List<Demo_Devic__c> updateList = new List<Demo_Devic__c>();
        for (Demo_Devic__c device : [SELECT Id, Status__c FROM Demo_Devic__c WHERE Id IN :deviceIds]) {
            if (device.Status__c == 'Written_Off') {
                continue;
            }
            Demo_Devic__c fresh = new Demo_Devic__c(Id = device.Id, Status__c = 'Available');
            fresh.Current_Customer__c = null;
            fresh.Current_Loan_Colleague__c = null;
            fresh.Current_Loan_Due_Date__c = null;
            updateList.add(fresh);
        }
        if (!updateList.isEmpty()) {
            update updateList;
        }
    }

    // dd.mm.yyyy, same shape as the lend-time facts in LoanRecordGuard.
    private static String historyDate(Date d) {
        String day = String.valueOf(d.getDay());
        String month = String.valueOf(d.getMonth());
        if (d.getDay() < 10) {
            day = '0' + day;
        }
        if (d.getMonth() < 10) {
            month = '0' + month;
        }
        return day + '.' + month + '.' + String.valueOf(d.getYear());
    }
}
