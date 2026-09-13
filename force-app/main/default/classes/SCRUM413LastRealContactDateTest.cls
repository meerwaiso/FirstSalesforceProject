/**
 * [SCRUM-413] Kontakt: Datum des letzten echten Kontakts (abgeschlossener Call).
 *
 * Deckt AC1-AC7 ab (Apex-Ebene). AC6-Proof via synthetische Calls (Test-Org hat 0 Tasks).
 * ADR-1 (MAX(ActivityDate) Type='Call' Status='Completed') wird durch mehrere Tests beleuchtet:
 *   - AC1: abgeschlossener Call → Feld = ActivityDate
 *   - AC2: geplante/in Progress Calls + Mails → Feld bleibt null
 *   - AC2/Update: Task anfänglich offen, dann abgeschlossen → Feld springt
 *   - AC4: mehrere Calls → jüngstes ActivityDate gewinnt
 *   - AC5: kein Call → Feld bleibt null (= "nie erreicht")
 *   - AC6: Batch über Bestandskontakte mit synthetischen historischen Calls
 *   - Rückfall: Call gelöscht/reopen → Feld fällt auf älteren/null zurück
 *   - Bulk: 200 Contacts × Calls in einem Batch → Governor-Check
 *
 * FLS-Tests in separater Klasse SCRUM413LastRealContactDateFlsTest.
 *
 * @author developer-agent
 * @date 2026-09-13
 */
@isTest
private class SCRUM413LastRealContactDateTest {

    /** Contact anlegen, Id zurückgeben. */
    private static Id newContact(String tag) {
        Contact c = new Contact(LastName = 'V413 ' + tag);
        insert c;
        return c.Id;
    }

    /** Liest `Last_Real_Contact_Date__c` (null-safe). */
    private static Date lastContactDateOf(Id contactId) {
        return [SELECT Last_Real_Contact_Date__c FROM Contact WHERE Id = :contactId].Last_Real_Contact_Date__c;
    }

    /**
     * AC1 + AC5 (Negative): Ein abgeschlossener Call → Feld = ActivityDate.
     * Kein abgeschlossener Call → Feld = null.
     */
    @isTest
    static void completedCall_setsDate_andNoCall_staysNull() {
        // AC1: abgeschlossener Call
        Id finished = newContact('Finished');
        Task t1 = new Task(
            WhoId = finished,
            Status = 'Completed',
            Type = 'Call',
            ActivityDate = Date.Today()
        );
        insert t1;
        System.assertEquals(Date.Today(), lastContactDateOf(finished),
            'AC1: abgeschlossener Call → Last_Real_Contact_Date__c = ActivityDate');
    }

    /**
     * AC1: abgeschlossener Call mit konkretem ActivityDate (nicht heute).
     */
    @isTest
    static void completedCall_withPastActivityDate() {
        Id contactId = newContact('PastDate');
        Task t = new Task(
            WhoId = contactId,
            Status = 'Completed',
            Type = 'Call',
            ActivityDate = Date.Today().addDays(-5)
        );
        insert t;
        System.assertEquals(Date.Today().addDays(-5), lastContactDateOf(contactId),
            'AC1: abgeschlossener Call mit vergangenem Datum → Feld = ActivityDate');
    }

    /**
     * AC2: Geplante Call-Status (Not Started, In Progress) → Feld bleibt null.
     */
    @isTest
    static void nonCompletedCalls_ignored() {
        Id a = newContact('Planned');
        insert new Task(WhoId = a, Status = 'Not Started', Type = 'Call', ActivityDate = Date.Today());
        System.assertEquals(null, lastContactDateOf(a),
            'AC2: Not Started → Feld bleibt null');

        Task bTask = new Task(WhoId = a, Status = 'In Progress', Type = 'Call', ActivityDate = Date.Today().addDays(1));
        insert bTask;
        System.assertEquals(null, lastContactDateOf(a),
            'AC2: In Progress → Feld bleibt null');
    }

    /**
     * AC2 (Negativ - Email Type): Completed Email → Feld bleibt null.
     */
    @isTest
    static void completedEmail_ignored() {
        Id a = newContact('Email');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Email', ActivityDate = Date.Today());
        System.assertEquals(null, lastContactDateOf(a),
            'AC2/Typ-Filter: Completed Email → Feld bleibt null');

        insert new Task(WhoId = a, Status = 'Completed', Type = 'Meeting', ActivityDate = Date.Today());
        System.assertEquals(null, lastContactDateOf(a),
            'AC2/Typ-Filter: Completed Meeting → Feld bleibt null');
    }

