// SCRUM-386 one-off backfill (run via `sf apex run`, ONCE, after Phase-2 deploy).
// Fill Email_Norm__c = lower(trim(Email)) for every non-converted Lead.
// Semantics: null when Email is blank. Idempotent (recomputes the same value).
List<Lead> toUpdate = new List<Lead>();
for (Lead l : [SELECT Id, Email, Email_Norm__c FROM Lead WHERE IsConverted = false]) {
    if (l.Email == null) {
        l.Email_Norm__c = null;
    } else {
        String t = l.Email.trim();
        l.Email_Norm__c = t == '' ? null : t.toLowerCase();
    }
    toUpdate.add(l);
}
if (toUpdate.size() > 0) {
    update toUpdate;
}
System.debug('SCRUM386 backfill: ' + toUpdate.size() + ' non-converted Leads normalized');