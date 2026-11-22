/**
 * SCRUM-468 Lend Devices: one loan at a time + never a loan on a written-off device
 * (AC4, AC9 negative half), and the device half of a lending (AC3, AC6 setup).
 *
 * BeforeInsert reads the device state ONCE for the whole batch, so a batch that
 * lends the same device twice is caught by the batch-local Set, not by a per-record
 * re-query. AfterInsert writes the device back in ONE bulk update of FRESH sObjects
 * (Id + the written fields only) - updating the records just read would also try to
 * write Serial_Number__c and Name, which are not writeable that way (SCRUM-459).
 *
 * @author developer-agent
 * @date 2026-11-21
 */
public class LoanRecordGuard {

    public static void handleBeforeInsert(List<Loan_Record__c> newRecords) {
        // SCRUM-468 round 4 (Architect AC7 shape): the history facts column is guard-
        // written Text, not a formula - a formula column does not render in the device
        // history list and the field type cannot be changed in place. Assigned in
        // beforeInsert so it saves with the record and needs no extra DML.
        for (Loan_Record__c loan : newRecords) {
            if (loan.Loan_Due_Datum__c != null) {
                loan.Loan_History_Facts__c = 'open / due ' + historyDate(loan.Loan_Due_Datum__c);
            }
        }
        Set<Id> deviceIds = new Set<Id>();
        Set<Id> customerIds = new Set<Id>();
        for (Loan_Record__c loan : newRecords) {
            if (loan.Loan_Devic__c != null) {
                deviceIds.add(loan.Loan_Devic__c);
            }
            if (loan.Loan_Customer__c != null) {
                customerIds.add(loan.Loan_Customer__c);
            }
        }
        if (deviceIds.isEmpty()) {
            return;
        }
        Map<Id, Demo_Devic__c> devices = new Map<Id, Demo_Devic__c>();
        for (Demo_Devic__c device : [SELECT Id, Name, Status__c, Current_Customer__c FROM Demo_Devic__c WHERE Id IN :deviceIds]) {
            devices.put(device.Id, device);
        }
        Map<Id, String> customerNames = new Map<Id, String>();
        if (!customerIds.isEmpty()) {
            for (Account customer : [SELECT Id, Name FROM Account WHERE Id IN :customerIds]) {
                customerNames.put(customer.Id, customer.Name);
            }
        }
        Id currentUserId = UserInfo.getUserId();
        // Only an OPEN loan claims a device: a device that was returned in this same
        // save may be lent on again, and the fixture batch writes the whole history of
        // one device in one bulk insert (closed loans first, the open one last).
        Set<Id> openInBatch = new Set<Id>();
        for (Loan_Record__c loan : newRecords) {
            if (loan.Loan_Devic__c == null) {
                loan.addError('Lend Devices: a loan record must name the device it is for (Loan_Devic__c is blank).');
                continue;
            }
            Demo_Devic__c device = devices.get(loan.Loan_Devic__c);
            if (device == null) {
                loan.addError('Lend Devices: the loan names a device that does not exist - a loan needs a real device.');
                continue;
            }
            if (device.Status__c == 'Written_Off') {
                loan.addError('Lend Devices: device ' + device.Name + ' is written off and can never be lent out again.');
                continue;
            }
            if (device.Status__c == 'Lent_Out' || openInBatch.contains(device.Id)) {
                String withWhom = customerNames.containsKey(device.Current_Customer__c)
                    ? customerNames.get(device.Current_Customer__c)
                    : 'a customer not in this save';
                loan.addError('Lend Devices: device ' + device.Name + ' is already on loan to ' + withWhom
                    + ' - a device may be with exactly one customer at a time.');
            }
            if (loan.Loan_Return_Datum__c == null) {
                openInBatch.add(device.Id);
            }
            // The colleague is the saving user unless the caller named one explicitly.
            if (loan.Loan_Colleague__c == null) {
                loan.Loan_Colleague__c = currentUserId;
            }
        }
    }

    public static void handleAfterInsert(List<Loan_Record__c> newRecords) {
        Map<Id, Loan_Record__c> loanByDevice = new Map<Id, Loan_Record__c>();
        List<Id> deviceIds = new List<Id>();
        for (Loan_Record__c loan : newRecords) {
            if (loan.Loan_Devic__c != null) {
                loanByDevice.put(loan.Loan_Devic__c, loan);
                deviceIds.add(loan.Loan_Devic__c);
            }
        }
        if (loanByDevice.isEmpty()) {
            return;
        }
        List<Demo_Devic__c> updateList = new List<Demo_Devic__c>();
        for (Demo_Devic__c device : [SELECT Id, Name, Current_Customer__c FROM Demo_Devic__c WHERE Id IN :deviceIds]) {
            Loan_Record__c loan = loanByDevice.get(device.Id);
            Demo_Devic__c fresh = new Demo_Devic__c(Id = device.Id, Status__c = 'Lent_Out');
            fresh.Current_Customer__c = loan.Loan_Customer__c;
            fresh.Current_Loan_Colleague__c = loan.Loan_Colleague__c;
            fresh.Current_Loan_Due_Date__c = loan.Loan_Due_Datum__c;
            updateList.add(fresh);
        }
        if (!updateList.isEmpty()) {
            update updateList;
        }
    }

    // dd.mm.yyyy so the history column reads like the dates the PO names in AC7.
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
