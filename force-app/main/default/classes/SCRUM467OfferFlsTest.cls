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
            Alias = 'scr467f' + tag,
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
            System.assertNotEquals(ownManager.Id, mine[0].OwnerId,
                'AC12: the record really belongs to another user');
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

    // AC13: a user WITHOUT the set cannot fill or change the two offer dates.
    @isTest
    static void ac13_userWithoutTheSet_refused_storedValueUnchanged() {
        User psHolder = mkUser('holder', new String[] { 'SCRUM467_Offer_Dates',
                                                        'SCRUM467_TestObjectAccess' });
        // object-level CRUD only: a refusal below is about the FIELD, not the object
        User outsider = mkUser('outsider', new String[] { 'SCRUM467_TestObjectAccess' });

        Date sent = Date.today().addDays(-8);
        Date until = Date.today().addDays(22);
        Date attemptedSent = Date.today().addDays(60);
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
        }
        System.assertNotEquals(null, openId, 'setup: the offer was recorded by a set holder');

        Boolean fillRefused = false;
        Boolean changeRefused = false;
        String fillMsg = '';
        System.runAs(outsider) {
            System.assertEquals(
                true,
                Opportunity.SObjectType.getDescribe().isAccessible(),
                'AC13 precondition: the Opportunity itself is reachable, so a false below is about the field'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Sent_On__c.getDescribe().isAccessible(),
                'AC13: without the Permission Set the offer dates are not even readable'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Valid_Until__c.getDescribe().isAccessible(),
                'AC13: the recorded end date is not readable either'
            );
            System.assertEquals(
                false,
                Opportunity.Offer_Status__c.getDescribe().isAccessible(),
                'AC13: the derived glance value is not readable either'
            );

            // attempt 1: fill the two dates on an open record that has an offer already
            try {
                Opportunity fillAttempt = new Opportunity(
                    Id = openId,
                    Offer_Sent_On__c = attemptedSent,
                    Offer_Valid_Until__c = attemptedSent.addDays(30)
                );
                update fillAttempt;
            } catch (DmlException e) {
                fillRefused = true;
                fillMsg = e.getMessage();
            }

            // attempt 2: change ONE of the two dates only
            try {
                Opportunity changeAttempt = new Opportunity(
                    Id = openId,
                    Offer_Valid_Until__c = Date.today().addDays(90)
                );
                update changeAttempt;
            } catch (DmlException e) {
                changeRefused = true;
            }
        }

        System.assert(fillRefused,
            'AC13: a user without SCRUM467_Offer_Dates MUST NOT be able to fill the offer dates. '
            + 'The save went through — the FLS entry is missing or the set is unassigned.');
        System.assert(fillMsg.length() > 0, 'AC13: the refusal names a reason: ' + fillMsg);
        System.assert(changeRefused,
            'AC13: the same user MUST NOT be able to change one of the two dates either');

        // the stored offer must be untouched
        Opportunity after = [SELECT Id, Offer_Sent_On__c, Offer_Valid_Until__c,
                             Offer_Expires_On__c, Offer_Status__c, Offer_Expired__c
                             FROM Opportunity WHERE Id = :openId LIMIT 1];
        System.assertEquals(sent, after.Offer_Sent_On__c,
            'AC13: the stored sent date is unchanged after the refused saves');
        System.assertEquals(until, after.Offer_Valid_Until__c,
            'AC13: the stored end date is unchanged after the refused saves');
        System.assertEquals('offer valid for 22 more days', after.Offer_Status__c,
            'AC13: the glance value still follows the STORED dates, not the refused attempt');
        System.assertEquals(false, after.Offer_Expired__c,
            'AC13: the refused attempt did not expire the offer');
    }
}
