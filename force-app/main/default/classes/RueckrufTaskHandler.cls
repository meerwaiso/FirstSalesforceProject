/**
 * RueckrufTaskHandler — SCRUM-440: automatische Callback-Task per Opportunity.
 *
 * Aufgerufen aus dem gemeinsamen Opportunity-Trigger (OpportunityOverdueReset,
 * after update) — ein Trigger pro Objekt, etabliertes Muster (SCRUM-319/381/416).
 *
 * Kontext: after update. Die ValRule-Pair (Rueckruf_am_PflichtBeiGesetzer,
 * Rueckruf_am_KeineNichte) already evaluated on the ENDSTAND, so every record
 * reaching here with Rueckruf_desired__c = true carries a non-null, future
 * Rueckruf_am__c. The save-rejection (AC2) is therefore declarative, never an
 * Apex throw (ADR, house SCRUM-359/381).
 *
 * Behaviour (AC3/AC4/AC5), decided by end-state vs old-state per record:
 *   - Rueckruf_desired__c true, no open callback Task yet  -> create one Task
 *     (Subject 'Rückruf: ' + Name, Priority High, Status Not Started,
 *      ActivityDate = date(Rueckruf_am__c), WhatId = opp.Id, OwnerId = opp.OwnerId).
 *   - Rueckruf_desired__c true, open callback Task exists  -> update its
 *     ActivityDate (AC4: no second Task).
 *   - Rueckruf_desired__c false, was true before           -> set the open
 *     callback Task to Status 'Deferred' (AC5: not deleted; 'Abgebrochen' does
 *     not exist on the Task picklist — OP-1, Architect default).
 *   - otherwise                                            -> no-op.
 *
 * "open callback Task" = Task WHERE WhatId = opp.Id AND Subject LIKE 'Rückruf:%'
 * AND IsClosed = false. Task links to Opportunity via WhatId (SCRUM-294 house).
 *
 * Bulk / Governor-Limits: ONE SOQL per invocation (WHERE WhatId IN :ids), then
 * batched single insert / update. No SOQL in loops. Task writes never touch
 * Opportunity fields -> no recursion into this trigger; the static hasFired flag
 * is a safety net, reset in finally so independent saves in one transaction each
 * run once.
 */
public with sharing class RueckrufTaskHandler {

    @testVisible
    private static Boolean hasFired = false;

    // Byte-exact Subject prefix per AC3 (trailing space).
    private static final String SUBJECT_PREFIX = 'Rückruf: ';

    public static void handleAfterUpdate(List<Opportunity> after, Map<Id, Opportunity> beforeMap) {
        if (hasFired) {
            return;
        }
        hasFired = true;
        try {
            // 1. One pass: collect Opportunity ids that need a Task side-effect.
            Set<Id> relevantIds = new Set<Id>();
            for (Opportunity opp : after) {
                Opportunity old = beforeMap.get(opp.Id);
                Boolean nowDesired = opp.Rueckruf_desired__c;
                Boolean wasDesired = (old != null) ? old.Rueckruf_desired__c : false;
                if (nowDesired || wasDesired) {
                    relevantIds.add(opp.Id);
                }
            }
            if (relevantIds.isEmpty()) {
                return;
            }

            // 2. Exactly ONE bulkified query for the open callback Tasks.
            Map<Id, Task> openByWhatId = new Map<Id, Task>();
            for (Task t : [SELECT Id, Subject, ActivityDate, Status, WhatId
                           FROM Task
                           WHERE WhatId IN :relevantIds
                             AND Subject LIKE 'Rückruf:%'
                             AND IsClosed = false]) {
                // One open callback Task per Opportunity expected; keep the first.
                if (!openByWhatId.containsKey(t.WhatId)) {
                    openByWhatId.put(t.WhatId, t);
                }
            }

            List<Task> toInsert = new List<Task>();
            List<Task> toUpdate = new List<Task>();

            // 3. Decide per record.
            for (Opportunity opp : after) {
                Opportunity old = beforeMap.get(opp.Id);
                Boolean nowDesired = opp.Rueckruf_desired__c;
                Boolean wasDesired = (old != null) ? old.Rueckruf_desired__c : false;
                Task existing = openByWhatId.get(opp.Id);

                if (nowDesired) {
                    // ValRule guarantees a non-null, future Rueckruf_am__c here.
                    Date due = opp.Rueckruf_am__c.date();
                    if (existing == null) {
                        toInsert.add(new Task(
                            Subject      = SUBJECT_PREFIX + opp.Name,
                            Priority     = 'High',
                            Status       = 'Not Started',
                            ActivityDate = due,
                            WhatId       = opp.Id
                            // OwnerId: Opportunity hat keinen Owner — Task.OwnerId
                            // defaults to the runner (the Opportunity's creator).
                        ));
                    } else if (existing.ActivityDate != due) {
                        existing.ActivityDate = due;
                        toUpdate.add(existing);
                    }
                } else if (wasDesired) {
                    // Unchecked: cancel the open callback Task (Deferred, not deleted).
                    if (existing != null && existing.Status != 'Deferred') {
                        existing.Status = 'Deferred';
                        toUpdate.add(existing);
                    }
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
}
