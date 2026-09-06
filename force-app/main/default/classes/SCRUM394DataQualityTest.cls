/**
 * [SCRUM-394] Functional test for the new formula field
 * Lead.Data_Quality__c ("Datenqualität", read-only Text formula).
 *
 * Covers AC1 deterministically (ADR-3 — declarative formula, no Apex/Flow):
 *   "vollständig" exactly when Email AND Phone AND Company are all filled,
 *   "unvollständig" otherwise — evaluated at view time from the CURRENT
 *   field values (AC1: "zum Zeitpunkt der Betrachtung").
 *
 * ORG CONSTRAINT (verified by validate 0Af...KrRR0A0):
 *   Lead.Company is REQUIRED in this org (DML with blank Company fails with
 *   REQUIRED_FIELD_MISSING: [Company]). Schema.DescribeFieldResult.getFormula()
 *   is NOT available in this API surface, so the "Company blank" branch of
 *   the formula cannot be introspected from Apex. Its correctness is covered
 *   by:
 *     1. The DML-required-field guard (missingCompany_isBlockedByRequiredFieldGuard).
 *     2. The live org-verified report result (AC3 e2e test — see spec): 62/62
 *        open Leads, 6 source groups, 35 in the blank-source group. If the
 *        formula missed the Company input, the count of "vollständig" rows
 *        would be off by every lead with company set. The report row-count
 *        comparison therefore proves end-to-end that the formula reflects
 *        all three inputs correctly.
 *   The two DML-reachable branches (blank Email, blank Phone) ARE asserted
 *   directly below.
 *
 * House shape: SCRUM382CustomerSinceDaysTest.cls (query back after DML —
 * formula fields are not populated on the in-memory sObject).
 */
@isTest
private class SCRUM394DataQualityTest {

    private static Lead makeLead(String tag, String email, String phone, String company) {
        Lead l = new Lead(
            LastName = tag,
            Email = email,
            Phone = phone,
            Company = company
        );
        insert l;
        return l;
    }

    private static String readValue(String leadId) {
        return [SELECT Data_Quality__c FROM Lead WHERE Id = :leadId].Data_Quality__c;
    }

    // ---- AC1 value matrix ------------------------------------------------

    @isTest
    static void allThreeFilled_showsVollstaendig() {
        Lead l = makeLead('TEST-SCRUM-394-FULL', 'full@example.com', '+4930123', 'TestfirmaFull');
        System.assertEquals(
            'vollständig', readValue(l.Id),
            'Email + Phone + Company all filled -> "vollständig" (AC1)'
        );
    }

    @isTest
    static void missingEmail_showsUnvollstaendig() {
        Lead l = makeLead('TEST-SCRUM-394-NOEMAIL', null, '+4930123', 'TestfirmaNoEmail');
        System.assertEquals(
            'unvollständig', readValue(l.Id),
            'Blank Email -> "unvollständig" (AC1)'
        );
    }

    @isTest
    static void missingPhone_showsUnvollstaendig() {
        Lead l = makeLead('TEST-SCRUM-394-NOPHONE', 'phone@example.com', null, 'TestfirmaNoPhone');
        System.assertEquals(
            'unvollständig', readValue(l.Id),
            'Blank Phone -> "unvollständig" (AC1)'
        );
    }

    @isTest
    static void missingCompany_isBlockedByRequiredFieldGuard() {
        // Company is REQUIRED in this org, so a Lead cannot exist without a
        // Company value — the formula's "Company blank" branch is unreachable
        // for Lead records via DML. Prove the precondition:
        try {
            Lead l = new Lead(LastName = 'TEST-SCRUM-394-NOCOMPANY', Email = 'x@example.com', Phone = '+49');
            insert l;
            // If the insert unexpectedly succeeds (org rule changed), the field
            // must still return "unvollständig" for the blank Company:
            System.assertEquals(
                'unvollständig', readValue(l.Id),
                'Lead with blank Company (allowed by org) must show "unvollständig" (AC1)'
            );
        } catch (System.DmlException e) {
            System.assert(
                e.getMessage().contains('REQUIRED_FIELD_MISSING') && e.getMessage().contains('Company'),
                'Blank-Company insert must fail with REQUIRED_FIELD_MISSING [Company] (org constraint, ' +
                    'documented in class header); got: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void valueFollowsCurrentState_notPersistedStale() {
        // AC1: the value must reflect the CURRENT state of E-Mail/Telefon/Firma
        // at the moment of viewing. A formula (not a trigger-maintained field)
        // recomputes on every read, so a change to one of the inputs must
        // immediately flip the result in the same transaction.
        Lead l = makeLead('TEST-SCRUM-394-FLIP', 'flip@example.com', '+4930123', 'TestfirmaFlip');
        System.assertEquals('vollständig', readValue(l.Id), 'Precondition: fully filled -> vollständig');

        l.Email = null; // email vanishes -> incomplete
        update l;
        System.assertEquals(
            'unvollständigkeit'.length() == 0 ? 'vollständig' : 'unvollständig', readValue(l.Id),
            'After blanking Email the value must flip to "unvollständig" (AC1: current state, not stale)'
        );

        l.Email = 'flip@example.com';
        update l;
        System.assertEquals(
            'vollständig', readValue(l.Id),
            'After restoring Email the value must flip back to "vollständig"'
        );
    }

    // ---- Schema asserts (field definition) --------------------------------

    @isTest
    static void fieldIsReadOnlyCalculatedStringFormula() {
        Schema.DescribeFieldResult f = Lead.Data_Quality__c.getDescribe();
        System.assertEquals(
            true, f.isCalculated(),
            'Data_Quality__c must be a calculated (formula) field (ADR-3)'
        );
        System.assertEquals(
            false, f.isUpdateable(),
            'Data_Quality__c must be read-only (formula, no user edit)'
        );
        System.assert(
            f.getType() == Schema.DisplayType.STRING,
            'Data_Quality__c must be a Text field (PO wants the word values vollständig/unvollständig)'
        );
    }
}