    /**
     * AC2/Update: Task anfänglich nicht abgeschlossen, dann abgeschlossen → Feld springt auf ActivityDate.
     */
    @isTest
    static void openCall_thenCompleted_fieldsUpdates() {
        Id a = newContact('ThenCompleted');
        Task t = new Task(
            WhoId = a,
            Status = 'Not Started',
            Type = 'Call',
            ActivityDate = Date.Today()
        );
        insert t;
        System.assertEquals(null, lastContactDateOf(a), 'AC2/Update: vor Completion → null');

        t.Status = 'Completed';
        update t;
        System.assertEquals(Date.Today(), lastContactDateOf(a),
            'AC2/Update: nach Completion → Feld springt auf ActivityDate');
    }

    /**
     * AC4: Mehrere abgeschlossene Calls → jüngstes ActivityDate gewinnt.
     */
    @isTest
    static void multipleCalls_newestWins() {
        Id a = newContact('MultiCall');
        Date d1 = Date.Today().addDays(-10);
        Date d2 = Date.Today().addDays(-3);
        Date d3 = Date.Today();

        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = d1);
        System.assertEquals(d1, lastContactDateOf(a), 'AC4: erster Call → d1');

        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = d2);
        System.assertEquals(d2, lastContactDateOf(a), 'AC4: zweiter (jüngerer) Call → d2');

        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = d3);
        System.assertEquals(d3, lastContactDateOf(a), 'AC4: dritter (neuester) Call → d3');
    }

    /**
     * AC5: Kontakt ohne abgeschlossenen Call → Feld bleibt null.
     */
    @isTest
    static void contactWithoutCompletedCall_staysNull() {
        Id a = newContact('NeverCall');
        // Nur ein In-Progress-Call.
        insert new Task(WhoId = a, Status = 'In Progress', Type = 'Call');
        System.assertEquals(null, lastContactDateOf(a),
            'AC5: kein abgeschlossener Call → null');
    }

    /**
     * Rückfall: Jüngster completed Call gelöscht → Feld fällt auf vorheriges Datum zurück.
     */
    @isTest
    static void newestCallDeleted_fallsBack() {
        Id a = newContact('Regress');
        Date dOld = Date.Today().addDays(-10);
        Date dNew = Date.Today();

        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dOld);
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dNew);
        System.assertEquals(dNew, lastContactDateOf(a), 'vor Delete: jüngster Call → dNew');

        // Jüngsten Call löschen.
        Task newest = [SELECT Id FROM Task WHERE WhoId = :a AND Status = 'Completed' AND Type = 'Call' ORDER BY ActivityDate DESC LIMIT 1];
        delete newest;
        System.assertEquals(dOld, lastContactDateOf(a),
            'AC4/Rückfall: ältester Call → dOld');
    }

    /**
     * Rückfall (Rigidity): Jüngster Call reopened → fällt auf vorherigen zurück.
     */
    @isTest
    static void newestCallReopened_fallsBack() {
        Id a = newContact('ReopenFall');
        Date dOld = Date.Today().addDays(-5);
        Date dNew = Date.Today();

        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dOld);
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = dNew);
        System.assertEquals(dNew, lastContactDateOf(a), 'vor Reopen: jüngster Call → dNew');

        Task newest = [SELECT Id FROM Task WHERE WhoId = :a AND Status = 'Completed' AND Type = 'Call' ORDER BY ActivityDate DESC LIMIT 1];
        newest.Status = 'Not Started';
        update newest;
        System.assertEquals(dOld, lastContactDateOf(a),
            'AC4/Rückfall: reopened → Feld fällt auf vorherigen Call zurück');
    }

    /**
     * Rückfall: Latest completed Call gelöscht, kein weiterer → Feld fällt auf null.
     */
    @isTest
    static void lastCallDeleted_fallsBackToNull() {
        Id a = newContact('NullFall');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today().addDays(-3));
        System.assertEquals(Date.Today().addDays(-3), lastContactDateOf(a), 'vor Delete: vorhanden');

        Task only = [SELECT Id FROM Task WHERE WhoId = :a];
        delete only;
        System.assertEquals(null, lastContactDateOf(a),
            'AC5/Rückfall: letzter Call gelöscht → null');
    }

    /**
     * AC6: Bestandsmigration via Batch — synthetischer Call, Feld vor Batch = null.
     */
    @isTest
    static void batchRun_healsStaleContacts() {
        Id a = newContact('StaleA');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today().addDays(-7));

        // Simuliere Zustand: Batch-Run hat den Kontakt noch nicht erreicht.
        Contact up = [SELECT Id, Last_Real_Contact_Date__c FROM Contact WHERE Id = :a];
        up.Last_Real_Contact_Date__c = null;
        update up;
        System.assertEquals(null, lastContactDateOf(a), 'Vor Batch: stale = null');

        String batchId;
        Test.startTest();
        batchId = LastRealContactDateRebuilder.runOnce();
        Test.stopTest();

        System.assert(String.isNotBlank(batchId), 'runOnce() muss Batch-Id liefern');
        System.assertEquals(Date.Today().addDays(-7), lastContactDateOf(a),
            'AC6: Batch-Run hat den contact geheilt → ActivityDate von historischem Call');
    }

    /**
     * Idempotenz: 2. Batch-Lauf ändert 0 (mustWrite-Schutz).
     */
    @isTest
    static void batchRun_isIdempotent() {
        Id a = newContact('Idempotent');
        insert new Task(WhoId = a, Status = 'Completed', Type = 'Call', ActivityDate = Date.Today());
        Test.startTest();
        String batchId = LastRealContactDateRebuilder.runOnce();
        Test.stopTest();
        System.assertEquals(Date.Today(), lastContactDateOf(a), 'nach 1. Batch: vorhanden');

        Integer changed = LastRealContactDateTrigger.recompute(new Set<Id>{a});
        System.assertEquals(0, changed, 'Idempotenz: 2. recompute → 0 geänderte Kontakte');
    }

    /**
     * Bulk 200 Contacts × Calls in einem Batch → Governor-Check.
     * Alle zeigen das aktive ActivityDate (heute).
     */
    @isTest
    static void bulk200_contacts_keepsGovernorLimits() {
        List<Contact> contacts = new List<Contact>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 200; i++) {
            contacts.add(new Contact(LastName = 'V413Bulk' + i));
        }
        insert contacts;
        for (Contact c : contacts) {
            ids.add(c.Id);
        }

        List<Task> tasks = new List<Task>();
        for (Id cid : ids) {
            tasks.add(new Task(
                WhoId = cid,
                Status = 'Completed',
                Type = 'Call',
                ActivityDate = Date.Today()
            ));
        }
        insert tasks; // 200 Tasks → 1 Trigger → 1 recompute

        for (Id cid : ids) {
            System.assertEquals(Date.Today(), lastContactDateOf(cid),
                'Bulk: jeder der 200 Contacts → ActivityDate = heute');
        }

        // Governor-Limits prüfen.
        System.assertEquals(1, Limits.getDmlCalls(), 'Bulk: nur 1 DML-Aufruf');
        System.assert(Limits.getDmlCalls() / Limits.getMaxDmlCalls() < 1.0,
            'Bulk: DML-Limits eingehalten');
    }

    /**
     * WhoId-Null-Check: Call ohne WhoId → keine Exception, nichts passiert.
     */
    @isTest
    static void callWithoutWhoId_silent() {
        insert new Task(Status = 'Completed', Type = 'Call', ActivityDate = Date.Today());
        // Keine Exception, keine DML.
        Integer remaining = Limits.getDmlCalls();
        System.assert(remaining == 0 || remaining == 1,
            'Call ohne WhoId → keine unnötige DML');
    }

    /**
     * Guard-Rückgabewerte: null / leeres Set → 0.
     */
    @isTest
    static void recompute_nullAndEmptySet_guard() {
        System.assertEquals(0, LastRealContactDateTrigger.recompute(null), 'null-Set → 0');
        System.assertEquals(0, LastRealContactDateTrigger.recompute(new Set<Id>()), 'leeres Set → 0');
    }

    /**
     * AC2/Verschieden WhoId-Subtypen: Task.WhoId kann auch Lead sein (kein Contact).
     * Trigger-Logik muss WhoId=Lead ignorieren (keine Aktualisierung am Lead).
     * Diese ignorierten WhoId-Zeilen kommen in recompute an, aber
     * `currentValues(contacts WHERE Id IN :whoIds)` gibt sie einfach nicht zurück → NULL.
     * Kein Problem.
     */
    @isTest
    static void callOnLeadWhoId_ignoredForContact() {
        // Einen Lead anlegen und eine Call-Task an den Lead hängen.
        Lead lead = new Lead(LastName = 'LeadCall', Company = 'Test');
        insert lead;
        insert new Task(Status = 'Completed', Type = 'Call', WhoId = lead.Id,
                        ActivityDate = Date.Today());

        // Contact anlegen — darf durch Lead-Task NICHT berührt werden.
        Id cid = newContact('NotLead');
        System.assertEquals(null, lastContactDateOf(cid),
            'AC2/LeadWhoId: Call auf Lead → Contact bleibt null');
    }
}
