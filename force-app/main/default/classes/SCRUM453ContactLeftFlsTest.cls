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

    /** Fixtures come in via @TestSetup: Account is a setup object, and setup
     * DML may not share a transaction with the User + PermissionSetAssignment
     * inserts of the test body (MIXED_DML_OPERATION, house lesson SCRUM-449 —
     * green under RunSpecifiedTests, red under RunLocalTests/CI). @TestSetup is
     * committed before the body runs, so both halves stay legal. The seeds are
     * created in System context, which is also why the marked one can carry the
     * fresh Contact fields. */
    @TestSetup
    static void seedFls() {
        Account a = new Account(Name = 'V453 fls');
        insert a;
        Contact m = new Contact(LastName = 'FLS marked', AccountId = a.Id,
                                Has_Left_Company__c = true,
                                Left_Company_Date__c = Date.today().addMonths(-2));
        insert m;
        Contact f = new Contact(LastName = 'FLS free', AccountId = a.Id);
        insert f;
    }

    /** @TestSetup statics are not visible from helpers (house SCRUM-449):
     * look the fixture up by a stable field and cache it. */
    private static Id accCache;
    private static Id markedCache;
    private static Id freeCache;

    private static Id flsAccount() {
        if (accCache == null) {
            accCache = [SELECT Id FROM Account WHERE Name = 'V453 fls' LIMIT 1].Id;
        }
        return accCache;
    }

    private static Id flsMarkedContact() {
        if (markedCache == null) {
            Id acc = flsAccount();
            markedCache = [SELECT Id FROM Contact
                           WHERE AccountId = :acc AND LastName = 'FLS marked' LIMIT 1].Id;
        }
        return markedCache;
    }

    private static Id flsFreeContact() {
        if (freeCache == null) {
            Id acc = flsAccount();
            freeCache = [SELECT Id FROM Contact
                         WHERE AccountId = :acc AND LastName = 'FLS free' LIMIT 1].Id;
        }
        return freeCache;
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
        Id cId = flsMarkedContact();

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
        Id cId = flsFreeContact();

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

    // ---------- AC-6 NEGATIVE: Set-PS without Undo-PS may NOT clear the mark ----------
    @isTest
    static void setPSWithoutUndo_cannotClearMark() {
        User seller = mkUser('nosetundo', null);
        grantPS(seller, new String[] { 'SCRUM453_ContactLeft_Read', 'SCRUM453_ContactLeft_Set',
                                 'SCRUM451_TestObjectAccess', 'SCRUM453_ContactLeft_System' });
        Id cId = flsMarkedContact();

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
        Id cId = flsMarkedContact();

        Boolean cleared = false;
        System.runAs(lead) {
            Contact c = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            c.Has_Left_Company__c = false;
            update c;
            Contact check = [SELECT Id, Has_Left_Company__c FROM Contact WHERE Id = :cId LIMIT 1];
            cleared = (check.Has_Left_Company__c == false);
        }
        System.assert(cleared, 'AC-6: a team lead holding the Undo-PS can undo the mark.');

        Id accId = flsAccount();
        Account acc = [SELECT Id, Contacts_Without_Mark__c, Contacts_Left_Count__c
                       FROM Account WHERE Id = :accId LIMIT 1];
        System.assertEquals(Decimal.valueOf(0), acc.Contacts_Left_Count__c,
            'AC-8: the undo is reflected in the Account aggregates');
        System.assertEquals(Decimal.valueOf(2), acc.Contacts_Without_Mark__c,
            'AC-8: both fixture contacts of the customer are unmarked again');
    }
}
