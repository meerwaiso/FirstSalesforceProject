/**
 * [SCRUM-468] SCRUM468LendDevicesTest - the lending rules on the device and its history.
 *
 * AC1  four devices recorded with designation and serial (TAC1)
 * AC2  a serial may belong to exactly one device (TAC2n: the duplicate save is refused)
 * AC3  lending fills the device half; the colleague defaults to the saving user (TAC3)
 * AC4  a device already on loan cannot be lent to a second customer (TAC4n)
 * AC6  recording a return makes the device Available and clears the current fields (TAC6)
 * AC7  the whole lending history survives returns (TAC7 counts, incl. durations)
 * AC8  the overdue data behind the report: 2 devices past due, longest overdue first (TAC8)
 * AC9  a sales team lead (holder of SCRUM468_Writeoff) may write a device off (TAC9)
 * AC12 nothing happens by itself: an overdue device is still Lent_Out with an open loan
 *
 * Test data (the counts the Tester is given, measured from the fixtures below):
 * 4 devices, 6 loans (2 still open, both past their due date: 30 and 15 days;
 * 4 loans returned, one of them 14 days long), 3 customers, 1 written-off device.
 *
 * MIXED_DML house rule (SCRUM-442): every System-mode DML (fixtures, users,
 * PermissionSetAssignment) comes first; the only user-mode DML is the write-off
 * under System.runAs, and it is the LAST method of this class.
 *
 * @author developer-agent
 * @date 2026-11-21
 */
@isTest
public class SCRUM468LendDevicesTest {

    private static final Date TODAY = Date.today();

    @TestSetup
    static void setup_fixtures() {
        Account alpha = new Account(Name = '468 Customer Alpha');
        Account beta = new Account(Name = '468 Customer Beta');
        Account gamma = new Account(Name = '468 Customer Gamma');
        insert new List<Account>{ alpha, beta, gamma };

        List<Demo_Devic__c> devices = new List<Demo_Devic__c>{
            new Demo_Devic__c(Designation_Name__c = 'Measuring instrument A', Serial_Number__c = 'SN-468-001'),
            new Demo_Devic__c(Designation_Name__c = 'Handheld scanner B', Serial_Number__c = 'SN-468-002'),
            new Demo_Devic__c(Designation_Name__c = 'Laptop with our software C', Serial_Number__c = 'SN-468-003'),
            new Demo_Devic__c(Designation_Name__c = 'Handheld scanner D', Serial_Number__c = 'SN-468-004')
        };
        insert devices;
        System.assertEquals(4, devices.size(), 'AC1: four devices seeded');

        Map<String, Id> bySerial = new Map<String, Id>();
        for (Demo_Devic__c d : [SELECT Id, Serial_Number__c FROM Demo_Devic__c WHERE Serial_Number__c LIKE 'SN-468%']) {
            bySerial.put(d.Serial_Number__c, d.Id);
        }
        System.assertEquals(4, bySerial.size(), 'AC1: all four devices are readable by serial');

        // Batch A: one open loan per device. LoanRecordGuard writes each device to Lent_Out.
        Loan_Record__c l6 = new Loan_Record__c(
            Loan_Devic__c = bySerial.get('SN-468-002'), Loan_Customer__c = alpha.Id,
            Loan_Start_Datum__c = TODAY - 80, Loan_Due_Datum__c = TODAY - 70, Loan_Return_Datum__c = TODAY - 70);
        Loan_Record__c l1 = new Loan_Record__c(
            Loan_Devic__c = bySerial.get('SN-468-001'), Loan_Customer__c = alpha.Id,
            Loan_Start_Datum__c = TODAY - 120, Loan_Due_Datum__c = TODAY - 100);
        Loan_Record__c l3 = new Loan_Record__c(
            Loan_Devic__c = bySerial.get('SN-468-002'), Loan_Customer__c = gamma.Id,
            Loan_Start_Datum__c = TODAY - 55, Loan_Due_Datum__c = TODAY - 15);
        Loan_Record__c l4 = new Loan_Record__c(
            Loan_Devic__c = bySerial.get('SN-468-003'), Loan_Customer__c = alpha.Id,
            Loan_Start_Datum__c = TODAY - 60, Loan_Due_Datum__c = TODAY - 45);
        Loan_Record__c l5 = new Loan_Record__c(
            Loan_Devic__c = bySerial.get('SN-468-004'), Loan_Customer__c = beta.Id,
            Loan_Start_Datum__c = TODAY - 90, Loan_Due_Datum__c = TODAY - 30);
        insert new List<Loan_Record__c>{ l6, l1, l3, l4, l5 };

        // Batch B: two of those loans come back -> LoanReturnGuard clears both devices.
        List<Loan_Record__c> returned = new List<Loan_Record__c>{
            new Loan_Record__c(Id = l1.Id, Loan_Return_Datum__c = TODAY - 100),
            new Loan_Record__c(Id = l4.Id, Loan_Return_Datum__c = TODAY - 45)
        };
        update returned;

        // Batch C: the measuring instrument is lent again (it is Available now).
        Loan_Record__c l2 = new Loan_Record__c(
            Loan_Devic__c = bySerial.get('SN-468-001'), Loan_Customer__c = beta.Id,
            Loan_Start_Datum__c = TODAY - 54, Loan_Due_Datum__c = TODAY - 40);
        insert l2;

        // Batch D: and that second loan came back as well -> d1 ends Available with two loans.
        update new Loan_Record__c(Id = l2.Id, Loan_Return_Datum__c = TODAY - 40);
    }

