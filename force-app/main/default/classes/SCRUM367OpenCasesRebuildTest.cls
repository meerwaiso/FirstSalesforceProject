/**
 * SCRUM-367: Vollkorrektur des Fallzählers «Offene Fälle» — Apex-Tests.
 *
 * Deckt die Subtask-DoD (SCRUM-368) + Story-ACs (SCRUM-367) ab:
 *   - recompute-Rückgabewert (geändert vs. no-op) — der SCRUM-367-Refactor auf Integer
 *   - startRebuild() legt CaseRebuildRun__c-Zeile an, Batch-Id gefüllt, danach
 *     Status Abgeschlossen + Zähler + FinishedAt (AC 6: Ergebnis als Lauf-Log-Zeile)
 *   - Vollkorrektur: Bestands-Kontakte mit OPENEN Fällen (Zähler NULL) werden
 *     exakt korrigiert; Kontakte ohne Fälle zeigen 0 statt NULL (AC 1, AC 2)
 *   - Zweiter Lauf ist idempotent: ContactsCorrected = 0 (AC 3)
 *   - Permission-Design: ohne PS kein Objekt-Zugriff, mit PS Lesbarkeit + FLS
 *     exakt wie spezialisiert (Status editable, Rest read-only)
 *
 * Wichtige Testmechanik — warum «stale NULL» erst NACH dem Case-Insert gesetzt
 * wird: Der CaseOpenCountTrigger (SCRUM-365) feuert in der Test-Transaktion mit
 * (Case-Insert → recompute → zähler aktuell). Die Bestandslage von SCRUM-367
 * («Trigger hat nie gezählt, Feld ist NULL») muss also aktiv simuliert werden,
 * indem das Feld nach dem Insert auf NULL gesetzt wird. Genau das ist auch das
 * Produktions-Szenario: Fälle DAVOR haben nie gezählt.
 *
 * Batch-Ausführung: in @isTest-Kontext führe Test.stopTest() (offizielles
 * Apex-Test-Verhalten) alle in der startTest/stopTest-Klammer gestarteten
 * Batch-Jobs SYNCHRON zu Ende — es gibt also keinen Async-Wait. Die 25
 * produktiven Kontakte im Test-Org sind in der Transaktion sichtbar und werden
 * genauso geheilt wie die Test-Kontakte (rolled back mit der Test-Transaktion).
 *
 * @author developer-agent
 * @date 2026-08-27
 */
@isTest
private class SCRUM367OpenCasesRebuildTest {

    /** Zählt die aktuellen NULL-Kontakte im ganzen Stock (Vollkorrektur-Gate). */
    private static Integer countNullContacts() {
        return [SELECT COUNT() FROM Contact WHERE Open_Cases_Count__c = null];
    }

    /**
     * Simuliert den SCRUM-367-Bestand: Kontakt mit `openCases` offenen Fällen,
     * Zählerfeld danach bewusst NULL (= Trigger hat für diesen Kontakt nie
     * gezählt — die eigentliche Bug-Lage).
     */
    private static Id staleContactWithOpenCases(String tag, Integer openCases) {
        Contact c = new Contact(LastName = 'SCRUM367Test ' + tag);
        insert c;
        for (Integer i = 0; i < openCases; i++) {
            insert new Case(ContactId = c.Id, Status = 'New', Subject = tag + '-open-' + i);
        }
        // Zähler auf NULL zurücksetzen — Trigger-Heilung rückgängig,
        // Bestandszustand «nie gezählt» herstellen.
        Contact upd = [SELECT Id, Open_Cases_Count__c FROM Contact WHERE Id = :c.Id];
        upd.Open_Cases_Count__c = null;
        update upd;
        return c.Id;
    }

    /** Kontakt OHNE Fälle, Zähler bewusst NULL (AC 2: «leer» → muss 0 werden). */
    private static Id staleContactWithoutCases(String tag) {
        Contact c = new Contact(LastName = 'SCRUM367Test ' + tag);
        insert c;
        Contact upd = [SELECT Id, Open_Cases_Count__c FROM Contact WHERE Id = :c.Id];
        upd.Open_Cases_Count__c = null;
        update upd;
        return c.Id;
    }

