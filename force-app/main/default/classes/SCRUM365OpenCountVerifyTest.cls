/**
 * [SCRUM-365] Tester-Agent unabh\u00e4ngige Verifikation \u2014 Offene F\u00e4lle auf dem Kontakt.
 *
 * Diese Klasse ist das UNABH\u00c4NGIGE TEST-ARTIFAKT der Testerin, namentlich getrennt von
 * SCRUM365OpenCasesCountTest (Developer). Sie erbringt dieselben Beweise aus eigenen
 * Datenformen, so dass ein gr\u00fcner Lauf nicht nur die Developer-Klasse abspiegelt.
 * Alles erzeugt hier r\u00f6llt mit der Test-Transaktion zur\u00fcck \u2014 die Org bleibt unber\u00fchrt.
 */
@isTest
private class SCRUM365OpenCountVerifyTest {

    private static Id mkContact(String tag) {
        Contact c = new Contact(LastName = 'T365 ' + tag);
        insert c;
        return c.Id;
    }

    private static Integer countOf(Id contactId) {
        Contact c = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :contactId];
        return c.Open_Cases_Count__c == null ? 0 : c.Open_Cases_Count__c.intValue();
    }

    /**
     * AC1 (Default 0, roh verifiziert): Ein frischer Kontakt OHNE F\u00e4lle zeigt exakt 0.
     * Roh-Assert (kein countOf()): ohne Feld-Default w\u00e4re der Wert NULL und scheitert hier.
     */
    @isTest
    static void freshContact_rawDefaultZero() {
        Id a = mkContact('RawDefault');
        Contact c = [SELECT Open_Cases_Count__c FROM Contact WHERE Id = :a];
        System.assertEquals(0, c.Open_Cases_Count__c,
            'Frischer Kontakt ohne F\u00e4lle muss roh 0 zeigen (Feld-Default), nicht NULL');
    }

    /**
     * AC1+AC2 (Lebenszyklus): Create +1, geschlossener neu 0, Close -1, Reopen +1, Escalated bleibt offen.
     * Beweist \u00bcber einen Voll-Lebenszyklus, dass die Zahl immer stimmt.
     */
    @isTest
    static void lifecycle_createCloseReopenEscalate() {
        Id a = mkContact('Life');

        // Create offen +1
        Case x = new Case(ContactId = a, Status = 'New', Subject = 'L1');
        insert x;
        System.assertEquals(1, countOf(a), 'Neuer offener Fall => 1');

        // Geschlossener Fall z\u00e4hlt NICHT (AC2)
        Case y = new Case(ContactId = a, Status = 'Closed', Subject = 'L2');
        insert y;
        System.assertEquals(1, countOf(a), 'Geschlossener Fall soll die Zahl nicht erh\u00f6hen');

        // Close senkt (AC2)
        x.Status = 'Closed';
        update x;
        System.assertEquals(0, countOf(a), 'Beide geschlossen => 0');

        // Reopen erh\u00f6ht wieder (AC2)
        x.Status = 'Working';
        update x;
        System.assertEquals(1, countOf(a), 'Wieder ge\u00f6ffnet (Working) => 1');

        // Escalated gilt als offen (AC2)
        x.Status = 'Escalated';
        update x;
        System.assertEquals(1, countOf(a), 'Escalated gilt als offen => bleibt 1');
    }

    /**
     * AC3 (Umh\u00e4ngen, beiste Kontakte in EINEM Schritt): F\u00fcr einen auf B gezogenen
     * Fall sinkt A und steigt B gleichzeitig, exakt korrekt.
     */
    @isTest
    static void reassign_bothContactsCorrectInOneStep() {
        Id a = mkContact('ReA');
        Id b = mkContact('ReB');

        List<Case> cs = new List<Case>();
        for (Integer i = 0; i < 3; i++) cs.add(new Case(ContactId = a, Status = 'New', Subject = 'r' + i));
        insert cs;
        System.assertEquals(3, countOf(a), 'A: 3 offen');
        System.assertEquals(0, countOf(b), 'B: 0');

        cs.get(1).ContactId = b;
        update cs.get(1);

        System.assertEquals(2, countOf(a), 'A sinkt auf 2');
        System.assertEquals(1, countOf(b), 'B steigt auf 1 \u2014 beide korrekt in einem Schritt');
    }

    /**
     * AC3 (Delete senkt): L\u00f6schen eines offenen Falls reduziert die Z\u00e4hlung.
     */
    @isTest
    static void deleteOpenCase_decrements() {
        Id a = mkContact('Del');
        List<Case> cs = new List<Case>();
        cs.add(new Case(ContactId = a, Status = 'New', Subject = 'd1'));
        cs.add(new Case(ContactId = a, Status = 'New', Subject = 'd2'));
        cs.add(new Case(ContactId = a, Status = 'Closed', Subject = 'd3'));
        insert cs;
        System.assertEquals(2, countOf(a), '2 offen vor Delete');

        delete cs.get(0);
        System.assertEquals(1, countOf(a), 'Nach Delete eines offenen Falls => 1');
    }

    /**
     * AC4 (Bulk 200 ohne Abbruch, exakte Werte): 200 F\u00e4lle in EINER DML \u00fcber 10 Kontakte
     * (je 20, gemischt offen/geschlossenen) \u2014 jede Z\u00e4hlung landet exakt.
     */
    @isTest
    static void bulk200_singleDml_exactCounts() {
        List<Id> cids = new List<Id>();
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 10; i++) {
            Contact c = new Contact(LastName = 'T365B ' + i);
            contacts.add(c);
        }
        insert contacts;
        for (Contact c : contacts) cids.add(c.Id);

        List<Case> batch = new List<Case>();
        for (Integer k = 0; k < 10; k++) {
            for (Integer r = 0; r < 20; r++) {
                // 12 offen + 8 geschlossen je Kontakt
                batch.add(new Case(
                    ContactId = cids.get(k),
                    Status = (r < 12) ? 'New' : 'Closed',
                    Subject = 'bulk-' + k + '-' + r
                ));
            }
        }
        insert batch; // 200 Zeilen, 1 DML, 1 Trigger-Durchlauf

        for (Id cid : cids) {
            System.assertEquals(12, countOf(cid), 'Jeder der 10 Kontakte muss exakt 12 offene zeigen');
        }
    }

    /**
     * AC5+FLS (Read-only f\u00fcr alle): System-User ohne Permission Set liest und schreibt
     * Open_Cases_Count__c NICHT; mit SCRUM365_OpenCasesCount liest er es, aber schreibt es
     * weiterhin NICHT. Mit Object-Vorbedingung, um die grobe Ebene auszuschliegen.
     */
    @isTest
    static void fls_readOnly_noWriteWithOrWithoutPermissionSet() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'TFls',
            Alias = 'tfls',
            Email = 'tfls@example.invalid',
            Username = 'tfls_' + DateTime.now().getTime() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;

        System.runAs(u) {
            System.assert(Contact.SObjectType.getDescribe().isAccessible(),
                'Vorbedingung: Object-Zugriff auf Contact muss vorliegen');
        }

        // NEGATIV \u2014 ohne Permission Set: noch nicht lesbar, auch nicht beschreibbar (AC5).
        System.runAs(u) {
            System.assertEquals(false, Contact.Open_Cases_Count__c.getDescribe().isAccessible(),
                'Ohne PS: Open_Cases_Count__c soll nicht lesbar sein');
            System.assertEquals(false, Contact.Open_Cases_Count__c.getDescribe().isUpdateable(),
                'Ohne PS: Open_Cases_Count__c soll nicht beschreibbar sein');
        }

        // Permission Set zuweisen.
        Id ps = [SELECT Id FROM PermissionSet WHERE Name = 'SCRUM365_OpenCasesCount' LIMIT 1].Id;
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps);

        // POSITIV + Read-only \u2014 mit PS: lesbar, aber immer noch nicht beschreibbar (AC5).
        System.runAs(u) {
            System.assertEquals(true, Contact.Open_Cases_Count__c.getDescribe().isAccessible(),
                'Mit PS: Open_Cases_Count__c soll lesbar sein');
            System.assertEquals(false, Contact.Open_Cases_Count__c.getDescribe().isUpdateable(),
                'Mit PS: Open_Cases_Count__c soll NICHT beschreibbar sein (Read-only)');
        }
    }
}
