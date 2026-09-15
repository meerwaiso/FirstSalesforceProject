/**
 * [SCRUM-417] Offener Chancen-Verlauf je Kunde — Apex-Funktionaltests.
 *
 * TA→AK-Mapping (docs/SCRUM-417-design.md):
 *   TA1/AK1: run() erzeugt je Kontext je Monat (Jan→heute) exakt 1 Zeile
 *            (Unique-Key hält); 0/0-Zeilen wo keine offenen Chancen.
 *   TA2/AK2: Idempotenz — zweiter Lauf ändert nichts, erzeugt keine Duplikate.
 *   TA3:     Account.Open_Value_Drop_Last_Month__c = Wert(letzter Monat) −
 *            Wert(Vormonat); null ohne Vormonat (Januar).
 *   TA4/AK4: letzte Verlaufs-Zeile == SCRUM-416-Live-Felder.
 *   TA5:     historisches Monat-Prädikat (Alt-Chance, erst nach M geschlossen
 *            → zählt in M) — per purer Funktion, da CreatedDate in der
 *            Test-Kontextumgebung nicht zurückdatiert werden kann.
 *
 * «offen» = IsClosed = false (Single Source of Truth, ADR-3 aus 416 — dieselbe
 * Menge wie die deployed Rollup-Handler → AK4 erfüllt konstruktiv). Die
 * org-seitige Ableitung: StageName → IsClosed (writable signal im Test).
 * Alles, was hier erzeugt wird, rollt mit der Test-Transaction zurück.
 */
@isTest
private class SCRUM417OpenOpportunityHistoryTest {

    private static final Date FUTURE_CLOSE = Date.today().addDays(30);

    /** Anzahl Zeilen via 1 Aggregate-SOQL (kein Record-Loop). */
    private static Integer countRows(Id accId) {
        AggregateResult r = Database.query(
            'SELECT COUNT(Id) FROM OpenOpportunityHistory__c WHERE AccountId__c = \'' + accId + '\'');
        return (Integer) r.get('expr0');
    }

    private static Integer countZeroRows(Id accId) {
        AggregateResult r = Database.query(
            'SELECT COUNT(Id) FROM OpenOpportunityHistory__c WHERE AccountId__c = \'' + accId +
            '\' AND Open_Count__c = 0');
        return (Integer) r.get('expr0');
    }

    private static String currentMonthKey() {
        List<String> keys = OpenOpportunityHistoryRebuilder.monthKeys(Date.today());
        return keys.get(keys.size() - 1);
    }

    /**
     * TA1: exakt 1 Zeile je Konto je Monat (Jan→heute); aktueller Monat trägt
     * die offene Chance (1/500), alle übrigen Monate 0/0.
     */
    @isTest
    static void oneRowPerMonth_zeroZeroWhereInactive() {
        Account a = new Account(Name = 'V417 A1');
        insert a;
        Integer nMonths = OpenOpportunityHistoryRebuilder.monthKeys(Date.today()).size();

        insert new Opportunity(Name = 'V417 active', AccountId = a.Id,
                               StageName = 'Prospecting', Amount = 500,
                               CloseDate = FUTURE_CLOSE);

        OpenOpportunityHistoryRebuilder.run();
        System.assertEquals(nMonths, countRows(a.Id), '1 Zeile je Monat (Jan→heute)');

        OpenOpportunityHistory__c last = [
            SELECT Open_Count__c, Open_Value__c
            FROM OpenOpportunityHistory__c
            WHERE AccountId__c = :a.Id AND Snapshot_Month__c = :currentMonthKey()
            LIMIT 1];
        System.assertEquals(1, last.Open_Count__c, 'aktueller Monat zählt die offene Chance');
        System.assertEquals(Decimal.valueOf(500), last.Open_Value__c);

        Integer zeros = countZeroRows(a.Id);
        System.assertEquals(nMonths - 1, zeros, 'übrige Monate = 0/0 (keine offenen Chancen)');
    }

