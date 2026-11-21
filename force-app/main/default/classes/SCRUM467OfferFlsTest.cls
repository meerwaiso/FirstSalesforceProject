/**
 * [SCRUM-467] Developer artefact — the permission boundary, AC12 positive / AC13 negative.
 *
 * The PO decision (2026-11-21, ticket SCRUM-467): the boundary is WHO HOLDS the ONE
 * new Permission Set, not who owns the record. There is no non-owner guard and no
 * second marker set, so AC12 is a capability and AC13 is the mandatory negative-access
 * test against a user WITHOUT the set (house pattern: SCRUM-451TesterFlsNegativeTest,
 * SCRUM-464DrittpartyFlsTest).
 *
 * Measured before this class was written (Test-Org, 2026-11-21, scripts/fls-check.sh):
 *   Opportunity.Offer_Sent_On__c / Offer_Valid_Until__c read+edit are granted by
 *   SCRUM467_Offer_Dates and by nothing else in the org, so the negative holds because
 *   no profile grants the new fields — not because anything revoked them
 *   (a Permission Set can only grant, never revoke).
 *
 * Mixed-DML house rule (SCRUM-442): the User and its PermissionSetAssignment are
 * System-context setup DML — a User cannot grant himself a Permission Set — and every
 * business DML/SOQL runs inside System.runAs.
 *
 * @author developer-agent
 * @date 2026-11-21
 */
@isTest
private class SCRUM467OfferFlsTest {

