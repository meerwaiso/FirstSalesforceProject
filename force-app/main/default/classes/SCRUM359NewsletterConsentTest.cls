/**
 * [SCRUM-359] Validation rules for NewsletterConsent__c / ConsentDate__c.
 *
 * Ticket section "Validierungsregeln / Verhalten" (SCRUM-359, re-read 2026-08-25,
 * comment 00519 era): three points, each tested here with its own method and a
 * POSITIVE case proving a valid combination still saves:
 *
 *   1. Checkbox set + NO date      -> save REJECTED with an understandable
 *      message that the date is missing.
 *   2. Future date (after today)   -> save REJECTED.
 *   3. Checkbox NOT set            -> an existing date REMAINS (historical
 *      proof of consent); clearing the checkbox does NOT auto-clear the date.
 *      Points 1 & 2 apply ONLY while the checkbox is set.
 *
 * Implemented as two Contact validation rules (active, onContact verified at
 * deploy time) — the exact error messages this class asserts against:
 *   NewsletterConsent_DatumPflicht
 *      AND(NewsletterConsent__c = true, ISBLANK(ConsentDate__c))
 *      -> "... Bitte das Einwilligungsdatum ausfüllen. Das Feld
 *          Einwilligung am ist dann Pflicht."
 *   NewsletterConsent_DatumKeineZukunft
 *      AND(NewsletterConsent__c = true, NOT(ISBLANK(ConsentDate__c)),
 *          ConsentDate__c > TODAY())
 *      -> "... Das Einwilligungsdatum darf nicht in der Zukunft liegen.
 *          Eine Einwilligung, die noch nicht erteilt wurde, gibt es nicht. ..."
 *
 * Validation rules fire on EVERY DML context (system and user alike), so the
 * tests run plain DML — no System.runAs() needed here (that belongs to the
 * FLS proof in SCRUM359NewsletterConsentFlsTest). Every negative case expects
 * a DmlException and asserts the rule's own message text; if no exception is
 * thrown the assertion right after the try-block fails the test, so the
 * catch-branch is never a silent pass. No dummy assertions anywhere.
 *
 * All created records roll back with the test transaction — org untouched.
 */
@isTest
private class SCRUM359NewsletterConsentTest {

    /** Fresh "today" at the moment of use — the rules compare against TODAY(). */
    private static Date today() {
        return Date.today();
    }

    /** Inserts a minimal Contact with the given consent state and returns it. */
    private static Contact insertContact(Boolean consent, Date consentDate, String tag) {
        Contact c = new Contact(
            LastName = 'V359 ' + tag,
            NewsletterConsent__c = consent,
            ConsentDate__c = consentDate
        );
        insert c;
        return c;
    }

    /**
     * Validation point 1 (AC2): consent set + empty date -> save rejected with
     * a clear "date is missing" message; a valid combination (consent + past
     * date) saves through and both fields persist.
     */
    @isTest
    static void validation1_missingDate_rejectedAndValidCombinationSaves() {
        // NEGATIVE: checkbox set, date left empty -> must NOT save.
        try {
            insertContact(true, null, 'Neg1');
            System.assert(false, 'Expected DmlException (missing-date rule) but the save succeeded');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('ist dann Pflicht'),
                'The rejection message is missing the clear "date is required" wording (rule ' +
                    'NewsletterConsent_DatumPflicht). Actual: ' + e.getMessage()
            );
        }
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contact WHERE LastName LIKE 'V359 Neg1%'],
            'The rejected save must not persist anything'
        );

        // POSITIVE: consent set + a past (valid) date -> saves through.
        Date past = today().addDays(-14);
        Contact created = insertContact(true, past, 'Pos1');
        Contact stored = [
            SELECT NewsletterConsent__c, ConsentDate__c FROM Contact WHERE Id = :created.Id
        ];
        System.assertEquals(true, stored.NewsletterConsent__c, 'consent checkbox not persisted');
        System.assertEquals(past, stored.ConsentDate__c, 'consent date not persisted');
    }

    /**
     * Validation point 2 (AC3): future date -> rejected; boundary positive:
     * TODAY itself is a valid consent date and must save (the rule fires only
     * for ConsentDate__c > TODAY()).
     */
    @isTest
    static void validation2_futureDate_rejectedAndTodaySaves() {
        // NEGATIVE: consent set + tomorrow -> must NOT save.
        try {
            insertContact(true, today().addDays(1), 'Neg2');
            System.assert(false, 'Expected DmlException (future-date rule) but the save succeeded');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('in der Zukunft liegen'),
                'The rejection message is missing the "may not be in the future" wording (rule ' +
                    'NewsletterConsent_DatumKeineZukunft). Actual: ' + e.getMessage()
            );
        }
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contact WHERE LastName LIKE 'V359 Neg2%'],
            'The rejected save must not persist anything'
        );

        // POSITIVE boundary: consent set + date = today -> allowed and persisted.
        Contact created = insertContact(true, today(), 'Pos2');
        Contact stored = [
            SELECT NewsletterConsent__c, ConsentDate__c FROM Contact WHERE Id = :created.Id
        ];
        System.assertEquals(true, stored.NewsletterConsent__c, 'consent checkbox not persisted');
        System.assertEquals(today(), stored.ConsentDate__c, 'a today consent date must be allowed and persisted');
    }

    /**
     * Validation point 3 (AC4): unchecking the consent keeps the existing date
     * (historical proof) — the date is NOT auto-cleared — and points 1 & 2 are
     * inert while the checkbox is NOT set (no date / future date both save).
     */
    @isTest
    static void validation3_checkboxOff_dateRetainedAndRulesInert() {
        // Setup: a valid consent (true + past date).
        Date past = today().addDays(-30);
        Contact c = insertContact(true, past, 'Pos3');

        // Act: turn the checkbox OFF, leave the date untouched.
        c.NewsletterConsent__c = false;
        update c; // must succeed — point 3 says clearing the box is valid

        // THEN SELECT: the date must still be there as historical proof.
        Contact stored = [
            SELECT NewsletterConsent__c, ConsentDate__c FROM Contact WHERE Id = :c.Id
        ];
        System.assertEquals(false, stored.NewsletterConsent__c, 'consent still set after uncheck');
        System.assertEquals(
            past,
            stored.ConsentDate__c,
            'The consent date was auto-cleared when the checkbox went off — it must remain as the historical proof of consent'
        );

        // Rules 1 & 2 must NOT fire while the checkbox is unset:
        // (a) rule 1 must not block "no consent + no date"
        Contact noDate = insertContact(false, null, 'Inert1');
        Contact noDateStored = [
            SELECT ConsentDate__c FROM Contact WHERE Id = :noDate.Id
        ];
        System.assertEquals(null, noDateStored.ConsentDate__c, 'a non-consented contact must be allowed to have no date');

        // (b) rule 2 must not block "no consent + future date"
        Date future = today().addDays(1);
        Contact futureNoConsent = insertContact(false, future, 'Inert2');
        Contact futureStored = [
            SELECT ConsentDate__c FROM Contact WHERE Id = :futureNoConsent.Id
        ];
        System.assertEquals(
            future,
            futureStored.ConsentDate__c,
            'Rule 2 must not fire while the checkbox is unset — a future date without consent must save'
        );
    }
}
