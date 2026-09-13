/**
 * [SCRUM-413] Feld, Trigger, Batch, Tests.
 */
@isTest
private class SCRUM413LastRealContactDateTest {
    private static Id newContact(String tag) {
        Contact c = new Contact(LastName = 'V413 ' + tag);
        insert c;
        return c.Id;
    }
    private static Date lastContactDateOf(Id contactId) {
        return [SELECT Last_Real_Contact_Date__c FROM Contact WHERE Id = :contactId].Last_Real_Contact_Date__c;
    }
    @isTest static void completedCall_setsDate() {
        Id a = newContact('Finished');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today());
        System.assertEquals(Date.Today(), lastContactDateOf(a), 'AC1: abgeschlossener Call → ActivityDate');
    }
    @isTest static void completedPastCall_setsPastDate() {
        Id a = newContact('Past');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today().addDays(-5));
        System.assertEquals(Date.Today().addDays(-5), lastContactDateOf(a), 'AC1: vergangenes Datum');
    }
    @isTest static void nonCompletedCalls_ignored() {
        Id a = newContact('Planned');
        insert new Task(WhoId = a, Status = 'Not Started', Type = 'Call');
        insert new Task(WhoId = a, Status = 'In Progress', Type = 'Call');
        System.assertEquals(null, lastContactDateOf(a), 'AC2: Incomplete Calls → null');
    }
    @isTest static void completedEmail_ignored() {
        Id a = newContact('Email');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Email', ActivityDate = Date.Today());
        System.assertEquals(null, lastContactDateOf(a), 'AC2/Typ-Filter: Email → null');
    }
    @isTest static void openCall_thenCompleted_writesDate() {
        Id a = newContact('ThenComp');
        Task t = new Task(WhoId = a, Status = 'Not Started', Type = 'Call', ActivityDate = Date.Today());
        insert t;
        System.assertEquals(null, lastContactDateOf(a), 'vor Completion: null');
        t.Status = 'Completed';
        update t;
        System.assertEquals(Date.Today(), lastContactDateOf(a), 'AC2/Update: nach Completion → Datum');
    }
    @isTest static void multipleCalls_newestWins() {
        Id a = newContact('Multi');
        Date d1 = Date.Today().addDays(-10), d2 = Date.Today().addDays(-3), d3 = Date.Today();
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = d1);
        System.assertEquals(d1, lastContactDateOf(a), 'AC4: erster Call → d1');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = d2);
        System.assertEquals(d2, lastContactDateOf(a), 'AC4: zweiter Call → d2');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = d3);
        System.assertEquals(d3, lastContactDateOf(a), 'AC4: neuester Call → d3');
    }
    @isTest static void noCall_staysNull() {
        Id a = newContact('Never');
        insert new Task(WhoId = a, Status = 'In Progress', Type = 'Call');
        System.assertEquals(null, lastContactDateOf(a), 'AC5: kein Call → null');
    }
    @isTest static void newestCallDeleted_fallsBack() {
        Id a = newContact('Regress');
        Date dOld = Date.Today().addDays(-10), dNew = Date.Today();
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dOld);
        Task newest = new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dNew);
        insert newest;
        System.assertEquals(dNew, lastContactDateOf(a), 'vor Delete: jüngster Call');
        delete newest;
        System.assertEquals(dOld, lastContactDateOf(a), 'AC4/Rückfall: älterer Call');
    }
    @isTest static void newestCallReopened_fallsBack() {
        Id a = newContact('Reopen');
        Date dOld = Date.Today().addDays(-5), dNew = Date.Today();
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dOld);
        Task newest = new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dNew);
        insert newest;
        System.assertEquals(dNew, lastContactDateOf(a), 'vor Reopen: jüngster Call');
        newest.Status = 'Not Started';
        update newest;
        System.assertEquals(dOld, lastContactDateOf(a), 'AC4/Rückfall: reopened → älterer Call');
    }
    @isTest static void lastCallDeleted_fallsToNull() {
        Id a = newContact('NullFall');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today().addDays(-3));
        System.assertEquals(Date.Today().addDays(-3), lastContactDateOf(a), 'vor Delete: vorhanden');
        Task only = [SELECT Id FROM Task WHERE WhoId = :a];
        delete only;
        System.assertEquals(null, lastContactDateOf(a), 'AC5/Rückfall: null');
    }
    @isTest static void batchRun_healsStale() {
        Id a = newContact('Stale');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today().addDays(-7));
        Contact up = [SELECT Id, Last_Real_Contact_Date__c FROM Contact WHERE Id = :a];
        up.Last_Real_Contact_Date__c = null;
        update up;
        System.assertEquals(null, lastContactDateOf(a), 'Vor Batch: stale');
        Test.startTest();
        String batchId = LastRealContactDateRebuilder.runOnce();
        Test.stopTest();
        System.assert(String.isNotBlank(batchId));
        System.assertEquals(Date.Today().addDays(-7), lastContactDateOf(a), 'AC6: Batch-Run → gehheilt');
    }
    @isTest static void batchIsIdempotent() {
        Id a = newContact('Idem');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today());
        LastRealContactDateRebuilder.runOnce();
        Integer changed = LastRealContactDateTrigger.recompute(new Set<Id>{a});
        System.assertEquals(0, changed, 'Idempotenz: 0 geändert');
    }
    @isTest static void bulk200_keepsGovernor() {
        List<Contact> con = new List<Contact>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 200; i++) con.add(new Contact(LastName = 'B' + i));
        insert con;
        for (Contact c : con) ids.add(c.Id);
        List<Task> tasks = new List<Task>();
        for (Id cid : ids)
            tasks.add(new Task(WhoId = cid, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today()));
        insert tasks;
        for (Id cid : ids)
            System.assertEquals(Date.Today(), lastContactDateOf(cid), 'Bulk jeder Contact → heute');
    }
    @isTest static void callWithoutWhoId_silent() {
        insert new Task(Status = 'Completed', Type = 'Call', ActivityDate = Date.Today());
        System.assert(Limits.getDmlCalls() <= 1, 'Kein unnötiger DML');
    }
    @isTest static void recompute_guards() {
        System.assertEquals(0, LastRealContactDateTrigger.recompute(null));
        System.assertEquals(0, LastRealContactDateTrigger.recompute(new Set<Id>()));
    }
    @isTest static void callOnLeadOnly_ignoredForContact() {
        Lead l = new Lead(LastName = 'Lead', Company = 'X');
        insert l;
        insert new Task(Status = 'Completed', Type = 'Call', WhoId = l.Id, ActivityDate = Date.Today());
        Id cid = newContact('NotLead');
        System.assertEquals(null, lastContactDateOf(cid), 'LeadWhoId → Contact null');
    }
}
