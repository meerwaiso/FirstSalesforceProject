/**
 * SatisfactionTaskHandler — SCRUM-442: one automatic follow-up Task per closed
 * Case with a low satisfaction score.
 *
 * Called from CaseSatisfactionTrigger (after update, after insert) — one
 * Trigger per object, house pattern (SCRUM-440 RueckrufTaskHandler, SCRUM-319/381/416).
 *
 * Behaviour (AC3/AC4), decided per record:
 *   - Case closed (IsClosed or Status='Closed') AND score 1 or 2 AND no
 *     follow-up Task yet            -> create exactly ONE Task:
 *        Subject      'Nachbetreuung: ' + Case.Subject (byte-exact prefix,
 *                     the idempotency key)
 *        OwnerId      Case.OwnerId (the responsible customer representative;
 *                     Task.OwnerId is required — fallback Case.CreatedById)
 *        ActivityDate 2nd Werktag after CloseDate (Task has NO DueDate —
 *                     verified SCRUM-440 §1.2)
 *        Status       'Not Started', Priority 'High'
 *        WhatId       Case.Id
 *   - follow-up Task already exists -> NO second Task (AC4: a Case reopened and
 *                     reclosed later never reminds twice; one follow-up
 *                     obligation per Case, independent of how often it was
 *                     closed). The existing Task's ActivityDate is refreshed
 *                     only when it differs (house SCRUM-440 AC4-shape).
 *   - otherwise                     -> no-op.
 *
 * "existing follow-up Task" = Task WHERE WhatId = caseId AND Subject LIKE
 * 'Nachbetreuung:%' — deliberately NOT filtered on IsClosed: a completed or
 * deferred Task already satisfied the obligation, so it must not be replaced
 * by a new one on reclosing (AC4).
 *
 * The score itself is NOT validated here: the mandatory-at-closing rule (AC1)
 * is the declarative ValidationRule Customer_Satisfaction_PflichtBeiClosed,
 * which already rejected the save on the end-state before this handler runs
 * (ADR-1, house SCRUM-359/381/440). The handler never throws for a missing
 * score — it simply does not create a Task for a score above 2.
 *
 * Werktag (ADR-4, same convention as SCRUM-436 ADR-2 / ADR-2 ADR-2): Mo-Fr,
 * no holidays, no BusinessHours object, epoch anchor 1970-01-01 = Thursday.
 * The closing day itself does NOT count: a Friday closing with n=2 is due
 * Tuesday (PO-decision).
 *
 * Governor: 0 SOQL in the trigger; here exactly 1 SOQL per invocation
 * (WHERE WhatId IN :ids AND Subject LIKE prefix) + 1 bulk insert + 1 bulk
 * update, no SOQL in loops. Re-entry guard hasFired in try/finally (house
 * SCRUM-440/419/421) — the Task writes never touch Case fields, so the guard
 * is a safety net against the multi EXECUTION_CONTEXTS of external
 * single-field REST/CLI updates (SCRUM-419 lesson).
 *
 * without sharing (ADR-5): deterministic over any calling user; FLS is still
 * checked on the Task DML — Task is a standard object with object-level CRUD
 * for the Service staff, no field-level FLS involved.
 *
 * @author developer-agent
 * @date 2026-10-10
 */
