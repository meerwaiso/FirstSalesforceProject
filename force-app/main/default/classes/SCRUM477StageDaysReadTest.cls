@isTest(SeeAllData=true)
public class SCRUM477StageDaysReadTest {

    // SCRUM-477: read-back of the live feature in Test-Org, NOT an isolated unit test.
    // SeeAllData is deliberate: the criteria this class carries (the human test user
    // can READ the counter, the counter equals today minus the LAST REAL stage change
    // of records that already exist, closed deals show NULL) are about records the
    // feature must not touch - a fixture cannot have a past stage history, because
    // CreatedDate and LastStageChangeDate cannot be backdated. Every assertion that
    // depends on org data says "criterion untested" instead of passing silently.

    @isTest(SeeAllData=true)
    static void humanSessionReadsTheCounter() {
        User hu = [SELECT Id, Username FROM User WHERE Username = 'meerwais.osmani@resourceful-bear-6f1u4j.com' LIMIT 1];
        Boolean readable = false;
        Boolean writable = true;
        Integer rows = -1;
        Double topDays = -1;
        System.runAs(hu) {
            readable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isAccessible();
            writable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isUpdateable();
            List<Opportunity> stuck = [SELECT Id, StageName, Stage_Days_In_Current_Stage__c
                                       FROM Opportunity
                                       WHERE Stage_Days_In_Current_Stage__c > 30
                                         AND StageName != 'Closed Won' AND StageName != 'Closed Lost'
                                       ORDER BY Stage_Days_In_Current_Stage__c DESC];
            rows = stuck.size();
            if (rows > 0) {
                topDays = stuck[0].Stage_Days_In_Current_Stage__c;
            }
        }
        // Asserted OUTSIDE the runAs block: an assert inside a block whose failure
        // the org swallows would read as a pass (house warning in SCRUM-449/453).
        System.assert(readable, 'the human test user must be able to READ the day counter (PS assigned)');
        System.assertEquals(false, writable, 'nobody may WRITE the day counter (editable=false in the PS)');
        System.assert(rows > 0, 'the stuck filter must match at least one open record, else the criterion is untested');
        System.assert(topDays > 30, 'the top row must be strictly over 30 days (greaterThan 30, AC6)');
    }

    @isTest(SeeAllData=true)
    static void anchorIsTheLastRealStageChange() {
        // AC1/AC4/AC5: the number equals today minus the LAST REAL stage change,
        // measured on records that already exist in Test-Org - nothing here was
        // created or touched by this test.
        List<Opportunity> records = [SELECT Id, Name, StageName, CreatedDate, LastStageChangeDate, Stage_Days_In_Current_Stage__c
                                     FROM Opportunity
                                     WHERE Stage_Days_In_Current_Stage__c > 30
                                       AND StageName != 'Closed Won' AND StageName != 'Closed Lost'
                                     ORDER BY Stage_Days_In_Current_Stage__c DESC LIMIT 10];
        System.assert(!records.isEmpty(), 'no stuck record found: criterion untested');
        for (Opportunity o : records) {
            Date anchor = (o.LastStageChangeDate != null)
                ? o.LastStageChangeDate.date()
                : o.CreatedDate.date();
            Integer expected = anchor.daysBetween(Date.today());
            System.assertEquals(expected, (Integer) o.Stage_Days_In_Current_Stage__c,
                                'days must be TODAY minus the last real stage change, not the go-live date (' + o.Name + ')');
        }
    }

    @isTest(SeeAllData=true)
    static void closedDealsCarryNoNumber() {
        // AC2, cell side: a closed deal returns NULL, so it can never satisfy the
        // > 30 filter of the stuck list - even before the STAGE_NAME filter.
        List<Opportunity> closed = [SELECT Id, Name, StageName, Stage_Days_In_Current_Stage__c
                                    FROM Opportunity
                                    WHERE StageName = 'Closed Won' OR StageName = 'Closed Lost'
                                    ORDER BY StageName DESC LIMIT 10];
        System.assert(!closed.isEmpty(), 'Test-Org holds no closed opportunity: criterion untested');
        Integer checked = 0;
        for (Opportunity o : closed) {
            System.assert(o.Stage_Days_In_Current_Stage__c == null,
                          'a closed deal must show no day counter (' + o.Name + ')');
            checked++;
        }
        System.assert(checked > 0, 'at least one closed record was asserted');
    }
}
