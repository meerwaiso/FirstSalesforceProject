/**
 * [SCRUM-453] FLS + undo-gate tests (AC-6, plus the read/write split of AC-1).
 *
 * House pattern: SCRUM445DiscountFlsTest / SCRUM442SatisfactionFlsTest —
 *   Standard-User profile, precondition assert (object access), independent
 *   System.runAs blocks (never nested), MIXED_DML: User + PermissionSetAssignment
 *   DML in System context FIRST, business DML under ONE runAs user (SCRUM-432/442).
 *
 * AC -> method:
 *   AC-1 read split ......... readPS_readableNotEditable / readPS_cannotSetMark
 *   AC-1 setting the mark ... setPS_setsMark
 *   AC-6 NEGATIVE ........... setPSWithoutUndo_cannotClearMark (the guard, not FLS)
 *   AC-6 positive ........... undoPS_clearsMark
 *   AC-1 negative FLS ....... withoutPS_markInvisible
 *
 * FLS-STATEMENT (measured, not assumed — SCRUM-421 vs SCRUM-430 measured OPPOSITE
 * profile defaults for a brand-new field): whether the Standard-User profile
 * auto-granted Read+Edit on the freshly deployed Contact fields is measured AFTER
 * the deploy with scripts/fls-check.sh. A Permission Set can only GRANT, never
 * revoke: if the profile already grants the field, the negative block below goes
 * red and that is an Org/profile finding, NOT a code bug — the Developer reports
 * it as such. The AC-6 undo gate itself is enforced by ContactLeftGuardTrigger
 * (ADR-2: FLS is per field, setting and clearing edit the same Checkbox), so its
 * negative test holds regardless of the profile.
 */
@isTest
private class SCRUM453ContactLeftFlsTest {

