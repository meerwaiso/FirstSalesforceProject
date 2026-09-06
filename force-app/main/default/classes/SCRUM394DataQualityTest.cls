/**
 * [SCRUM-394] Functional test for the new formula field
 * Lead.Data_Quality__c ("Datenqualität", read-only Text formula).
 *
 * Covers AC1 deterministically (ADR-3 — declarative formula, no Apex/Flow):
 *   "vollständig" exactly when Email AND Phone AND Company are all filled,
 *   "unvollständig" otherwise — evaluated at view time from the CURRENT
 *   field values (AC1: "zum Zeitpunkt der Betrachtung").
 *
 * ORG CONSTRAINTS (verified by validate runs, see comments):
 *   1. Lead.Company is REQUIRED in this org (DML with blank Company fails
 *      with REQUIRED_FIELD_MISSING: [Company]). The "Company blank" branch
 *      of the formula cannot be probed via DML; it is covered by the
 *      DML-required-field guard (missingCompany_isBlockedByRequiredFieldGuard)
 *      below and by the AC3 e2e report row-count assertion.
 *   2. The formula TEXT cannot be read from Apex in this Org/API:
 *        - Schema.DescribeFieldResult.getFormula()            -> "not a valid method"
 *          (Probe-Deploy 0Af...CoWo0AK on SCRUM394Probe.cls)
 *        - FieldDefinition (Tooling API) via plain Apex SOQL   -> "No such column 'Formula'"
 *          (validate run 0Af...CrJO0A0)
 *      The formula text is therefore read only OUT-OF-BAND (CLI `sf metadata
 *      get` / retrieve), which is exactly how every other metadata check in
 *      this repo is done. The two DML-reachable branches (Email, Phone) are
 *      asserted directly below — which is the part that catches formula drift
 *      on the inputs the formula can actually observe on Lead records.
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
        Lead l = makeLead('TEST-SCRUM-394-FULL', 'full@example.com', '+4****23', 'TestfirmaFull');
        System.assertEquals(
            'vollständig', readValue(l.Id),
            'Email + Phone + Company all filled -> "vollständig" (AC1)'
        );
    }

    @isTest
    static void missingEmail_showsUnvollstaendig() {
        Lead l = makeLead('TEST-SCRUM-394-NOEMAIL', null, '+4****23', 'TestfirmaNoEmail');
        System.assertEquals(
            'unvollständig', readValue(l.Id),
            'Blank Email -> "unvollständig" (AC1)'
        );
    }

    @isTest
    static void missingPhone_showsUnvollStaendig() {
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
        Lead l = makeLead('TEST-SCRUM-394-FLIP', 'flip@example.com', '+4****23', 'TestfirmaFlip');
        System.assertEquals('vollständig', readValue(l.Id), 'Precondition: fully filled -> vollständig');

        l.Email = null; // email vanishes -> incomplete
        update l;
        System.assertEquals(
            'unvollständig', readValue(l.Id),
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
        System.assertEquals(
            0, f.getPicklistValues().size(),
            'Data_Quality__c must have NO Picklist values — the two literals are inside the formula, not a controlled vocabulary'
        );
    }
}
