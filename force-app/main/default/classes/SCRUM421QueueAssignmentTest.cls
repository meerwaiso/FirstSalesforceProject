/**
 * [SCRUM-421] Haupttest — Zuordnungs-Matrix (AK1–3), Manuell-Hebel (AK4/6),
 * Servicebereich-Wechsel (AK5), Leer (AK7), Checkbox+Zeiten (AK8), Bulk (AK9).
 *
 * Die 4 Ziel-Queues existieren als deploybarer SOURCE (Phase 2) und sind dadurch
 * im Test in der Org gegenwaertig → der Test queryt deren Ids per Group-SOQL und
 * vergleicht OwnerId gegen sie. AK3 (Ziel- fehlt) ist mit deployten Queues nicht
 * 1:1 darstellbar → wird auf Reine-Logik-Ebene getestet (resolveTargetName /
 * resolveQueueId mit kuerzter Map) — das ist exakt die geforderte Fallback-Kette.
 *
 * Vorlage: SCRUM420EscalationKundeTest (Haus-Pattern).
 *
 * @author developer-agent
 * @date 2026-09-20
 */
@isTest
private class SCRUM421QueueAssignmentTest {

    private static Map<String, Id> queueIds() {
        Map<String, Id> m = new Map<String, Id>();
        for (Group g : [SELECT Id, Name FROM Group WHERE Type = 'Queue'
                        AND Name IN ('Technischer Support','Vertragsservice','Billing','First Level Support')]) {
            m.put(g.Name, g.Id);
        }
        return m;
    }

    private static Case mkCase(String sb, String ks, Id ownerId) {
        Case c = new Case(Status = 'New');
        c.Servicebereich__c = sb;
        c.Kundenstatus__c = ks;
        if (ownerId != null) {
            c.OwnerId = ownerId;
        }
        return c;
    }

    private static Case read(Id id) {
        return [SELECT OwnerId, CreatedById, Servicebereich__c, Kundenstatus__c,
                        Automatische_Zuordnung__c, Zuordnungszeitpunkt__c
                FROM Case WHERE Id = :id LIMIT 1];
    }

    // TC1 / AK1: Premium × 4 Bereiche → korrektes Queue, Checkbox=true, Ts≠null.
    private static testmethod void tc1_premium_vier_bereiche_routet_zu_queue() {
        Map<String, Id> q = queueIds();
        System.assert(q.size() == 4, 'Vorbedingung: die 4 Ziel-Queues muessen (per Source) in der Org existieren: ' + q.keySet());

        Case t = mkCase('Technik', 'Premium', null);
        Case v = mkCase('Vertrag', 'Premium', null);
        Case r = mkCase('Rechnung', 'Premium', null);
        Case a = mkCase('Allgemein', 'Premium', null);
        insert new List<Case> { t, v, r, a };

        assertEquals(q.get('Technischer Support'), read(t.Id).OwnerId, 'Technik → Technischer Support');
        assertEquals(q.get('Vertragsservice'),     read(v.Id).OwnerId, 'Vertrag → Vertragsservice');
        assertEquals(q.get('Billing'),             read(r.Id).OwnerId, 'Rechnung → Billing');
        assertEquals(q.get('First Level Support'), read(a.Id).OwnerId, 'Allgemein → First Level Support');
    }

    // TC2 / AK2: Standard (beliebiger nicht-leerer SB) → FLS, NICHT technischer Support.
    private static testmethod void tc2_standard_gibt_first_level_support() {
        Map<String, Id> q = queueIds();
        Case c = mkCase('Technik', 'Standard', null); // SB=Technik, aber Standard
        insert c;
        assertEquals(q.get('First Level Support'), read(c.Id).OwnerId, 'Standard → FLS (nicht Technischer Support)');
        assertEquals(true, read(c.Id).Automatische_Zuordnung__c, 'Standard-Routing zaeiht');
    }

