/**
 * [SCRUM-431] Functional test for the two new fields (ADR-1: declarative,
 * no Apex/Flow).
 *
 *   Account.Wartungsvertrag__c  — Checkbox, default false (the customer's
 *                                 maintenance-contract flag).
 *   Case.Wartungsvertrag_Anzeige__c — read-only Text formula returning
 *   "Ja"/"Nein", derived live from the related Account (cross-object on
 *   AccountId). Formula: IF( Account.Wartungsvertrag__c , "Ja" , "Nein" ).
 *
 * Covers the value side of the acceptance criteria:
 *   AC1  Account Ja  + open Case  -> Case shows "Ja"  (no account switch)
 *   AC2  Account Nein + open Case -> Case shows "Nein"
 *   ADR-1 (dynamic): flipping the Account flag recomputes every Case value
 *         in the same transaction — no Rebuilder, no stored value.
 *   Edge: Case with no Account -> "Nein" (blank boolean treated as false).
 *
 * House shape: SCRUM394DataQualityTest.cls — query the field back after DML
 * (formula fields are not populated on the in-memory sObject). Everything
 * created here rolls back with the test transaction.
 */
@isTest
private class SCRUM431WartungsvertragTest {

    private static Account makeAccount(Boolean wartungsvertrag) {
        Account a = new Account(
            Name = 'TEST-SCRUM-431-' + (wartungsvertrag ? 'JA' : 'NEIN') + '-' + DateTime.now().getTime(),
            Wartungsvertrag__c = wartungsvertrag
        );
        insert a;
        return a;
    }

    private static Case makeCase(Account a) {
        Case c = new Case(
            Subject = 'TEST-SCRUM-431-' + DateTime.now().getTime(),
            AccountId = a.Id,
            Origin = 'Phone'
        );
        insert c;
        return c;
    }

    private static Case makeOrphanCase() {
        Case c = new Case(
            Subject = 'TEST-SCRUM-431-ORPHAN-' + DateTime.now().getTime(),
            AccountId = null,
            Origin = 'Phone'
        );
        insert c;
        return c;
    }

    private static String readAnzeige(String caseId) {
        return [SELECT Wartungsvertrag_Anzeige__c FROM Case WHERE Id = :caseId].Wartungsvertrag_Anzeige__c;
    }

    // ---- AC1: Account Ja -> Case "Ja" ------------------------------------
    @isTest
    static void accountJa_openCaseShowsJa() {
        Account a = makeAccount(true);
        Case c = makeCase(a);
        System.assertEquals(
            'Ja', readAnzeige(c.Id),
            'AC1: Account mit Wartungsvertrag=Ja -> Case zeigt "Ja" ohne zum Account zu wechseln'
        );
    }

    // ---- AC2: Account Nein -> Case "Nein" --------------------------------
    @isTest
    static void accountNein_openCaseShowsNein() {
        Account a = makeAccount(false);
        Case c = makeCase(a);
        System.assertEquals(
            'Nein', readAnzeige(c.Id),
            'AC2: Account mit Wartungsvertrag=Nein -> Case zeigt "Nein"'
        );
    }

    // ---- ADR-1: value is live, not stored --------------------------------
    @isTest
    static void flipAccountFlag_caseValueFollowsLive() {
        Account a = makeAccount(false);
        Case c = makeCase(a);
        System.assertEquals('Nein', readAnzeige(c.Id), 'Precondition: Account Nein -> "Nein"');

        a.Wartungsvertrag__c = true;
        update a;
        System.assertEquals(
            'Ja', readAnzeige(c.Id),
            'ADR-1: nach Ja am Account folgt der Case-Wert LIVE (Formel, kein Rebuild/gespeicherter Wert)'
        );

        a.Wartungsvertrag__c = false;
        update a;
        System.assertEquals(
            'Nein', readAnzeige(c.Id),
            'ADR-1: zurueck auf Nein am Account -> Case-Wert wird live zurueckgesetzt'
        );
    }

    // ---- Edge: Case ohne Account -----------------------------------------
    @isTest
    static void orphanCase_showsNein() {
        Case c = makeOrphanCase();
        System.assertEquals(
            'Nein', readAnzeige(c.Id),
            'Case ohne Account -> leerer boolean wird als false behandelt -> "Nein"'
        );
    }

    // ---- Schema: the Case field is a read-only string formula ------------
    @isTest
    static void caseAnzeigeFieldIsReadOnlyTextFormula() {
        Schema.DescribeFieldResult f = Case.Wartungsvertrag_Anzeige__c.getDescribe();
        System.assertEquals(true, f.isCalculated(), 'AC-Anzeige: calculated (Formul) Feld (ADR-1)');
        System.assertEquals(false, f.isUpdateable(), 'AC-Anzeige: read-only (Formul, kein User-Write)');
        System.assert(f.getType() == Schema.DisplayType.STRING, 'AC-Anzeige: Text-Feld (Wortwerte Ja/Nein)');
        System.assertEquals(0, f.getPicklistValues().size(), 'AC-Anzeige: KEIN Picklist-Vocabulary (Werte liegen in der Formel)');
    }

    // ---- Schema: the Account field is a checkbox default false -----------
    @isTest
    static void accountFieldIsCheckbox() {
        Schema.DescribeFieldResult f = Account.Wartungsvertrag__c.getDescribe();
        System.assert(!f.isCalculated(), 'Account-Feld: kein calculated, sondern editierbares Checkbox-Feld');
        System.assert(f.getType() == Schema.DisplayType.BOOLEAN, 'Account-Feld: BOOLEAN (Checkbox)');
        Account a = new Account(Name = 'TEST-SCRUM-431-DEFAULT-' + DateTime.now().getTime());
        insert a;
        Boolean d = [SELECT Wartungsvertrag__c FROM Account WHERE Id = :a.Id].Wartungsvertrag__c;
        System.assertEquals(false, d, 'Account-Feld: Default = Nein (false)');
    }

    // FLS-Gate (Lücke C / SCRUM-430): the two fields are NEW. Prove from the
    // executing-user side that they are guarded — under System.runAs a user
    // WITHOUT the SCRUM431 permission set must NOT be able to read either
    // field. Pure reflection (getDescribe): no object CRUD, no sharing, no
    // DML inside runAs (no MIXED_DML). House pattern: SCRUM431FlsTest /
    // SCRUM424FirstResponseFlsTest.
    @isTest
    static void flsGuard_newFieldsNotReadableWithoutPS() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String sfx = String.valueOf(DateTime.now().getTime());
        User u = new User(
            ProfileId = p.Id,
            LastName = 'Scr431',
            Alias = 'flt431',
            Email = 'flt431-' + sfx + '@example.invalid',
            Username = 'flt431-' + sfx + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert u;
        System.runAs(u) {
            System.assertEquals(false, Account.Wartungsvertrag__c.getDescribe().isAccessible(),
                'FLS: Account field must NOT be readable without the SCRUM431 PS');
            System.assertEquals(false, Case.Wartungsvertrag_Anzeige__c.getDescribe().isAccessible(),
                'FLS: Case field must NOT be readable without the SCRUM431 PS');
        }
    }
}
