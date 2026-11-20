/**
 * [SCRUM-434] Apex-Test-Suite: „Ursache" beim Schliessen eines Cases (Picklist) + Pflicht-Gate.
 *
 * Build-Spec: docs/SCRUM-434-design.md (Commit 5255638, byte-exakte Namen).
 * Deckt die Review-Kontrakt-ACs ab:
 *   1. test_AC1_Picklist_ExaktFuenfWerte      (AC1) — Ursache__c ist eine Picklist
 *      mit genau den 5 vom PO fixierten Werten.
 *   2. test_AC2_Geschlossen_OhneUrsache_Block (AC2) — Status „Closed" + leere
 *      Ursache__c wird per ValidationRule beim Speichern hart blockiert.
 *   3. test_AC2_Geschlossen_MitUrsache_Speichert (AC2) — mit gesetztem Wert wird
 *      gespeichert; Wert wird per Query zurueckgelesen.
 *   4. test_AC3_Offen_OhneUrsache_Speichert   (AC3) — offener Status (New) ohne
 *      Ursache ist freiwillig, das Feld bleibt null.
 *   5. test_FLS_Negativ_OhnePS               (AC5) — Standard User ohne PS:
 *      kein Read/Edit auf Ursache__c.
 *   6. test_FLS_Positiv_MitPS                (AC5) — mit PS SCRUM434_Ursache:
 *      Read UND Edit auf Ursache__c.
 *
 * Stil/Strategie 1:1 aus SCRUM381LostReasonTest (Behavioral: DML-Weg gegen die
 * ValRule, FLS via getDescribe() im runAs-Kontext, User+PSA-Setup OUTSIDE-
 * runAs). ValRules feuern im Apex-Test auf jedem DML-Weg (UI/Trigger/API/Bulk-
 * aequivalent), daher der direkte Insert/Update als Pruefstand.
 *
 * Org-Fakten (read-back Test-Org, 28.09.26): Case.Status = New | Working |
 * Escalated | Closed; nur „Closed" ist ein Closed-Status; Case hat KEIN
 * Pflichtfeld ausser Id (CaseNumber/Subject sind frei) -> Test-Insert mit
 * Subject + Status.
 */
@isTest
private class SCRUM434UrsacheTest {

