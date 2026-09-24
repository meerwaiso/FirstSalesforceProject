/**
 * [SCRUM-428] TC1 — Phase A Ingest (AC1–AC5) + AC2 (Controller) + AC11 (Bestätigung).
 *
 * Strategie:
 * - Phase A laeuft SYNCHRON im after-insert-Trigger => `insert Case` reicht;
 *   Readback danach liefert die finalen Werte.
 * - Dedup (AC4/5): erst ZIEL-Case inserten (bleibt offen), dann DUP-Case.
 *   421 darf nebenbei routen (OwnerId auf FLS) — pruefen wir hier NICHT,
 *   das ist 421's Kompetenz.
 * - AC11: nahtlose Tests von buildMessage/sendAll (rein, keine Insert-Kopplung,
 *   keine echte Mail an PII).
 * - KEIN Setup-Object-DML in dieser Klasse (kein MIXED_DML).
 *
 * MDT-Keywords (Startliste, 24.09 via SOQL verifiziert):
 *   Technik: Defekt, Fehler, Stoerung
 *   Rechnung: Buchung, Gutschrift, Zahlung
 *   Vertrag: Kuendigung, Laufzeit, Vereinbarung, Verlaengerung
 *
 * @author developer-agent
 * @date 2026-09-24
 */
@isTest
private class SCRUM428IngestTest {
  /** Neue E-Mail-Case; laedt sie danach zurueck (Trigger laeuft synchron). */
  private static Case emailCase(String subject, String description) {
    Case c = new Case(Origin = 'Email', Status = 'New', Subject = subject);
    if (description != null) {
      c.Description = description;
    }
    insert c;
    return [
      SELECT
        Erfassungsquelle__c,
        Servicebereich__c,
        Status,
        Subject,
        Dedupliziert__c,
        CaseNumber
      FROM Case
      WHERE Id = :c.Id
    ];
  }

  /** Case-Number einer offenen Case (AC4-Text-Einbettung). */
  private static String openCaseNumber(Id caseId) {
    return [SELECT CaseNumber FROM Case WHERE Id = :caseId].CaseNumber;
  }

  // ------------------------------------------------------------------
  // AC1: Origin='Email' -> Erfassungsquelle__c='E-Mail'
  // ------------------------------------------------------------------
  @isTest
  static void ac1_email_sets_source() {
    Case c = emailCase('AC1 Anrede', 'kein Keyword enthalten');
    System.assertEquals(
      'E-Mail',
      c.Erfassungsquelle__c,
      'AC1: Origin=Email => Erfassungsquelle=E-Mail'
    );
    // Nebeneffekt AC3-Default: kein Keyword => Allgemein.
    System.assertEquals(
      'Allgemein',
      c.Servicebereich__c,
      'AC1/AC3: ohne Keyword => Fallback Allgemein'
    );
  }

  // ------------------------------------------------------------------
  // AC2: Kontaktformular (Controller) -> Case mit Kontaktformular-Quelle,
  // Contact per E-Mail angelegt/gematcht, CaseNumber zurueck.
  // ------------------------------------------------------------------
  @isTest
  static void ac2_controller_creates_case_and_contact() {
    String uniq = String.valueOf(System.currentTimeMillis());
    String email = 'form' + uniq + '@example.invalid';
    String caseNumber = SCRUM428ContactFormController.submitForm(
      'Formkunde ' + uniq,
      email,
      'Vertrag',
      'Mein Vertrag sollte verlängert werden.'
    );
    System.assertNotEquals(null, caseNumber, 'AC2: CaseNumber zurueck');
    List<Case> rows = [
      SELECT
        Erfassungsquelle__c,
        Servicebereich__c,
        Subject,
        Contact.LastName,
        Contact.Email
      FROM Case
      WHERE CaseNumber = :caseNumber
    ];
    System.assertEquals(1, rows.size(), 'AC2: genau ein Case');
    Case c = rows[0];
    System.assertEquals(
      'Kontaktformular',
      c.Erfassungsquelle__c,
      'AC2: Erfassungsquelle=Kontaktformular'
    );
    System.assertEquals(
      'Vertrag',
      c.Servicebereich__c,
      'AC2: Servicebereich aus dem Formular'
    );
    System.assertNotEquals(
      null,
      c.Contact.LastName,
      'AC2: Contact angelegt/gematcht'
    );
    System.assertEquals(
      email,
      c.Contact.Email,
      'AC2: Contact mit der Formular-E-Mail'
    );
  }