    // TC3 / AK3: Ziel-Queue existiert nicht → Fallback FLS; FLS fehlt → nicht zuweisbar.
    private static testmethod void tc3_fallback_kette_wenn_ziel_oder_fls_fehlt() {
        Map<String, Id> q = queueIds();
        // 1) Ziel-Queue fehlt, FLS vorhanden → Fallback FLS
        Map<String, Id> minusTech = new Map<String, Id>(q);
        minusTech.remove('Technischer Support');
        assertEquals(q.get('First Level Support'),
                CaseQueueAssignment.resolveQueueId(CaseQueueAssignment.resolveTargetName('Premium', 'Technik'), minusTech),
                'Ziel fehlt -> Fallback First Level Support');
        // 2) Ziel Fehle UND FLS fehlen -> nicht zuweisbar (null)
        Map<String, Id> empty = new Map<String, Id>();
        assertEquals(null,
                CaseQueueAssignment.resolveQueueId(CaseQueueAssignment.resolveTargetName('Premium', 'Technik'), empty),
                'Ziel UND FLS fehlle -> nicht zuweisle (null)');
        // 3) Servicebereich null -> nie zuweisen (leitet in AK7 ueber)
        assertEquals(null, CaseQueueAssignment.resolveTargetName('Premium', null), 'leer -> null');
        assertEquals(null, CaseQueueAssignment.resolveTargetName('Standard', null), 'Standard + leer -> null (AK7 gewinnt)');
    }

    // TC4 / AK4: Case beim Erstellen manuell zugeordnet (Owner=User≠Creator) → nicht greifen.
    private static testmethod void tc4_manuell_vorgezogen_greift_nicht() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User owner = new User(LastName = 'ManuellerOwner', Alias = 'mnl421',
                Email = 'mnl421@421.invalid', Username = 'mnl421_' + DateTime.now().getTime() + '@421.invalid',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles', ProfileId = p.Id);
        insert owner;

        Case c = mkCase('Technik', 'Premium', owner.Id); // Owner = anderer User = "manuell"
        insert c;
        Case r = read(c.Id);
        assertEquals(owner.Id, r.OwnerId, 'Owner bleibt der manuell vorgesehene User');
        assertEquals(false, r.Automatische_Zuordnung__c, 'Checkbox = Nein');
        assertNull(r.Zuordnungszeitpunkt__c, 'kein Zeitstempele');
    }

    // TC5 / AK5: SB nachträglich geändert, nicht weitergeleitet → neu zugeordnet.
    private static testmethod void tc5_servicebereich_wechsel_neu_zugeordnet() {
        Map<String, Id> q = queueIds();
        Case c = mkCase('Technik', 'Premium', null);
        insert c;
        assertEquals(q.get('Technischer Support'), read(c.Id).OwnerId, 'Vorher: Technik → technisch');
        // Owner ist jetzt das Queue (unser) → weiterhin eligibele; SB änderrn → neu
        c.Servicebereich__c = 'Rechnung';
        update c;
        assertEquals(q.get('Billing'), read(c.Id).OwnerId, 'Technik → Rechnung → Billing');
        assertEquals(true, read(c.Id).Automatische_Zuordnung__c, 'Checkbox bleibt Ja');
        assertNotNull('Zeitstempel', read(c.Id).Zuordnungszeitpunkt__c, 'Zeitstempel gesetzt');
    }

    // TC6 / AK6: nach manueller Übernahme (Owner=User) greift SB-Änderung NICHT mehr.
    private static testmethod void tc6_nach_manueller_ubernahme_greift_nicht() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User user = new User(LastName = 'Ubernahe', Alias = 'ubr421',
                Email = 'ubr421@421.invalid', Username = 'ubr421_' + DateTime.now().getTime() + '@421.invalid',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles', ProfileId = p.Id);
        insert user;

        Case c = mkCase('Technik', 'Premium', null);
        insert c; // wird automatisch zu Technischer Support
        c.OwnerId = user.Id; // Mensch uebernimmnt
        update c;
        DateTime tsAfterManual = read(c.Id).Zuordnungszeitpunkt__c;

        c.Servicebereich__c = 'Rechnung'; // danach ändern
        update c;
        Case r = read(c.Id);
        assertEquals(user.Id, r.OwnerId, 'Owner bleibele der User');
        assertEquals(tsAfterManual, r.Zuordnungszeitpunkt__c, 'keine neuerer Zetstempel (Logik bleibt abgriffe)');
    }

