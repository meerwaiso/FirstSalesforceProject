/**
 * [SCRUM-388] Functional + FLS test for Account.Last_Opportunity__c and
 * Is_Inactive__c, computed by the nightly AccountReactivationBatch.
 *
 * --------------------------------------------------------------------------
 * WARUM execute()/finish() DIREKT gefahren werden statt Database.executeBatch()
 * (empirisch in der Test-Org belegt, SCRUM-367 Probe-Run 707WU00001GGEk7):
 *   Der Test-Framework-Wrapper dieser Org verweigert einen executeBatch-Lauf,
 *   sobald der QueryLocator UEBER EINZEL-CHUNK HINAUSSPANT
 *   (System.UnexpectedException: No more than one executeBatch …). Deshalb
 *   fahre ich die PRODUKTIONS-Methode execute() auf dem GLEICHEN Instanz-Objekt
 *   (Database.Stateful: dieselbe Instanz ueberlebt Chunk-Grenzen) Chunk fuer
 *   Chunk an — exakt die Chunk-Schleife, die das Batch-Framework ausfuehren
 *   wuerde — danach finish(). ctx wird von execute/finish nicht verwendet
 *   => null ist erlaubt. (Direkt-Fahren => dieselbe Instanz, NICHT
 *   serialisiert => die processed/corrected-Zaehler sind per Getter lesbar;
 *   im echten executeBatch-Rundtrip ware das nicht so.)
 *
 *   Direkt-Fahren ist im Test-Kontext ein SYNCHRON-Transaction: governor
 *   Limits (SOQL 200 / DML 150 je Context) gelten. Deshalb AC7 mit 1000
 *   Accounts in 20 Chunks (chunkSize 50) statt tausenden — das beweisstarke
 *   Merkmal ist die Stateful-Summation ueber Chunk-GRENZEN (20+ Grenzen),
 *   nicht die absolute Anzahl. Timeout-bei-THAUSENDAEN ist eine
 *   Laufzeit-/Architektur-Eigenschaft (kurze DML-Transaktion je Chunk, kein
 *   SELECT FOR UPDATE) und kein deterministisch unit-testbarer Wert — wie bei
 *   SCRUM-367 im Review-Kommentar genannt.
 *
 * Deterministische Tagesdifferenz OHNE CreatedDate-Mocking:
 *   CreatedDate ist per DML nicht setzbar; ein frisch angelegter Record hat
 *   CreatedDate = jetzt. Der Batch rechnet die ganzen Kalendertage zwischen
 *   refDate und asOf (wholeDaysBetween), wobei refDate = das TATSACHLICHE
 *   CreatedDate (Opportunity, sonst Account). Deshalb leite ich asOf IMMER
 *   aus dem wirklich gespeicherten CreatedDate ab: asOf = refDate.addDays(N)
 *   ⇒ daysSince = exakt N, unabhaengig von Zeitzone/Uhrzeit. Das ist robuster
 *   als das im Design vorgeschlagene System.today().addDays(N), das rund um
 *   UTC-Mitternacht um ±1 Tag abdriften konnte. ⇒ AC5-Grenze (180 vs 181) &
 *   AC6-Schwelle sind exakt & deterministisch.
 *
 * FLS (Cases 9–11): 1:1 aus dem verifizierten SCRUM-382/378-Pattern — ein
 * Lizenz-freier Standard-User via System.runAs (runAs umgeht FLS NICHT); der
 * DML-Beleg isoliert FLS von Sharing, indem der User sein EIGENES Account
 * anlegt (Owner => Sharing-Access gegeben, nur FLS ist die Variable).
 *
 * @author developer-agent
 * @date 2026-09-05
 */
@isTest
private class SCRUM388AccountReactivationTest {