  @isTest
  static void ac2_controller_rejects_short_message() {
    Boolean threw = false;
    try {
      SCRUM428ContactFormController.submitForm(
        'AC2 Kurz',
        'kurz' + System.currentTimeMillis() + '@example.invalid',
        null,
        'zu kurz'
      ); // < 10 Zeichen
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'AC2: nachricht < 10 Zeichen muss abgelehnt werden');
  }

  // ------------------------------------------------------------------
  // AC3: Keyword-Kategorisierung (nur E-Mail) + Priority + Fallback
  // ------------------------------------------------------------------
  @isTest
  static void ac3_keyword_tech_rechnung_vertrag_fallback() {
    Case t = emailCase('AC3 Technik: der Drucker hat ein Defekt', null);
    System.assertEquals(
      'Technik',
      t.Servicebereich__c,
      'AC3: Keyword "Defekt" => Technik'
    );

    Case r = emailCase('AC3 Rechnung: Gutschrift fehlt', null);
    System.assertEquals(
      'Rechnung',
      r.Servicebereich__c,
      'AC3: Keyword "Gutschrift" => Rechnung'
    );

    Case v = emailCase('AC3 Vertrag: Kuendigung zum Quartalsende', null);
    System.assertEquals(
      'Vertrag',
      v.Servicebereich__c,
      'AC3: Keyword "Kuendigung" => Vertrag'
    );

    Case f = emailCase('AC3 Fallback: alles in Ordnung', null);
    System.assertEquals(
      'Allgemein',
      f.Servicebereich__c,
      'AC3: ohne Keyword => Allgemein'
    );
  }

  @isTest
  static void ac3_priority_tech_over_rechnung() {
    Case c = emailCase('AC3 Prioritaet: Fehler bei der Zahlung', null);
    System.assertEquals(
      'Technik',
      c.Servicebereich__c,
      'AC3: zwei Treffer (Fehler+Zahlung) => Technik (hohere Priority)'
    );
  }

  @isTest
  static void ac3_not_applied_to_non_email() {
    // Origin=null + Servicebereich=null: Trigger darf NICHT kategorisieren.
    Case raw = new Case(
      Status = 'New',
      Subject = 'AC3 nicht-Email Fehler Zahlung'
    );
    insert raw;
    Case after = [SELECT Servicebereich__c FROM Case WHERE Id = :raw.Id];
    System.assertEquals(
      null,
      after.Servicebereich__c,
      'AC3: nur E-Mail-Case werden kategorisiert'
    );
  }

  // ------------------------------------------------------------------
  // AC4: Case-Nummer im Text -> bestehende offene Case anhaengen
  // ------------------------------------------------------------------
  @isTest
  static void ac4_case_number_in_text_dedupes() {
    // Ziel: offene Case ohne Kontakt (AC5-Hebel bewusst leer).
    Case ziel = new Case(
      Status = 'New',
      Subject = 'AC4 Ziel',
      Origin = 'Phone'
    );
    insert ziel;
    String nummer = openCaseNumber(ziel.Id);

    Case dup = new Case(
      Status = 'New',
      Subject = 'AC4 Dup: Bezug ' + nummer,
      Description = 'Wie geht es mit ' + nummer + ' weiter?',
      Origin = 'Email'
    );
    insert dup;

    Case dupAfter = [
      SELECT Status, Subject, Dedupliziert__c
      FROM Case
      WHERE Id = :dup.Id
    ];
    System.assertEquals(
      'Closed',
      dupAfter.Status,
      'AC4: Dup-Case wird geschlossen'
    );
    System.assertEquals(
      true,
      dupAfter.Dedupliziert__c,
      'AC4: Dup-Case wird markiert'
    );
    System.assert(
      dupAfter.Subject.indexOf('[Dedupliziert: ' + nummer + ']') == 0,
      'AC4: Subject erhaelt Praefix [Dedupliziert: <Ziel>]: ' + dupAfter.Subject
    );
    // Ziel: offen, Kommentar mit dem Dup-Text.
    Case zielAfter = [SELECT Status FROM Case WHERE Id = :ziel.Id];
    System.assertNotEquals(
      'Closed',
      zielAfter.Status,
      'AC4: Ziel-Case bleibt offen'
    );
    AggregateResult cr = [
      SELECT COUNT(Id) n
      FROM CaseComment
      WHERE ParentId = :ziel.Id
    ];
    Integer comments = (Integer) cr.get('n');
    System.assertEquals(1, comments, 'AC4: ein CaseComment auf der Ziel-Case');
  }

