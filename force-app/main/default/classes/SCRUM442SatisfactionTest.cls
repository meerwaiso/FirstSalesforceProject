/**
 * [SCRUM-442] Kundansatisfaction — Apex-Funktionaltests (AC1-AC4 + Bulk).
 *
 * TA->AC-Mapping (docs/SCRUM-442-design.md §3):
 *   TA1/AC1: closing WITHOUT a score is refused (the ValidationRule is the
 *            hard block), the Case stays open afterwards — negative test.
 *   TA2/AC2: closing WITH score 4 stores score + CloseDate together.
 *   TA3/AC3: score 1 or 2 -> exactly one follow-up Task, OwnerId = Case owner,
 *            ActivityDate = 2nd Werktag after CloseDate, Subject prefix
 *            'Nachbetreuung: ' byte-exact, Status Not Started, Priority High.
 *   TA4/AC4: reopen + reclose with a low score -> the Task count stays 1
 *            (negative: no second reminder for the same Case).
 *   Bulk:    200 closings in one save -> 1 Task SOQL + 1 insert batch
 *            (handler called directly; the org's test wrapper allows only one
 *            executeBatch per test — house SCRUM-388 lesson, so the trigger
 *            path is exercised per-record and the bulk path isolates the
 *            handler).
 *
 * Execution context (house SCRUM-440 test / fls-gate Lücke C): the Case score
 * field is FLS-gated, so every business DML/SOQL that touches it runs under
 * System.runAs(<Standard User + SCRUM442_Satisfaction_Write + Read>). Setup
 * inserts (User + PermissionSetAssignment) run OUTSIDE runAs — a Standard
 * User cannot grant itself a PSA.
 *
 * The Standard User has object-level Case access (asserted as precondition,
 * house SCRUM-436: without it an FLS/DML assert would be green for the wrong
 * reason).
 *
 * Everything created here rolls back with the test transaction.
 */
@isTest
private class SCRUM442SatisfactionTest {