    /**
     * TA2: Idempotenz — zweiter Lauf: gleiche Zeilenzahl, gleiche Werte, keine
     * Duplikate (Unique-Key History_Key__c hält).
     */
    @isTest
    static void idempotentSecondRun() {
        Account a = new Account(Name = 'V417 A2');
        insert a;
        insert new Opportunity(Name = 'V417 idem2', AccountId = a.Id,
                               StageName = 'Prospecting', Amount = 300,
                               CloseDate = FUTURE_CLOSE);

        OpenOpportunityHistoryRebuilder.run();
        OpenOpportunityHistory__c first = [
            SELECT Id, Open_Value__c FROM OpenOpportunityHistory__c
            WHERE AccountId__c = :a.Id AND Snapshot_Month__c = :currentMonthKey() LIMIT 1];

        OpenOpportunityHistoryRebuilder.run(); // zweiter Lauf
        Integer total = OpenOpportunityHistoryRebuilder.monthKeys(Date.today()).size();
        System.assertEquals(total, countRows(a.Id), 'keine zusätzlichen Zeilen');

        OpenOpportunityHistory__c again = [
            SELECT Id, Open_Value__c FROM OpenOpportunityHistory__c
            WHERE AccountId__c = :a.Id AND Snapshot_Month__c = :currentMonthKey() LIMIT 1];
        System.assertEquals(first.Id, again.Id, 'Upsert trifft dieselbe Zeile (kein Duplikat)');
        System.assertEquals(first.Open_Value__c, again.Open_Value__c, 'Wert unverändert');
    }

    /**
     * TA4/AK4: die letzte (aktuelle) Verlaufs-Zeile zeigt EXAKT die SCRUM-416-
     * Live-Felder: 3 offen (100+200+300=600) + 1 won (999, zählt NICHT). Gleiche
     * offen-Chance-Menge (IsClosed=false), gleicher Amount-Standard.
     */
    @isTest
    static void latestMonthRow_matches416LiveFields() {
        Account a = new Account(Name = 'V417 A4');
        insert a;
        List<Opportunity> ops = new List<Opportunity>();
        ops.add(new Opportunity(Name = 'V417 o1', AccountId = a.Id, StageName = 'Prospecting',
                                Amount = 100, CloseDate = FUTURE_CLOSE));
        ops.add(new Opportunity(Name = 'V417 o2', AccountId = a.Id, StageName = 'Qualification',
                                Amount = 200, CloseDate = FUTURE_CLOSE));
        ops.add(new Opportunity(Name = 'V417 o3', AccountId = a.Id, StageName = 'Proposed',
                                Amount = 300, CloseDate = FUTURE_CLOSE));
        ops.add(new Opportunity(Name = 'V417 won', AccountId = a.Id, StageName = 'Closed Won',
                                Amount = 999, CloseDate = FUTURE_CLOSE));
        insert ops;

        // 416-Live-Felder (vom deployed Rollup-Trigger gepflegt).
        Account live = [SELECT Id, Open_Opportunity_Count__c, Open_Opportunity_Value__c
                        FROM Account WHERE Id = :a.Id];
        System.assertEquals(Decimal.valueOf(3), live.Open_Opportunity_Count__c, '416 Count = 3 offen');
        System.assertEquals(Decimal.valueOf(600), live.Open_Opportunity_Value__c, '416 Value = 600');

        OpenOpportunityHistoryRebuilder.run();
        OpenOpportunityHistory__c row = [
            SELECT Open_Count__c, Open_Value__c FROM OpenOpportunityHistory__c
            WHERE AccountId__c = :a.Id AND Snapshot_Month__c = :currentMonthKey() LIMIT 1];

        System.assertEquals(live.Open_Opportunity_Count__c, row.Open_Count__c,
            'AK4: letzte Verlaufs-Zeile == 416 Count');
        System.assertEquals(live.Open_Opportunity_Value__c, row.Open_Value__c,
            'AK4: letzte Verlaufs-Zeile == 416 Value');
    }

    /**
     * TA3: Drop-Feld = Wert(letzter Monat) − Wert(Vormonat), direkt gegen die
     * persistierten Zeilen geprüft (kein CreatedDate-Backdating nötig).
     */
    @isTest
    static void dropField_equalsLastMinusPrevFromRows() {
        Account a = new Account(Name = 'V417 A3');
        insert a;
        insert new Opportunity(Name = 'V417 drop', AccountId = a.Id,
                               StageName = 'Prospecting', Amount = 800,
                               CloseDate = FUTURE_CLOSE);
        OpenOpportunityHistoryRebuilder.run();

        List<OpenOpportunityHistory__c> rows = [
            SELECT Snapshot_Month__c, Open_Value__c FROM OpenOpportunityHistory__c
            WHERE AccountId__c = :a.Id ORDER BY Snapshot_Month__c];
        Integer n = rows.size();
        Decimal expected;
        if (n >= 2) {
            Decimal prev = (rows[n - 2].Open_Value__c == null) ? 0 : rows[n - 2].Open_Value__c;
            expected = rows[n - 1].Open_Value__c - prev;
        } else {
            // Jahres-Monat, kein Vormonat → Drop null
            expected = null;
        }

        Account acc = [SELECT Open_Value_Drop_Last_Month__c FROM Account WHERE Id = :a.Id];
        System.assertEquals(expected, acc.Open_Value_Drop_Last_Month__c,
            'Drop = letzter Monat − Vormonat');
    }

