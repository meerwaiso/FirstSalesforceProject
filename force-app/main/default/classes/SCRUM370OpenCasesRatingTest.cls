/**
 * SCRUM-370: Einstufung «Offene Fälle» am Contact (Open_Cases_Rating__c) — Apex-Tests.
 *
 * Deckt die Subtask-DoD (SCRUM-371) + Story-ACs (SCRUM-370) ab:
 *   - Grenzwert-Einheiten fuer deriveRating: 0 / 1 / 2 / 3 / 4 / 5 / 6 (inklusive Grenzen)
 *   - End-to-End ueber Case-Events: 0 offene -> Unauffaellig, 1 und 2 -> Normal,
 *     3 und 4 -> Erhoeht, 5 und mehr -> Kritisch (Zaehler + Einstufung in derselben DML)
 *   - AK Senkung: 3 offene (Erhoeht), einer wird geschlossen -> 2 -> Normal
 *   - First-Write: Bestands-Contact mit NULL-Zaehler wird beim naechsten Case-Event
 *     mit Zaehler 0 und Rating Unauffaellig geschrieben (wie SCRUM-367)
 *   - No-op: Case-Update ohne Status-/ContactId-Wechsel aendert weder Rating noch
 *     LastModifiedDate (DML unterdrueckt, exakte SCRUM-365-Logik)
 *   - FLS (Hause-Pattern SCRUM-353/359): User OHNE PS SCRUM365_OpenCasesCount darf
 *     das Feld NICHT lesen (Negativ); mit PS wird es lesbar, aber NICHT editierbar
 *     (read-only-Enforcement: editable=false im PS).
 *
 * Mechanik: Der CaseOpenCountTrigger (SCRUM-365/370) feuert in der Test-Transaktion
 * mit. «offen» = Case.Status != 'Closed' (CaseOpenCountTrigger.CLOSED_STATUS).
 * Alles, was hier erzeugt wird, rollt mit der Test-Transaktion rueck.
 *
 * @author developer-agent
 * @date 2026-08-29
 */
@isTest
private class SCRUM370OpenCasesRatingTest {

    /** Erzeugt einen Contact ohne Aussenbeziehungen, die den Zähler stören würden. */
    private static Id makeContact(String tag) {
        Contact c = new Contact(LastName = 'Scr70 ' + tag);
        insert c;
        return c.Id;
    }

    /** Erzeugt `n` offene Fälle (Status 'New') für den Contact. */
    private static void openCases(Id contactId, Integer n) {
        for (Integer i = 0; i < n; i++) {
            insert new Case(ContactId = contactId, Status = 'New', Subject = 'open ' + i);
        }
    }

    /** Schliesst genau `n` offene Cases des Contacts (Status -> 'Closed'). */
    private static void closeCases(Id contactId, Integer n) {
        List<Case> open = [
            SELECT Id FROM Case WHERE ContactId = :contactId AND Status != 'Closed'
            LIMIT :n
        ];
        for (Case cc : open) {
            cc.Status = 'Closed';
        }
        update open.size() > 0 ? open : new List<Case>();
    }

    private static Contact read(String id) {
        return [SELECT Open_Cases_Count__c, Open_Cases_Rating__c FROM Contact WHERE Id = :id];
    }

    /** AK-Grenzwerte des reinen Mappings — exakt inklusive Grenzen. */
    @isTest
    static void deriveRating_boundaryValues() {
        System.assertEquals('Unauffaellig', CaseOpenCountTrigger.deriveRating(null),
            'NULL (nie gezählt) -> Unauffaellig');
        System.assertEquals('Unauffaellig', CaseOpenCountTrigger.deriveRating(0), '0 -> Unauffaellig');
        System.assertEquals('Normal', CaseOpenCountTrigger.deriveRating(1), '1 -> Normal');
        System.assertEquals('Normal', CaseOpenCountTrigger.deriveRating(2), '2 (inklusiv Grenze) -> Normal');
        System.assertEquals('Erhoeht', CaseOpenCountTrigger.deriveRating(3), '3 -> Erhoeht');
        System.assertEquals('Erhoeht', CaseOpenCountTrigger.deriveRating(4), '4 (inklusiv Grenze) -> Erhoeht');
        System.assertEquals('Kritisch', CaseOpenCountTrigger.deriveRating(5), '5 (inklusiv Grenze) -> Kritisch');
        System.assertEquals('Kritisch', CaseOpenCountTrigger.deriveRating(6), '6 -> Kritisch');
        System.assertEquals('Kritisch', CaseOpenCountTrigger.deriveRating(42), '>=5 -> Kritisch');
    }

    /** End-to-End über echte Case-Events: Zaehler + Einstufung stimmen fuer 0..6. */
    @isTest
    static void caseEvents_deriveCorrectRatingFor0To6() {
        // expected[want] = Einstufung, die exakt nach `want` offenen Fällen stehen muss.
        Map<Integer, String> expected = new Map<Integer, String>{
            0 => 'Unauffaellig', 1 => 'Normal', 2 => 'Normal',
            3 => 'Erhoeht', 4 => 'Erhoeht', 5 => 'Kritisch', 6 => 'Kritisch'
        };
        for (Integer want : expected.keySet()) {
            Id cid = makeContact('E2E' + want);
            if (want > 0) {
                openCases(cid, want);   // nach letztem Insert: recompute -> count=want
            } else {
                // 0 offene: Contact hat das Feld-Default (0 / Unauffaellig). Ein
                // no-op-Case-Event (Case anlegen, sofort schliessen) zwingt einen
                // echten Recompute-Lauf ueber den Trigger, nicht nur das Default.
                Case tmp = new Case(ContactId = cid, Status = 'New', Subject = 'zero');
                insert tmp;
                tmp = [SELECT Id, Status FROM Case WHERE ContactId = :cid LIMIT 1];
                tmp.Status = 'Closed';
                update tmp;
            }
            Contact r = read(cid);
            System.assertEquals(Decimal.valueOf(want), r.Open_Cases_Count__c,
                'Zähler nach ' + want + ' offenen Fällen');
            System.assertEquals(expected.get(want), r.Open_Cases_Rating__c,
                'Einstufung nach ' + want + ' offenen Fällen');
        }
    }

