/**
 * [SCRUM-451] CRUD/FLS test for the contract dates and the derived display.
 *
 * Permission Sets (design finding 5):
 *   SCRUM451_Wartungsvertrag_Dates_Teamleitung  Read+Edit on the two recorded
 *                                               dates, Read on the four derived
 *   SCRUM451_Wartungsvertrag_Dates_Read         Read on all six fields
 *
 * House shape: SCRUM431FlsTest — a User is created with a Profile, the
 * PermissionSetAssignment is setup DML OUTSIDE System.runAs (a User cannot
 * grant himself a PSA), the reflection and the business DML run inside it.
 *
 * Measured before writing (Test-Org, FieldPermissions WHERE
 * Field='Account.Wartungsvertrag_End__c'): the new dates are granted READ by
 * the permission group "Agentic Near Core CRM" (PermissionsEdit = false) and by
 * nothing else. A Permission Set can only grant, never revoke — so the
 * satisfiable negative here is the EDIT side: without the team-lead PS the
 * dates are not updatable. The read side is asserted as granted, never as
 * invisible.
 */
@isTest
private class SCRUM451WartungsvertragFlsTest {

    private static Profile standardProfile() {
        return [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    }

    private static User newUser(String tag) {
        Profile p = standardProfile();
        String uName = 'scr451fls-' + tag + '-' + DateTime.now().getTime() + '@example.invalid';
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr451Fls-' + tag,
            Alias = ('45f' + tag).left(8),
            Email = uName,
            Username = uName,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static void assignPS(String psName, Id userId) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
    }

    private static Schema.DescribeFieldResult[] allSix() {
        return new Schema.DescribeFieldResult[] {
            Account.Wartungsvertrag_Start__c.getDescribe(),
            Account.Wartungsvertrag_End__c.getDescribe(),
            Account.Wartungsvertrag_Ende_Tage__c.getDescribe(),
            Account.Wartungsvertrag_Status__c.getDescribe(),
            Account.Wartungsvertrag_Active__c.getDescribe(),
            Account.Wartungsvertrag_Renewal_Soon__c.getDescribe()
        };
    }

    private static Schema.DescribeFieldResult[] onlyDerived() {
        return new Schema.DescribeFieldResult[] {
            Account.Wartungsvertrag_Ende_Tage__c.getDescribe(),
            Account.Wartungsvertrag_Status__c.getDescribe(),
            Account.Wartungsvertrag_Active__c.getDescribe(),
            Account.Wartungsvertrag_Renewal_Soon__c.getDescribe()
        };
    }

    // ---- negative: nobody but the team leads may change the dates ---------
    @isTest
    static void userWithoutScrum451CannotEditDates() {
        User u = newUser('none');
        System.runAs(u) {
            System.assertEquals(false, Account.Wartungsvertrag_Start__c.getDescribe().isUpdateable(),
                'AC9: without the team-lead PS the start date is not updatable');
            System.assertEquals(false, Account.Wartungsvertrag_End__c.getDescribe().isUpdateable(),
                'AC9: without the team-lead PS the end date is not updatable');
            for (Schema.DescribeFieldResult f : onlyDerived()) {
                System.assertEquals(false, f.isUpdateable(),
                    'a derived field is never writable, for any user');
            }
        }
    }

    // ---- positive: service and sales read all six, change none ------------
    @isTest
    static void serviceAndSalesReadNotEdit() {
        User u = newUser('read');
        assignPS('SCRUM451_Wartungsvertrag_Dates_Read', u.Id);
        System.runAs(u) {
            for (Schema.DescribeFieldResult f : allSix()) {
                System.assertEquals(true, f.isAccessible(),
                    'AC9: service and sales see the contract dates and the derived display');
                System.assertEquals(false, f.isUpdateable(),
                    'AC9: service and sales change nothing');
            }
        }
    }

    // ---- positive: the team lead reads and edits the recorded dates ------
    @isTest
    static void teamleadReadsAndEditsDates() {
        User u = newUser('lead');
        assignPS('SCRUM451_Wartungsvertrag_Dates_Teamleitung', u.Id);
        assignPS('SCRUM451_TestObjectAccess', u.Id);
        System.runAs(u) {
            System.assertEquals(true, Account.Wartungsvertrag_Start__c.getDescribe().isAccessible(),
                'AC9: the team lead reads the start date');
            System.assertEquals(true, Account.Wartungsvertrag_Start__c.getDescribe().isUpdateable(),
                'AC9: the team lead records the start date');
            System.assertEquals(true, Account.Wartungsvertrag_End__c.getDescribe().isUpdateable(),
                'AC9: the team lead records the end date');
            for (Schema.DescribeFieldResult f : onlyDerived()) {
                System.assertEquals(true, f.isAccessible(),
                    'AC9: the team lead reads the derived display');
                System.assertEquals(false, f.isUpdateable(),
                    'the derived display stays read-only even for the team lead');
            }
            // the round trip really works for this user
            Account a = new Account(
                Name = 'TEST-SCRUM-451-FLS-ROUNDTRIP',
                Wartungsvertrag__c = true,
                Wartungsvertrag_Start__c = Date.today().addMonths(-6),
                Wartungsvertrag_End__c = Date.today().addDays(20)
            );
            insert a;
            Account back = [SELECT Wartungsvertrag_End__c, Wartungsvertrag_Ende_Tage__c
                            FROM Account WHERE Id = :a.Id];
            System.assertEquals(Date.today().addDays(20), back.Wartungsvertrag_End__c,
                'AC9: the recorded end date is stored for the team lead');
            System.assertEquals(20, (Decimal) back.Wartungsvertrag_Ende_Tage__c,
                'AC9: and the derived remaining time follows it');
        }
    }
}