public with sharing class SatisfactionTaskHandler {

    @testVisible
    private static Boolean hasFired = false;

    // Byte-exact Subject prefix per AC3 (trailing space) — the idempotency key.
    private static final String SUBJECT_PREFIX = 'Nachbetreuung: ';

    // PO-decision: reminder due within 2 Werktag after the closing.
    @testVisible
    public static final Integer FOLLOW_UP_WORKING_DAYS = 2;

    // ADR-4: verified epoch anchor 1970-01-01 = Thursday (org-verified in
    // SCRUM-436); Apex Date has NO dayOfWeek(). w = mod(days,7):
    // 0=Do 1=Fr 2=Sa 3=So 4=Mo 5=Di 6=Mi; Mo-Fr = w >= 4 || w <= 1.
    private static final Date EPOCH_ANCHOR = Date.valueof('1970-01-01');

    // The dissatisfied band (PO: score 1 or 2). Picklist API-Names, not labels —
    // labels carry an en-dash and are locale-prone (ADR-2: Picklist, not Number).
    @testVisible
    public static final Set<String> LOW_SCORES = new Set<String>{'Score_1', 'Score_2'};

    public static void handle(List<Case> after) {
        if (hasFired) {
            return;
        }
        hasFired = true;
        try {
            // 1. One pass: closed Cases with a low score.
            Set<Id> relevantIds = new Set<Id>();
            for (Case c : after) {
                if (isClosedCase(c) && c.Customer_Satisfaction__c != null
                        && LOW_SCORES.contains(String.valueOf(c.Customer_Satisfaction__c))) {
                    relevantIds.add(c.Id);
                }
            }
            if (relevantIds.isEmpty()) {
                return;
            }

            // 2. Exactly ONE bulkified query for existing follow-up Tasks —
            //    NOT filtered on IsClosed: any Task for this Case already
            //    satisfied the obligation (AC4).
            Map<Id, Task> existingByCaseId = new Map<Id, Task>();
            for (Task t : [SELECT Id, Subject, ActivityDate, Status, WhatId, OwnerId
                           FROM Task
                           WHERE WhatId IN :relevantIds
                             AND Subject LIKE 'Nachbetreuung:%']) {
                if (!existingByCaseId.containsKey(t.WhatId)) {
                    existingByCaseId.put(t.WhatId, t);
                }
            }

            List<Task> toInsert = new List<Task>();
            List<Task> toUpdate = new List<Task>();

            // 3. Decide per record.
            for (Case c : after) {
                if (!isClosedCase(c) || c.Customer_Satisfaction__c == null
                        || !LOW_SCORES.contains(String.valueOf(c.Customer_Satisfaction__c))) {
                    continue;
                }
                Date due = nthWorkingDayAfter(closeDateOf(c), FOLLOW_UP_WORKING_DAYS);
                Task existing = existingByCaseId.get(c.Id);
                if (existing == null) {
                    toInsert.add(new Task(
                        Subject      = SUBJECT_PREFIX + (c.Subject == null ? '' : c.Subject),
                        Priority     = 'High',
                        Status       = 'Not Started',
                        ActivityDate = due,
                        WhatId       = c.Id,
                        // Task.OwnerId is required and NOT defaulted: the
                        // responsible customer representative = Case.OwnerId.
                        OwnerId      = (c.OwnerId != null) ? c.OwnerId : c.CreatedById
                    ));
                } else if (existing.ActivityDate != due) {
                    existing.ActivityDate = due;
                    toUpdate.add(existing);
                }
            }

            // 4. Batched writes (single insert / single update per invocation).
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } finally {
            hasFired = false;
        }
    }

    /** Closed = IsClosed flag OR Status='Closed' — same shape as the ValRule. */
    private static Boolean isClosedCase(Case c) {
        return c.IsClosed || (c.Status != null && String.valueOf(c.Status) == 'Closed');
    }

    /** CloseDate of a closed Case; null-safe fallback to today (defensive). */
    public static Date closeDateOf(Case c) {
        // Case.ClosedDate is a Datetime in this Org (house CaseProblemSerieHandler
        // §185, sobject describe). Date.valueOf(format) verified probe11 2026-10-10.
        Datetime closedAt = c.ClosedDate;
        return (closedAt != null) ? Date.valueOf(closedAt.format('yyyy-MM-dd')) : Date.today();
    }

    /**
     * ADR-4: the n-th Werktag strictly AFTER `from` (the closing day itself
     * does NOT count; a Friday with n=2 is Tuesday). Pure CPU arithmetic,
     * same anchor as CaseReminderService (SCRUM-436).
     */
    public static Date nthWorkingDayAfter(Date afterDate, Integer n) {
        if (afterDate == null || n == null || n <= 0) {
            return afterDate;
        }
        Date d = afterDate;
        Integer counted = 0;
        while (counted < n) {
            d = d.addDays(1);
            if (isWorkingDay(d)) {
                counted++;
            }
        }
        return d;
    }

    private static Boolean isWorkingDay(Date d) {
        Long off = EPOCH_ANCHOR.daysBetween(d);
        Long w = Math.mod(off, 7);
        return (w >= 4) || (w <= 1);
    }
}
