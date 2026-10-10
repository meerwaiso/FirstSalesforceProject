/**
 * [SCRUM-440] Rueckrufwish — Apex-Funktionaltests (AC3/AC4/AC5 + Bulk).
 *
 * TA→AC-Mapping (docs/SCRUM-440-design.md):
 *   AC3: checked + valid future Rueckruf_am -> exactly one open callback Task
 *        (Subject 'Rückruf: '+Name, Priority High, Status Not Started,
 *         ActivityDate = date(Rueckruf_am), OwnerId = Opportunity creator).
 *   AC4: change the date while an open Task exists -> that Task updated, NO second Task.
 *   AC5: uncheck -> the open Task set to Status 'Deferred' (OP-1 default; not deleted).
 *   Bulk: 200 Opportunity updates in one save -> 1 Task SOQL + 1 insert batch.
 *
 * Execution context (house SCRUM-432 / fls-gate Lücke C): the two Opportunity
 * fields are FLS-gated, so every business DML/SOQL that touches them runs under
 * System.runAs(<Standard User + SCRUM440 PS>). Setup inserts (Account, Opportunity
 * with checkbox off — no FLS-gated field touched) run OUTSIDE runAs; a Standard
 * User cannot grant itself a PSA. Bulk isolates the handler by calling
 * handleAfterUpdate directly (no Opportunity save -> the trigger does not fire).
 */
@isTest
private class SCRUM440RueckrufwunschTest {

    private static Id newAccountId(String tag) {
        Account a = new Account(Name = 'V440 ' + tag);
        insert a;
        return a.Id;
    }

    private static Opportunity newOpp(Id accId, String name) {
        Opportunity o = new Opportunity(
            Name = name, AccountId = accId, StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(3)
        );
        insert o;
        return o;
    }

    // A future callback datetime (ValRule requires > NOW()).
    private static Datetime futureDate() {
        return Datetime.now().addDays(2);
    }

