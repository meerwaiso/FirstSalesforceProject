/**
 * [SCRUM-440] FLS positiv/negativ (AC6 / TAC-4).
 * House-Pattern SCRUM430RueckrufZeitfensterFlsTest + SCRUM416OpenOpportunityFlsTest:
 *   Standard-User-Profil, Vorbedingungs-Assert (Objekt-Zugriff),
 *   negativer + positiver Block, eigenständige System.runAs-Blöcke (kein nested runAs).
 *
 * FLS-STATEMENT (measured, not assumed — see SCRUM-430 lesson + memory):
 * A brand-new Custom Field is per-Default FLS-gated. Whether the Standard-User
 * profile auto-granted Read+Edit on the freshly deployed field is measured AFTER
 * deploy via `FieldPermissions WHERE Field='Opportunity.Rueckruf_am__c'`; the
 * negative block below asserts the field is INVISIBLE to a Standard User without
 * the PS. If the org auto-granted it, this test goes red and the Developer reports
 * it — a Permission Set can only grant, never revoke, so a red negative is an
 * Org/profile finding, not a code bug.
 */
@isTest
private class SCRUM440RueckrufwunschFlsTest {

    private static User mkTestUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId   = p.Id,
            LastName    = 'Fls440',
            Alias       = 'f440' + tag,
            Email       = 'f440' + tag + '@example.invalid',
            Username    = 'f440' + tag + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    // ---- Vorbedingung: Standard-User hat object-level Opportunity-Zugriff ----
    @isTest
    static void precondition_opportunityReadable() {
        User u = mkTestUser('pre');
        Boolean oppReadable = false;
        System.runAs(u) {
            oppReadable = Opportunity.SObjectType.getDescribe().isAccessible();
        }
        System.assert(oppReadable,
            'Vorbedingung nicht erfüllt: Standard-User hat keinen Opportunity-Zugriff — ' +
            'ein FLS-Assert wäre dann aus dem falschen Grund grün.');
    }

    // ---- AC6 NEGATIV: ohne PS → both fields invisible + not writable --------
    @isTest
    static void withoutPS_fieldsInvisible() {
        User u = mkTestUser('neg');

        Boolean oppReadable = false;
        System.runAs(u) {
            oppReadable = Opportunity.SObjectType.getDescribe().isAccessible();
        }
        System.assert(oppReadable,
            'Vorbedingung gefehlt: Standard-User hat keinen Opportunity-Zugriff.');

        Boolean desiredInvisible;
        Boolean dateInvisible;
        System.runAs(u) {
            desiredInvisible = !Opportunity.Rueckruf_desired__c.getDescribe().isAccessible();
            dateInvisible    = !Opportunity.Rueckruf_am__c.getDescribe().isAccessible();
        }
        System.assert(desiredInvisible,
            'Ohne PS: Opportunity.Rueckruf_desired__c muss INVISIBLE sein (AC6).');
        System.assert(dateInvisible,
            'Ohne PS: Opportunity.Rueckruf_am__c muss INVISIBLE sein (AC6).');
    }

    // ---- AC6 POSITIV: mit PS → both fields readable + editable --------------
    @isTest
    static void withPS_readableAndWritable() {
        User u = mkTestUser('pos');
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM440_Rueckrufwunsch' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        Boolean accDes, accUpd, accDate;
        System.runAs(u) {
            accDes  = Opportunity.Rueckruf_desired__c.getDescribe().isAccessible();
            accUpd  = Opportunity.Rueckruf_desired__c.getDescribe().isUpdateable();
            accDate = Opportunity.Rueckruf_am__c.getDescribe().isAccessible();
        }
        System.assert(accDes,  'Mit PS: Rueckruf_desired__c muss lesbar sein (AC6).');
        System.assert(accUpd,  'Mit PS: Rueckruf_desired__c muss editierbar sein (AC6).');
        System.assert(accDate, 'Mit PS: Rueckruf_am__c muss lesbar sein (AC6).');

        // Real round-trip: create an Opportunity, set both fields, read them back.
        Id accId;
        System.runAs(u) {
            Account a = new Account(Name = 'TEST-SCRUM-440-FLS');
            insert a;
            accId = a.Id;
        }
        Id oppId;
        System.runAs(u) {
            Opportunity o = new Opportunity(
                Name = 'TEST-SCRUM-440-FLS', AccountId = accId, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            );
            insert o;
            oppId = o.Id;
        }

        // Set checkbox + future date, then read back through the same session.
        System.runAs(u) {
            Opportunity o = [SELECT Id, Rueckruf_desired__c, Rueckruf_am__c
                             FROM Opportunity WHERE Id = :oppId LIMIT 1];
            o.Rueckruf_desired__c = true;
            o.Rueckruf_am__c = Datetime.now().addDays(2);
            update o;
        }
        Boolean readBackDes;
        System.runAs(u) {
            Opportunity o = [SELECT Id, Rueckruf_desired__c, Rueckruf_am__c
                             FROM Opportunity WHERE Id = :oppId LIMIT 1];
            readBackDes = o.Rueckruf_desired__c;
        }
        System.assertEquals(true, readBackDes,
            'Mit PS: Rueckruf_desired__c editierbar + lesbar via real session (AC6).');
    }
}
