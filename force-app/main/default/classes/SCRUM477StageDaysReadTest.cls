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
        // ORG-AGNOSTIC session user (SCRUM-478): a hardcoded username exists only in Test-Org,
        // so the Prod-Org Drift Gate threw 'List has no rows for assignment to SObject'.
        // No username is named any more — every ACTIVE user of THIS org is asked, house pattern
        // SCRUM410CustomerTransferTest ('FROM User WHERE IsActive = true'). runAs consumes no
        // licence, so this also covers the orgs where only System Administrators hold licences.
        List<User> users = [SELECT Id, Username FROM User WHERE IsActive = true];
        System.assert(!users.isEmpty(), 'no active User in this org: criterion untested');
        Integer seesStage = 0;
        Integer counterReadable = 0;
        Integer blindWhileOpen = 0;
        String blind = '';
        Integer writableCount = 0;
        for (User hu : users) {
            Boolean stageReadable = false;
            Boolean readable = false;
            Boolean writable = false;
            System.runAs(hu) {
                stageReadable = Opportunity.StageName.getDescribe().isAccessible();
                readable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isAccessible();
                writable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe().isUpdateable();
            }
            if (stageReadable) { seesStage++; }
            if (readable) { counterReadable++; }
            // The criterion: everyone who can SEE the opportunity sees the day number.
            // StageName is the marker of "can see the opportunity" — a standard field granted
            // by OWD, so a user who reads it but not the counter is a real gap.
            if (stageReadable && !readable) { blindWhileOpen++; blind += (blind == '' ? '' : ', ') + hu.Username; }
            if (writable) { writableCount++; }
        }
        System.debug('SCRUM477 read-back: activeUsers=' + users.size()
            + ' seesStage=' + seesStage + ' counterReadable=' + counterReadable
            + ' blindWhileOpen=' + blindWhileOpen + ' writable=' + writableCount);
        Integer rows = -1;
        Double topDays = -1;
        List<Opportunity> stuck = [SELECT Id, StageName, Stage_Days_In_Current_Stage__c
                                   FROM Opportunity
                                   WHERE Stage_Days_In_Current_Stage__c > 30
                                     AND StageName != 'Closed Won' AND StageName != 'Closed Lost'
                                   ORDER BY Stage_Days_In_Current_Stage__c DESC];
        rows = stuck.size();
        if (rows > 0) { topDays = stuck[0].Stage_Days_In_Current_Stage__c; }
        // Assertions live OUTSIDE every runAs block: a failure inside a block the org
        // swallows would read as a pass (house warning in SCRUM-449/453).
        System.assert(counterReadable > 0, 'no active user can READ the counter: the PS is assigned to nobody');
        System.assertEquals(0, blindWhileOpen, 'users who can see StageName but NOT the day counter (' + blind + ') — AC9/everyone-who-can-see must hold');
        System.assertEquals(0, writableCount, 'no active user may WRITE the counter (' + writableCount + ' can)');
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
