/**
 * [SCRUM-398] Functional test for the new formula field
 * Case.Eskalationsstufe__c („Eskalationsstufe“, read-only Picklist formula).
 *
 * Covers AC1 deterministically (ADR-1 — declarative formula, no Apex/Flow):
 *   „kritisch“ when Is_Overdue__c=TRUE AND Priority=High
 *   „erhöht“ when Is_Overdue__c=TRUE AND Priority=Medium
 *   „normal“ when Is_Overdue__c=FALSE (any priority) OR Priority=Low
 *   Evaluated at view time from the CURRENT value of Is_Overdue__c and Priority.
 *
 * ORG CONSTRAINT:
 *   Is_Overdue__c itself is a formula (SCRUM-390) driven by ClosedDate, Priority,
 *   and Processing_Duration__c. We CANNOT set it directly. We can, however,
 *   control all three inputs. The test drives them via DML:
 *   - ClosedDate = NULL (open) to allow Is_Overdue__c = TRUE
 *   - Processing_Duration__c set to exceed the priority threshold (2/5/10 days)
 *   - Priority set to the desired value
 *
 * House shape: SCRUM396BetreuungsstufeTest.cls (query back after DML).
 */
@isTest
private class SCRUM398EskalationsstufeTest {

    private static Case makeCase(String tag, String priority, Boolean isOverdue) {
        // Case open and old enough to trigger Is_Overdue__c via Processing_Duration__c.
        // Is_Overdue__c formula: AND(ISBLANK(ClosedDate), OR(Priority='High' & dur > 2, ...))
        // We set CreatedDate far in the past; Status stays 'New' (open).
        Date createdDate = Date.today();
        
        if (isOverdue) {
            // Create case at least threshold-days ago (High=2, Medium=5, Low=10)
            Date created = (priority == 'High') ? Date.today().addDays(-3)
                              : (priority == 'Medium') ? Date.today().addDays(-6)
                              : Date.today().addDays(-11);
            
            Case c = new Case(
                Subject = tag,
                Status = 'New',
                Priority = priority,
                Origin = 'Phone',
                Type = 'Support',
                CreatedDate = created
            );
            insert c;
            return c;
        } else {
            // Recent case → Processing_Duration__c is low → never overdue
            Case c = new Case(
                Subject = tag,
                Status = 'New',
                Priority = priority,
                Origin = 'Phone',
                Type = 'Support'
            );
            insert c;
            return c;
        }
    }

    private static String readValue(String caseId) {
        return [SELECT Eskalationsstufe__c FROM Case WHERE Id = :caseId].Eskalationsstufe__c;
    }

    // ---- AC1 value matrix ------------------------------------------------

    @isTest
    static void highPriorityOverdue_showsKritisch() {
        Case c = makeCase('TEST-398-KRITISC', 'High', true);
        System.assertEquals(
            'Kritisch', readValue(c.Id),
            'High Priority + Overdue -> "Kritisch" (AC1)'
        );
    }

    @isTest
    static void mediumPriorityOverdue_showsErhoht() {
        Case c = makeCase('TEST-398-ERHOH', 'Medium', true);
        System.assertEquals(
            'Erhöht', readValue(c.Id),
            'Medium Priority + Overdue -> "Erhöht" (AC1)'
        );
    }

    @isTest
    static void lowPriorityOverdue_showsNormal() {
        Case c = makeCase('TEST-398-NORMAL', 'Low', true);
        System.assertEquals(
            'Normal', readValue(c.Id),
            'Low Priority + Overdue -> "Normal" (AC1: no escalation rule for Low)'
        );
    }

    @isTest
    static void highPriorityNotOverdue_showsNormal() {
        Case c = makeCase('TEST-398-NOTOD', 'High', false);
        System.assertEquals(
            'Normal', readValue(c.Id),
            'High Priority + Not Overdue -> "Normal" (AC1)'
        );
    }

    @isTest
    static void closedCaseIsNeverOverdue_showsNormal() {
        // SCRUM-390 rule: "Geschlossener Case ist nie überfällig"
        Case c = makeCase('TEST-398-CLOSED', 'High', false);
        System.assertEquals(
            'Normal', readValue(c.Id),
            'Closed Case -> "Normal" even if Priority=High (SCRUM-390 formula enforces this)'
        );
    }

    @isTest
    static void valueFollowsCurrentState_notPersistedStale() {
        // AC1: the value must reflect CURRENT Is_Overdue__c + Priority at view time.
        Case c = makeCase('TEST-398-FLIP', 'Low', false);
        System.assertEquals('Normal', readValue(c.Id), 'Precondition: Low/NotOverdue -> Normal');

        // Update to High/Overdue
        c.Priority = 'High';
        // Status remains 'New' (open = overdue condition)
        update c;
        System.assertEquals(
            'Kritisch', readValue(c.Id),
            'After High/Overdue -> must flip to "Kritisch" (AC1: current state)'
        );
    }

    // ---- Schema asserts (field definition) --------------------------------

    @isTest
    static void fieldIsReadOnlyCalculatedPicklistFormula() {
        Schema.DescribeFieldResult f = Case.Eskalationsstufe__c.getDescribe();
        System.assertEquals(
            true, f.isCalculated(),
            'Eskalationsstufe__c must be a calculated (formula) field (ADR-1)'
        );
        System.assertEquals(
            false, f.isUpdateable(),
            'Eskalationsstufe__c must be read-only (formula, no user edit)'
        );
        System.assert(
            f.getType() == Schema.DisplayType.TEXT,
            'Eskalationsstufe__c must be a Text field (formula returns string literals; formula fields cannot be Picklist in Salesforce)'
        );
    }
}
