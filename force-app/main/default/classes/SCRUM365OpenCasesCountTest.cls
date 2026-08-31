/**
 * [SCRUM-365] Offene Fälle auf dem Kontakt — Apex-Funktionaltests.
 *
 * Deckt die 6 Gherkin-Acceptance-Criterias + Bulk 200 + FLS (read-only) + eine
 * Regression für die bestehende Cases-Automatisierung (CasePriorityTrigger,
 * SCRUM-333) ab. Der Deploy mit --test-level RunLocalTests führt genau diese
 * Klasss aus — sie ist das Coverage-/Qualitäts-Gate für den Deploy.
 *
 * Design (bulkified Recomputation, ADR SCRUM-365):
 *   «offen» = Case.Status != 'Closed'. Bei jedem relevanten Case-Event zählt
 *   CaseOpenCountTrigger.recompute() die offenen Fälle der betroffenen Kontakte
 *   exakt neu (GROUP BY) und schreibt nur die Kontakt-Records, deren sich
 *   geändert hat. Der Test verifieert das RESULTAT (den Wert auf dem Contact)
 *   aus Sicht des Users — nicht das interne Mechanik.
 *
 * Alles, was hier erzeugt wird, rollt mit der Test-Transaction zurück — die Org
 * bleibt unberührt.
 */
@isTest
private class SCRUM365OpenCasesCountTest {

    /** Erzeugt einen minimalen Contact und gibt die Id zurück. */
    private static Id newContact(String tag) {
        Contact c = new Contact(LastName = 'V365 ' + tag);
        insert c;
        return c.Id;
    }

