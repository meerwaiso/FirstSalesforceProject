/**
 * [SCRUM-461] SCRUM461TesterSaveTest — the save paths the PR does not exercise.
 *
 * Tester artifact. Covers the acceptance-criteria steps that SCRUM461CompetitorLossTest
 * does not reach: the UPDATE half of the gate (AC2/AC6), the historical deal that must
 * stay saveable (AC6/TAC8), and AC9 (a competitor save produces no automation).
 *
 * Names avoid the fixture names of SCRUM461CompetitorFlsTest ('Müller GmbH',
 * 'Müller Group'): Apex test SOQL sees the org's records, and the duplicate guard
 * would refuse a test insert whose Name already exists in the org.
 *
 * @author tester-agent
 * @date 2026-11-17
 */
@isTest
private class SCRUM461TesterSaveTest {

    @TestSetup
    static void setup_fixtures() {
        Account a = new Account(Name = '461 Tester Account');
        insert a;
        Competitor__c rival = new Competitor__c(Name = '461 Tester Rival');
        insert rival;

        // The shape a historical deal has: Closed Lost, a loss reason, no competitor.
        Opportunity historical = new Opportunity(
            Name = '461 Tester Historical',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 400,
            Amount = 40000,
            Loss_Reason__c = 'ZuTeuer'
        );
        insert historical;

        // A deal already lost to a competitor: the reopen path must stay clean.
        Opportunity competitorDeal = new Opportunity(
            Name = '461 Tester Competitor Deal',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 20,
            Amount = 70000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = rival.Id
        );
        insert competitorDeal;
    }

    // ── AC6 / TAC8: a deal that predates the feature stays usable ──────────
    @isTest
    static void historicalDealWithoutCompetitor_staysSaveable() {
        Opportunity original = [
            SELECT Id, Name, StageName, Loss_Reason__c, Competitor_Lost_To__c, Amount
            FROM Opportunity WHERE Name = '461 Tester Historical' LIMIT 1
        ];
        System.assert(original != null, 'precondition: historical fixture exists');
        System.assert(original.Competitor_Lost_To__c == null,
            'precondition: the fixture has no competitor');

        // Openable + listable: the SOQL above is the listing, the read below the view.
        // Saveable unchanged: a fresh sObject with only the fields being written
        // (house SCRUM-459 lesson — a record read from the org drags every field
        // into the save and can trip the duplicate guard on the competitor's Name).
        Opportunity touched = new Opportunity(Id = original.Id);
        touched.Amount = 41000;
        update touched;

        Opportunity back = [
            SELECT Id, StageName, Loss_Reason__c, Competitor_Lost_To__c, Amount
            FROM Opportunity WHERE Name = '461 Tester Historical' LIMIT 1
        ];
        System.assertEquals(41000, back.Amount, 'AC6: the untouched-by-design deal saved');
        System.assert(back.Competitor_Lost_To__c == null,
            'AC6: nothing demanded a competitor on a non-competitor loss');
        System.assertEquals('ZuTeuer', back.Loss_Reason__c,
            'AC6: the loss reason survived the save unchanged');
    }

    // ── AC2, the update half: the gate must also fire on a stage/reason change ──
    @isTest
    static void reasonChangedToCompetitorWithoutCompetitor_refused() {
        Opportunity original = [
            SELECT Id FROM Opportunity WHERE Name = '461 Tester Historical' LIMIT 1
        ];
        System.assert(original != null, 'precondition: historical fixture exists');

        Opportunity clash = new Opportunity(Id = original.Id);
        clash.Loss_Reason__c = 'Wettbewerber';

        boolean refused = false;
        String message = null;
        try {
            update clash;
        } catch (Exception e) {
            refused = true;
            message = e.getMessage();
        }
        System.assertEquals(true, refused,
            'AC2: switching the reason to a competitor loss without a competitor must not save');
        System.assert(message != null && message.contains('Wettbewerber'),
            'AC2: the message names the competitor requirement');

        // The same change WITH a competitor saves — the gate is conditional, not blanket.
        Competitor__c rival = [
            SELECT Id, Name FROM Competitor__c WHERE Name = '461 Tester Rival' LIMIT 1
        ];
        System.assert(rival != null, 'precondition: tester rival exists');
        Opportunity fixed = new Opportunity(Id = original.Id);
        fixed.Loss_Reason__c = 'Wettbewerber';
        fixed.Competitor_Lost_To__c = rival.Id;
        update fixed;
        Opportunity after = [
            SELECT Id, Loss_Reason__c, Competitor_Lost_To__c
            FROM Opportunity WHERE Name = '461 Tester Historical' LIMIT 1
        ];
        System.assert(after.Competitor_Lost_To__c != null,
            'AC2: the same change with a competitor saves');
    }