  // ------------------------------------------------------------------
  // AC5: gleicheContactId + gleicher Bereich + offen -> anhaengen;
  // anderer Bereich -> NICHT dupliziert.
  // ------------------------------------------------------------------
  @isTest
  static void ac5_same_contact_same_bereich_dedupes() {
    Contact k = new Contact(
      LastName = 'AC5 Kunde',
      Email = 'ac5' + System.currentTimeMillis() + '@example.invalid'
    );
    insert k;

    Case ziel = new Case(
      Status = 'New',
      ContactId = k.Id,
      Servicebereich__c = 'Technik',
      Subject = 'AC5 Ziel Technik'
    );
    insert ziel;

    Case dup = new Case(
      Status = 'New',
      ContactId = k.Id,
      Servicebereich__c = 'Technik',
      Subject = 'AC5 Dup Technik'
    );
    insert dup;

    Case dupAfter = [
      SELECT Status, Dedupliziert__c
      FROM Case
      WHERE Id = :dup.Id
    ];
    System.assertEquals(
      'Closed',
      dupAfter.Status,
      'AC5: gleiche ContactId + gleicher offener Bereich => Dup'
    );
    System.assertEquals(
      true,
      dupAfter.Dedupliziert__c,
      'AC5: Dup-Case wird markiert'
    );

    // Andere Bereich (Vertrag) mit gleichem Kontakt => KEIN Dup.
    Case other = new Case(
      Status = 'New',
      ContactId = k.Id,
      Servicebereich__c = 'Vertrag',
      Subject = 'AC5 Andere Bereich'
    );
    insert other;
    Case otherAfter = [
      SELECT Status, Dedupliziert__c
      FROM Case
      WHERE Id = :other.Id
    ];
    System.assertNotEquals(
      'Closed',
      otherAfter.Status,
      'AC5: anderer Bereich => offen'
    );
    System.assertNotEquals(
      true,
      otherAfter.Dedupliziert__c,
      'AC5: anderer Bereich => nicht markiert'
    );
  }

  // ------------------------------------------------------------------
  // AC11: Eingangsbestätigung — nahtlos (buildMessage/sendAll).
  // Reale Cases (CaseNumber ist read-only) werden geladen und über die
  // echte sendAll-Pipeline geschickt (inkl. Contact-E-Mail-Pfad).
  // ------------------------------------------------------------------
  @isTest
  static void ac11_build_message_and_skip_dup() {
    // (a) buildMessage: mit/ohne Empfänger.
    Messaging.SingleEmailMessage m = SCRUM428CaseConfirmation.buildMessage(
      '00009999',
      'kunde@example.invalid',
      'Hans'
    );
    System.assertNotEquals(null, m, 'AC11: mit Empfänger => Message');
    System.assert(
      m.getSubject().indexOf('00009999') != -1,
      'AC11: Subject enthaelt die Fallnummer'
    );
    System.assert(
      m.getPlainTextBody().indexOf('Hans') != -1,
      'AC11: Anrede im Text'
    );
    Messaging.SingleEmailMessage none = SCRUM428CaseConfirmation.buildMessage(
      '00009999',
      null,
      'Hans'
    );
    System.assertEquals(null, none, 'AC11: ohne Empfänger => null');

    // (b) Real-Case: mit Contact => sendAll liefert 1 Mail.
    Contact k = new Contact(
      LastName = 'AC11 Hans',
      Email = 'ac11' + System.currentTimeMillis() + '@example.invalid'
    );
    insert k;
    Case c = new Case(
      Status = 'New',
      Origin = 'Phone',
      Subject = 'AC11 Bestaetigung',
      ContactId = k.Id
    );
    insert c;
    Case loaded = [
      SELECT
        Id,
        CaseNumber,
        SuppliedEmail,
        SuppliedName,
        Dedupliziert__c,
        Contact.Name,
        Contact.Email
      FROM Case
      WHERE Id = :c.Id
    ];
    Integer sent = SCRUM428CaseConfirmation.sendAll(new List<Case>{ loaded });
    System.assertEquals(
      1,
      sent,
      'AC11: Case mit Contact-E-Mail => genau 1 Bestaetigung'
    );

    // (c) Dup-Case (Dedupliziert__c=true) wird NIE bestätigt.
    Case dup = [
      SELECT
        Id,
        CaseNumber,
        SuppliedEmail,
        SuppliedName,
        Dedupliziert__c,
        Contact.Name,
        Contact.Email
      FROM Case
      WHERE Id = :c.Id
    ];
    dup.Dedupliziert__c = true;
    sent = SCRUM428CaseConfirmation.sendAll(new List<Case>{ dup });
    System.assertEquals(0, sent, 'AC11: Dup-Case => 0 Mails');
  }
}