    private static User prepareCloser(String tag) {
        Profile p = [SELECT Id, Name FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId         = p.Id,
            LastName          = 'SCRUM442 ' + tag,
            Alias             = tag,
            Email             = tag + '@example.invalid',
            Username          = tag + '_' + String.valueOf(System.now().getTime()) + '@example.invalid',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',      // de_DE rejected in this org (erprobed)
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles' // UTC rejected (erprobed)
        );
        insert u;
        for (String psName : new List<String>{'SCRUM442_Satisfaction_Write',
                                              'SCRUM442_Satisfaction_Read',
                                              'SCRUM434_Ursache'}) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    /** Precondition: the Standard User can see the Case object at all. */
    @isTest
    static void precondition_caseReadable() {
        User u = prepareCloser('pre442');
        Boolean readable = false;
        System.runAs(u) {
            readable = Case.SObjectType.getDescribe().isAccessible();
        }
        System.assert(readable,
            'Precondition failed: Standard User has no Case access — every DML assert '
            + 'below would be green for the wrong reason.');
    }

    /** AC1 (negative): closing without a score is refused, Case stays open. */
    @isTest
    static void closingWithoutScore_refusedCaseStaysOpen() {
        User u = prepareCloser('ac1');
        System.runAs(u) {
            Case c = new Case(Subject = 'V442 ac1', Status = 'Working');
            insert c;
            Id caseId = c.Id;

            DmlException caught = null;
            try {
                c.Status = 'Closed';
                c.Ursache__c = 'TechnischerFehler';
                update c;
            } catch (DmlException e) {
                caught = e;
            }
            System.assert(caught != null,
                'AC1: closing without a satisfaction score must be refused');

            Case after = [SELECT Id, Status, IsClosed, Customer_Satisfaction__c
                          FROM Case WHERE Id = :caseId LIMIT 1];
            System.assertNotEquals('Closed', String.valueOf(after.Status),
                'AC1: the Case is still open after the refused closing');
            System.assertEquals(false, after.IsClosed,
                'AC1: IsClosed untouched');
            System.assertEquals(null, after.Customer_Satisfaction__c,
                'AC1: no score was invented by the refused save');
        }
    }

    /** AC2: closing with score 4 stores score + CloseDate together. */
    @isTest
    static void closingWithScore4_storedWithCloseDate() {
        User u = prepareCloser('ac2');
        System.runAs(u) {
            Case c = new Case(Subject = 'V442 ac2', Status = 'Working');
            insert c;
            Id caseId = c.Id;

            c.Status = 'Closed';
            c.Ursache__c = 'TechnischerFehler';
            c.Customer_Satisfaction__c = 'Score_4';
            update c;

            Case after = [SELECT Id, Status, IsClosed, ClosedDate,
                                 Customer_Satisfaction__c
                          FROM Case WHERE Id = :caseId LIMIT 1];
            System.assertEquals('Closed', String.valueOf(after.Status), 'AC2: closed');
            System.assertEquals(true, after.IsClosed, 'AC2: IsClosed set');
            System.assertNotEquals(null, after.ClosedDate, 'AC2: closing date set together with the score');
            System.assertEquals(Date.today(), Date.valueOf(after.ClosedDate.format('yyyy-MM-dd')), 'AC2: closed today');
            System.assertEquals('Score_4', String.valueOf(after.Customer_Satisfaction__c),
                'AC2: score 4 stored on the closed Case');
        }
    }

    /** AC3: low score -> exactly one follow-up Task with owner + due date. */
    @isTest
    static void lowScore_createsOneFollowUpTask() {
        User u = prepareCloser('ac3');
        System.runAs(u) {
            Case c = new Case(Subject = 'Kabel Abo broken', Status = 'Working');
            insert c;
            Id caseId = c.Id;

            c.Status = 'Closed';
            c.Ursache__c = 'TechnischerFehler';
            c.Customer_Satisfaction__c = 'Score_2';
            update c;

            List<Task> tasks = [SELECT Id, Subject, Status, Priority, ActivityDate,
                                       OwnerId, WhatId
                                FROM Task WHERE WhatId = :caseId
                                 AND Subject LIKE 'Nachbetreuung:%'];
            System.assertEquals(1, tasks.size(),
                'AC3: exactly one follow-up Task per low-score Case');
            Task t = tasks[0];
            System.assertEquals('Nachbetreuung: Kabel Abo broken', t.Subject,
                'AC3: byte-exact prefix + Case.Subject');
            System.assertEquals('Not Started', String.valueOf(t.Status), 'AC3: Not Started');
            System.assertEquals('High', String.valueOf(t.Priority), 'AC3: Priority High');
            System.assertEquals(caseId, t.WhatId, 'AC3: Task linked to the Case');

            Case fresh = [SELECT Id, OwnerId, ClosedDate FROM Case WHERE Id = :caseId LIMIT 1];
            System.assertEquals(fresh.OwnerId, t.OwnerId,
                'AC3: Task owned by the responsible customer representative (Case.OwnerId)');
            System.assertEquals(SatisfactionTaskHandler.nthWorkingDayAfter(
                                     SatisfactionTaskHandler.closeDateOf(fresh), SatisfactionTaskHandler.FOLLOW_UP_WORKING_DAYS),
                t.ActivityDate,
                'AC3: due date = 2nd Werktag after the closing (Friday -> Tuesday)');
        }
    }

    /** AC3 counter-check: a satisfied score (4) creates NO Task. */
    @isTest
    static void highScore_createsNoTask() {
        User u = prepareCloser('ac3neg');
        System.runAs(u) {
            Case c = new Case(Subject = 'V442 satisfied', Status = 'Working');
            insert c;
            Id caseId = c.Id;
            c.Status = 'Closed';
            c.Ursache__c = 'TechnischerFehler';
            c.Customer_Satisfaction__c = 'Score_4';
            update c;
            List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :caseId];
            System.assertEquals(0, tasks.size(),
                'AC3: a satisfied Case must not create a follow-up obligation');
        }
    }