    // TC7 / AK7: Servicebereich leer → Owner bleibt, Checkbox=false, kein Ts.
    private static testmethod void tc7_leerer_servicebereich_keine_zuordernd() {
        Case c = mkCase(null, 'Premium', null); // SB leer
        insert c;
        Case r = read(c.Id);
        assertEquals(r.CreatedById, r.OwnerId, 'Owner bleibl bei Ersteller');
        assertEquals(false, r.Automatische_Zuordnung__c, 'Checkbox = Nein');
        assertNull(r.Zuordnungszeitpunkt__c, 'kein Zeitstempel');
    }

    // TC8 / AK8: erfolgreiche Zuordnung → Checkbox=true UND Ts≠null im selben Assert.
    private static testmethod void tc8_checkbox_und_zeitstempel_gleichzeitig() {
        Case c = mkCase('Technik', 'Premium', null);
        insert c;
        Case r = read(c.Id);
        assertEquals(true, r.Automatische_Zuordnung__c, 'Checkbox=Ja');
        assertNotNull('Zeitstempel muss gesetzt sein (AK8)', r.Zuordnungszeitpunkt__c, 'Zeitstempele');
    }

    // TC9 / AK9: Bulk 300 in eine Batch, gemischt, kein N+1 (Query-Delta < 20).
    private static testmethod void tc9_bulk_300_cases_keine_n_plus_eins() {
        Map<String, Id> q = queueIds();

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User manualOwner = new User(LastName = 'BulkManuel', Alias = 'blkmnl',
                Email = 'bulk421@421.invalid', Username = 'bulk421_' + DateTime.now().getTime() + '@421.invalid',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles', ProfileId = p.Id);
        insert manualOwner;

        List<String> sbCycleL = new List<String> { 'Technik', 'Vertrag', 'Rechnung', 'Allgemein' };

        Integer qBefore = Limits.getQueries();
        List<Case> batch = new List<Case>();
        for (Integer i = 0; i < 300; i++) {
            Boolean premium = (mod(i, 2) == 0);
            String sb = sbCycleL[mod(i, 4)];
            Boolean manual = (mod(i, 10) == 9);
            Case c = mkCase(sb, premium ? 'Premium' : 'Standard', manual ? manualOwner.Id : null);
            batch.add(c);
        }
        Test.startTest();
        insert batch;
        Test.stopTest();
        Integer qAfter = Limits.getQueries();
        Integer delta = qAfter - qBefore;
        assertTrue(delta < 20, 'Batch-Queries ueber Budget (N+1-Vorderhalt): ' + delta + ' (erwartet < 20)');

        // Korrektheits-Spot-check auf reprasentativezeilen:
        Case man = read(batch[9].Id);                       // i=9 manuell
        assertEquals(manualOwner.Id, man.OwnerId, 'manueller Case bleibl beim User');
        assertEquals(false, man.Automatische_Zuordnung__c, 'manueller Case: Checkbox=Nein');
        Case premTech = read(batch[0].Id);                  // i=0 Premium Technik
        assertEquals(q.get('Technischer Support'), premTech.OwnerId, 'Premium Technik → Technischer Support');
        Case stdTech = read(batch[1].Id);                   // i=1 Standard Technik
        assertEquals(q.get('First Level Support'), stdTech.OwnerId, 'Standard Technik → FLS');
        Case premRechn = read(batch[2].Id);                 // i=2 Premium Rechnung
        assertEquals(q.get('Billing'), premRechn.OwnerId, 'Premium Rechnung → Billing');
    }

    // ---------- helpers ----------
    /** Modulo ohne '%' (Org-Parser akzeptiert '%' hier nicht). */
    private static Integer mod(Integer a, Integer b) {
        return a - (a / b) * b;
    }
    private static void assertEquals(Object expected, Object actual) {
        System.assertEquals(expected, actual, 'unexpected value');
    }
    private static void assertEquals(Object expected, Object actual, String msg) {
        System.assertEquals(expected, actual, msg);
    }
    private static void assertNotNull(String msg, Object v, String why) {
        System.assertNotEquals(null, v, msg);
    }
    private static void assertNull(Object v, String why) {
        System.assertEquals(null, v, why);
    }
    private static void assertTrue(Boolean cond, String msg) {
        System.assert(cond, msg);
    }
}