    /**
     * TA5/pure: aktueller Monat zählt NUR offene Chancen (IsClosed = false).
     * (StageName ist das writable signal; die org leitet IsClosed davon ab.)
     */
    @isTest
    static void purePredicate_currentMonth_onlyOpen() {
        Date asOf = Date.today();
        Date curEnd = OpenOpportunityHistoryRebuilder.monthEnd(asOf.year(), asOf.month());
        System.isTrue(
            OpenOpportunityHistoryRebuilder.isCountedInMonth(
                new Opportunity(IsClosed = false, CloseDate = FUTURE_CLOSE, Amount = 100),
                curEnd, asOf),
            'aktueller Monat: offene Chance zählt');
        System.assertFalse(
            OpenOpportunityHistoryRebuilder.isCountedInMonth(
                new Opportunity(IsClosed = true, CloseDate = Date.today(), Amount = 900),
                curEnd, asOf),
            'aktueller Monat: geschlossene Chance (won/lost) zählt NICHT');
    }

    /**
     * TA5/pure: vergangener Monat M — eine Chance zählt, wenn sie Ende M offen
     * war: (a) ist jetzt noch offen (IsClosed = false), oder (b) erst NACH
     * Monats-Ende M geschlossen (CloseDate > M). Eine vor/bei M geschlossene
     * Chance zählt NICHT in M.
     */
    @isTest
    static void purePredicate_pastMonth_openAtMonthEnd() {
        Integer y = Date.today().year();
        Date janEnd = OpenOpportunityHistoryRebuilder.monthEnd(y, 1);
        Date asOf = Date.today();

        // Jetzt offen → war Ende Jan offen (vorausgesetzt: CreatedDate <= janEnd).
        System.isTrue(
            OpenOpportunityHistoryRebuilder.isCountedInMonth(
                new Opportunity(IsClosed = false, CloseDate = FUTURE_CLOSE, Amount = 100),
                janEnd, asOf),
            'Jahr-Monat: Chance, die jetzt offen ist, war Ende Jan offen');

        // Im (fiktiven) Februar nach Jan-Ende geschlossen → war Ende Jan offen.
        Date afterJan = janEnd.addDays(1);
        System.isTrue(
            OpenOpportunityHistoryRebuilder.isCountedInMonth(
                new Opportunity(IsClosed = true, CloseDate = afterJan, Amount = 500),
                janEnd, asOf),
            'Jahr-Monat: erst Ende Januar/Anfang Februar geschlossen → zählt noch in Jan');

        // Erst im Januar selbst geschlossen → nicht offen am Jan-Ende.
        Date midJan = Date.newInstance(y, 1, 15);
        System.assertFalse(
            OpenOpportunityHistoryRebuilder.isCountedInMonth(
                new Opportunity(IsClosed = true, CloseDate = midJan, Amount = 300),
                janEnd, asOf),
            'Jahr-Monat: im Januar selbst geschlossen → zählt NICHT in Jan');
    }

    /**
     * TA3/pure: Drop-Wert — null ohne Vormonat (Jahr-Monat), negativ bei
     * Rückgang, positiv bei Anstieg, fehlender Vormonat = 0.
     */
    @isTest
    static void pureDrop_nullFirstMonth_negativeOnDecrease() {
        System.assertEquals(null,
            OpenOpportunityHistoryRebuilder.dropValue(100, 50, false),
            'kein Vormonat → null (Jahr-Monat Januar)');
        System.assertEquals(Decimal.valueOf(-50),
            OpenOpportunityHistoryRebuilder.dropValue(100, 150, true),
            'Rückgang 150→100 → −50');
        System.assertEquals(Decimal.valueOf(50),
            OpenOpportunityHistoryRebuilder.dropValue(150, 100, true),
            'Anstieg 100→150 → +50');
        System.assertEquals(Decimal.valueOf(100),
            OpenOpportunityHistoryRebuilder.dropValue(100, null, true),
            'Vormonat null → als 0 behandelt (100−0)');
    }
}