    /**
     * Fahren der Produktions-Chunk-Schleife wie das Batch-Framework: die
     * uebergebene Scope-Liste wird in Stuecken von `chunkSize` auf dem
     * GLEICHEN Batch-Objekt ueber die PRODUKTIONS-Methode execute()
     * verarbeitet (Stateful: dieselbe Instanz ueberlebt Chunk-Grenzen), danach
     * finish(). ctx wird von execute/finish nicht verwendet => null erlaubt.
     * (Shape 1:1 aus SCRUM367OpenCasesRebuildScaleTest; ohne sublist — das
     * Apex-List-API hier heisst subList, der Loop ist expliziter.)
     */
    private static void driveBatchAcrossChunks(AccountReactivationBatch batch,
            List<Account> scope, Integer chunkSize) {
        Integer totalRecords = scope.size();
        for (Integer startIdx = 0; startIdx < totalRecords; startIdx += chunkSize) {
            Integer endIdx = (startIdx + chunkSize > totalRecords)
                    ? totalRecords : (startIdx + chunkSize);
            List<Account> chunk = new List<Account>();
            for (Integer j = startIdx; j < endIdx; j++) {
                chunk.add(scope[j]);
            }
            batch.execute(null, chunk);
        }
        batch.finish(null);
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private static Account createAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    /** Opportunity wie in dieser Org bewaehrt: Prospecting + offene CloseDate. */
    private static Opportunity createOpportunity(String name, Id accountId) {
        Opportunity o = new Opportunity(
            Name = name,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = accountId);
        insert o;
        return o;
    }

    /** Scope-Read exakt wie der QueryLocator (incl. CreatedDate fuer AC6). */
    private static List<Account> scopeFor(Set<Id> accountIds) {
        return [SELECT Id, CreatedDate, Last_Opportunity__c, Is_Inactive__c
                FROM Account WHERE Id IN :accountIds];
    }

    private static Account readAccount(Id accId) {
        return [SELECT Id, CreatedDate, Last_Opportunity__c, Is_Inactive__c
                FROM Account WHERE Id = :accId LIMIT 1];
    }

    /** Tatsaechliches CreatedDate (DateTime) des Account — Referenz fuer asOf. */
    private static DateTime accountCreatedDateTime(Id accId) {
        return [SELECT CreatedDate FROM Account WHERE Id = :accId LIMIT 1].CreatedDate;
    }

    /**
     * asOf = das wirklich gespeicherte refDate + N Tage ⇒ daysSince = exakt N.
     * refDate = juengste Opportunity (Date), sonst das Account-CreatedDate.
     */
    private static Date dialAsOf(Id accId, Integer nDays) {
        Date ref;
        List<Opportunity> opps = [SELECT CreatedDate FROM Opportunity
                                  WHERE AccountId = :accId ORDER BY CreatedDate DESC];
        if (opps.isEmpty()) {
            ref = accountCreatedDateTime(accId).date();
        } else {
            ref = opps[0].CreatedDate.date();
        }
        return ref.addDays(nDays);
    }

    /** Lizenz-freier Standard-User (runAs-Kontext; 2 Lizenzen in der Test-Org). */
    private static User createStdUser(String suffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls388' + suffix,
            Alias = 'fls388' + suffix,
            Email = 'fls388' + suffix + '@example.invalid',
            Username = 'fls388' + suffix + '_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles');
        insert u;
        return u;
    }

    // ------------------------------------------------------------------
    // AC-Tests (Batch, direkt gefahren)
    // ------------------------------------------------------------------

    /** AC1/AC2: Account + 3 Opportunities => Datum = juengste CreatedDate, aktiv. */
    @isTest
    static void ac1_ac2_threeOpportunities_newestOpportunity_shown_active() {
        Account a = createAccount('Scr388 AC2 ThreeOpps');
        createOpportunity('Scr388 OppA', a.Id);
        createOpportunity('Scr388 OppB', a.Id);
        createOpportunity('Scr388 OppC', a.Id);

        // asOf = refDate + 0 => daysSince 0 => aktiv; Datum = juengste Opp.
        Date asOf = dialAsOf(a.Id, 0);
        AccountReactivationBatch b = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b, scopeFor(new Set<Id>{ a.Id }), 200);