    // ── AC1 / AC6: reopening a competitor deal must not be blocked ─────────
    @isTest
    static void reopeningACompetitorDeal_savesWithoutComplaint() {
        Opportunity original = [
            SELECT Id FROM Opportunity WHERE Name = '461 Tester Competitor Deal' LIMIT 1
        ];
        System.assert(original != null, 'precondition: competitor fixture exists');

        Opportunity reopened = new Opportunity(Id = original.Id);
        reopened.StageName = 'Closed Won';
        update reopened;

        Opportunity back = [
            SELECT Id, StageName FROM Opportunity WHERE Name = '461 Tester Competitor Deal' LIMIT 1
        ];
        System.assertEquals('Closed Won', back.StageName,
            'AC1/AC6: a won deal is not blocked by the competitor rule');
    }

    // ── AC9: nothing automatic on a competitor save ────────────────────────
    @isTest
    static void competitorSave_producesNoAutomation() {
        Account a = [SELECT Id FROM Account WHERE Name = '461 Tester Account' LIMIT 1];
        Competitor__c rival = [
            SELECT Id, Name FROM Competitor__c WHERE Name = '461 Tester Rival' LIMIT 1
        ];
        System.assert(a != null && rival != null, 'precondition: fixtures exist');

        Opportunity fresh = new Opportunity(
            Name = '461 Tester Quiet Save',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 5,
            Amount = 90000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = rival.Id,
            Competitor_Price__c = 80000
        );
        insert fresh;

        Id oppId = fresh.Id;
        List<FeedItem> feed = [SELECT Id, ParentId FROM FeedItem WHERE ParentId = :oppId];
        System.assertEquals(0, feed.size(),
            'AC9: the save posted nothing to the record feed');

        List<Task> tasks = [SELECT Id, WhatId FROM Task WHERE WhatId = :oppId];
        System.assertEquals(0, tasks.size(),
            'AC9: the save created no task on the record');

        List<EmailMessage> emails = [SELECT Id, ParentId FROM EmailMessage WHERE ParentId = :oppId];
        System.assertEquals(0, emails.size(),
            'AC9: the save sent no email that is logged on the record');

        // The save itself did land, so the three zero-asserts above are not vacuous.
        Opportunity back = [
            SELECT Id, StageName, Loss_Reason__c, Competitor_Lost_To__c, Competitor_Price__c
            FROM Opportunity WHERE Name = '461 Tester Quiet Save' LIMIT 1
        ];
        System.assert(back != null && back.Competitor_Lost_To__c != null,
            'AC9 precondition: the competitor deal really saved');
    }

    // ── AC5: the no-price deal counts, but not in the average gap ──────────
    @isTest
    static void competitorWithoutPrice_countsButStaysOutOfTheAverage() {
        Account a = [SELECT Id FROM Account WHERE Name = '461 Tester Account' LIMIT 1];
        Competitor__c rival = [
            SELECT Id, Name FROM Competitor__c WHERE Name = '461 Tester Rival' LIMIT 1
        ];

        Opportunity noPrice = new Opportunity(
            Name = '461 Tester No Price',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 5,
            Amount = 55000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = rival.Id
        );
        insert noPrice;

        Opportunity cheaper = new Opportunity(
            Name = '461 Tester WeWereCheaper',
            AccountId = a.Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today() - 5,
            Amount = 30000,
            Loss_Reason__c = 'Wettbewerber',
            Competitor_Lost_To__c = rival.Id,
            Competitor_Price__c = 45000
        );
        insert cheaper;

        List<Opportunity> both = [
            SELECT Id, Amount, Competitor_Price__c, Competitor_Gap__c, Lost_Last_12M__c
            FROM Opportunity
            WHERE StageName = 'Closed Lost' AND Loss_Reason__c = 'Wettbewerber'
              AND Name IN ('461 Tester No Price', '461 Tester WeWereCheaper')
        ];
        System.assertEquals(2, both.size(),
            'AC5: both competitor deals are in the org and countable');

        Integer inWindow = 0;
        Integer gapBlank = 0;
        Integer negativeGap = 0;
        for (Opportunity o : both) {
            if (o.Lost_Last_12M__c) {
                inWindow++;
            }
            if (o.Competitor_Gap__c == null) {
                gapBlank++;
            } else if (o.Competitor_Gap__c < 0) {
                negativeGap++;
            }
        }
        System.assertEquals(2, inWindow,
            'AC5/TAC3: both deals sit inside the rolling twelve months');
        System.assertEquals(1, gapBlank,
            'AC5/TAC1: the no-price deal has a BLANK gap, not 0 — so the average ignores it');
        System.assertEquals(1, negativeGap,
            'TAC2: the deal where we were cheaper keeps a negative gap and is still counted');
    }
}