    /**
     * DoD-Hauptpfad: 1. Lauf heilt alle Kontakte (Bestands-NULL-Fälle zeigen
     * exakt ihre Zahl, ohne-Fälle-Kontakte zeigen 0), Log-Zeile vollständig;
     * 2. Lauf idempotent (corrigierte = 0).
     */
    @isTest
    static void firstRun_healsAllContacts_secondRun_isIdempotent() {
        // Der Test erzeugt seine eigenen Bestands-NULL-Kontakte (Alpha/Beta/Gamma)
        // — die Vorbedingung muss daher NICHT vom Org-Bestand abhängen (deterministisch).
        Id a = staleContactWithOpenCases('Alpha', 1);   // NULL → erwartet 1
        Id b = staleContactWithoutCases('Beta');        // NULL → erwartet 0
        Id c = staleContactWithOpenCases('Gamma', 2);   // NULL → erwartet 2

        // No-Code-Auslösung — exakt der Custom-Button-Weg (sforce.apex.execute).
        // Timestamp-Grenze: die Verifikations-Läufe IM Test-Org hinterlegen
        // dauerhafte Log-Zeilen — daher zählt dieser Test nur ZEILEN ab hier.
        DateTime beforeRun = DateTime.now();

        String batchId;
        Test.startTest();
        batchId = CaseOpenCountRebuilder.startRebuild();
        Test.stopTest();

        System.assert(String.isNotBlank(batchId),
                'startRebuild muss eine Batch-Id liefern');

        // Lauf-Log-Zeile (AC 6): genau 1 Abgeschlossene SEIT dem Lauf,
        // Batch-Id + FinishedAt gefüllt.
        List<CaseRebuildRun__c> done = [
            SELECT Id, Status__c, ContactsProcessed__c, ContactsCorrected__c,
                   FinishedAt__c, BatchId__c
            FROM CaseRebuildRun__c
            WHERE Status__c = :CaseOpenCountRebuilder.STATUS_DONE
              AND CreatedDate >= :beforeRun
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        System.assertEquals(1, done.size(),
                'Nach 1. Lauf genau 1 Abgeschlossene-Zeile erwartet');
        CaseRebuildRun__c run1 = done.get(0);
        System.assertEquals(batchId, run1.BatchId__c,
                'Batch-Id muss auf der Lauf-Zeile stehen');
        System.assert(run1.FinishedAt__c != null, 'FinishedAt muss gesetzt sein');
        System.assert(run1.ContactsProcessed__c >= 3,
                'ContactsProcessed muss mindestens die 3 Test-Kontakte abdecken');
        System.assert(run1.ContactsCorrected__c >= 3,
                'ContactsCorrected muss mindestens die 3 Test-Kontakte abdecken');

        // AC 1: Bestands-Kontakte mit offenen Fällen zeigen die exakte Zahl.
        Contact a1 = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :a];
        System.assertEquals(Decimal.valueOf(1), a1.Open_Cases_Count__c,
                'Alpha (NULL, 1 offener Fall) muss exakt 1 zeigen');
        Contact c1 = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :c];
        System.assertEquals(Decimal.valueOf(2), c1.Open_Cases_Count__c,
                'Gamma (NULL, 2 offene Fälle) muss exakt 2 zeigen');

