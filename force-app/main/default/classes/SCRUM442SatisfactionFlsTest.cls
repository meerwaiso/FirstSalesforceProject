/**
 * [SCRUM-442] FLS positiv/negativ — AC7 (Sales cannot change a rating) and
 * AC8 (a non-Service person is not offered the rating).
 *
 * House-Pattern SCRUM440RueckrufwunschFlsTest + SCRUM436CaseReminderFlsTest:
 *   Standard-User-Profil, Precondition-Assert (object access), independent
 *   System.runAs-Blocks (no nested runAs).
 *
 * FLS-STATEMENT (measured, not assumed — SCRUM-421 vs SCRUM-430 measured
 * OPPOSITE defaults for a brand-new field): whether the Standard-User profile
 * auto-granted Read+Edit on the freshly deployed field is measured AFTER the
 * deploy via scripts/fls-check.sh; the negative block below asserts the field
 * is INVISIBLE to a User without the PS. A Permission Set can only GRANT,
 * never revoke — so a red negative is an Org/profile finding, not a code bug.
 *
 * AC7 is asserted as isUpdateable()==false under the Read-PS alone: the Sales
 * shape sees the score but cannot change it, even though it has full object
 * access today (precondition).
 */
@isTest
private class SCRUM442SatisfactionFlsTest {

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'Fls442 ' + tag,
            Alias             = tag,
            Email             = tag + '@example.invalid',
            Username          = tag + '_' + String.valueOf(System.now().getTime()) + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    private static User grantPS(User u, String psName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    /** Precondition: the Standard User has object-level Case + Account access. */
    @isTest
    static void precondition_objectAccess() {
        User u = mkTestUser('pre442fls');
        Boolean caseReadable = false;
        Boolean accountReadable = false;
        System.runAs(u) {
            caseReadable = Case.SObjectType.getDescribe().isAccessible();
            accountReadable = Account.SObjectType.getDescribe().isAccessible();
        }
        System.assert(caseReadable && accountReadable,
            'Precondition failed: no object-level access to Case/Account — the FLS asserts '
            + 'below would be green for the wrong reason (house SCRUM-436).');
    }

    /** AC8 (negative): without any PS the score field is not offered at all. */
    @isTest
    static void withoutPS_scoreInvisible() {
        User u = mkTestUser('neg442fls');
        Boolean invisible;
        System.runAs(u) {
            invisible = !Case.Customer_Satisfaction__c.getDescribe().isAccessible();
        }
        System.assert(invisible,
            'AC8: without SCRUM442_Satisfaction_Write the score must NOT be offered '
            + 'to a non-Service person (not accessible).');
    }

    /** AC7: with the Read-PS only the score is readable but NOT updateable. */
    @isTest
    static void readPS_readableNotUpdateable() {
        User u = grantPS(mkTestUser('sales442fls'), 'SCRUM442_Satisfaction_Read');
        Boolean accessible;
        Boolean updateable;
        System.runAs(u) {
            DescribeFieldResult d = Case.Customer_Satisfaction__c.getDescribe();
            accessible = d.isAccessible();
            updateable = d.isUpdateable();
        }
        System.assert(accessible, 'AC2/AC7: with Read-PS the Sales shape sees the score.');
        System.assertEquals(false, updateable,
            'AC7: the Sales shape must NOT be able to change a rating.');
    }

    /** AC7 real round-trip: a Sales-shaped user refuses to write the score. */
    @isTest
    static void salesShape_writeRefusedValueUnchanged() {
        // Setup OUTSIDE runAs: a Standard User cannot grant itself a PSA, and
        // the Case is created by the System context (a Service colleague).
        User u = grantPS(mkTestUser('sales442rt'), 'SCRUM442_Satisfaction_Read');

        Case seed = new Case(Subject = 'V442 fls rt', Status = 'Working');
        insert seed;
        Id caseId = seed.Id;
        seed.Status = 'Closed';
        seed.Customer_Satisfaction__c = 'Score_4';
        update seed;

        SalesforceException caught = null;
        System.runAs(u) {
            try {
                Case c = [SELECT Id, Customer_Satisfaction__c FROM Case WHERE Id = :caseId LIMIT 1];
                c.Customer_Satisfaction__c = 'Score_1';
                update c;
            } catch (SalesforceException e) {
                caught = e;
            }
        }
        System.assert(caught != null,
            'AC7: the Sales-shaped user must not be able to change the score.');

        Case after = [SELECT Id, Customer_Satisfaction__c FROM Case WHERE Id = :caseId LIMIT 1];
        System.assertEquals('Score_4', String.valueOf(after.Customer_Satisfaction__c),
            'AC7: the score still shows the value the Service colleague gave.');
    }

    /** AC2/AC8 positive: with the Write-PS the Service shape reads + writes. */
    @isTest
    static void writePS_readableAndUpdateable() {
        User u = grantPS(mkTestUser('service442fls'), 'SCRUM442_Satisfaction_Write');
        Boolean accessible;
        Boolean updateable;
        System.runAs(u) {
            DescribeFieldResult d = Case.Customer_Satisfaction__c.getDescribe();
            accessible = d.isAccessible();
            updateable = d.isUpdateable();
        }
        System.assert(accessible, 'AC2: with Write-PS the Service shape sees the score.');
        System.assert(updateable, 'AC2/AC8: with Write-PS the Service shape may set it.');
    }

    /** AC5 read-path: the Account overview fields follow the Read-PS. */
    @isTest
    static void readPS_accountOverviewReadable() {
        User u = grantPS(mkTestUser('sales442acc'), 'SCRUM442_Satisfaction_Read');
        Boolean avgReadable;
        Boolean argerReadable;
        System.runAs(u) {
            avgReadable = Account.Satisfaction_Durchdurch__c.getDescribe().isAccessible();
            argerReadable = Account.Satisfaction_Arger__c.getDescribe().isAccessible();
        }
        System.assert(avgReadable && argerReadable,
            'AC5: with Read-PS the Sales shape must see the Account average and the '
            + 'Arger-indicator.');
    }
}