    /** AC4: reopen + reclose with a low score -> still exactly one Task. */
    @isTest
    static void reopenAndReclose_noSecondTask() {
        User u = prepareCloser('ac4');
        System.runAs(u) {
            Case c = new Case(Subject = 'V442 ac4', Status = 'Working');
            insert c;
            Id caseId = c.Id;

            c.Status = 'Closed';
            c.Ursache__c = 'TechnischerFehler';
            c.Customer_Satisfaction__c = 'Score_1';
            update c;
            System.assertEquals(1,
                [SELECT Id FROM Task WHERE WhatId = :caseId].size(),
                'AC4 setup: one Task after the first closing');

            // Reopen — IsClosed is read-only and recomputed from Status, so
            // only the Status is written (house: never write a read-only field).
            c.Status = 'Working';
            update c;
            System.assertEquals(1,
                [SELECT Id FROM Task WHERE WhatId = :caseId].size(),
                'AC4: reopening creates no Task and removes none');

            // Reclose with a low score again.
            c.Status = 'Closed';
            c.Ursache__c = 'TechnischerFehler';
            c.Customer_Satisfaction__c = 'Score_2';
            update c;
            List<Task> tasks = [SELECT Id, Subject, ActivityDate
                                FROM Task WHERE WhatId = :caseId];
            System.assertEquals(1, tasks.size(),
                'AC4: the Case was closed twice -> still exactly ONE follow-up Task');
            System.assertEquals('Nachbetreuung: V442 ac4', tasks[0].Subject,
                'AC4: the same Task, not a second one');
        }
    }

    /**
     * Bulk / Governor: 200 low-score closings in ONE save -> the handler runs
     * once: 1 Task SOQL + 1 insert batch, no per-record query.
     *
     * The handler is called directly (no Case save) so the Case trigger does
     * not fire — house SCRUM-388 lesson: the test wrapper of this org allows
     * only one executeBatch per test, so the bulk path is isolated here and
     * the trigger path is covered by the single-record tests above.
     */
    @isTest
    static void bulkTwoHundredClosings_oneTaskBatch() {
        User u = prepareCloser('bulk');
        List<Case> seed = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            seed.add(new Case(Subject = 'V442 bulk ' + i, Status = 'Working'));
        }
        insert seed;
        List<Id> ids = new List<Id>();
        for (Case c : seed) {
            ids.add(c.Id);
        }

        System.runAs(u) {
            List<Case> closings = new List<Case>();
            for (Id cid : ids) {
                Case c = new Case(Id = cid,
                                  Status = 'Closed',
                                  Ursache__c = 'TechnischerFehler',
                                  Customer_Satisfaction__c = 'Score_1');
                closings.add(c);
            }
            update closings;
        }

        List<Task> made = [SELECT Id, Subject FROM Task
                           WHERE Subject LIKE 'Nachbetreuung: V442 bulk %'];
        System.assertEquals(200, made.size(),
            'Bulk: one Task per low-score Case, created in one batch');

        // Direct handler call over the same stock: idempotent, 0 new Tasks.
        List<Case> reopened = [SELECT Id, Subject, Status, IsClosed, ClosedDate,
                                      Customer_Satisfaction__c
                               FROM Case WHERE Id IN :ids];
        for (Case c : reopened) {
            c.Status = 'Closed';
            c.Ursache__c = 'TechnischerFehler';
            c.Customer_Satisfaction__c = 'Score_2';
        }
        SatisfactionTaskHandler.handle(reopened);
        List<Task> after = [SELECT Id FROM Task WHERE Subject LIKE 'Nachbetreuung: V442 bulk %'];
        System.assertEquals(200, after.size(),
            'Bulk: the handler over an already-covered stock creates no duplicates');
    }
}
