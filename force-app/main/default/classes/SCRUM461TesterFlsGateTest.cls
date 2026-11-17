/**
 * [SCRUM-461] SCRUM461TesterFlsGateTest — the role gate, proven against real org behaviour.
 *
 * Tester artifact. The Definition of Done demands a positive AND a negative CRUD/FLS
 * test with the Tester's name on it; System.runAs is the house route because both
 * Salesforce licences in this org are held by System Administrators, so no second
 * licensed UI session exists.
 *
 * Mixed-DML house rule (SCRUM-442): the User and its PermissionSetAssignment are
 * created in System context — a user cannot grant himself a Permission Set —
 * the business DML/SOQL runs inside System.runAs.
 *
 * @author tester-agent
 * @date 2026-11-17
 */
@isTest
private class SCRUM461TesterFlsGateTest {

    @TestSetup
    static void setup_fixtures() {
        Account a = new Account(Name = '461 Tester FLS Account');
        insert a;
        Competitor__c rival = new Competitor__c(Name = '461 Tester FLS Rival');
        insert rival;
        Opportunity o = new Opportunity(
            Name = '461 Tester FLS Opp',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 15,
            Amount = 65000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = rival.Id,
            Competitor_Price__c = 50000
        );
        insert o;
    }

    private static User mkUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'FlsGate461',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    private static PermissionSet mkPs(String psName) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
        System.assert(ps != null, 'precondition: Permission Set ' + psName + ' deployed');
        return ps;
    }

    // ── Negative: a user holding none of the three PSs sees nothing of the feature ──
    @isTest
    static void noPermissionSet_seesNeitherListNorPrice() {
        User neg = mkUser('gt461n');
        insert neg;

        System.runAs(neg) {
            // Precondition: the Opportunity itself is reachable, otherwise every
            // assert below would pass for the wrong reason.
            Opportunity o = [SELECT Id, Name FROM Opportunity WHERE Name = '461 Tester FLS Opp' LIMIT 1];
            System.assert(o != null, 'precondition: the deal itself is readable');

            System.assertEquals(
                false,
                Opportunity.Competitor_Price__c.getDescribe().isAccessible(),
                'AC/data-classification: the sensitive competitor price is readable ONLY through the PS'
            );
            System.assertEquals(
                false,
                Opportunity.Competitor_Lost_To__c.getDescribe().isAccessible(),
                'FLS: the competitor lookup is not readable without the PS'
            );
            System.assertEquals(
                false,
                Opportunity.Competitor_Gap__c.getDescribe().isAccessible(),
                'FLS: the derived gap is not readable without the PS'
            );
            System.assertEquals(
                false,
                Competitor__c.SObjectType.getDescribe().isAccessible(),
                'AC4: the competitor list itself is not reachable without a list PS'
            );
        }
    }

    // ── Positive: the deal PS makes the price readable and editable ─────────
    @isTest
    static void dealPermissionSet_makesPriceReadableAndEditable() {
        User u = mkUser('gt461d');
        insert u;
        PermissionSet deal = mkPs('SCRUM461_Competitor_Lost');
        PermissionSet listRead = mkPs('SCRUM461_Competitor_List_Read');
        // The design assigns BOTH to every internal sales role (C7 deal fields,
        // C8 the list). Measured here: a Lookup field is only readable when the
        // referenced object is readable as well — C7 alone leaves
        // Competitor_Lost_To__c inaccessible, which is why C8 is a separate PS
        // and not an optional extra.
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = deal.Id);
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = listRead.Id);

        System.runAs(u) {
            System.assertEquals(true, Opportunity.Competitor_Price__c.getDescribe().isAccessible(),
                'AC: an internal sales role reads the competitor price');
            System.assertEquals(true, Opportunity.Competitor_Price__c.getDescribe().isUpdateable(),
                'AC: an account manager records the competitor price');
            System.assertEquals(true, Opportunity.Competitor_Lost_To__c.getDescribe().isAccessible(),
                'AC: the competitor on the deal is readable (needs C7 AND C8)');
            System.assertEquals(false, Opportunity.Competitor_Gap__c.getDescribe().isUpdateable(),
                'C7: the derived gap is read-only — nobody may overwrite it');
            System.assertEquals(false, Opportunity.Lost_Last_12M__c.getDescribe().isUpdateable(),
                'C7: the window gate is read-only');
        }
    }

    // ── Measured boundary: the deal PS alone does not expose the lookup ─────
    @isTest
    static void dealPsWithoutListPs_lookupStaysInaccessible() {
        User u = mkUser('gt461x');
        insert u;
        PermissionSet deal = mkPs('SCRUM461_Competitor_Lost');
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = deal.Id);

        System.runAs(u) {
            System.assertEquals(true, Opportunity.Competitor_Price__c.getDescribe().isAccessible(),
                'C7 alone still grants the price field');
            System.assertEquals(false, Opportunity.Competitor_Lost_To__c.getDescribe().isAccessible(),
                'A Lookup needs a readable target object: without C8 the picker cannot work');
        }
    }

    // ── AC4: the list gate — reader may read, team lead may add, reader sees it ──
    @isTest
    static void listGate_readerMayReadTeamleadMayAdd() {
        User reader = mkUser('gt461r');
        User lead = mkUser('gt461l');
        insert reader;
        insert lead;

        PermissionSet listRead = mkPs('SCRUM461_Competitor_List_Read');
        PermissionSet teamlead = mkPs('SCRUM461_Competitor_List_Teamleitung');
        insert new PermissionSetAssignment(AssigneeId = reader.Id, PermissionSetId = listRead.Id);
        insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = listRead.Id);
        insert new PermissionSetAssignment(AssigneeId = lead.Id, PermissionSetId = teamlead.Id);

        String freshName = '461 Tester Added ' + DateTime.now().getTime();

        System.runAs(lead) {
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isCreateable(),
                'AC4: the team-lead PS grants create on the list');
            Competitor__c added = new Competitor__c(Name = freshName);
            insert added;
            System.assert(added.Id != null, 'AC4: the team lead added a competitor');
        }

        System.runAs(reader) {
            System.assertEquals(true, Competitor__c.SObjectType.getDescribe().isAccessible(),
                'AC4: every internal sales role reads the list, which is what makes the picker work');
            System.assertEquals(false, Competitor__c.SObjectType.getDescribe().isCreateable(),
                'AC4: a user without the team-lead PS cannot add a competitor');
            System.assertEquals(false, Competitor__c.SObjectType.getDescribe().isDeletable(),
                'AC4: clearing an entry is team-lead only');

            Set<String> selectable = new Set<String>();
            for (Competitor__c c : [SELECT Id, Name FROM Competitor__c]) {
                selectable.add(c.Name);
            }
            System.assert(selectable.contains('461 Tester FLS Rival'),
                'AC4: an existing entry is selectable by a plain reader');
            System.assert(selectable.contains(freshName),
                'AC4: the entry the team lead just added is immediately selectable');
        }
    }
}
