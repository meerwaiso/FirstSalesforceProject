/**
 * [SCRUM-414] Value + FLS tests for the two Opportunity formula fields
 *   Opportunity.Is_Close_Date_Overdue__c   (Checkbox formula, read-only)
 *   Opportunity.Days_Close_Date_Overdue__c (Numberformula, read-only, 10/0)
 *
 * Formula contract (docs/SCRUM-414-design.md, ADR-3):
 *   offen + CloseDate < heute        -> true  / today - CloseDate
 *   offen + CloseDate = heute        -> false / 0
 *   offen + CloseDate > heute        -> false / 0
 *   offen + CloseDate leer           -> false / 0
 *   Closed Won / Closed Lost         -> false / NULL
 *
 * Value assertions read the live formula results from the just-inserted
 * records (formula fields compute on read — no backfill needed, TC7 is
 * inherent: an old record with a past CloseDate reads as overdue immediately).
 * FLS part: House-Pattern SCRUM390OverdueCaseFlsTest (System.runAs + temp
 * user, PS SCRUM414_CloseDateOverdue). Everything rolls back with the txn.
 */
@isTest
private class SCRUM414CloseDateOverdueTest {

    private static Opportunity mkOpp(String name, String stage, Date closeDate) {
        return new Opportunity(
            Name = name,
            StageName = stage,
            CloseDate = closeDate,
            OwnerId = UserInfo.getUserId()
        );
    }

    private static Opportunity readOverdue(Id id) {
        return [SELECT Is_Close_Date_Overdue__c, Days_Close_Date_Overdue__c FROM Opportunity WHERE Id = :id];
    }

    /** TC1: offen, CloseDate 3 Tage in der Vergangenheit -> true / 3. */
    @isTest
    static void open_threeDaysPast_isOverdue() {
        Opportunity o = mkOpp('TC1 open past', 'Proposal', Date.today().addDays(-3));
        insert o;
        Opportunity r = readOverdue(o.Id);
        System.assertEquals(true, r.Is_Close_Date_Overdue__c, 'TC1: open + 3 days past must be overdue');
        System.assertEquals(3, r.Days_Close_Date_Overdue__c, 'TC1: 3 days past must give 3, got ' + r.Days_Close_Date_Overdue__c);
    }

    /** TC2: offen, CloseDate 5 Tage in der Zukunft -> false / 0. */
    @isTest
    static void open_fiveDaysFuture_notOverdue() {
        Opportunity o = mkOpp('TC2 open future', 'Qualification', Date.today().addDays(5));
        insert o;
        Opportunity r = readOverdue(o.Id);
        System.assertEquals(false, r.Is_Close_Date_Overdue__c, 'TC2: open + future CloseDate must NOT be overdue');
        System.assertEquals(0, r.Days_Close_Date_Overdue__c, 'TC2: future CloseDate must give 0, got ' + r.Days_Close_Date_Overdue__c);
    }

    /** TC3: offen, CloseDate HEUTE strikte Grenze -> false / 0 (< nicht <=). */
    @isTest
    static void open_closeDateToday_notOverdue_strict() {
        Opportunity o = mkOpp('TC3 open today', 'Proposal', Date.today());
        insert o;
        Opportunity r = readOverdue(o.Id);
        System.assertEquals(false, r.Is_Close_Date_Overdue__c, 'TC3: CloseDate today must NOT be overdue (strict <)');
        System.assertEquals(0, r.Days_Close_Date_Overdue__c, 'TC3: CloseDate today must give 0, got ' + r.Days_Close_Date_Overdue__c);
    }

    /** TC4: Closed Won, CloseDate 100 Tage alt -> false / NULL (niemals markiert). */
    @isTest
    static void closedWon_hundredDaysOld_neverOverdue() {
        Opportunity o = mkOpp('TC4 closed won old', 'Closed Won', Date.today().addDays(-100));
        insert o;
        Opportunity r = readOverdue(o.Id);
        System.assertEquals(false, r.Is_Close_Date_Overdue__c, 'TC4: Closed Won must NEVER be overdue, no matter how old');
        System.assertEquals(null, r.Days_Close_Date_Overdue__c, 'TC4: closed stage must give NULL (empty), got ' + r.Days_Close_Date_Overdue__c);
    }

    /** TC5: Closed Lost, CloseDate 100 Tage alt -> false / NULL. */
    @isTest
    static void closedLost_hundredDaysOld_neverOverdue() {
        Opportunity o = mkOpp('TC5 closed lost old', 'Closed Lost', Date.today().addDays(-100));
        o.Loss_Reason__c = 'ZuTeuer'; // seit SCRUM-381 Pflicht bei Closed Lost
        insert o;
        Opportunity r = readOverdue(o.Id);
        System.assertEquals(false, r.Is_Close_Date_Overdue__c, 'TC5: Closed Lost must NEVER be overdue, no matter how old');
        System.assertEquals(null, r.Days_Close_Date_Overdue__c, 'TC5: closed stage must give NULL (empty), got ' + r.Days_Close_Date_Overdue__c);
    }