    private static User mkUser(String tag, String[] psNames) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr467Fls-' + tag,
            Alias = ('f467' + tag).left(8),
            Email = 'scr467fls-' + tag + '@example.invalid',
            Username = 'scr467fls-' + tag + '-' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        for (String psName : psNames) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    // AC12: a holder of the set records and renews an offer on a FOREIGN open record.
    @isTest
    static void ac12_psHolder_recordsOnForeignOpenOpportunity() {
        User ownManager = mkUser('owner', new String[] { 'SCRUM467_Offer_Dates',
                                                        'SCRUM467_TestObjectAccess' });
        User otherManager = mkUser('lead', new String[] { 'SCRUM467_Offer_Dates',
                                                          'SCRUM467_TestObjectAccess' });

        Date sent = Date.today().addDays(-8);
        Date until = Date.today().addDays(22);
        Id foreignId = null;

        // the record belongs to one account manager ...
        System.runAs(ownManager) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC12 foreign record',
                StageName = 'Prospecting',
                Amount = 3000.00,
                CloseDate = Date.today().addDays(25)
            );
            insert o;
            foreignId = o.Id;
        }
        System.assertNotEquals(null, foreignId, 'setup: the owning manager stored the record');

        // ... and a holder of the Permission Set renews the offer on it
        System.runAs(otherManager) {
            Opportunity[] mine = [SELECT Id, OwnerId, Offer_Sent_On__c,
                                  Offer_Valid_Until__c, Offer_Status__c
                                  FROM Opportunity WHERE Id = :foreignId];
            System.assertEquals(1, mine.size(),
                'AC12 precondition: the foreign record is reachable (OWD Public Read/Write, no sharing change)');
            System.assertEquals(ownManager.Id, mine[0].OwnerId,
                'AC12 precondition: the record belongs to the OWNING account manager');
            System.assertNotEquals(otherManager.Id, mine[0].OwnerId,
                'AC12: the acting user is not the owner — the renewal crosses the owner boundary');
            System.assertEquals(null, mine[0].Offer_Sent_On__c,
                'AC12 precondition: no offer recorded yet');

            Opportunity renewal = new Opportunity(
                Id = foreignId,
                Offer_Sent_On__c = sent,
                Offer_Valid_Until__c = until
            );
            update renewal;

            Opportunity after = [SELECT Id, OwnerId, Offer_Sent_On__c, Offer_Valid_Until__c,
                                 Offer_Expires_On__c, Offer_Status__c, Offer_Expired__c
                                 FROM Opportunity WHERE Id = :foreignId LIMIT 1];
            System.assertEquals(sent, after.Offer_Sent_On__c,
                'AC12: the set holder stored the sent date on the foreign record');
            System.assertEquals(until, after.Offer_Valid_Until__c,
                'AC12: the set holder stored the end date on the foreign record');
            System.assertEquals(until, after.Offer_Expires_On__c,
                'AC12: the expiry follows the recorded end date');
            System.assertEquals('offer valid for 22 more days', after.Offer_Status__c,
                'AC12: the derived glance value follows the new offer');
            System.assertEquals(false, after.Offer_Expired__c,
                'AC12: the renewed offer is valid');
        }
    }

    // AC13: the negative boundary for a user WITHOUT SCRUM467_Offer_Dates.
    // House pattern (SCRUM-464/465, measured 2026-11-20/21): the negative is asserted with
    // getDescribe().isAccessible()/isUpdateable(), NOT with a thrown exception — Apex runs
    // "on the inside", so an Apex update by such a user is not refused (measured 2026-11-21:
    // a blind Apex write went through and moved the stored dates, op 0AfWU00000dIkcD0AS),
    // while the FLS boundary IS enforced for the UI and the API: scripts/fls-check.sh shows
    // zero FieldPermissions rows for the two dates, which is what the record page and the
    // Tester's browser/API checks exercise.
    @isTest
    static void ac13_userWithoutTheSet_offerFieldsNotReadableNotUpdatable() {
        User psHolder = mkUser('holder', new String[] { 'SCRUM467_Offer_Dates',
                                                        'SCRUM467_TestObjectAccess' });
        User outsider = mkUser('outsider', new String[] { 'SCRUM467_TestObjectAccess' });

        Date sent = Date.today().addDays(-8);
        Date until = Date.today().addDays(22);
        Id openId = null;

        System.runAs(psHolder) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC13 recorded offer',
                StageName = 'Prospecting',
                Amount = 1200.00,
                CloseDate = Date.today().addDays(25),
                Offer_Sent_On__c = sent,
                Offer_Valid_Until__c = until
            );
            insert o;
            openId = o.Id;

            // the set holder sees all seven (the capability half of AC12/AC13)
            System.assertEquals(true, Opportunity.Offer_Sent_On__c.getDescribe().isAccessible(),
                'AC12: the holder reads the recorded sent date');
            System.assertEquals(true, Opportunity.Offer_Valid_Until__c.getDescribe().isAccessible(),
                'AC12: the holder reads the recorded end date');
            System.assertEquals(true, Opportunity.Offer_Sent_On__c.getDescribe().isUpdateable(),
                'AC12: the holder can record the sent date');
            System.assertEquals(true, Opportunity.Offer_Valid_Until__c.getDescribe().isUpdateable(),
                'AC12: the holder can record the end date');
        }
        System.assertNotEquals(null, openId, 'setup: the offer was recorded by a set holder');

        System.runAs(outsider) {
            // precondition: the record page is reachable, so a false below is about the fields
            System.assertEquals(
                true,
                Opportunity.SObjectType.getDescribe().isAccessible(),
                'AC13 precondition: Opportunity is reachable — a false below is about the FIELDS'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Sent_On__c.getDescribe().isAccessible(),
                'AC13: without the Permission Set the recorded sent date is not visible'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Valid_Until__c.getDescribe().isAccessible(),
                'AC13: without the Permission Set the recorded end date is not visible'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Sent_On__c.getDescribe().isUpdateable(),
                'AC13: the user without the set cannot record the sent date on the record page'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Valid_Until__c.getDescribe().isUpdateable(),
                'AC13: and not the end date'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Expires_On__c.getDescribe().isAccessible(),
                'AC13: none of the five derived fields is visible either'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Days_Left__c.getDescribe().isAccessible(),
                'AC13: none of the five derived fields is visible either'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Status__c.getDescribe().isAccessible(),
                'AC13: the glance value is invisible without the Permission Set'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Expired__c.getDescribe().isAccessible(),
                'AC13: the expiry marker is invisible without the Permission Set'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Expiring_14D__c.getDescribe().isAccessible(),
                'AC13: the 14-day marker is invisible without the Permission Set'
            );
        }
    }
}
