/**
 * [SCRUM-416] Rollup offener Chancen auf den Account.
 *
 * Auf Account werden zwei systemmaintained, read-only Felder gepflegt:
 *   Open_Opportunity_Count__c  — Anzahl offener Chancen (IsClosed = false)
 *   Open_Opportunity_Value__c  — Summe der Amounts offener Chancen (fehlend = 0)
 *
 * Mechanik (ADR-1/ADR-2, docs/SCRUM-416-design.md):
 *   Vollrecompute der betroffenen Accounts pro Trigger-Batch per GROUP-BY-Query
 *   (Filter: IsClosed = false, Single Source of Truth — Stage-Namen bleiben aus
 *   der Logik heraus, ADR-3). Write nur bei tatsächlicher Änderung. Idempotent,
 *   driftfrei; heilt Reassign (Account-Wechsel, AK4) und manuelle Reparatur selbst.
 *
 * Relevanz-Filter (Update): nur AccountId-, IsClosed- oder Amount-Änderung
 * rechnet neu; reine Stage-Wechsel innerhalb offener Stages ändern weder
 * Anzahl noch Summe. Bei Umhängen werden ALTER und NEUER Account recompute.
 *
 * Governor-Limits: 1 GROUP-BY-SOQL + 1 SELECT Account + 1 update je
 * Trigger-Batch, unabhängig von der Batch-Grösse (kein SOQL in Loop).
 * Account-Update löst keinen Opportunity-Trigger aus → keine Rekursion.
 *
 * Systemwrites laufen im System-Kontext und umgehen FLS (Vorgang SCRUM-365).
 */
public without sharing class OpenOpportunityRollupHandler {

    // insert: alle Opportunities mit AccountId
    public static void onOpportunityInsert(List<Opportunity> newOpps) {
        Set<Id> ids = accountIds(newOpps);
        if (!ids.isEmpty()) {
            recompute(ids);
        }
    }

    // delete: AccountIds aus old
    public static void onOpportunityDelete(List<Opportunity> oldOpps) {
        Set<Id> ids = accountIds(oldOpps);
        if (!ids.isEmpty()) {
            recompute(ids);
        }
    }

    // update: nur wenn sich AccountId (Umhängen), IsClosed (gewonnen/verloren/geöffnet)
    // oder Amount (Umwertung) geändert hat — dann alter UND neuer Account.
    public static void onOpportunityUpdate(List<Opportunity> newOpps,
                                           Map<Id, Opportunity> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity o : newOpps) {
            Opportunity old = oldMap.get(o.Id);
            if (o.AccountId != old.AccountId
                    || o.IsClosed != old.IsClosed
                    || o.Amount != old.Amount) {
                if (o.AccountId != null) {
                    ids.add(o.AccountId);
                }
                if (old.AccountId != null) {
                    ids.add(old.AccountId);
                }
            }
        }
        if (!ids.isEmpty()) {
            recompute(ids);
        }
    }

    public static Set<Id> accountIds(List<Opportunity> opps) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity o : opps) {
            if (o.AccountId != null) {
                ids.add(o.AccountId);
            }
        }
        return ids;
    }

    // Vollrecompute pro betroffener Account: idempotent, heilt Drift und
    // Reassign selbst. Write nur bei tatsächlicher Änderung.
    public static void recompute(Set<Id> accountIds) {
        Map<Id, Account> current = new Map<Id, Account>(
            [SELECT Id, Open_Opportunity_Count__c, Open_Opportunity_Value__c
             FROM Account WHERE Id IN :accountIds]);

        Map<Id, Decimal> sumById = new Map<Id, Decimal>();
        Map<Id, Integer> cntById = new Map<Id, Integer>();
        // Muster wie CaseOpenCountTrigger (SCRUM-396): AggregateResult-Loop.
        for (AggregateResult r : [SELECT AccountId, COUNT(Id) cnt, SUM(Amount) amt
                                   FROM Opportunity
                                   WHERE AccountId IN :accountIds AND IsClosed = false
                                   GROUP BY AccountId]) {
            Id accId = (Id) r.get('AccountId');
            cntById.put(accId, (Integer) r.get('cnt'));
            sumById.put(accId, (Decimal) r.get('amt'));
        }

        List<Account> toUpdate = new List<Account>();
        for (Id accId : accountIds) {
            Account acc = current.get(accId);
            if (acc == null) {
                continue;
            }
            Integer newCount = cntById.containsKey(accId) ? cntById.get(accId) : 0;
            Decimal newValue = sumById.containsKey(accId) ? sumById.get(accId) : 0;
            if (acc.Open_Opportunity_Count__c != newCount
                    || acc.Open_Opportunity_Value__c != newValue) {
                acc.Open_Opportunity_Count__c = newCount;
                acc.Open_Opportunity_Value__c = newValue;
                toUpdate.add(acc);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