    /**
     * Standard-User ohne das SCRUM-434-Permission-Set. Nur fuer die FLS-
     * Pruefungen (Tests 5/6). runAs() umgeht FLS nicht, aber der User kann
     * sich selbst kein PSA geben -> User + PermissionSetAssignment werden
     * OUTSIDE-runAs als Admin-Testrunner angelegt.
     */
    private static User createStandardUser(String suffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uname = 'scr434_' + suffix + '@test.com';
        return new User(
            ProfileId = p.Id,
            LastName = 'TestUser434' + suffix,
            Email = uname,
            Username = uname,
            Alias = 't434',
            TimeZoneSidKey = 'America/Los_Angeles', // UTC wird hier abgelehnt (org-verifiziert, SCRUM382)
            LocaleSidKey = 'en_US',                // de_DE wird hier abgelehnt (org-verifiziert, SCRUM382)
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    // 1. AC1 — die 5 PO-Labels stay; a 6th value is allowed only if it is exactly
    //    the third-party value SCRUM-464 appended, and nothing else may appear.
    //    RE-ANCHORED in SCRUM-464: the old pin "genau 5 / exakt this set" broke the
    //    drift gate as soon as a later story added a cause value (Prod-Org still
    //    has 5, Test-Org has 6). The surviving invariant is: PO-labels intact,
    //    at most one extra value, and that extra is the third-party option.
    @isTest
    static void test_AC1_Picklist_POLabelsIntact() {
        List<Schema.PicklistEntry> entries = Case.Ursache__c.getDescribe().getPicklistValues();
        Set<String> poLabels = new Set<String>{
            'How-to / Anfrage',
            'Rechnung / Abrechnung',
            'Technischer Fehler',
            'Fehlkonfiguration',
            'Kein Fehler / Keine Maßnahme'
        };
        String thirdPartyLabel = 'Drittparty / Fremdfabrik Produkt';

        String found = '';
        Integer foreign = 0;
        for (Schema.PicklistEntry e : entries) {
            String label = e.getLabel();
            found += (found == '' ? '' : ', ') + label;
            if (!poLabels.contains(label)) {
                System.assertEquals(thirdPartyLabel, label,
                    'AC1: a cause value outside the PO set is only allowed if it is exactly the third-party option');
                foreign++;
            }
        }
        // a) none of the PO-fixed labels may have vanished
        for (String po : poLabels) {
            System.assert(found.contains(po),
                'AC1: PO-Label "' + po + '" must still exist — found: ' + found);
        }
        // b) at most ONE value beyond the 5 PO labels, and every label is accounted for
        System.assert(entries.size() <= poLabels.size() + 1,
            'AC1: at most one extra cause value (the third-party option) — found: ' + entries.size() + ' (' + found + ')');
        System.assertEquals(poLabels.size() + foreign, entries.size(),
            'AC1: every cause value is either a PO label or the third-party option — found: ' + entries.size() + ' (' + found + ')');
    }

    // 2. AC2 — geschlossener Case OHNE Ursache MUSS blockiert werden (ValRule,
    //    härte Blockade, keine Warnung).
    @isTest
    static void test_AC2_Geschlossen_OhneUrsache_Block() {
        Test.startTest();
        DmlException ex = null;
        try {
            insert new Case(Subject = 'SCR434 closed ohne ursache', Customer_Satisfaction__c = 'Score_4', Status = 'Closed');
        } catch (DmlException e) {
            ex = e;
        }
        Test.stopTest();
        System.assertNotEquals(null, ex,
            'AC2: Geschlossener Case ohne Ursache MUSS beim Speichern blockiert werden');
        System.assert(String.isBlank(ex.getMessage()) == false,
            'DmlException sollte eine Fehlermeldung tragen');
        System.assert(ex.getMessage().contains('Ursache'),
            'Fehlermeldung muss „Ursache" enthalten. Tatsächlich: ' + ex.getMessage());
    }

    // 3. AC2 — geschlossener Case MIT gesetztem Wert wird gespeichert.
    @isTest
    static void test_AC2_Geschlossen_MitUrsache_Speichert() {
        User u = SCRUM442TestFixtures.satisfactionUser('434ac2a');
        System.runAs(u) {
            Case c = new Case(
                Subject = 'SCR434 closed mit ursache',
                Customer_Satisfaction__c = 'Score_4', Status = 'Closed',
                Ursache__c = 'TechnischerFehler'
            );
            insert c;
            Case r = [SELECT Status, Ursache__c FROM Case WHERE Id = :c.Id];
            System.assertEquals('Closed', r.Status);
            System.assertEquals('TechnischerFehler', r.Ursache__c,
                'AC2: Persistenter Wert muss per Query TechnischerFehler sein');
        }
    }

    // 4. AC3 — offener Case (Status New) ohne Ursache ist freiwillig.
    @isTest
    static void test_AC3_Offen_OhneUrsache_Speichert() {
        // SCRUM-434 Lücke C: PSA (setup DML) ERST, dann die non-setup DML (Case)
        // IM runAs-Block — Hausmuster SCRUM418. Setup-Außerhalb + Non-Setup-Innen;
        // beide im selben outer-Savepoint wäre MIXED_DML (in beide Richtungen).
        User u434 = SCRUM434TestFixtures.ursacheUser('434ac3');
        Case r;
        System.runAs(u434) {
            Case c = new Case(
                Subject = 'SCR434 offen ohne ursache',
                Status = 'New',
                OwnerId = u434.Id
            );
            insert c;
            r = [SELECT Status, Ursache__c FROM Case WHERE Id = :c.Id];
        }
        System.assertEquals('New', r.Status);
        System.assertEquals(null, r.Ursache__c,
            'AC3: Offener Case ohne Ursache muss das Feld null lassen');
    }

    // 5. AC5 — FLS negativ: Standard User OHNE das SCRUM-434-PS hat weder Read
    //    noch Edit auf Ursache__c (Default = kein Zugriff, FLS wird nicht von
    //    Object-CRUD geerbt).
    @isTest
    static void test_FLS_Negativ_OhnePS() {
        User u = createStandardUser('neg');
        insert u;

        System.runAs(u) {
            // Precondition: Standard User hat Case-Objektzugriff, sonst waere
            // die FLS-Pruefung unten aus falschem Grund wahr (SCRUM382-Muster).
            System.assert(
                Case.SObjectType.getDescribe().isAccessible(),
                'Precondition fehlgeschlagen: Standard User hat kein Case-Objektzugriff'
            );
            System.assertEquals(
                false, Case.Ursache__c.getDescribe().isAccessible(),
                'Ohne PS SCRUM434_Ursache muss Ursache__c NICHT lesbar sein'
            );
            System.assertEquals(
                false, Case.Ursache__c.getDescribe().isUpdateable(),
                'Ohne PS SCRUM434_Ursache muss Ursache__c NICHT schreibbar sein'
            );
        }
    }

    // 6. AC5 — FLS positiv: mit PS SCRUM434_Ursache hat der Standard User
    //    Read UND Edit auf Ursache__c. (User + PSA werden OUTSIDE-runAs
    //    gesetzt, da sich ein User kein PSA geben kann.)
    @isTest
    static void test_FLS_Positiv_MitPS() {
        User u = createStandardUser('pos');
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM434_Ursache' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        System.runAs(u) {
            System.assert(Case.SObjectType.getDescribe().isAccessible(),
                'Precondition fehlgeschlagen: Standard User hat kein Case-Objektzugriff');
            System.assertEquals(
                true, Case.Ursache__c.getDescribe().isAccessible(),
                'Mit PS SCRUM434_Ursache muss Ursache__c lesbar sein'
            );
            System.assertEquals(
                true, Case.Ursache__c.getDescribe().isUpdateable(),
                'Mit PS SCRUM434_Ursache muss Ursache__c schreibbar sein'
            );
        }
    }
}