    private static Id deviceIdOf(String serial) {
        List<Demo_Devic__c> rows = [SELECT Id FROM Demo_Devic__c WHERE Serial_Number__c = :serial LIMIT 1];
        System.assert(!rows.isEmpty(), 'fixture device with serial ' + serial + ' must exist');
        return rows[0].Id;
    }

    // dd.mm.yyyy, same shape as the guards (measured: Date.toString() is ISO yyyy-MM-dd).
    private static String ddmmyyyy(Date d) {
        String iso = String.valueOf(d);
        return iso.substring(8, 10) + '.' + iso.substring(5, 7) + '.' + iso.substring(0, 4);
    }

    // ---- AC1 + AC2 / TAC2n ----------------------------------------------------
    @isTest
    static void serialNumber_mustBeUnique() {
        List<Demo_Devic__c> all = [SELECT Id, Name, Designation_Name__c, Serial_Number__c FROM Demo_Devic__c WHERE Serial_Number__c LIKE 'SN-468%'];
        System.assertEquals(4, all.size(), 'AC1: exactly four devices exist');
        for (Demo_Devic__c d : all) {
            System.assert(d.Designation_Name__c != null && d.Designation_Name__c != '', 'AC1: every device carries a designation');
            System.assert(d.Serial_Number__c != null && d.Serial_Number__c != '', 'AC1: every device carries a serial');
        }

        Boolean refused = false;
        try {
            Demo_Devic__c dupe = new Demo_Devic__c(
                Designation_Name__c = '468 duplicate scanner', Serial_Number__c = 'SN-468-002');
            insert dupe;
        } catch (Exception e) {
            refused = true;
            System.debug('468 duplicate serial refused: ' + e.getMessage());
        }
        System.assert(refused, 'AC2/TAC2n: a second device with SN-468-002 must be refused');
        System.assertEquals(4,
            [SELECT Id FROM Demo_Devic__c WHERE Serial_Number__c LIKE 'SN-468%'].size(),
            'AC2n: the refused save left no device behind');
    }

    // ---- AC3 + AC4 / TAC4n ----------------------------------------------------
    @isTest
    static void lending_fillsTheDevice_half_and_a_second_lending_is_refused() {
        Id deviceId = deviceIdOf('SN-468-003');
        Demo_Devic__c before = [SELECT Id, Status__c, Current_Customer__c, Current_Loan_Due_Date__c FROM Demo_Devic__c WHERE Id = :deviceId];
        System.assertEquals('Available', before.Status__c, 'AC6: a returned device is Available again');
        System.assertEquals(null, before.Current_Customer__c, 'AC6: the current customer was cleared');
        System.assertEquals(null, before.Current_Loan_Due_Date__c, 'AC6: the due date was cleared');

        Account gamma = [SELECT Id FROM Account WHERE Name = '468 Customer Gamma' LIMIT 1];
        Loan_Record__c loan = new Loan_Record__c(
            Loan_Devic__c = deviceId, Loan_Customer__c = gamma.Id,
            Loan_Start_Datum__c = TODAY - 14, Loan_Due_Datum__c = TODAY + 3);
        insert loan;

        Demo_Devic__c after = [SELECT Id, Status__c, Current_Customer__c, Current_Loan_Colleague__c, Current_Loan_Due_Date__c FROM Demo_Devic__c WHERE Id = :deviceId];
        System.assertEquals('Lent_Out', after.Status__c, 'AC3: the device reads lent out');
        System.assertEquals(gamma.Id, after.Current_Customer__c, 'AC3: the device names the customer');
        System.assert(after.Current_Loan_Due_Date__c == TODAY + 3, 'AC3: the device carries the due date');
        Loan_Record__c savedLoan = [SELECT Id, Loan_History_Facts__c FROM Loan_Record__c WHERE Id = :loan.Id LIMIT 1];
        System.assertEquals('open / due ' + ddmmyyyy(TODAY + 3), savedLoan.Loan_History_Facts__c,
            'AC7 round 4: the guard-written facts column names the due date at lend time');
        System.assert(after.Current_Loan_Colleague__c != null, 'AC3: the lending colleague is recorded (defaults to the saving user)');
        System.assert(loan.Loan_Due_Datum__c == TODAY + 3, 'AC3: the loan record keeps the due date');
        System.assertEquals(null, loan.Loan_Return_Datum__c, 'AC3: the new loan is still open');

        Boolean refused = false;
        try {
            Account beta = [SELECT Id FROM Account WHERE Name = '468 Customer Beta' LIMIT 1];
            Loan_Record__c second = new Loan_Record__c(
                Loan_Devic__c = deviceId, Loan_Customer__c = beta.Id,
                Loan_Start_Datum__c = TODAY, Loan_Due_Datum__c = TODAY + 10);
            insert second;
        } catch (Exception e) {
            refused = true;
            System.debug('468 second lending refused: ' + e.getMessage());
        }
        System.assert(refused, 'AC4/TAC4n: the same device may not be lent to a second customer');
        List<Loan_Record__c> openOnDevice = [
            SELECT Id, Loan_Return_Datum__c FROM Loan_Record__c WHERE Loan_Devic__c = :deviceId AND Loan_Return_Datum__c = null
        ];
        System.assertEquals(1, openOnDevice.size(), 'AC4: still exactly one open loan on that device');
    }

