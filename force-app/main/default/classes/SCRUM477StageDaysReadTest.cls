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
 *   The magnitude IS asserted here, on a fixture the test aged itself: Test.setCreatedDate
 *   writes the CreatedDate of a record the test created after the insert (house precedent:
 *   SCRUM398EskalationsstufeTest L42, SCRUM424FirstResponseTest L62). createable:false on
 *   an autofill anchor only means the constructor cannot carry it — it does not make the
 *   magnitude untestable. What stays untestable is an aged STAGE CHANGE: LastStageChangeDate
 *   is refused at compile time ("Field is not writeable"), so an old stage change cannot be
 *   manufactured; the release read-back of Sales/Chancen_Over_30_Tage covers the org's own
 *   data, not the magnitude.
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
        List<Opportunity> created = new List<Opportunity>();

        Opportunity fresh = new Opportunity(
            Name = 'TEST-SCRUM-482-T1',
            StageName = 'Prospecting',
            Amount = 1500.00,
            CloseDate = Date.today().addDays(25)
        );
        insert fresh;
        created.add(fresh);

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

    // T2 — the magnitude on a fixture the test aged itself, plus the anchor switch in one proof.
    @isTest
    static void agedOpenDeal_showsTheAgedDays_andAStageChangeRestartsThem() {
        List<Opportunity> created = new List<Opportunity>();

        Opportunity aged = new Opportunity(
            Name = 'TEST-SCRUM-482-T2',
            StageName = 'Prospecting',
            Amount = 1800.00,
            CloseDate = Date.today().addDays(25)
        );
        insert aged;
        created.add(aged);

        Opportunity fresh = readBack(aged.Id);
        System.assertEquals(null, fresh.LastStageChangeDate,
            'T2 precondition: a fixture that never changed stage has no LastStageChangeDate, ' +
                'so the formula takes the CreatedDate branch');
        System.assertEquals(0.0, fresh.Stage_Days_In_Current_Stage__c,
            'T2 precondition: before the backdate the anchor is the run day, so the number is 0');

        // The only way to age a fixture: CreatedDate is autofilled and not writeable in a
        // constructor, but a test may set it on a record the test created.
        Datetime anchor = Datetime.now().addDays(-40);
        Test.setCreatedDate(aged.Id, anchor);

        Opportunity old = readBack(aged.Id);
        System.assertEquals(anchor.date(), old.CreatedDate.date(),
            'T2: the test moved the anchor of THIS record 40 days into the past');
        Integer expectedAged = anchor.date().daysBetween(Date.today());
        System.assertEquals(40, expectedAged,
            'T2 precondition: the expectation is derived from the date the test set, relative to the run day');
        System.assertEquals((Double) expectedAged, old.Stage_Days_In_Current_Stage__c,
            'T2: a fixture that sat 40 days in its stage shows 40 = TODAY minus its own anchor');

        Opportunity movedOn = new Opportunity(
            Id = aged.Id,
            StageName = 'Value Proposition'
        );
        update movedOn;

        Opportunity after = readBack(aged.Id);
        System.assertEquals('Value Proposition', after.StageName, 'T2 precondition: the stage really moved');
        System.assertNotEquals(null, after.LastStageChangeDate,
            'T2: the stage change stamps the new anchor — LastStageChangeDate, never ModifiedDate');
        System.assertEquals(0, after.LastStageChangeDate.date().daysBetween(Date.today()),
            'T2: the new anchor is the day of the change');
        System.assertEquals(0.0, after.Stage_Days_In_Current_Stage__c,
            'T2/T3: after the stage change the count restarted at 0, on an aged record');

        delete created;
    }

    // T3 — changing the stage moves the anchor to LastStageChangeDate and restarts the count.
    @isTest
    static void stageChange_restartsTheCount() {
        List<Opportunity> created = new List<Opportunity>();

        Opportunity moved = new Opportunity(
            Name = 'TEST-SCRUM-482-T3',
            StageName = 'Prospecting',
            Amount = 2000.00,
            CloseDate = Date.today().addDays(25)
        );
        insert moved;
        created.add(moved);

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
        List<Id> ids = new List<Id>();

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
            ids.add(o.Id);
        }

        List<Opportunity> back = [
            SELECT Id, Name, StageName, Stage_Days_In_Current_Stage__c
            FROM Opportunity
            WHERE Id IN :ids
        ];
        System.assertEquals(2, back.size(), 'T4: both closed fixtures must be readable exactly once');
        Integer checked = 0;
        for (Opportunity o : back) {
            System.assertEquals(null, o.Stage_Days_In_Current_Stage__c,
                'T4: a closed deal shows no number (' + o.Name + ')');
            checked++;
        }
        System.assertEquals(2, checked, 'T4: two closed records were asserted, not zero');

        delete closed;
    }
}
