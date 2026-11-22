/**
 * [SCRUM-468] SCRUM468FlsTest - who may see a device and who may lend/write one off.
 *
 * AC11 / TAC11   a Service employee (SCRUM468_Read only) reads every device and its
 *                status, and gets neither create nor edit rights.
 * TAC-cust       a user holding none of the three sets (a customer-facing user) sees
 *                neither object at all: both objects are Locked internally and carry
 *                externalSharingModel Private, so nothing reaches Experience Cloud.
 * AC9n / TAC9n   a Sales employee (SCRUM468_Loan + SCRUM468_Read, NO marker set) is
 *                refused by DemoDevicWriteoffGuard the moment the save sets
 *                Status__c = Written_Off. The marker set SCRUM468_Writeoff grants
 *                nothing - it is the discriminator, and this test is only
 *                satisfiable because a Permission Set can grant, never revoke
 *                (skill salesforce-describe-first section 4).
 *
 * The user-mode DML (the refused write-off) is the LAST method, so every System-mode
 * DML - fixtures, users, PermissionSetAssignment - comes first (MIXED_DML, SCRUM-442).
 *
 * @author developer-agent
 * @date 2026-11-21
 */
@isTest
public class SCRUM468FlsTest {

    @TestSetup
    static void setup_fixtures() {
        Account alpha = new Account(Name = '468 FLS Customer');
        insert alpha;
        List<Demo_Devic__c> devices = new List<Demo_Devic__c>{
            new Demo_Devic__c(Designation_Name__c = 'FLS scanner E', Serial_Number__c = 'SN-468-101'),
            new Demo_Devic__c(Designation_Name__c = 'FLS laptop F', Serial_Number__c = 'SN-468-102')
        };
        insert devices;
        Loan_Record__c loan = new Loan_Record__c(
            Loan_Devic__c = devices[0].Id, Loan_Customer__c = alpha.Id,
            Loan_Start_Datum__c = Date.today() - 40, Loan_Due_Datum__c = Date.today() - 12);
        insert loan;
    }

    private static User mkUser(String alias) {
        Profile standardUser = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = standardUser.Id, LastName = 'Fls468', Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '.' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles');
    }

    private static void givePs(User u, List<String> psNames) {
        for (String psName : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    // ---- AC11 / TAC11: a Service employee reads, but may not lend or write off --
    @isTest
    static void serviceEmployee_reads_but_hasNoWriteRights() {
        User service = mkUser('s468svc');
        insert service;
        givePs(service, new List<String>{ 'SCRUM468_Read' });

        System.runAs(service) {
            // WITH USER_MODE is what makes the FLS check run at all (house SCRUM-421).
            List<Demo_Devic__c> rows = [
                SELECT Id, Name, Serial_Number__c, Status__c FROM Demo_Devic__c WITH USER_MODE
            ];
            System.assert(rows.size() >= 2, 'AC11: the Service employee sees the devices and where they are');
            List<Loan_Record__c> loans = [
                SELECT Id, Loan_Devic__c, Loan_Due_Datum__c FROM Loan_Record__c WITH USER_MODE
            ];
            System.assert(loans.size() >= 1, 'AC11: the Service employee also sees the lending periods');
            // getDescribe() answers for the RUNNING user, so these belong inside runAs.
            // isUpdateable() is the house API (SCRUM-4xx FLS tests); DescribeSObjectResult
            // has no isEditable() (measured compile failure on this org's compiler).
            System.assertEquals(true, Demo_Devic__c.SObjectType.getDescribe().isAccessible(),
                'AC11: the read set grants object access');
            System.assertEquals(true, Demo_Devic__c.Serial_Number__c.getDescribe().isAccessible(),
                'AC11: the read set grants the serial field');
            System.assertEquals(true, Loan_Record__c.SObjectType.getDescribe().isAccessible(),
                'AC11: the read set grants the loan records');
            System.assertEquals(false, Demo_Devic__c.Status__c.getDescribe().isUpdateable(),
                'AC11: a Service employee cannot change the device status');
            System.assertEquals(false, Loan_Record__c.Loan_Devic__c.getDescribe().isUpdateable(),
                'AC11: a Service employee cannot lend (loan lookups are not writable)');
            System.assertEquals(false, Loan_Record__c.Loan_History_Facts__c.getDescribe().isUpdateable(),
                'AC11 round 4: a Service employee cannot write the history facts column');
        }
        // Measured in Test-Org (house SCRUM-461): an Apex insert of a typed object is
        // NOT blocked by the object-level create flag, so the FLS assertions above are
        // the enforceable gate; the UI half (the Setup picker) is the Tester's Playwright test.
    }

    // ---- TAC-cust: a user without any of the three sets sees nothing -----------
    @isTest
    static void customerFacingUser_seesNeitherObject() {
        User outsider = mkUser('s468out');
        insert outsider;

        Boolean deviceReadable = false;
        Boolean loanReadable = false;
        System.runAs(outsider) {
            deviceReadable = Demo_Devic__c.SObjectType.getDescribe().isAccessible();
            loanReadable = Loan_Record__c.SObjectType.getDescribe().isAccessible();
        }
        System.assertEquals(false, deviceReadable, 'TAC-cust: Demo_Devic__c is not reachable without a PS');
        System.assertEquals(false, loanReadable, 'TAC-cust: Loan_Record__c is not reachable without a PS');
    }

    // ---- AC9n / TAC9n: a Sales employee without the marker set is refused ------
    // Last method: the refused save is the only user-mode DML in this class.
    @isTest
    static void salesEmployee_withoutMarkerSet_cannotWriteOff() {
        User salesStaff = mkUser('s468sls');
        insert salesStaff;
        givePs(salesStaff, new List<String>{ 'SCRUM468_Loan', 'SCRUM468_Read' });

        Boolean refused = false;
        System.runAs(salesStaff) {
            Demo_Devic__c device = [SELECT Id, Status__c FROM Demo_Devic__c WHERE Serial_Number__c = 'SN-468-102' WITH USER_MODE LIMIT 1];
            System.assertEquals(true, Loan_Record__c.Loan_History_Facts__c.getDescribe().isUpdateable(),
                'AC11 round 4: a sales employee may write the history facts column');
            try {
                update new Demo_Devic__c(Id = device.Id, Status__c = 'Written_Off');
            } catch (Exception e) {
                refused = true;
                System.debug('468 write-off refused for a plain sales employee: ' + e.getMessage());
            }
        }
        System.assert(refused, 'AC9n/TAC9n: without SCRUM468_Writeoff the write-off must be refused');

        Demo_Devic__c device = [SELECT Id, Status__c FROM Demo_Devic__c WHERE Serial_Number__c = 'SN-468-102' LIMIT 1];
        System.assertEquals('Available', device.Status__c,
            'AC9n: the refused save left the device Available, not Written_Off');
    }
}