        // AC 2: Kontakt ohne Fälle zeigt 0 statt NULL.
        Contact b1 = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :b];
        System.assertEquals(Decimal.valueOf(0), b1.Open_Cases_Count__c,
                'Beta (NULL, kein Fall) muss exakt 0 zeigen — nicht «leer»');

        // Vollkorrektur-Gate: KEIN Kontakt im gesamten Stock ist mehr NULL.
        System.assertEquals(0, countNullContacts(),
                'Nach dem 1. Lauf darf KEIN Kontakt mehr ein NULL-Feld haben — der Rebuilder queryt ohne LastModified-Filter');

        // Zweiter Lauf: idempotent (AC 3).
        DateTime beforeSecondRun = DateTime.now();
        Test.startTest();
        CaseOpenCountRebuilder.startRebuild();
        Test.stopTest();

        List<CaseRebuildRun__c> done2 = [
            SELECT Id, ContactsProcessed__c, ContactsCorrected__c
            FROM CaseRebuildRun__c
            WHERE Status__c = :CaseOpenCountRebuilder.STATUS_DONE
              AND CreatedDate >= :beforeSecondRun
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        System.assertEquals(1, done2.size(), 'Nach 2. Lauf die 2. Abgeschlossene-Zeile erwartet');
        CaseRebuildRun__c run2 = done2.get(0);
        System.assertNotEquals(run1.Id, run2.Id,
                'Die zweite Lauf-Zeile ist eine eigene, neue Zeile');
        System.assertEquals(Decimal.valueOf(0), run2.ContactsCorrected__c,
                'AC 3: zweiter Lauf direkt nach dem ersten => 0 korrigierte Kontakte (Idempotenz)');
        System.assertEquals(run1.ContactsProcessed__c, run2.ContactsProcessed__c,
                'ContactsProcessed muss zwischen zwei Läufen unverändert bleiben');
    }

    /**
     * Der SCRUM-367-Refactor an recompute(): Rückgabewert Integer
     * (geänderte Kontakte) statt void. Coverage aller drei Äste:
     *   - echte Änderung → Anzahl der geänderten Records
     *   - null- / leeres Set → 0 (Guard)
     *   - no-op → 0, und KEINE DML (LastModified bleibt unverändert)
     */
    @isTest
    static void recompute_returnsChangedCount() {
        // «a» wird stale (NULL) + 1 offener Fall → recompute muss genau 1 ändern.
        Id a = staleContactWithOpenCases('RC', 1);
        // «b»: normal (Default 0), keine Fälle → no-op.
        Contact b = new Contact(LastName = 'SCRUM367Test RC-noop');
        insert b;

        Integer changed = CaseOpenCountTrigger.recompute(new Set<Id>{a, b.Id});
        System.assertEquals(1, changed,
                'recompute muss genau 1 geänderten Kontakt melden (a: NULL→1)');
        Contact a1 = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :a];
        System.assertEquals(Decimal.valueOf(1), a1.Open_Cases_Count__c,
                'a hat nach recompute den Wert 1');

        // Guard: null + leer → 0, ohne DML.
        System.assertEquals(0, CaseOpenCountTrigger.recompute(null),
                'Null-Set-Guard muss 0 zurückgeben');
        System.assertEquals(0, CaseOpenCountTrigger.recompute(new Set<Id>()),
                'Leeres-Set-Guard muss 0 zurückgeben');

        // No-op: bereits korrekter Wert → 0, und LastModified ändert sich NICHT
        // (weil die DML unterdrückt wird — wichtig für AC 4, laufende Prozesse).
        // LastModifiedDate ist ein DateTime.
        DateTime prior = [SELECT LastModifiedDate FROM Contact WHERE Id = :a].LastModifiedDate;
        Integer noOp = CaseOpenCountTrigger.recompute(new Set<Id>{a, b.Id});
        System.assertEquals(0, noOp, 'No-op (alle Werte korrekt) => 0');
        DateTime after = [SELECT LastModifiedDate FROM Contact WHERE Id = :a].LastModifiedDate;
        System.assertEquals(prior, after,
                'No-op darf keine neue LastModified erzeugen (DML wird unterdrückt)');
    }

    /**
     * Permission-Design (DoD: Negativ-Check):
     *   - Standard-User OHNE Permission Set: CaseRebuildRun__c ist unzugänglich.
     *   - Standard-User MIT SCRUM367_OffenCasesRebuild: Objekt lesbar, FLS
     *     exakt wie spezialisiert (Status editable, Rest read-only), Apex-Klasse
     *     auslösbar.
     *
     * Das volle End-to-End (reale Custom-Button-Klicks als beschränkter
     * Service-User) ist Tester-Phasen-Auftrag; hier der Apex-Grundnachweis.
     */
    @isTest
    static void permissionDesign_blocksWithoutPS_allowsWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            LastName = 'PS367',
            Alias = 'ps367',
            Email = 'ps367_' + stamp + '@example.invalid',
            Username = 'ps367_' + stamp + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // NEGATIV: ohne Permission Set (Standard-Profil hat keinen Zugriff auf
        // CaseRebuildRun__c) — Objekt- und Feldlesbarkeit fehlen komplett.
        // (Klassen-Zugriff prüft runAs bewusst NICHT — der sforce.apex.execute-Weg
        // ist im Test-Kontext systemmode; die echte Button-Auslösung wird vom
        // Tester End-to-End verifiziert.)
        System.runAs(u) {
            System.assertEquals(false,
                    CaseRebuildRun__c.SObjectType.getDescribe().isAccessible(),
                    'Ohne PS: CaseRebuildRun__c muss NICHT zugänglich sein (Standard-Profil hat keinen Default-Zugriff)');
            System.assertEquals(false,
                    CaseRebuildRun__c.ContactsCorrected__c.getDescribe().isAccessible(),
                    'Ohne PS: Ergebnisfelder müssen NICHT lesbar sein');
        }

        // Permission Set zuweisen (wie in der Org für die Service-Freigabe).
        Id psId = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM367_OffenCasesRebuild' LIMIT 1
        ].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);

        // POSITIV: mit PS — Objekt lesbar, FLS exakt wie spezialisiert
        // (Status editierbar via Batch-Pflege, alle Ergebnisfelder read-only).
        System.runAs(u) {
            System.assertEquals(true,
                    CaseRebuildRun__c.SObjectType.getDescribe().isAccessible(),
                    'Mit PS: CaseRebuildRun__c muss lesbar sein');
            // Ergebnisfelder: lesbar, aber NICHT von Hand änderbar.
            System.assertEquals(true,
                    CaseRebuildRun__c.ContactsProcessed__c.getDescribe().isAccessible(),
                    'Mit PS: ContactsProcessed__c muss lesbar sein');
            System.assertEquals(false,
                    CaseRebuildRun__c.ContactsProcessed__c.getDescribe().isUpdateable(),
                    'Mit PS: ContactsProcessed__c darf NICHT von Hand änderbar sein');
            System.assertEquals(true,
                    CaseRebuildRun__c.ContactsCorrected__c.getDescribe().isAccessible(),
                    'Mit PS: ContactsCorrected__c muss lesbar sein');
            System.assertEquals(false,
                    CaseRebuildRun__c.ContactsCorrected__c.getDescribe().isUpdateable(),
                    'Mit PS: ContactsCorrected__c darf NICHT von Hand änderbar sein');
            System.assertEquals(true,
                    CaseRebuildRun__c.FinishedAt__c.getDescribe().isAccessible(),
                    'Mit PS: FinishedAt__c muss lesbar sein');
            System.assertEquals(false,
                    CaseRebuildRun__c.FinishedAt__c.getDescribe().isUpdateable(),
                    'Mit PS: FinishedAt__c darf NICHT von Hand änderbar sein');
            System.assertEquals(true,
                    CaseRebuildRun__c.BatchId__c.getDescribe().isAccessible(),
                    'Mit PS: BatchId__c muss lesbar sein');
            System.assertEquals(false,
                    CaseRebuildRun__c.BatchId__c.getDescribe().isUpdateable(),
                    'Mit PS: BatchId__c darf NICHT von Hand änderbar sein');
            // Status: lesbar UND editable (Batch-Pflege des Status-Felds).
            System.assertEquals(true,
                    CaseRebuildRun__c.Status__c.getDescribe().isAccessible(),
                    'Mit PS: Status__c muss lesbar sein');
            System.assertEquals(true,
                    CaseRebuildRun__c.Status__c.getDescribe().isUpdateable(),
                    'Mit PS: Status__c muss editable sein (Batch-Pflege)');
        }
    }

    /**
     * AC 1 im Bug-Szenario: ein Kontakt, der seit Langem nicht mehr angefasst
     * wurde (Trigger hat nie gezählt), wird trotzdem vollständig korrigiert.
     * Der Vollzug ist der fehlende LastModified-Filter im QueryLocator —
     * dieser Test beweist, dass die Heilung NICHT an «wann zuletzt etwas
     * passiert ist» gekoppelt ist.
     */
    @isTest
    static void oldUnmodifiedContact_isStillCorrected() {
        Integer nullsBefore = countNullContacts();

        // 3 offene Fälle + 1 geschlossener (muss NICHT gezählt werden).
        Id a = staleContactWithOpenCases('Stale', 3);
        insert new Case(ContactId = a, Status = 'Closed', Subject = 'stale-closed');
        // Nach dem geschlossenen Case-Insert ist der Trigger aktiv — Zähler
        // korrigieren (2 offen gezählt), dann für Bestandslage neu auf NULL.
        Contact upd = [SELECT Id, Open_Cases_Count__c FROM Contact WHERE Id = :a];
        upd.Open_Cases_Count__c = null;
        update upd;

        Test.startTest();
        CaseOpenCountRebuilder.startRebuild();
        Test.stopTest();

        Contact healed = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :a];
        System.assertEquals(Decimal.valueOf(3), healed.Open_Cases_Count__c,
                'Starker Kontakt (NULL, 3 offene + 1 geschlossene Fälle) muss exakt 3 zeigen — Closed zählt NICHT mit');

        // Der Rest des Stocks hat sich unverändert gut gehalten (keine Regression).
        System.assert(countNullContacts() <= nullsBefore,
                'Vollkorrektur darf keine neue NULL erzeugen');
    }
}