    /**
     * TC6 (entfällt in dieser Org): offen + CloseDate LEER wäre defensiv false / 0
     * (ADR-3 ISBLANK-Guard). In dieser Test-Org ist Opportunity.CloseDate ERFORDERLICH
     * (REQUIRED_FIELD_MISSING), daher lässt sich kein blank-CloseDate-Record erstellen —
     * der Guard-Case ist hier nicht ausübbar und wird bewusst NICHT getestet. Die Formel
     * behält den ISBLANK-Guard für Orgs, die CloseDate optional zulassen.
     */

    /**
     * TC7 (Bestand): eine 60 Tage alte offene Opportunity mit vergangenem
     * CloseDate ist SOFORT bei jedem Lesen überfällig — ohne Backfill-Schritt.
     * (Die Formel liest TODAY() bei jedem Read; der Rekord wird hier alt gemacht,
     * um den Bestand-Fall zu simulieren.)
     */
    @isTest
    static void existing_oldOpenRecord_isOverdueWithoutBackfill() {
        Opportunity o = mkOpp('TC7 old open opp', 'Qualification', Date.today().addDays(-60));
        insert o;
        // Der Bestand-Fall beruht allein auf CloseDate im Verhältnis zu TODAY():
        // die existierende Zeile mit vergangenem CloseDate ist bei jedem Lesen
        // sofort überfällig — es gibt keinen Backfill-Schritt, der fehlen könnte.
        Opportunity r = readOverdue(o.Id);
        System.assertEquals(true, r.Is_Close_Date_Overdue__c, 'TC7: existing open record with 60-day-old CloseDate must read as overdue immediately');
        System.assertEquals(60, r.Days_Close_Date_Overdue__c, 'TC7: 60 days past must give 60, got ' + r.Days_Close_Date_Overdue__c);
    }

    /**
     * TC8 (FLS): ohne PS SCRUM414_CloseDateOverdue sind beide Felder NICHT
     * les-/schreibbar; mit PS lesbar, nie schreibbar (read-only Formeln).
     * House-Pattern SCRUM390OverdueCaseFlsTest 1:1 (System.runAs, temp user).
     */
    @isTest
    static void fls_invisibleWithoutPS_readableOnlyWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls414Neg',
            Alias = 'fls414',
            Email = 'fls414neg@example.invalid',
            Username = 'fls414neg_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // 2. Precondition: Standard User has Opportunity object access.
        System.runAs(u) {
            System.assert(
                Opportunity.SObjectType.getDescribe().isAccessible(),
                'Precondition failed: Standard User has no Opportunity object access - ' +
                    'the FLS assertions below would pass for the wrong reason.'
            );
        }

        // 3. NEGATIVE: no Permission Set -> neither field is visible.
        System.runAs(u) {
            System.assertEquals(
                false, Opportunity.Is_Close_Date_Overdue__c.getDescribe().isAccessible(),
                'Without PS SCRUM414_CloseDateOverdue Is_Close_Date_Overdue__c must NOT be readable'
            );
            System.assertEquals(
                false, Opportunity.Is_Close_Date_Overdue__c.getDescribe().isUpdateable(),
                'Without PS SCRUM414_CloseDateOverdue Is_Close_Date_Overdue__c must NOT be writable'
            );
            System.assertEquals(
                false, Opportunity.Days_Close_Date_Overdue__c.getDescribe().isAccessible(),
                'Without PS SCRUM414_CloseDateOverdue Days_Close_Date_Overdue__c must NOT be readable'
            );
            System.assertEquals(
                false, Opportunity.Days_Close_Date_Overdue__c.getDescribe().isUpdateable(),
                'Without PS SCRUM414_CloseDateOverdue Days_Close_Date_Overdue__c must NOT be writable'
            );
        }

        // 4. Grant the Permission Set.
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM414_CloseDateOverdue' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // 5. POSITIVE: with Permission Set -> both readable; both stay read-only.
        System.runAs(u) {
            System.assertEquals(
                true, Opportunity.Is_Close_Date_Overdue__c.getDescribe().isAccessible(),
                'With PS SCRUM414_CloseDateOverdue Is_Close_Date_Overdue__c must be readable'
            );
            System.assertEquals(
                false, Opportunity.Is_Close_Date_Overdue__c.getDescribe().isUpdateable(),
                'With PS SCRUM414_CloseDateOverdue Is_Close_Date_Overdue__c must remain read-only (formula + editable=false)'
            );
            System.assertEquals(
                true, Opportunity.Days_Close_Date_Overdue__c.getDescribe().isAccessible(),
                'With PS SCRUM414_CloseDateOverdue Days_Close_Date_Overdue__c must be readable'
            );
            System.assertEquals(
                false, Opportunity.Days_Close_Date_Overdue__c.getDescribe().isUpdateable(),
                'With PS SCRUM414_CloseDateOverdue Days_Close_Date_Overdue__c must remain read-only (formula + editable=false)'
            );
        }
    }
}
