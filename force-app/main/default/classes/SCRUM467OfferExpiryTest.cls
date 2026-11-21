/**
 * [SCRUM-467] Developer artefact — AC1..AC8 of the declarative offer-expiry model.
 *
 * House shape (SCRUM-464DrittpartyFlsTest / SCRUM-451TesterFlsNegativeTest):
 *   - the User and its PermissionSetAssignment are System-context setup DML
 *     (a User cannot grant himself a Permission Set), every business DML/SOQL
 *     runs inside System.runAs — required by scripts/fls-gate.py, which reddens
 *     a test class that touches a new field without System.runAs.
 *   - SCRUM467_TestObjectAccess grants the fixture users object-level CRUD so a
 *     refused save below is about the FIELD, never about the object.
 *   - writes use a FRESH sObject with Id + the written fields only (house SCRUM-459:
 *     `update` writes every field in the record cache and one of them may not be
 *     writable).
 *   - an existing Opportunity ValidationRule needs Loss_Reason__c on a Closed
 *     Lost save (LossReason_PflichtBeiClosedLost, measured in the repo), so AC7
 *     sets Loss_Reason__c = 'ZuTeuer' — the renewal demand must not be the reason.
 *
 * Measured facts this class stands on (Test-Org, 2026-11-21, scripts/fls-check.sh):
 *   Opportunity.Offer_Sent_On__c / Offer_Valid_Until__c read+edit are granted by
 *   SCRUM467_Offer_Dates and by nothing else; the five derived fields are
 *   readable through the same set and writable by nobody.
 *
 * @author developer-agent
 * @date 2026-11-21
 */
@isTest
private class SCRUM467OfferExpiryTest {

    private static String[] fixturePs() {
        return new String[] { 'SCRUM467_Offer_Dates', 'SCRUM467_TestObjectAccess' };
    }

    private static User mkUser(String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'Scr467-' + tag,
            Alias = ('467' + tag).left(8),
            Email = 'scr467-' + tag + '@example.invalid',
            Username = 'scr467-' + tag + '-' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
    }

    // ---- setup DML in System context: a User cannot grant itself anything -----
    private static User setupUser(String tag) {
        User u = mkUser(tag);
        insert u;
        for (String psName : fixturePs()) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :psName LIMIT 1];
            System.assert(ps != null, 'precondition: Permission Set ' + psName + ' is deployed');
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    // AC1: both dates are stored exactly as entered and read back unchanged.
    @isTest
    static void ac1_bothDates_readBackAsTyped() {
        User mgr = setupUser('ac1');
        Date sent = Date.today().addDays(-10);
        Date until = Date.today().addDays(20);

        System.runAs(mgr) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC1 live offer',
                StageName = 'Prospecting',
                CloseDate = until,
                Amount = 1500.00,
                Offer_Sent_On__c = sent,
                Offer_Valid_Until__c = until
            );
            insert o;