    /** AK Senkung: 3 offen (Erhoeht) -> einer geschlossen -> 2 -> Normal. */
    @isTest
    static void ratingDropsWhenCaseCountFallsBelowThreshold() {
        Id cid = makeContact('Reduc');
        openCases(cid, 3);
        System.assertEquals('Erhoeht', read(cid).Open_Cases_Rating__c, 'Start: 3 offen = Erhoeht');

        closeCases(cid, 1);
        Contact r = read(cid);
        System.assertEquals(Decimal.valueOf(2), r.Open_Cases_Count__c, 'Nach Close: 2 offen');
        System.assertEquals('Normal', r.Open_Cases_Rating__c, 'AK: Einstufung wird gesenkt (2 = Normal)');
    }

    /** First-Write (SCRUM-367-Semantik): NULL-Zähler -> beim naechsten Case-Event Zaehler 0 + Unauffaellig. */
    @isTest
    static void firstWrite_nullCounterBecomesZeroAndUnauffaellig() {
        Id cid = makeContact('First');
        // Ein offene Fall, danach bewusst wieder NULL = «Trigger hat nie gezählt».
        openCases(cid, 1);
        Contact upd = read(cid);
        upd.Open_Cases_Count__c = null;
        update upd;

        // Nächstes Case-Event (den offenen Fall schliessen) -> openCount 0,
        // currentValue null -> mustWrite -> Zaehler 0 + Rating Unauffaellig.
        closeCases(cid, 1);
        Contact r = read(cid);
        System.assertEquals(Decimal.valueOf(0), r.Open_Cases_Count__c,
            'NULL-Zähler wird mit 0 geschrieben (nicht leer)');
        System.assertEquals('Unauffaellig', r.Open_Cases_Rating__c,
            'Erster Write bringt Rating Unauffaellig mit');
    }

    /** No-op: Case-Update ohne Status-/ContactId-Wechsel aendert weder Rating noch LastModified. */
    @isTest
    static void noRelevantCaseUpdate_leavesRatingAndLastModifiedUntouched() {
        Id cid = makeContact('Noop');
        openCases(cid, 2); // 2 offen -> Normal

        Case cc = [SELECT Id, Subject FROM Case WHERE ContactId = :cid AND Status != 'Closed' LIMIT 1];
        Contact before = [SELECT Open_Cases_Rating__c, LastModifiedDate FROM Contact WHERE Id = :cid];

        cc.Subject = 'nur Text, kein Status-/Kontaktwechsel';
        update cc; // Trigger feuert, Relevanz-Check ist false -> kein recompute, keine DML

        Contact after = [SELECT Open_Cases_Rating__c, LastModifiedDate FROM Contact WHERE Id = :cid];
        System.assertEquals('Normal', after.Open_Cases_Rating__c, 'Rating bleibt Normal');
        System.assertEquals(before.LastModifiedDate, after.LastModifiedDate,
            'No-op darf keine neue LastModified erzeugen (DML unterdrückt)');
    }

    /**
     * FLS (Hause-Pattern SCRUM-353/359): read-only-Enforcement.
     *   - User OHNE PS SCRUM365_OpenCasesCount: Feld NICHT lesbar, NICHT editierbar.
     *   - User MIT PS: Feld lesbar, aber NICHT editierbar (editable=false im PS).
     */
    @isTest
    static void fls_notReadableWithoutPS_readableButNotEditableWithPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls370',
            Alias = 'fls37',
            Email = 'fls370_' + stamp + '@example.invalid',
            Username = 'fls370_' + stamp + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // Precondition: Standard User hat Objekt-Zugriff auf Contact — sonst
        // würden die FLS-Pruefungen aus dem falschen Grund (fehlendes Objekt-CRUD)
        // «bestehen».
        System.runAs(u) {
            System.assert(
                Contact.SObjectType.getDescribe().isAccessible(),
                'Precondition: Standard User ohne Contact-Zugriff — FLS-Test waere nicht aussagekraeftig.'
            );
        }

        // NEGATIV: ohne Permission Set -> Feld unlesbar, uneditierbar.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.Open_Cases_Rating__c.getDescribe().isAccessible(),
                'Ohne PS muss Open_Cases_Rating__c NICHT lesbar sein (Negativ-Test)'
            );
            System.assertEquals(
                false, Contact.Open_Cases_Rating__c.getDescribe().isUpdateable(),
                'Ohne PS muss Open_Cases_Rating__c NICHT editierbar sein'
            );
        }

        // PS zuweisen (enthaelt Open_Cases_Rating__c: readable=true, editable=false).
        Id psId = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM365_OpenCasesCount' LIMIT 1
        ].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);

        // POSITIV: mit PS -> lesbar, aber read-only (NICHT editierbar).
        System.runAs(u) {
            System.assertEquals(
                true, Contact.Open_Cases_Rating__c.getDescribe().isAccessible(),
                'Mit PS muss Open_Cases_Rating__c lesbar sein'
            );
            System.assertEquals(
                false, Contact.Open_Cases_Rating__c.getDescribe().isUpdateable(),
                'Mit PS darf Open_Cases_Rating__c NICHT editierbar sein (read-only)'
            );
        }
    }
}