    // ---- AC8 data + AC12 (nothing automatic) -----------------------------------
    @isTest
    static void overdue_devices_stay_untouched_without_automation() {
        List<Demo_Devic__c> overdue = new List<Demo_Devic__c>();
        for (Demo_Devic__c d : [SELECT Id, Name, Status__c, Current_Loan_Due_Date__c, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Status__c = 'Lent_Out']) {
            if (d.Current_Loan_Overdue_Days__c != null && d.Current_Loan_Overdue_Days__c > 0) {
                overdue.add(d);
            }
        }
        System.assertEquals(2, overdue.size(), 'AC8: two devices are lent out past their due date');
        Set<Decimal> days = new Set<Decimal>();
        for (Demo_Devic__c d : overdue) {
            days.add(d.Current_Loan_Overdue_Days__c);
        }
        System.assert(days.contains(30) && days.contains(15),
            'AC8: the overdue devices are 30 and 15 days past due, so a longest-first sort is well defined');

        // AC8 carrier: the ListView SCRUM468_Overdue filters on Overdue_Today__c, so the
        // formula must be true for exactly the two past-due devices and false for the rest.
        Integer flagged = 0;
        for (Demo_Devic__c d : [SELECT Id, Status__c, Overdue_Today__c FROM Demo_Devic__c]) {
            if (d.Overdue_Today__c) {
                flagged++;
            }
        }
        System.assertEquals(2, flagged,
            'AC8: Overdue_Today__c is true for exactly the two past-due devices, so the list view shows the right set');

        // AC12: saving an overdue device changes nothing by itself - no reminder,
        // no auto-return, no status flip. The loan stays open and overdue.
        Id overdueId = overdue[1].Id;
        Demo_Devic__c touched = [SELECT Id, Status__c, Current_Loan_Due_Date__c, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Id = :overdueId];
        update new Demo_Devic__c(Id = touched.Id, Status__c = 'Lent_Out');

        Demo_Devic__c after = [SELECT Id, Status__c, Current_Loan_Due_Date__c, Current_Loan_Overdue_Days__c FROM Demo_Devic__c WHERE Id = :overdueId];
        System.assertEquals('Lent_Out', after.Status__c, 'AC12: the save did not write the device off or return it');
        System.assert(after.Current_Loan_Due_Date__c == touched.Current_Loan_Due_Date__c, 'AC12: the due date was not moved');
        System.assert(after.Current_Loan_Overdue_Days__c == touched.Current_Loan_Overdue_Days__c,
            'AC12: the overdue count is still the formula value, not zeroed');
        List<Loan_Record__c> openLoans = [SELECT Id, Loan_Return_Datum__c FROM Loan_Record__c WHERE Loan_Return_Datum__c = null];
        System.assertEquals(2, openLoans.size(), 'AC12: no automation closed or opened a loan');
    }