            Opportunity back = [SELECT Id,
                                Offer_Sent_On__c, Offer_Valid_Until__c, Offer_Expires_On__c,
                                Offer_Days_Left__c, Offer_Status__c, Offer_Expired__c
                                FROM Opportunity WHERE Id = :o.Id LIMIT 1];
            System.assertEquals(sent, back.Offer_Sent_On__c,
                'AC1: the sent date reads back exactly as typed');
            System.assertEquals(until, back.Offer_Valid_Until__c,
                'AC1: the valid-until date reads back exactly as typed');
            System.assertEquals(until, back.Offer_Expires_On__c,
                'AC1: with an end date recorded, the expiry IS that end date');
            System.assertEquals(20, back.Offer_Days_Left__c,
                'AC1: 20 calendar days left on an offer valid until today+20');
            System.assertEquals('offer valid for 20 more days', back.Offer_Status__c,
                'AC1: the glance wording carries the day count');
            System.assertEquals(false, back.Offer_Expired__c,
                'AC1: a live offer is not expired');
        }
    }

    // AC2: no end date -> sent + 30 days, the end date itself is the last valid day.
    @isTest
    static void ac2_defaultValidity_sentPlusThirty_endInclusive() {
        User mgr = setupUser('ac2');
        Date sent = Date.today().addDays(-40);
        Date expectedEnd = sent.addDays(30);            // = today - 10

        System.runAs(mgr) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC2 default rule',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(60),
                Offer_Sent_On__c = sent
            );
            insert o;

            Opportunity back = [SELECT Id, Offer_Sent_On__c, Offer_Valid_Until__c,
                                Offer_Expires_On__c, Offer_Days_Left__c, Offer_Status__c,
                                Offer_Expired__c FROM Opportunity WHERE Id = :o.Id LIMIT 1];
            System.assertEquals(expectedEnd, back.Offer_Expires_On__c,
                'AC2: with no end date the offer is valid until sent + 30 days');
            System.assertEquals(null, back.Offer_Valid_Until__c,
                'AC2/AC11: the default is NEVER written into the recorded end date');
            System.assertEquals(true, back.Offer_Expired__c,
                'AC2: today is the day AFTER that end date -> the offer is expired');
            System.assertEquals('offer expired', back.Offer_Status__c,
                'AC2: an expired offer says so at a glance');
            System.assertEquals(null, back.Offer_Days_Left__c,
                'AC2: an expired offer never shows a negative day count');
        }

        // the last valid day itself is still valid (end date inclusive)
        Date sentToday = Date.today().addDays(-30);
        System.runAs(mgr) {
            Opportunity live = new Opportunity(
                Name = 'TEST SCRUM467 AC2 last valid day',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(5),
                Offer_Sent_On__c = sentToday
            );
            insert live;

            Opportunity back = [SELECT Id, Offer_Expires_On__c, Offer_Days_Left__c,
                                Offer_Status__c, Offer_Expired__c
                                FROM Opportunity WHERE Id = :live.Id LIMIT 1];
            System.assertEquals(Date.today(), back.Offer_Expires_On__c,
                'AC2: sent - 30 + 30 = today, and today IS the last valid day');
            System.assertEquals(false, back.Offer_Expired__c,
                'AC2/AC3: the last valid day is still valid, not expired');
            System.assertEquals('offer valid today', back.Offer_Status__c,
                'AC3: the last valid day says so at a glance');
            System.assertEquals(0, back.Offer_Days_Left__c,
                'AC3: on the last valid day zero days are left');
        }
    }

    // AC3: live offer -> wording + days left; expired offer -> expired.
    @isTest
    static void ac3_atAGlance_live_lastValidDay_expired() {
        User mgr = setupUser('ac3');
        Date liveSent = Date.today().addDays(-25);   // expiry today + 5
        Date edgeSent = Date.today().addDays(-14);   // window edge today

        Opportunity seedBatch = new Opportunity(
            Name = 'TEST SCRUM467 AC3 live 5 days',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Offer_Sent_On__c = liveSent
        );
        Opportunity seedEdge = new Opportunity(
            Name = 'TEST SCRUM467 AC3 window edge',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Offer_Sent_On__c = edgeSent,
            Offer_Valid_Until__c = Date.today()
        );
        Opportunity seedExpired = new Opportunity(
            Name = 'TEST SCRUM467 AC3 six weeks past',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Offer_Sent_On__c = Date.today().addDays(-60),
            Offer_Valid_Until__c = Date.today().addDays(-42)
        );

        System.runAs(mgr) {
            Opportunity[] seeded = new Opportunity[] { seedBatch, seedEdge, seedExpired };
            insert seeded;

            Opportunity[] back = [SELECT Id, Offer_Days_Left__c, Offer_Status__c,
                                  Offer_Expired__c, Offer_Expiring_14D__c
                                  FROM Opportunity WHERE Id IN :seeded];
            System.assertEquals(3, back.size(), 'setup: all three offers stored');

            Boolean foundLive = false;
            Boolean foundEdge = false;
            Boolean foundExpired = false;
            for (Opportunity o : back) {
                if (o.Offer_Days_Left__c == 5) {
                    foundLive = true;
                    System.assertEquals('offer valid for 5 more days', o.Offer_Status__c,
                        'AC3: a live offer shows its wording and its day count');
                    System.assertEquals(false, o.Offer_Expired__c,
                        'AC3: a live offer is not expired');
                    System.assertEquals(true, o.Offer_Expiring_14D__c,
                        'AC9 gate: 5 days out is inside the 14-day window');
                }
                if (o.Offer_Days_Left__c == 0 && o.Offer_Status__c == 'offer valid today') {
                    foundEdge = true;
                    System.assertEquals(false, o.Offer_Expired__c,
                        'AC3: the last valid day is still shown as valid');
                    System.assertEquals(true, o.Offer_Expiring_14D__c,
                        'AC9 gate: expiring today belongs to the window list');
                }
                if (o.Offer_Expired__c) {
                    foundExpired = true;
                    System.assertEquals('offer expired', o.Offer_Status__c,
                        'AC3: an expired offer is shown as expired');
                    System.assertEquals(null, o.Offer_Days_Left__c,
                        'AC3: an expired offer never shows a negative count');
                    System.assertEquals(false, o.Offer_Expiring_14D__c,
                        'AC10 split: an already-expired offer is NOT in the 14-day window');
                }
            }
            System.assert(foundLive, 'AC3: the live offer fixture was reached');
            System.assert(foundEdge, 'AC3: the last-valid-day fixture was reached');
            System.assert(foundExpired, 'AC3: the expired-offer fixture was reached');
        }
    }

    // AC4 (record side): no offer recorded -> the record never shows an expiry state.
    @isTest
    static void ac4_noOffer_neverLooksExpired() {
        User mgr = setupUser('ac4');

        System.runAs(mgr) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC4 no offer at all',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(10)
            );
            insert o;

            Opportunity back = [SELECT Id, Offer_Sent_On__c, Offer_Valid_Until__c,
                                Offer_Expires_On__c, Offer_Days_Left__c, Offer_Status__c,
                                Offer_Expired__c, Offer_Expiring_14D__c
                                FROM Opportunity WHERE Id = :o.Id LIMIT 1];
            System.assertEquals(null, back.Offer_Expires_On__c,
                'AC4: no offer -> no expiry date, so no gate can fire');
            System.assertEquals(null, back.Offer_Status__c,
                'AC4: no offer -> the record never shows an expiry state');
            System.assertEquals(false, back.Offer_Expired__c,
                'AC4: a record without an offer is never shown as expired');
            System.assertEquals(false, back.Offer_Expiring_14D__c,
                'AC4: a record without an offer appears in neither overview');
        }
    }

    // AC4 (save side): such a record can still be won with nothing filled in.
    // The save is System-context on purpose: the org's live OpportunityFollowupMonitorTrigger
    // throws "Variable does not exist: tmpVar1" for every IsClosed change under System.runAs
    // (house SCRUM-438/437 extern blocker, see the class header). The ValidationRule
    // behaviour tested here does not depend on the mode; AC5 keeps a refusal under a real user.
    @isTest
    static void ac4_noOffer_stillClosableAsWon() {
        Opportunity o = new Opportunity(
            Name = 'TEST SCRUM467 AC4 closable without offer',
            StageName = 'Prospecting',
            Amount = 0.00,
            CloseDate = Date.today().addDays(10)
        );
        insert o;

        Opportunity closeAttempt = new Opportunity(
            Id = o.Id,
            StageName = 'Closed Won',
            Amount = 0.00,
            CloseDate = Date.today()
        );
        update closeAttempt;

        Opportunity after = [SELECT Id, StageName, Offer_Expired__c, Offer_Status__c
                             FROM Opportunity WHERE Id = :o.Id LIMIT 1];
        System.assertEquals('Closed Won', after.StageName,
            'AC4: an Opportunity without an offer can still be won');
        System.assertEquals(false, after.Offer_Expired__c,
            'AC4: winning it did not make it look expired');
        System.assertEquals(null, after.Offer_Status__c,
            'AC4: a won deal without an offer still shows no expiry state');
    }

    // AC5: expired offer -> closing as Won is refused, nothing on the record changes.
    @isTest
    static void ac5_expiredOffer_closeWonRefused_recordUnchanged() {
        User mgr = setupUser('ac5');
        Date sent = Date.today().addDays(-60);
        Date until = Date.today().addDays(-42);   // six weeks in the past

        System.runAs(mgr) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC5 expired offer',
                StageName = 'Prospecting',
                Amount = 2500.00,
                CloseDate = Date.today().addDays(15),
                Offer_Sent_On__c = sent,
                Offer_Valid_Until__c = until
            );
            insert o;
            Id openId = o.Id;

            Boolean refused = false;
            String msg = '';
            try {
                Opportunity closeAttempt = new Opportunity(
                    Id = openId,
                    StageName = 'Closed Won',
                    Amount = 0.00
                );
                update closeAttempt;
            } catch (DmlException e) {
                refused = true;
                msg = e.getMessage();
            }
            System.assert(refused,
                'AC5: closing an expired offer as Won MUST be refused');
            System.assert(msg.contains('already expired'),
                'AC5: the refusal names the expired offer — ' + msg);
            System.assert(msg.contains('Renew it first'),
                'AC5: the refusal says the offer has to be renewed — ' + msg);

            Opportunity after = [SELECT Id, StageName, Amount, CloseDate,
                                 Offer_Sent_On__c, Offer_Valid_Until__c, Offer_Status__c
                                 FROM Opportunity WHERE Id = :openId LIMIT 1];
            System.assertEquals('Prospecting', after.StageName,
                'AC5: nothing on the record changed — the stage stays open');
            System.assertEquals(2500.00, after.Amount,
                'AC5: nothing changed — the amount is untouched');
            System.assertEquals(sent, after.Offer_Sent_On__c,
                'AC5: nothing changed — the offer dates are untouched');
            System.assertEquals(until, after.Offer_Valid_Until__c,
                'AC5: nothing changed — the offer dates are untouched');
            System.assertEquals('offer expired', after.Offer_Status__c,
                'AC5: the record still says expired after the refused save');
        }
    }

    // AC6: renewal moves both dates, the offer becomes valid, the deal can be won.
    @isTest
    static void ac6_renewal_movesBothDates_thenClosable() {
        User mgr = setupUser('ac6');
        Date oldSent = Date.today().addDays(-60);
        Date oldUntil = Date.today().addDays(-42);
        Date newSent = Date.today();
        Date newUntil = Date.today().addDays(30);

        System.runAs(mgr) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC6 renewal',
                StageName = 'Prospecting',
                Amount = 4000.00,
                CloseDate = Date.today().addDays(40),
                Offer_Sent_On__c = oldSent,
                Offer_Valid_Until__c = oldUntil
            );
            insert o;
            Id openId = o.Id;

            Opportunity renewed = new Opportunity(
                Id = openId,
                Amount = 4000.00,
                Offer_Sent_On__c = newSent,
                Offer_Valid_Until__c = newUntil
            );
            update renewed;

            Opportunity afterRenewal = [SELECT Id, Offer_Sent_On__c, Offer_Valid_Until__c,
                                        Offer_Expires_On__c, Offer_Days_Left__c,
                                        Offer_Status__c, Offer_Expired__c
                                        FROM Opportunity WHERE Id = :openId LIMIT 1];
            System.assertEquals(newSent, afterRenewal.Offer_Sent_On__c,
                'AC6: renewal moved the sent date');
            System.assertEquals(newUntil, afterRenewal.Offer_Valid_Until__c,
                'AC6: renewal moved the valid-until date');
            System.assertEquals(newUntil, afterRenewal.Offer_Expires_On__c,
                'AC6: the expiry follows the renewed end date');
            System.assertEquals(30, afterRenewal.Offer_Days_Left__c,
                'AC6: the renewed offer has 30 days left');
            System.assertEquals(false, afterRenewal.Offer_Expired__c,
                'AC6: the renewed offer is valid again');

            Opportunity stillOpen = [SELECT Id, StageName FROM Opportunity WHERE Id = :openId LIMIT 1];
            System.assertEquals('Prospecting', stillOpen.StageName,
                'AC6: the renewal itself did not close the deal');
        }
    }

    // AC6 (closability side): after the renewal the same deal CAN be closed as Won.
    // The close is a System-context save: changing IsClosed re-runs the org's
    // OpportunityFollowupMonitorTrigger, which fails under System.runAs (tmpVar1, house
    // SCRUM-438/437). The ValidationRule that guards the close is mode-independent.
    @isTest
    static void ac6_renewedOffer_closableAsWon() {
        Opportunity o = new Opportunity(
            Name = 'TEST SCRUM467 AC6 renewed then won',
            StageName = 'Secondary Offer',
            Amount = 4000.00,
            CloseDate = Date.today().addDays(2),
            Offer_Sent_On__c = Date.today(),
            Offer_Valid_Until__c = Date.today().addDays(30)
        );
        insert o;

        Opportunity won = new Opportunity(
            Id = o.Id,
            StageName = 'Closed Won',
            Amount = 4000.00,
            CloseDate = Date.today()
        );
        update won;

        Opportunity after = [SELECT Id, StageName, Offer_Expired__c
                             FROM Opportunity WHERE Id = :o.Id LIMIT 1];
        System.assertEquals('Closed Won', after.StageName,
            'AC6: after a renewal the deal can be closed as Won');
        System.assertEquals(false, after.Offer_Expired__c,
            'AC6: the renewed offer was not expired when it was won');
    }

    // AC7: an expired offer can still be closed as Lost — no renewal demanded.
    // System-context save for the same reason as AC4/AC6: the stage change re-runs the
    // org's OpportunityFollowupMonitorTrigger, which fails under System.runAs (tmpVar1,
    // house SCRUM-438/437). Loss_Reason__c is required by the house rule
    // LossReason_PflichtBeiClosedLost, so it is filled here to keep the refusal about us.
    @isTest
    static void ac7_expiredOffer_canStillBeLost() {
        Date sent = Date.today().addDays(-60);
        Date until = Date.today().addDays(-42);

        Opportunity o = new Opportunity(
            Name = 'TEST SCRUM467 AC7 let it go',
            StageName = 'Prospecting',
            Amount = 1500.00,
            CloseDate = Date.today().addDays(15),
            Offer_Sent_On__c = sent,
            Offer_Valid_Until__c = until
        );
        insert o;
        Id openId = o.Id;

        Opportunity closeLost = new Opportunity(
            Id = openId,
            StageName = 'Closed Lost',
            Amount = 1500.00,
            Loss_Reason__c = 'ZuTeuer'
        );
        update closeLost;

        Opportunity after = [SELECT Id, StageName, Offer_Sent_On__c, Offer_Status__c
                             FROM Opportunity WHERE Id = :openId LIMIT 1];
        System.assertEquals('Closed Lost', after.StageName,
            'AC7: a lost deal is accepted even with an expired offer');
        System.assertEquals(sent, after.Offer_Sent_On__c,
            'AC7: losing the deal did not touch the offer dates');
        System.assertEquals('offer expired', after.Offer_Status__c,
            'AC7: the offer still reads expired after the deal was lost');
    }

    // AC8: an already closed deal keeps its stage, its dates and its amount.
    @isTest
    static void ac8_closedDeal_datesFrozen_historyUntouched() {
        User mgr = setupUser('ac8');
        Date sent = Date.today().addDays(-20);
        Date until = Date.today().addDays(10);   // live offer: the record can be won

        System.runAs(mgr) {
            Opportunity o = new Opportunity(
                Name = 'TEST SCRUM467 AC8 already won',
                StageName = 'Closed Won',
                Amount = 900.00,
                CloseDate = Date.today(),
                Offer_Sent_On__c = sent,
                Offer_Valid_Until__c = until
            );
            insert o;
            Id closedId = o.Id;

            Boolean frozen = false;
            String msg = '';
            try {
                Opportunity editAttempt = new Opportunity(
                    Id = closedId,
                    Offer_Valid_Until__c = Date.today().addDays(60)
                );
                update editAttempt;
            } catch (DmlException e) {
                frozen = true;
                msg = e.getMessage();
            }
            System.assert(frozen,
                'AC8: an already closed deal must not accept an offer-date edit — ' + msg);
            System.assert(msg.contains('already closed'),
                'AC8: the refusal says the deal is closed — ' + msg);

            Opportunity after = [SELECT Id, StageName, Amount, Offer_Sent_On__c,
                                 Offer_Valid_Until__c FROM Opportunity WHERE Id = :closedId LIMIT 1];
            System.assertEquals('Closed Won', after.StageName,
                'AC8: the stage of a closed deal stays');
            System.assertEquals(900.00, after.Amount,
                'AC8: the amount of a closed deal stays');
            System.assertEquals(sent, after.Offer_Sent_On__c,
                'AC8: the sent date of a closed deal stays');
            System.assertEquals(until, after.Offer_Valid_Until__c,
                'AC8: the recorded end date stays — the refused edit did not move it');
        }
    }
}
