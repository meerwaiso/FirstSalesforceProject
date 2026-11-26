/**
 * [SCRUM-477][Developer] Tage jetzige Stage — the counter RULE, judged only on fixtures.
 * [SCRUM-482] Rebuilt: the class used to run @isTest(SeeAllData=true) and ask the whole
 * org how many deals are stuck today. That verdict moved with the org's data (76 -> 61
 * stuck chances within one day), so it turned red on every unrelated change.
 *
 * What is asserted now (SCRUM-482 ADR-2/ADR-3):
 *   the rule — counter == TODAY minus the record's OWN anchor; the anchor is
 *   LastStageChangeDate once a stage change happened, CreatedDate before that; a
 *   stage change moves the anchor and keeps the count at 0; a closed deal has no number.
 *   The magnitude "> 30 days" is NOT asserted here: CreatedDate and LastStageChangeDate
 *   are createable:false in BOTH orgs (measured 2026-11-26 with sf sobject describe), so
 *   a record a test creates always anchors on the run day and can never be 31+ days old.
 *   That magnitude is the release read-back of the report Sales/Chancen_Over_30_Tage.
 *
 * Isolation: SeeAllData is dropped, so every SOQL below sees only records THIS test
 * created. Each read-back is a WHERE Id = :fixtureId query with an asserted row count,
 * so a vacuous pass is impossible. No username, no date constant, no org-wide query.
 *
 * @author developer-agent
 * @date 2026-11-26
 */
@isTest
public class SCRUM477StageDaysReadTest {

    // One read-back for every fixture: formula fields are not on the in-memory SObject
    // after DML (house note SCRUM-403), so the number always comes from a query.
    private static Opportunity readBack(Id id) {
        List<Opportunity> rows = [
            SELECT Id, Name, StageName, CreatedDate, LastStageChangeDate,
            Stage_Days_In_Current_Stage__c
            FROM Opportunity
            WHERE Id = :id
        ];
        System.assertEquals(1, rows.size(), 'the fixture must be readable exactly once: ' + id);
        return rows[0];
    }

    // T1 — a brand new open deal shows zero days, anchored on its own CreatedDate.
    @isTest
    static void newOpenDeal_showsZeroDays() {
        List<Id> created = new List<Id>();

        Opportunity fresh = new Opportunity(
            Name = 'TEST-SCRUM-482-T1',
            StageName = 'Prospecting',
            Amount = 1500.00,
            CloseDate = Date.today().addDays(25)
        );
        insert fresh;
        created.add(fresh.Id);

        Opportunity o = readBack(fresh.Id);
        System.assertEquals(null, o.LastStageChangeDate,
            'T1 precondition: a deal that never changed stage has no LastStageChangeDate, ' +
                'so the formula must fall back to CreatedDate');

        Double anchor = (Double) o.CreatedDate.date().daysBetween(Date.today());
        System.assertEquals(0.0, anchor,
            'T1 precondition: the anchor is the record itself, created today — no date constant is used');
        System.assertEquals(anchor, o.Stage_Days_In_Current_Stage__c,
            'T1: a new open deal shows 0 days = TODAY minus its own CreatedDate');

        delete created;
    }

    // T3 — changing the stage moves the anchor to LastStageChangeDate and restarts the count.
    @isTest
    static void stageChange_restartsTheCount() {
        List<Id> created = new List<Id>();

        Opportunity moved = new Opportunity(
            Name = 'TEST-SCRUM-482-T3',
            StageName = 'Prospecting',
            Amount = 2000.00,
            CloseDate = Date.today().addDays(25)
        );
        insert moved;
        created.add(moved.Id);

        Opportunity before = readBack(moved.Id);
        System.assertEquals(null, before.LastStageChangeDate,
            'T3 precondition: the fixture starts without a stage change');
        System.assertEquals(0.0, (Double) before.CreatedDate.date().daysBetween(Date.today()),
            'T3 precondition: before the change the count is anchored on CreatedDate, i.e. today');

        // The house transition for T3: both values are open stages, so the record stays on
        // the stuck list and the transition itself stays outside the closed-stage rules.
        Opportunity toValueProposition = new Opportunity(
            Id = moved.Id,
            StageName = 'Value Proposition'
        );
        update toValueProposition;

        Opportunity after = readBack(moved.Id);
        System.assertEquals('Value Proposition', after.StageName, 'T3 precondition: the stage really moved');
        System.assertNotEquals(null, after.LastStageChangeDate,
            'T3: a stage change stamps LastStageChangeDate — the new anchor, never ModifiedDate');
        Double anchor = (Double) after.LastStageChangeDate.date().daysBetween(Date.today());
        System.assertEquals(0.0, anchor,
            'T3: the count restarts — the new anchor is the day of the change, so the number is back at 0');
        System.assertEquals(anchor, after.Stage_Days_In_Current_Stage__c,
            'T3: after the change the counter follows the NEW anchor, not the creation date');

        delete created;
    }

    // T4 — a closed deal carries no number at all, so it can never reach the stuck list.
    @isTest
    static void closedDeal_carriesNoNumber() {
        List<Id> created = new List<Id>();

        // Discount stays blank, so the SCRUM-445 approval rule and the 25 % cap stay quiet;
        // Loss_Reason__c is set to a value that is not 'Wettbewerber', so SCRUM-461's
        // competitor rule stays quiet as well.
        Opportunity won = new Opportunity(
            Name = 'TEST-SCRUM-482-T4-won',
            StageName = 'Closed Won',
            Amount = 1000.00,
            CloseDate = Date.today().addDays(5)
        );
        Opportunity lost = new Opportunity(
            Name = 'TEST-SCRUM-482-T4-lost',
            StageName = 'Closed Lost',
            Amount = 900.00,
            CloseDate = Date.today().addDays(5),
            Loss_Reason__c = 'KeinBudget'
        );
        List<Opportunity> closed = new List<Opportunity>{ won, lost };
        insert closed;
        for (Opportunity o : closed) {
            created.add(o.Id);
        }

        List<Opportunity> back = [
            SELECT Id, Name, StageName, Stage_Days_In_Current_Stage__c
            FROM Opportunity
            WHERE Id IN :created
        ];
        System.assertEquals(2, back.size(), 'T4: both closed fixtures must be readable exactly once');
        Integer checked = 0;
        for (Opportunity o : back) {
            System.assertEquals(null, o.Stage_Days_In_Current_Stage__c,
                'T4: a closed deal shows no number (' + o.Name + ')');
            checked++;
        }
        System.assertEquals(2, checked, 'T4: two closed records were asserted, not zero');

        delete created;
    }
}