        Account r = readAccount(a.Id);
        System.assertEquals(dialOppDate(a.Id), r.Last_Opportunity__c,
            'AC2: Letze Opportunity = CreatedDate der juengsten Opportunity');
        System.assertEquals(false, r.Is_Inactive__c,
            'AC1: frisch (0 Tage) => aktiv');
        System.assertEquals(1, b.getProcessed());
        System.assertEquals(1, b.getCorrected());
    }

    /** AC3: keine Opportunity je => Datum bleibt leer (hier <180 => aktiv, 0 Korrekturen). */
    @isTest
    static void ac3_noOpportunity_fieldRemainsEmpty() {
        Account a = createAccount('Scr388 AC3 NoOpp');
        Date asOf = dialAsOf(a.Id, 50);   // 50 Tage, ab Account-Anlage
        AccountReactivationBatch b = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b, scopeFor(new Set<Id>{ a.Id }), 200);

        Account r = readAccount(a.Id);
        System.assertEquals(null, r.Last_Opportunity__c,
            'AC3: ohne je eine Opportunity ist das Datum leer');
        System.assertEquals(false, r.Is_Inactive__c,
            'AC3: <180 Tage (ab Account-Anlage) => aktiv');
        System.assertEquals(1, b.getProcessed());
        // frisch: Is_Inactive Default schon false, Datum schon leer => nichts aendern
        System.assertEquals(0, b.getCorrected());
    }

    /** AC4: juengste Opportunity 181 Tage zurueck => inaktiv. */
    @isTest
    static void ac4_oneEightyOneDays_inactive() {
        Account a = createAccount('Scr388 AC4 Opp181');
        createOpportunity('Scr388 Opp181', a.Id);
        Date asOf = dialAsOf(a.Id, 181);
        AccountReactivationBatch b = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b, scopeFor(new Set<Id>{ a.Id }), 200);

        Account r = readAccount(a.Id);
        System.assertEquals(true, r.Is_Inactive__c,
            'AC4: 181 Tage (> 180) => inaktiv');
        System.assertEquals(dialOppDate(a.Id), r.Last_Opportunity__c,
            'AC4: Datum der juengsten Opportunity');
        System.assertEquals(1, b.getCorrected());
    }

    /** AC5 (Grenzwert): EXAKT 180 Tage => NOCH aktiv (strikt >). */
    @isTest
    static void ac5_exactly180Days_stillActive() {
        Account a = createAccount('Scr388 AC5 Opp180');
        createOpportunity('Scr388 Opp180', a.Id);
        Date asOf = dialAsOf(a.Id, 180);
        AccountReactivationBatch b = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b, scopeFor(new Set<Id>{ a.Id }), 200);

        Account r = readAccount(a.Id);
        System.assertEquals(false, r.Is_Inactive__c,
            'AC5: EXAKT 180 Tage => 180 > 180 ist false => noch aktiv');
    }

    /** AC5b (Flanke): EXAKT 181 Tage => inaktiv (anderes Flankenpaar der Grenze). */
    @isTest
    static void ac5b_exactly181Days_inactive() {
        Account a = createAccount('Scr388 AC5b Opp181b');
        createOpportunity('Scr388 Opp181b', a.Id);
        Date asOf = dialAsOf(a.Id, 181);
        AccountReactivationBatch b = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b, scopeFor(new Set<Id>{ a.Id }), 200);

        Account r = readAccount(a.Id);
        System.assertEquals(true, r.Is_Inactive__c,
            'AC5b: 181 Tage (> 180) => inaktiv');
    }

    /** AC6: keine Opportunity je => Schwelle ab dem EIGNEN Anlagedatum (200 => inaktiv, 100 => aktiv). */
    @isTest
    static void ac6_noOpportunity_thresholdFromAccountCreated() {
        Account old = createAccount('Scr388 AC6 NoOpp Old');
        Date asOfOld = dialAsOf(old.Id, 200);
        AccountReactivationBatch bOld = new AccountReactivationBatch(asOfOld, 200);
        driveBatchAcrossChunks(bOld, scopeFor(new Set<Id>{ old.Id }), 200);
        Account rOld = readAccount(old.Id);
        System.assertEquals(null, rOld.Last_Opportunity__c,
            'AC6: ohne Opp bleibt Datum leer');
        System.assertEquals(true, rOld.Is_Inactive__c,
            'AC6: >180 Tage ab Account-EIGENER Anlage => inaktiv');

        Account recent = createAccount('Scr388 AC6 NoOpp Recent');
        Date asOfRecent = dialAsOf(recent.Id, 100);
        AccountReactivationBatch bRecent = new AccountReactivationBatch(asOfRecent, 200);
        driveBatchAcrossChunks(bRecent, scopeFor(new Set<Id>{ recent.Id }), 200);
        Account rRecent = readAccount(recent.Id);
        System.assertEquals(null, rRecent.Last_Opportunity__c,
            'AC6: ohne Opp bleibt Datum leer');
        System.assertEquals(false, rRecent.Is_Inactive__c,
            'AC6: <180 Tage ab Account-EIGENER Anlage => aktiv');
    }

    /**
     * AC7 (Skalierung / Multi-Chunk): 1000 Accounts in 20 Chunks (chunkSize 50).
     * Beweis: Stateful processed/corrected summieren ueber ALLE Chunk-Grenzen;
     * alle 1000 korrekt gesetzt (100 mit Datung, 900 leer, alle inaktiv).
     */
    @isTest
    static void ac7_multiChunk_1000Accounts_processedAndCorrectedSummation() {
        Integer n = 1000;
        Integer withOpp = 100;
        List<Account> accs = new List<Account>();
        Set<Id> occIds = new Set<Id>();
        Set<Id> noOppIds = new Set<Id>();
        Set<Id> allIds = new Set<Id>();
        for (Integer i = 0; i < n; i++) {
            Account acc = new Account(Name = 'Scr388 AC7 ' + String.valueOf(i));
            accs.add(acc);
        }
        insert accs;
        for (Integer i = 0; i < n; i++) {
            allIds.add(accs[i].Id);
            if (i < withOpp) {
                occIds.add(accs[i].Id);
            } else {
                noOppIds.add(accs[i].Id);
            }
        }
        List<Opportunity> opps = new List<Opportunity>();
        Integer c = 0;
        for (Id occId : occIds) {
            opps.add(new Opportunity(
                Name = 'Scr388 AC7 Opp ' + String.valueOf(c),
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = occId));
            c++;
        }
        insert opps;

        // asOf => ~200 Tage => alle inaktiv (auch no-opp); robust gegen ±1-Tag.
        Date asOf = accountCreatedDateTime(accs[0].Id).date().addDays(200);
        AccountReactivationBatch b = new AccountReactivationBatch(asOf, 50);
        List<Account> fullScope = [SELECT Id, CreatedDate, Last_Opportunity__c, Is_Inactive__c
                                   FROM Account WHERE Id IN :allIds];
        driveBatchAcrossChunks(b, fullScope, 50);

        // AC-7-Beleg: exakte Summe ueber ALLE 20 Chunk-Grenzen.
        System.assertEquals(n, b.getProcessed(),
            'AC7: processed == 1000 (Stateful-Summation ueber 20 Chunks)');
        System.assertEquals(n, b.getCorrected(),
            'AC7: corrected == 1000 (alle Accounts im 1. Lauf gesetzt)');

        Integer lastOppSet = (Integer)[
            SELECT COUNT(Id) cnt FROM Account
            WHERE Id IN :occIds AND Last_Opportunity__c != null
        ].get(0).get('cnt');
        System.assertEquals(withOpp, lastOppSet,
            'AC7: genau die 100 mit Opportunity zeigen ein Datum');

        Integer lastOppNull = (Integer)[
            SELECT COUNT(Id) cnt FROM Account
            WHERE Id IN :noOppIds AND Last_Opportunity__c = null
        ].get(0).get('cnt');
        System.assertEquals(n - withOpp, lastOppNull,
            'AC7: die 900 ohne Opportunity haben leeres Datum');

        Integer inactive = (Integer)[
            SELECT COUNT(Id) cnt FROM Account
            WHERE Id IN :allIds AND Is_Inactive__c = true
        ].get(0).get('cnt');
        System.assertEquals(n, inactive,
            'AC7: alle 1000 neu bewertet & als inaktiv markiert');
    }

    /**
     * AC8 (Idempotenz): 1. Lauf korrigiert (fresh -> aktiv/inaktiv gesetzt);
     * 2. Lauf (gleiche Daten, gleicher asOf, neue Instanz) => corrected 0 UND
     * LastModifiedDate aller Accounts unveraendert (0 DML).
     */
    @isTest
    static void ac8_idempotency_secondRunZeroDml_lastModifiedDateUnchanged() {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 0; i < 5; i++) {
            Account acc = createAccount('Scr388 AC8 ' + String.valueOf(i));
            ids.add(acc.Id);
            if (i < 2) {   // 2 von 5 mit einer Opportunity
                createOpportunity('Scr388 AC8 Opp ' + i, acc.Id);
            }
        }
        Date asOf = accountCreatedDateTime(
            [SELECT Id, CreatedDate FROM Account WHERE Id IN :ids ORDER BY CreatedDate
             LIMIT 1][0].Id).date().addDays(200);

        // Lauf 1
        AccountReactivationBatch b1 = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b1, scopeFor(ids), 200);
        System.assert(b1.getCorrected() > 0,
            'AC8: 1. Lauf auf frischen Werten muss korrigieren');
        Map<Id, DateTime> lm1 = lastModifiedOf(ids);

        // Lauf 2 (neue Instanz, frisch gelesener Scope, gleicher asOf)
        AccountReactivationBatch b2 = new AccountReactivationBatch(asOf, 200);
        driveBatchAcrossChunks(b2, scopeFor(ids), 200);
        System.assertEquals(0, b2.getCorrected(),
            'AC8: 2. Lauf ohne Datenanderung korrigiert genau 0 (Idempotenz)');
        Map<Id, DateTime> lm2 = lastModifiedOf(ids);

        for (Id id : ids) {
            System.assertEquals(lm1.get(id), lm2.get(id),
                'AC8: LastModifiedDate von ' + id + ' muss im 2. Lauf unveraendert sein (0 DML)');
        }
    }

    private static Map<Id, DateTime> lastModifiedOf(Set<Id> ids) {
        Map<Id, DateTime> m = new Map<Id, DateTime>();
        for (Account a : [SELECT Id, LastModifiedDate FROM Account WHERE Id IN :ids]) {
            m.put(a.Id, a.LastModifiedDate);
        }
        return m;
    }

    /** CreatedDate der juengsten Opportunity eines Accounts (Date) fuer Assert-Vergleich. */
    private static Date dialOppDate(Id accId) {
        return [SELECT CreatedDate FROM Opportunity
                WHERE AccountId = :accId ORDER BY CreatedDate DESC LIMIT 1][0].CreatedDate.date();
    }

    // ------------------------------------------------------------------
    // FLS (Cases 9–11): 1:1 aus dem verifizierten SCRUM-382/378-Pattern
    // ------------------------------------------------------------------

    /** Without PS: beide Felder weder lesbar noch schreibbar. */
    @isTest
    static void fls_withoutPS_bothFieldsInvisible() {
        User u = createStdUser('n');
        System.runAs(u) {
            System.assert(Account.SObjectType.getDescribe().isAccessible(),
                'Precondition: Standard User hat Account-Objektzugriff');
            System.assertEquals(false, Account.Last_Opportunity__c.getDescribe().isAccessible(),
                'Ohne PS Last_Opportunity__c nicht lesbar');
            System.assertEquals(false, Account.Last_Opportunity__c.getDescribe().isUpdateable(),
                'Ohne PS Last_Opportunity__c nicht schreibbar');
            System.assertEquals(false, Account.Is_Inactive__c.getDescribe().isAccessible(),
                'Ohne PS Is_Inactive__c nicht lesbar');
            System.assertEquals(false, Account.Is_Inactive__c.getDescribe().isUpdateable(),
                'Ohne PS Is_Inactive__c nicht schreibbar');
        }
    }

    /** Read-PS: lesbar, NICHT schreibbar (getDescribe, wie SCRUM-382/378). */
    @isTest
    static void fls_readPS_readable_notUpdatable_updateThrows() {
        User u = createStdUser('r');
        System.runAs(u) {
            System.assert(Account.SObjectType.getDescribe().isAccessible(),
                'Precondition: Standard User hat Account-Objektzugriff');
        }
        PermissionSet ps = [SELECT Id FROM PermissionSet
                            WHERE Name = 'SCRUM388_AccountReactivation' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // FLS-Beleg per getDescribe(), 1:1 aus dem verifizierten SCRUM-382/378-
        // Pattern: lesbar, aber NICHT schreibbar (editable=false). Bewusst KEIN
        // DML-Wurf: ein Update-Fehler koennte auch an Objekt-CRUD liegen
        // ("falscher Grund"); isUpdateable() trifft exakt die FLS-Zusage.
        System.runAs(u) {
            System.assertEquals(true, Account.Last_Opportunity__c.getDescribe().isAccessible(),
                'Read-PS: lesbar');
            System.assertEquals(false, Account.Last_Opportunity__c.getDescribe().isUpdateable(),
                'Read-PS: nicht schreibbar');
            System.assertEquals(true, Account.Is_Inactive__c.getDescribe().isAccessible(),
                'Read-PS: lesbar');
            System.assertEquals(false, Account.Is_Inactive__c.getDescribe().isUpdateable(),
                'Read-PS: nicht schreibbar');
        }
    }

    /** Write-PS: schreibbar (getDescribe: isUpdateable true beider Felder). */
    @isTest
    static void fls_writePS_updatable_updateSucceeds() {
        User u = createStdUser('w');
        System.runAs(u) {
            System.assert(Account.SObjectType.getDescribe().isAccessible(),
                'Precondition: Standard User hat Account-Objektzugriff');
        }
        PermissionSet ps = [SELECT Id FROM PermissionSet
                            WHERE Name = 'SCRUM388_AccountReactivationWrite' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        // FLS-Beleg per getDescribe(): schreibbar (editable=true) auf beiden.
        // Beweist die Update-FLS, die der Batch-Lauf-User braucht (ADR-5/6).
        // 1:1 mit dem verifizierten SCRUM-382/378-Pattern (keine DML; ein
        //  Schreib-Erfolg hielte auch von Objekt-CRUD ab => FLS nicht isoliert).
        System.runAs(u) {
            System.assertEquals(true, Account.Is_Inactive__c.getDescribe().isAccessible(),
                'Write-PS: lesbar');
            System.assertEquals(true, Account.Is_Inactive__c.getDescribe().isUpdateable(),
                'Write-PS: schreibbar');
            System.assertEquals(true, Account.Last_Opportunity__c.getDescribe().isAccessible(),
                'Write-PS: lesbar');
            System.assertEquals(true, Account.Last_Opportunity__c.getDescribe().isUpdateable(),
                'Write-PS: schreibbar');
        }
    }
}