    /** Standard User + SCRUM440 PS. Setup DML (User + PSA) OUTSIDE runAs. */
    private static User prepareReader(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'SCRUM440 ' + tag,
            Alias             = tag,
            Email             = tag + '@example.invalid',
            Username          = tag + '_' + String.valueOf(System.now().getTime()) + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM440_Rueckrufwunsch' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    /** AC3: check + future date on an existing Opportunity -> one open callback Task. */
    @isTest
    static void checkAndFutureDate_createsOneTask() {
        Id acc = newAccountId('AC3');
        User su = prepareReader('ac3');
        System.runAs(su) {
            // Opportunity created BY the reader, so the auto-Task (OwnerId = CreatedById)
            // is owned by su and su can update it later (real scenario: the editor owns it).
            Opportunity o = new Opportunity(
                Name = 'V440 ac3', AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            );
            insert o;

            o.Rueckruf_desired__c = true;
            o.Rueckruf_am__c = futureDate();
            update o;

            List<Task> tasks = [SELECT Id, Subject, Status, Priority, ActivityDate, OwnerId, WhatId
                                FROM Task WHERE WhatId = :o.Id AND Subject LIKE 'Rückruf:%'];
            System.assertEquals(1, tasks.size(), 'AC3: exactly one callback Task per Opportunity');
            Task t = tasks[0];
            System.assertEquals('Rückruf: V440 ac3', t.Subject, 'AC3: Subject = prefix + Opportunity Name');
            System.assertEquals('High', t.Priority, 'AC3: Priority Hoch = High');
            System.assertEquals('Not Started', t.Status, 'AC3: new Task Not Started');
            System.assertEquals(o.Id, t.WhatId, 'AC3: Task linked via WhatId');
            Opportunity fresh = [SELECT Id, CreatedById FROM Opportunity WHERE Id = :o.Id LIMIT 1];
            System.assertEquals(fresh.CreatedById, t.OwnerId,
                'AC3: Task owned by the Opportunity creator (Task.OwnerId required, set to CreatedById)');
            System.assertEquals(futureDate().date(), t.ActivityDate, 'AC3: due date = date(Rueckruf_am)');
        }
    }

    /** AC4: change the date while an open Task exists -> that Task updated, no second. */
    @isTest
    static void changeDate_updatesExistingTaskNoDuplicate() {
        Id acc = newAccountId('AC4');
        User su = prepareReader('ac4');
        System.runAs(su) {
            Opportunity o = new Opportunity(
                Name = 'V440 ac4', AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            );
            insert o;

            o.Rueckruf_desired__c = true;
            o.Rueckruf_am__c = futureDate();
            update o;
            System.assertEquals(1,
                [SELECT Id FROM Task WHERE WhatId = :o.Id AND Subject LIKE 'Rückruf:%' AND IsClosed = false].size(),
                'AC4 setup: one open Task after first save');

            // Later: move the callback date forward.
            Datetime later = futureDate().addHours(6);
            o.Rueckruf_am__c = later;
            update o;

            List<Task> tasks = [SELECT Id, Subject, ActivityDate FROM Task
                                WHERE WhatId = :o.Id AND Subject LIKE 'Rückruf:%' AND IsClosed = false];
            System.assertEquals(1, tasks.size(), 'AC4: still exactly one open Task (no duplicate)');
            System.assertEquals(later.date(), tasks[0].ActivityDate, 'AC4: existing Task ActivityDate updated');
        }
    }

    /** AC5: uncheck -> the open Task set to Deferred (not deleted). */
    @isTest
    static void uncheck_defersOpenTask() {
        Id acc = newAccountId('AC5');
        User su = prepareReader('ac5');
        System.runAs(su) {
            Opportunity o = new Opportunity(
                Name = 'V440 ac5', AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            );
            insert o;

            o.Rueckruf_desired__c = true;
            o.Rueckruf_am__c = futureDate();
            update o;
            System.assertEquals(1,
                [SELECT Id FROM Task WHERE WhatId = :o.Id AND Subject LIKE 'Rückruf:%'].size(),
                'AC5 setup: one callback Task after first save');

            o.Rueckruf_desired__c = false;
            update o;

            List<Task> tasks = [SELECT Id, Status, IsClosed FROM Task
                                WHERE WhatId = :o.Id AND Subject LIKE 'Rückruf:%'];
            System.assertEquals(1, tasks.size(), 'AC5: Task NOT deleted (still present)');
            System.assertEquals('Deferred', tasks[0].Status, 'AC5: open Task set to Deferred (OP-1 default)');
            System.assertEquals(false, tasks[0].IsClosed, 'AC5: Task not closed, only deferred');
        }
    }

    /** Bulk: 200 Opportunity end-states -> 1 Task query + 1 insert batch.
     * Handler ISOLIERT messen (house SCRUM-437): call handleAfterUpdate directly so
     * only the RueckrufTaskHandler's own SOQL counts, not the rollup handler's.
     * No Opportunity save here -> the OpportunityOverdueReset trigger does not fire. */
    @isTest
    static void bulk200_createsOneTaskEach() {
        Id acc = newAccountId('Bulk');
        // EINEM Multi-Record-Insert (house SCRUM-437): 200 separate inserts would
        // each fire the pre-existing rollup handler's per-record SOQL and blow the
        // 100-query governor limit in the SETUP, not in our handler.
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(
                Name = 'V440 bulk-' + i, AccountId = acc, StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            ));
        }
        insert opps;   // setup, checkbox off, outside runAs

        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) {
            oppIds.add(o.Id);
        }

        User su = prepareReader('bulk');
        System.runAs(su) {
            // Old state (checkbox off) captured fresh, so the handler sees false->true.
            Map<Id, Opportunity> beforeMap = new Map<Id, Opportunity>();
            for (Opportunity o : [SELECT Id, Name, Rueckruf_desired__c, Rueckruf_am__c, CreatedById
                                  FROM Opportunity WHERE Id IN :oppIds]) {
                beforeMap.put(o.Id, o);
            }

            // End state on SOQL-backed records — CreatedById is only populated via SOQL,
            // and the handler needs it for the required Task.OwnerId.
            Datetime due = futureDate();
            List<Opportunity> after = new List<Opportunity>();
            for (Opportunity o : [SELECT Id, Name, Rueckruf_desired__c, Rueckruf_am__c, CreatedById
                                  FROM Opportunity WHERE Id IN :oppIds]) {
                o.Rueckruf_desired__c = true;
                o.Rueckruf_am__c = due;
                after.add(o);
            }

            Integer queriesBefore = Limits.getQueries();
            RueckrufTaskHandler.handleAfterUpdate(after, beforeMap);
            Integer handlerQueries = Limits.getQueries() - queriesBefore;

            System.assertEquals(1, handlerQueries,
                'AC7 (Governance): Handler macht exakt 1 bulkified Task SOQL pro Batch '
                + '(' + handlerQueries + ' gemessen) — KEINE pro-Record-Query');

            List<Task> tasks = [SELECT Id, Subject FROM Task WHERE WhatId IN :oppIds AND Subject LIKE 'Rückruf:%'];
            System.assertEquals(200, tasks.size(), 'Bulk: one Task per Opportunity, no per-record blowup');
        }
    }
}