    /** Liest den aktuellen Wert von Contact.Open_Cases_Count__c. */
    private static Integer countOf(Id contactId) {
        Contact ct = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :contactId];
        return ct.Open_Cases_Count__c == null ? 0 : ct.Open_Cases_Count__c.intValue();
    }

    /**
     * AC (Feld immer stimmt / Create): Ein neuer (offener) Fall erhöht die Zahl
     * des Kontakts um 1. «offen» = Status != Closed (Neu = 'New').
     * Der Startwert wird ROH assertet (kein countOf()): ohne Feld-Default 0
     * wäre er NULL und dieser Test scheitert — das AC «Kontakt ohne Fälle → 0»
     * ist ein echtes Gate (Review SCRUM-365, Round 2).
     */
    @isTest
    static void createNewCase_incrementsCount() {
        Id a = newContact('Create');
        Contact a0 = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :a LIMIT 1];
        System.assertEquals(0, a0.Open_Cases_Count__c, 'Roh-Startwert muss 0 sein (Feld-Default), nicht NULL');

        insert new Case(ContactId = a, Status = 'New', Subject = 'c1');
        System.assertEquals(1, countOf(a), 'Ein neuer offener Fall muss die Zahl auf 1 setzen');

        insert new Case(ContactId = a, Status = 'New', Subject = 'c2');
        System.assertEquals(2, countOf(a), 'Zweiter offener Fall muss die Zahl auf 2 erhöhen');
    }

    /**
     * AC (geschlossene Fälle zählen nicht / Close + Reopen): Schliessen senkt die
     * Zahl, Wiederaufmachen (Status zurück aus Closed) erhöht sie erneut.
     */
    @isTest
    static void closeAndReopen_movesCount() {
        Id a = newContact('CloseReopen');

        Case c = new Case(ContactId = a, Status = 'New', Subject = 'cr');
        insert c;
        System.assertEquals(1, countOf(a), 'offener Fall => 1');

        c.Status = 'Closed';
        update c;
        System.assertEquals(0, countOf(a), 'geschlossener Fall => 0');

        c.Status = 'New';
        update c;
        System.assertEquals(1, countOf(a), 'wieder geöffneter Fall => 1');

        c.Status = 'Working';
        update c;
        System.assertEquals(1, countOf(a), 'Working gilt als offen => bleibt 1');
    }

    /**
     * AC (Umhängen — beide Kontakte stimmen): Wird ein Fall von Kontakt A auf B
     * verschoben, sinkt die Zahl von A und steigt die von B — in EINEM Schritt.
     */
    @isTest
    static void reassign_keepsBothContactsCorrect() {
        Id a = newContact('ReassignA');
        Id b = newContact('ReassignB');

        Case c1 = new Case(ContactId = a, Status = 'New');
        Case c2 = new Case(ContactId = a, Status = 'New');
        insert new List<Case> { c1, c2 };
        System.assertEquals(2, countOf(a), 'A hat 2 offene');
        System.assertEquals(0, countOf(b), 'B hat 0');

        // c2 auf B umhängen (Status bleibt offen).
        c2.ContactId = b;
        update c2;
        System.assertEquals(1, countOf(a), 'A muss auf 1 sinken');
        System.assertEquals(1, countOf(b), 'B muss auf 1 steigen — beide korrekt in einem Schritt');
    }

    /**
     * AC (Delete senkt die Zahl): Die Löschung eines offenen Falls reduziert die
     * Zählung des Kontakts. (Delete-Trigger: Trigger.old trägt den ContactId.)
     */
    @isTest
    static void delete_caseDecrementsCount() {
        Id a = newContact('Delete');

        Case c1 = new Case(ContactId = a, Status = 'New');
        Case c2 = new Case(ContactId = a, Status = 'New');
        insert new List<Case> { c1, c2 };
        System.assertEquals(2, countOf(a), '2 offene');

        delete c1;
        System.assertEquals(1, countOf(a), 'nach Delete des einen Falls => 1');
    }

    /**
     * AC (inert bei irrelevanten Updates): Ein Update, das weder ContactId noch
     * Status ändert, darf die Zählung NICHT verzerren (Trigger bleibt inert).
     * Der Wert bleibt stabil und korrekt.
     */
    @isTest
    static void unrelatedUpdate_keepsCountStable() {
        Id a = newContact('Inert');
        Case c = new Case(ContactId = a, Status = 'New', Subject = 'v1');
        insert c;
        System.assertEquals(1, countOf(a), '1 offen');

        // nur Subject ändern → weder Status noch Kontakt → inert.
        c.Subject = 'v2';
        update c;
        System.assertEquals(1, countOf(a), 'irrelevantes Update darf die Zahl nicht verändern');

        c.Priority = 'High';
        update c;
        System.assertEquals(1, countOf(a), 'Priority-Update bleibt ebenfalls inert');
    }

    /**
     * AC (Bulk 200 = 1 SOQL + 1 DML, kein Abbruch): 200 Fälle auf einmal einspielen
     * — die Zählung bleibt exakt und es läuft nichts voll.
     *
     * Verteilung: 25 Kontakte, 8 Runden je ein Fall pro Kontakt = 200 Fälle. Runden
     * 0–3 offen ('New'), Runden 4–7 geschlossen ('Closed') → jeder Kontakt exakt
     * 4 offene + 4 geschlossene. Zusammen 100 neue offene Fälle zusätzlich.
     */
    @isTest
    static void bulk200_insertKeepsExactCounts() {
        List<Contact> contacts = new List<Contact>();
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 25; i++) {
            Contact c = new Contact(LastName = 'V365Bulk ' + i);
            contacts.add(c);
        }
        insert contacts;
        for (Contact c : contacts) {
            ids.add(c.Id);
        }

        Integer openBefore = [SELECT COUNT() FROM Case WHERE Status != 'Closed'];

        List<Case> bigBatch = new List<Case>();
        for (Integer round = 0; round < 8; round++) {
            for (Integer k = 0; k < ids.size(); k++) {
                bigBatch.add(new Case(
                    ContactId = ids.get(k),
                    Status = round < 4 ? 'New' : 'Closed',
                    Subject = 'bulk ' + round + '-' + k
                ));
            }
        }
        insert bigBatch; // 1 DML, 200 Zeilen → 1 Trigger → 1 SOQL (GROUP BY) + 1 DML

        for (Id cid : ids) {
            System.assertEquals(4, countOf(cid), 'jeder der 25 Kontakte muss auf exakt 4 offene Fälle laufen');
        }
        System.assertEquals(
            openBefore + 100,
            [SELECT COUNT() FROM Case WHERE Status != 'Closed'],
            'zusätzlich genau 100 offene Fälle erzeugt'
        );
    }

    /**
     * AC (Feld lässt sich von Hand NICHT ändern — FLS read-only für alle):
     *   - Ohne Permission Set: NICHT lesbar, NICHT beschreibbar.
     *   - MIT Permission Set (readable=true, editable=false): LESBAR, aber immer
     *     noch NICHT beschreibbar.
     *
     * Standard-User-Profil wird verwendet, weil Custom-Fields Standard-Profilen
     * default unsichtbar sind (das macht die Negativ-Assertion meaningful) und
     * System-Admins FLS unabhängig vererben (negativer Run SCRUM-329, 2026-08-23).
     */
    @isTest
    static void fls_readOnlyForEveryone() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Fls365',
            Alias = 'fls365',
            Email = 'fls365@example.invalid',
            Username = 'fls365_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        // Vorbedingung: Standard User hat Object-Level-Zugriff auf Contact.
        System.runAs(u) {
            System.assert(
                Contact.SObjectType.getDescribe().isAccessible(),
                'Vorbedingung: Standard User braucht Object-Zugriff auf Contact, sonst testen wir das Falsche.'
            );
        }

        // NEGATIV: ohne PS → weder lesbar noch beschreibbar.
        System.runAs(u) {
            System.assertEquals(
                false, Contact.Open_Cases_Count__c.getDescribe().isAccessible(),
                'Ohne PS muss Open_Cases_Count__c NICHT lesbar sein'
            );
            System.assertEquals(
                false, Contact.Open_Cases_Count__c.getDescribe().isUpdateable(),
                'Ohne PS muss Open_Cases_Count__c NICHT beschreibbar sein'
            );
        }

        // PS zuweisen.
        Id psId = [
            SELECT Id FROM PermissionSet WHERE Name = 'SCRUM365_OpenCasesCount' LIMIT 1
        ].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);

        // POSITIV: mit PS → lesbar, aber NICHT beschreibbar (read-only für alle).
        System.runAs(u) {
            System.assertEquals(
                true, Contact.Open_Cases_Count__c.getDescribe().isAccessible(),
                'Mit PS muss Open_Cases_Count__c lesbar sein'
            );
            System.assertEquals(
                false, Contact.Open_Cases_Count__c.getDescribe().isUpdateable(),
                'Mit PS darf Open_Cases_Count__c NICHT beschreibbar sein (read-only, systemmaintained)'
            );
        }
    }
}
