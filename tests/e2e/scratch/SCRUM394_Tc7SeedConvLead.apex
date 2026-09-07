// SCRUM-394 TC7 seed-helper (run by the E2E spec via `sf apex run -o Test-Org -f`).
//
// A converted Lead CANNOT be seeded by DML/API create in this org (verified 2026-09-07):
//   - Lead.IsConverted: createable=true, updateable=false (sobjects/Lead describe)
//   - create w/ IsConverted=true  -> FIELD_INTEGRITY_EXCEPTION: "Converted Account empty"
//     (direct setting of ConvertedAccountId/ConvertedOpportunityId -> INVALID_FIELD_FOR_INSERT_UPDATE; FLS read-only, probes in SCRUM-394-design.md TC7)
//   - SCRUM-386LeadDuplicateTest proves the same: "IsConverted is NOT writeable via DML in this org"
// The only supported path is Database.convertLead, which the platform drives — exactly what this
// block does, idempotently (create-if-missing, convert only while IsConverted=false). Read-back
// (IsConverted + ConvertedAccountId) is verified AFTER the conversion, per Verify-at-the-Target.
//
// House shape: same Database.LeadConvert / setConvertedStatus('Closed - Converted') / setDoNotCreateOpportunity(true)
// pattern as SCRUM386LeadDuplicateTest.cls:63-66.

Id fixtureId = null;
for (Lead l : [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE LastName = 'TEST-SCRUM-394-CONV']) {
    fixtureId = l.Id;
    if (!l.IsConverted) {
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        lc.setConvertedStatus('Closed - Converted');      // only IsConverted=true picklist value (SOQL read-back, design-doc TC7)
        lc.setDoNotCreateOpportunity(true);
        Database.LeadConvertResult res = Database.convertLead(lc);
        System.assert(res.isSuccess(), 'SCRUM-394 TC7: convertLead must succeed, got: ' + res.isSuccess());
        l = [SELECT Id, IsConverted, ConvertedAccountId FROM Lead WHERE Id = :l.Id];
        System.assert(l.IsConverted,  'SCRUM-394 TC7: lead is not IsConverted after convertLead');
        System.assert(l.ConvertedAccountId != null, 'SCRUM-394 TC7: ConvertedAccountId must be set after convertLead');
    }
}
if (fixtureId == null) {
    throw new IllegalStateException('SCRUM-394 TC7: fixture lead TEST-SCRUM-394-CONV not seeded by spec (sfCount/create path failed?)');
}
System.debug('SCRUM394-TC7 CONV fixture ready: ' + fixtureId);
