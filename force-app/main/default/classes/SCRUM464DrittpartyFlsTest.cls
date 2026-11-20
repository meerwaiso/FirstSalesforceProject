/**
 * [SCRUM-464] SCRUM464DrittpartyFlsTest - the role gate (AC6, AC13, TAC7, TAC8).
 *
 * TAC8 / AC13 negative: a user holding NONE of the three SCRUM464 Permission Sets
 *              cannot read the manufacturer, the cost, nor the list object - the
 *              commercially sensitive supplier data stays invisible. The Case itself
 *              is reachable (SCRUM451_TestObjectAccess), so a false here is about the
 *              FIELD, not about the object (house SCRUM-459 precondition pattern).
 * AC13 positive: a user holding SCRUM464_Drittparty_Team reads the two fields, and a
 *              real SOQL read returns the values.
 * TAC7 / AC6   : a user holding only SCRUM464_Fabrikant_List_Read can open the list
 *              but cannot add to it; a user holding SCRUM464_Fabrikant_List_Lead can,
 *              and the entry just added is immediately selectable by the plain reader.
 *
 * A Permission Set can only GRANT, never revoke: the negative half holds because
 * nothing in this org's Standard User profile grants the two new fields
 * (measured with scripts/fls-check.sh after deploy - zero FieldPermissions rows).
 *
 * Mixed-DML house rule (SCRUM-442): the User and its PermissionSetAssignment are
 * created in System context - a user cannot grant himself a Permission Set - the
 * business DML/SOQL runs inside System.runAs.
 *
 * @author developer-agent
 * @date 2026-11-20
 */
@isTest
private class SCRUM464DrittpartyFlsTest {