    // ---- AC6 + AC7 (history survives) ------------------------------------------
    @isTest
    static void return_clears_the_device_and_history_survives() {
        Id deviceId = deviceIdOf('SN-468-002');
        Loan_Record__c open = [SELECT Id, Loan_Devic__c, Loan_Customer__c, Loan_Start_Datum__c, Loan_Due_Datum__c, Loan_Return_Datum__c
                               FROM Loan_Record__c WHERE Loan_Devic__c = :deviceId AND Loan_Return_Datum__c = null LIMIT 1];
        System.assert(open != null, 'AC6: an open loan exists on that device');

        update new Loan_Record__c(Id = open.Id, Loan_Return_Datum__c = TODAY);

        Demo_Devic__c device = [SELECT Id, Status__c, Current_Customer__c, Current_Loan_Colleague__c, Current_Loan_Due_Date__c FROM Demo_Devic__c WHERE Id = :deviceId];
        System.assertEquals('Available', device.Status__c, 'AC6: the device is available again');
        System.assertEquals(null, device.Current_Customer__c, 'AC6: no current customer left');
        System.assertEquals(null, device.Current_Loan_Colleague__c, 'AC6: no current colleague left');
        System.assertEquals(null, device.Current_Loan_Due_Date__c, 'AC6: no due date left');

        // AC7 round 4: a REAL return (an update, not a fixture insert) fires the
        // LoanReturnGuard rewrite - the facts column names the return date and the duration.
        Loan_Record__c returnedLoan = [SELECT Id, Loan_History_Facts__c FROM Loan_Record__c WHERE Id = :open.Id LIMIT 1];
        String returnedFacts = String.valueOf(returnedLoan.Loan_History_Facts__c);
        System.assert(returnedFacts.startsWith('returned '),
            'AC7 round 4: the facts column names the actual return date');
        System.assert(returnedFacts.contains(' Tage'),
            'AC7 round 4: the facts column names the duration in days');

        // AC7 reads the whole history of the device that was lent twice (SN-468-001);
        // the return above belongs to SN-468-002.
        Id historyDeviceId = deviceIdOf('SN-468-001');
        List<Loan_Record__c> history = [
            SELECT Id, Loan_Customer__c, Loan_Duration_Days__c, Loan_History_Facts__c FROM Loan_Record__c WHERE Loan_Devic__c = :historyDeviceId
        ];
        System.assertEquals(2, history.size(), 'AC7: both lending periods of that device are still there');
        Boolean periodOf14Days = false;
        for (Loan_Record__c h : history) {
            System.assert(h.Loan_Duration_Days__c != null, 'AC7: every returned period reports its duration');
            System.assert(String.isNotBlank(h.Loan_History_Facts__c), 'AC7 round 4: every period carries its facts column');
            if (h.Loan_Duration_Days__c == 14) {
                periodOf14Days = true;
            }
        }
        System.assert(periodOf14Days, 'AC7: the period just returned lasted 14 days');
    }

    // ---- AC9 positive: a team lead (holder of the marker PS) writes a device off
    // LAST method: user-mode DML must come after all System-mode DML (MIXED_DML).
    @isTest
    static void teamLead_mayWriteOff_andHistoryStaysVisible() {
        Profile standardUser = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User lead = new User(
            ProfileId = standardUser.Id, LastName = 'Lead468', Alias = 'lead468',
            Email = 'lead468@example.invalid', Username = 'lead468.' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles');
        insert lead;

        for (String psName : new List<String>{ 'SCRUM468_Loan', 'SCRUM468_Read', 'SCRUM468_Writeoff' }) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = ps.Id);
        }

        Id deviceId = deviceIdOf('SN-468-003');
        Integer historyBefore = [SELECT Id FROM Loan_Record__c WHERE Loan_Devic__c = :deviceId].size();

        System.runAs(lead) {
            Demo_Devic__c device = [SELECT Id, Status__c FROM Demo_Devic__c WHERE Id = :deviceId];
            update new Demo_Devic__c(Id = device.Id, Status__c = 'Written_Off');
        }

        Demo_Devic__c written = [SELECT Id, Status__c FROM Demo_Devic__c WHERE Id = :deviceId];
        System.assertEquals('Written_Off', written.Status__c, 'AC9/TAC9: the team lead wrote the device off');
        System.assertEquals(historyBefore,
            [SELECT Id FROM Loan_Record__c WHERE Loan_Devic__c = :deviceId].size(),
            'AC9: the lending history of a written-off device stays visible');

        Boolean refused = false;
        try {
            Account alpha = [SELECT Id FROM Account WHERE Name = '468 Customer Alpha' LIMIT 1];
            insert new Loan_Record__c(Loan_Devic__c = deviceId, Loan_Customer__c = alpha.Id,
                Loan_Start_Datum__c = TODAY, Loan_Due_Datum__c = TODAY + 7);
        } catch (Exception e) {
            refused = true;
            System.debug('468 lending a written-off device refused: ' + e.getMessage());
        }
        System.assert(refused, 'AC9/TAC9n: a written-off device can never be lent out again');
    }
}
