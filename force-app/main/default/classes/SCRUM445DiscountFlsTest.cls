/**
 * [SCRUM-445] DiscountFlsTest — Permission-Set enforcement (AC11 view rights,
 * AC12 edit rights, AC14 negative access, plus the security-critical rule:
 * a rep must NEVER be able to set Discount_Approval__c = Approved).
 *
 * House-Pattern SCRUM440RueckrufwunschFlsTest / SCRUM442SatisfactionFlsTest:
 *   Standard-User-Profil, Vorbedingungs-Assert (object access), independent
 *   System.runAs-Blocks (no nested runAs), MIXED_DML: PSA inserts in System
 *   context, business DML under runAs (SCRUM-442 rule).
 *
 * FLS-STATEMENT (measured, not assumed — SCRUM-421 vs SCRUM-430 measured OPPOSITE
 * profile defaults for a brand-new field): whether the Standard-User profile
 * auto-granted Read+Edit on the freshly deployed fields is measured AFTER the
 * deploy via scripts/fls-check.sh. A Permission Set can only GRANT, never revoke:
 * if the profile already grants the field, the negative block goes red and this
 * is an Org/profile finding, NOT a code bug — the Developer reports it as such.
 */
@isTest
private class SCRUM445DiscountFlsTest {

    private static User mkUser(String tag, String[] psNames) {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'SCRUM445FLS ' + tag,
            Alias             = tag,
            Email             = tag + '@scr445fls.example.invalid',
            Username          = 'scr445fls_' + tag + '_' + String.valueOf(System.now().getTime()) + '@scr445fls.example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        if (psNames != null) {
            for (String psName : psNames) {
                PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
        return u;
    }

    // ---- Vorbedingung: Standard-User has object-level Opportunity access ----
    @isTest
    static void precondition_opportunityReadable() {
        User u = mkUser('pre', (String[]) null);
        Boolean oppReadable = false;
        System.runAs(u) {
            oppReadable = Opportunity.SObjectType.getDescribe().isAccessible();
        }
        System.assert(oppReadable,
            'Vorbedingung not met: Standard-User has no Opportunity access — the FLS asserts '
            + 'below would be green for the wrong reason (house SCRUM-436/442).');
    }

    // ---- AC14 NEGATIV: without any PS the discount fields are not offered ----
    @isTest
    static void withoutPS_discountInvisible() {
        User outsider = mkUser('out', (String[]) null);
        Boolean discountInvisible;
        Boolean approvalInvisible;
        System.runAs(outsider) {
            discountInvisible  = !Opportunity.Discount_in_Pct__c.getDescribe().isAccessible();
            approvalInvisible  = !Opportunity.Discount_Approval__c.getDescribe().isAccessible();
        }
        System.assert(discountInvisible,
            'AC14: without SCRUM445_Discount_Read the discount must NOT be visible (commercially sensitive).');
        System.assert(approvalInvisible,
            'AC14: without any PS the approval state must NOT be visible either.');
    }

    // ---- AC11: with the Read-PS only the rep SEES but cannot CHANGE anything ----
    @isTest
    static void readPS_readableNotUpdateable() {
        User viewer = mkUser('view', new String[] { 'SCRUM445_Discount_Read' });
        Boolean accessible;
        Boolean discountUpdateable;
        Boolean approvalUpdateable;
        System.runAs(viewer) {
            accessible        = Opportunity.Discount_in_Pct__c.getDescribe().isAccessible();
            discountUpdateable = Opportunity.Discount_in_Pct__c.getDescribe().isUpdateable();
            approvalUpdateable = Opportunity.Discount_Approval__c.getDescribe().isUpdateable();
        }
        System.assert(accessible, 'AC11: with the Read-PS the rep sees the discount.');
        System.assertEquals(false, discountUpdateable,
            'AC11: a non-owner rep with the Read-PS alone cannot change the discount.');
        System.assertEquals(false, approvalUpdateable,
            'SECURITY: with the Read-PS alone the rep cannot touch the approval state.');
    }

    // ---- SECURITY: even Owner+Read, a rep cannot set Approved ----
    @isTest
    static void ownerRep_cannotSetApproved() {
        User rep = mkUser('ownerrep', new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner' });
        Id acc = null;
        Account a = new Account(Name = 'V445 fls');
        insert a;
        acc = a.Id;
        Id oppId = null;
        Boolean selfApproved = false;
        System.runAs(rep) {
            Opportunity o = new Opportunity(
                Name = 'AC12 self-approve', AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3), Discount_in_Pct__c = 20
            );
            insert o;
            oppId = o.Id;
            o = [SELECT Id, Discount_Approval__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.Discount_Approval__c = 'Approved';
            try {
                update o;
                Opportunity check = [SELECT Id, Discount_Approval__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
                selfApproved = (check.Discount_Approval__c == 'Approved');
            } catch (DmlException e) {
                selfApproved = false;
            }
        }
        System.assertEquals(false, selfApproved,
            'SECURITY: a rep holding Owner+Read but NOT SCRUM445_Discount_Manager must never '
            + 'be able to set Approved — that would defeat the whole story.');
    }

    // ---- AC12a: the owner (Owner-PS) changes the discount ----
    @isTest
    static void ac12a_ownerEditsDiscount() {
        User owner = mkUser('own', new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner' });
        Account a = new Account(Name = 'V445 ac12a');
        insert a;
        Id acc = a.Id;
        Id oppId = null;
        System.runAs(owner) {
            Opportunity o = new Opportunity(
                Name = 'AC12a owner edit', AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            );
            insert o;
            oppId = o.Id;
            o = [SELECT Id FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.Discount_in_Pct__c = 18;
            update o;
        }
        Opportunity afterOwner = [SELECT Id, Discount_in_Pct__c, Discount_Approval__c
                                 FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
        System.assertEquals(18, afterOwner.Discount_in_Pct__c, 'AC12: the owner changed the discount.');
        System.assertEquals('Pending', String.valueOf(afterOwner.Discount_Approval__c),
            'AC12: above 15 % the system created the approval request.');
    }

    // ---- AC12b: the manager/sales-management shape sets Approved (own record,
    // own runAs — MIXED_DML rule SCRUM-442: one user per transaction) ----
    @isTest
    static void ac12b_managerShapeSetsApproved() {
        User mgmt = mkUser('mgmt', new String[] { 'SCRUM445_Discount_Read', 'SCRUM445_Discount_Owner', 'SCRUM445_Discount_Manager' });
        Account a = new Account(Name = 'V445 ac12b');
        insert a;
        Id acc = a.Id;
        Id oppId = null;
        Boolean approved = false;
        System.runAs(mgmt) {
            Opportunity o = new Opportunity(
                Name = 'AC12b manager approves', AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3), Discount_in_Pct__c = 20
            );
            insert o;
            oppId = o.Id;
            o = [SELECT Id, Discount_Approval__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            o.Discount_Approval__c = 'Approved';
            update o;
            o = [SELECT Id, Discount_Approval__c FROM Opportunity WHERE Id = :oppId LIMIT 1][0];
            approved = (o.Discount_Approval__c == 'Approved');
        }
        System.assert(approved, 'AC5/AC12: the manager/sales-management shape can set Approved.');
    }
}