    private static User mkUser(String tag, String[] psNames) {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'SCRUM453FLS ' + tag,
            Alias             = tag.substring(0, Math.min(8, tag.length())),   // User Alias <= 8 chars
            Email             = tag + '@scr453fls.example.invalid',
            Username          = 'scr453fls_' + tag + '_'
                                + String.valueOf(System.now().getTime()) + '@scr453fls.example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /** PSA inserts in System context — a User cannot grant himself a PSA. */
    private static void grantPS(User u, String[] psNames) {
        if (psNames == null) {
            return;
        }
        for (String psName : psNames) {
            List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assertEquals(1, sets.size(), 'the Permission Set ' + psName + ' must be deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = sets[0].Id);
        }
    }

    /** Fixture Contact that is already marked, so an undo can be attempted. */
    private static Id markedContact(Id accId) {
        Contact c = new Contact(LastName = 'FLS',  AccountId = accId,
                                Has_Left_Company__c = true, Left_Company_Date__c = Date.today().addMonths(-2));
        insert c;
        return c.Id;
    }

    private static Boolean markReadable(User u) {
        Boolean r = false;
        System.runAs(u) {
            r = Contact.Has_Left_Company__c.getDescribe().isAccessible();
        }
        return r;
    }

    // ---------- precondition: Standard User has Contact object access ----------
    @isTest
    static void precondition_contactReadable() {
        User u = mkUser('pre', (String[]) null);
        Boolean accessible = false;
        System.runAs(u) {
            accessible = Contact.SObjectType.getDescribe().isAccessible();
        }
        System.assert(accessible,
            'precondition not met: Standard-User has no Contact access — the asserts below '
            + 'would be green for the wrong reason (house SCRUM-436/442).');
    }

    // ---------- AC-1 NEGATIVE: without any PS the mark is not offered ----------
    @isTest
    static void withoutPS_markInvisible() {
        User outsider = mkUser('out', (String[]) null);
        Boolean invisible = !markReadable(outsider);
        System.assert(invisible,
            'AC-1: without SCRUM453_ContactLeft_Read the mark must NOT be visible. If this '
            + 'fails, the Standard-User profile already grants the fresh field (a Permission '
            + 'Set can only grant, never revoke) — an Org finding, not a code bug.');
    }

    // ---------- AC-1: the Read-PS sees but changes nothing ----------
    @isTest
    static void readPS_readableNotEditable() {
        User viewer = mkUser('view', null);
        grantPS(viewer, new String[] { 'SCRUM453_ContactLeft_Read', 'SCRUM451_TestObjectAccess', 'SCRUM453_ContactLeft_System' });
        Boolean accessible = false;
        Boolean updateable = false;
        System.runAs(viewer) {
            accessible = Contact.Has_Left_Company__c.getDescribe().isAccessible();
            updateable = Contact.Has_Left_Company__c.getDescribe().isUpdateable();
        }
        System.assert(accessible, 'AC-1: with the Read-PS the mark is visible.');
        System.assertEquals(false, updateable,
            'AC-1: the Read-PS alone never makes the mark editable.');
    }

    // ---------- AC-1 negative: the Read-PS cannot SET the mark ----------
    @isTest
    static void readPS_cannotSetMark() {
        User viewer = mkUser('viewset', null);
        grantPS(viewer, new String[] { 'SCRUM453_ContactLeft_Read', 'SCRUM451_TestObjectAccess', 'SCRUM453_ContactLeft_System' });
        Account a = new Account(Name = 'V453 fls-read');
        insert a;
        Id cId = markedContact(a.Id);

        Boolean setByReadPs = false;
        System.runAs(viewer) {
            Contact c = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            c.Has_Left_Company__c = true;
            try {
                update c;
                Contact check = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
                setByReadPs = check.Has_Left_Company__c;
            } catch (DmlException e) {
                setByReadPs = false;
            }
        }
        System.assertEquals(false, setByReadPs,
            'AC-1: a reader (Marketing) must never change the mark.');
    }

    // ---------- AC-1 positive: Sales/Service (Set-PS) sets the mark ----------
    @isTest
    static void setPS_setsMark() {
        User seller = mkUser('setter', null);
        grantPS(seller, new String[] { 'SCRUM453_ContactLeft_Read', 'SCRUM453_ContactLeft_Set',
                                 'SCRUM451_TestObjectAccess', 'SCRUM453_ContactLeft_System' });
        Account a = new Account(Name = 'V453 fls-set');
        insert a;
        Id cId = newContact(a.Id);

        Boolean wasSet = false;
        System.runAs(seller) {
            Contact c = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            c.Has_Left_Company__c = true;
            update c;
            Contact check = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            wasSet = check.Has_Left_Company__c;
        }
        System.assert(wasSet, 'AC-1: a Sales/Service user holding the Set-PS marks the contact.');
    }

    private static Id newContact(Id accId) {
        Contact c = new Contact(LastName = 'FLS-set',  AccountId = accId);
        insert c;
        return c.Id;
    }

    // ---------- AC-6 NEGATIVE: Set-PS without Undo-PS may NOT clear the mark ----------
    @isTest
    static void setPSWithoutUndo_cannotClearMark() {
        User seller = mkUser('nosetundo', null);
        grantPS(seller, new String[] { 'SCRUM453_ContactLeft_Read', 'SCRUM453_ContactLeft_Set',
                                 'SCRUM451_TestObjectAccess', 'SCRUM453_ContactLeft_System' });
        Account a = new Account(Name = 'V453 fls-undo');
        insert a;
        Id cId = markedContact(a.Id);

        Boolean cleared = false;
        System.runAs(seller) {
            Contact c = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            c.Has_Left_Company__c = false;
            try {
                update c;
            } catch (DmlException e) {
                // expected: ContactLeftGuardTrigger refused the clearing
            }
            Contact check = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            cleared = (check.Has_Left_Company__c == false);
        }
        System.assertEquals(false, cleared,
            'AC-6: a Sales/Service user WITHOUT the Undo-PS cannot undo the mark — '
            + 'the guard trigger, not FLS, refuses it (ADR-2).');
    }

    // ---------- AC-6 positive: a team lead (Undo-PS) clears the mark ----------
    @isTest
    static void undoPS_clearsMark() {
        User lead = mkUser('lead', null);
        grantPS(lead, new String[] { 'SCRUM453_ContactLeft_Read', 'SCRUM453_ContactLeft_Set',
                                     'SCRUM453_ContactLeft_Undo', 'SCRUM451_TestObjectAccess', 'SCRUM453_ContactLeft_System' });
        Account a = new Account(Name = 'V453 fls-lead');
        insert a;
        Id cId = markedContact(a.Id);

        Boolean cleared = false;
        System.runAs(lead) {
            Contact c = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            c.Has_Left_Company__c = false;
            update c;
            Contact check = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            cleared = (check.Has_Left_Company__c == false);
        }
        System.assert(cleared, 'AC-6: a team lead holding the Undo-PS can undo the mark.');

        Account acc = [SELECT Id, Contacts_Without_Mark__c, Contacts_Left_Count__c
                       FROM Account WHERE Id = :a.Id LIMIT 1];
        System.assertEquals(Decimal.valueOf(0), acc.Contacts_Left_Count__c,
            'AC-8: the undo is reflected in the Account aggregates');
        System.assertEquals(Decimal.valueOf(1), acc.Contacts_Without_Mark__c,
            'AC-8: the customer has a contact person again');
    }
}