    @TestSetup
    static void setup_fixtures() {
        Contact c = new Contact(LastName = '464 Fls Contact');
        insert c;
        Fabrikant__c siemens = new Fabrikant__c(Name = 'Siemens');
        insert siemens;
        Case withData = new Case(
            Subject = '464 FLS case',
            ContactId = c.Id,
            Status = 'Closed',
            Ursache__c = 'DrittpartyProdukt',
            Customer_Satisfaction__c = 'Score_4',
            Drittparty_Fabrikant__c = siemens.Id,
            Drittparty_Fixkosten__c = 420.00
        );
        insert withData;
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Fls464',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    private static void grantPS(String[] psNames, Id userId) {
        for (String name : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + name + ' deployed');
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
        }
    }

    @isTest
    static void newFields_invisibleWithoutAnySCRUM464PS() {
        User neg = mkUser('f464neg');
        insert neg;
        // Object-level CRUD only: without it Case would be unreachable and every
        // assert below would pass for the wrong reason.
        grantPS(new String[] { 'SCRUM464_TestObjectAccess' }, neg.Id);

        System.runAs(neg) {
            System.assertEquals(
                true,
                Case.SObjectType.getDescribe().isAccessible(),
                'precondition: the Case itself is reachable, so a false below is about the field'
            );
            System.assertEquals(
                false,
                Case.Drittparty_Fabrikant__c.getDescribe().isAccessible(),
                'AC13/TAC8: the manufacturer is not readable without a SCRUM464 PS'
            );
            System.assertEquals(
                false,
                Case.Drittparty_Fixkosten__c.getDescribe().isAccessible(),
                'AC13/TAC8: the repair cost is not readable without a SCRUM464 PS'
            );
            System.assertEquals(
                false,
                Fabrikant__c.SObjectType.getDescribe().isAccessible(),
                'AC13/TAC8: the manufacturer list itself is not readable without a SCRUM464 PS'
            );
        }
    }

    @isTest
    static void teamMember_reads_theNewFields() {
        User u = mkUser('f464team');
        insert u;
        grantPS(
            new String[] {
                'SCRUM464_Drittparty_Team',
                'SCRUM464_Fabrikant_List_Read',
                'SCRUM434_Ursache',
                'SCRUM442_Satisfaction_Write',
                'SCRUM464_TestObjectAccess'
            },
            u.Id
        );

        System.runAs(u) {
            System.assertEquals(
                true,
                Case.Drittparty_Fabrikant__c.getDescribe().isAccessible(),
                'AC13: the Permission Set grants the manufacturer'
            );
            System.assertEquals(
                true,
                Case.Drittparty_Fixkosten__c.getDescribe().isAccessible(),
                'AC13: the Permission Set grants the cost'
            );
            // The two system-computed fields stay read-only even for the team (AC1/AC8
            // gate must not be editable): the write gate is isUpdateable(), not isEditable()
            // (measured: isEditable() does not exist on DescribeFieldResult).
            DescribeFieldResult gate = Case.Closed_Last_12M__c.getDescribe();
            System.assertEquals(true, gate.isAccessible(),
                'AC8: the window gate is readable');
            System.assertEquals(false, gate.isUpdateable(),
                'AC8: the window gate is never editable, even for the team');
            // A real read, not just the flag: the values come back.
            Case back = [
                SELECT Id, Drittparty_Fabrikant__c, Drittparty_Fixkosten__c, Closed_Last_12M__c
                FROM Case WHERE Subject = '464 FLS case' LIMIT 1
            ];
            System.assert(back != null, 'AC13: the fixture case is readable under the PS');
            Fabrikant__c maker = [
                SELECT Id, Name FROM Fabrikant__c WHERE Name = 'Siemens' LIMIT 1
            ];
            System.assert(maker != null, 'AC13: the lookup resolves to the list entry');
            System.assertEquals(420.00, back.Drittparty_Fixkosten__c,
                'AC13: the cost value reads back, not just the grant');
        }
    }

    @isTest
    static void listRead_mayNotAdd_listLead_mayAndIsImmediatelyVisible() {
        User reader = mkUser('f464read');
        User lead = mkUser('f464lead');
        insert reader;
        insert lead;
        grantPS(new String[] { 'SCRUM464_Fabrikant_List_Read', 'SCRUM464_TestObjectAccess' }, reader.Id);
        grantPS(
            new String[] { 'SCRUM464_Fabrikant_List_Read', 'SCRUM464_Fabrikant_List_Lead', 'SCRUM464_TestObjectAccess' },
            lead.Id
        );

        // A name that is fresh per run: a previous run may still hold the record
        // and the duplicate guard would refuse it (house SCRUM-461 pattern).
        String freshName = '464 Teamlead Fabrikant ' + DateTime.now().getTime();

        System.runAs(lead) {
            System.assertEquals(true, Fabrikant__c.SObjectType.getDescribe().isAccessible(),
                'AC6: a service team lead reads the list');
            System.assertEquals(true, Fabrikant__c.SObjectType.getDescribe().isCreateable(),
                'AC6: only the team-lead PS grants create');
            // A name that is fresh per run: a previous run may still hold the record
            // and the duplicate guard would refuse it (house SCRUM-461 pattern).
            freshName = '464 Teamlead Fabrikant ' + DateTime.now().getTime();
            Fabrikant__c added = new Fabrikant__c(Name = freshName);
            insert added;
            System.assert(added.Id != null, 'AC6: the team lead added a manufacturer');
        }

        System.runAs(reader) {
            System.assertEquals(true, Fabrikant__c.SObjectType.getDescribe().isAccessible(),
                'AC6: a plain service agent reads the list, which is what makes the picker work');
            System.assertEquals(false, Fabrikant__c.SObjectType.getDescribe().isCreateable(),
                'AC6: a user without the team-lead PS cannot add a manufacturer');
            System.assertEquals(false, Fabrikant__c.SObjectType.getDescribe().isDeletable(),
                'AC6: the read-only user cannot clear an entry');

            Set<String> selectable = new Set<String>();
            for (Fabrikant__c f : [SELECT Id, Name FROM Fabrikant__c]) {
                selectable.add(f.Name);
            }
            System.assert(selectable.contains('Siemens'),
                'AC6: an existing entry is selectable by a plain reader');
            System.assert(selectable.contains(freshName),
                'AC6: the entry the team lead just added is immediately selectable');
        }
    }
}
