/**
 * [SCRUM-435] Tester-Agent Verification — applyDup setzt Ursache__c.
 *
 * Schliesst die Luecke in den Developer-Tests: ac4/ac5 pruefen, dass der
 * Dedup-Abschluss die Case schliesst (Status='Closed'), assertieren aber
 * nicht den geforderten Wert an Ursache__c. AC1 verlangt beides:
 *   Then hat sie Ursache__c = 'KeinFehlerKeineMassnahme'
 *    und die Schliessung blockt NICHT.
 *
 * Der Test laeuft Ueber den echten Pfad: Trigger SCRUM428CaseIngestTrigger
 * (after insert) -> SCRUM428CaseIngestHandler.process -> applyDup.
 * Keine Test-Mocks, keine direkte Handler-Aufrufe.
 *
 * neg_control_valrule_still_active: Negative Kontrolle. Ein manuelles
 * Schliessen OHNE Ursache__c muss an der SCRUM-434-ValRule scheitern.
 * Beweist, dass die ValRule aktiv ist und das Gruen der Dedup-Tests nicht
 * vakuum ist (die Schliessung blockt nicht, WEIL applyDup den Wert setzt).
 *
 * @author tester-agent
 * @date 2026-09-29
 */
@IsTest
private class SCRUM435TesterVerificationTest {

  // ------------------------------------------------------------------
  // AC1a: Dedup ueber Case-Im Text (ac4-Pfad) — Wert + Schliessung
  // ------------------------------------------------------------------
  @IsTest
  static void ac1_dedup_case_number_sets_ursache() {
    Case ziel = new Case(
      Status = 'New',
      Subject = 'T435 Ziel',
      Origin = 'Phone'
    );
    insert ziel;
    String nummer = [SELECT CaseNumber FROM Case WHERE Id = :ziel.Id].CaseNumber;

    Case dup = new Case(
      Status = 'New',
      Subject = 'T435 Dup: Bezug ' + nummer,
      Description = 'Wie geht es mit ' + nummer + ' weiter?',
      Origin = 'Email'
    );
    insert dup; // feuert SCRUM428CaseIngestTrigger -> process -> applyDup

    Case dupAfter = [
      SELECT Status, Dedupliziert__c, Ursache__c
      FROM Case
      WHERE Id = :dup.Id
    ];
    // AC1: Schliessung blockt NICHT
    System.assertEquals(
      'Closed', dupAfter.Status,
      'AC1: Dup-Case wird geschlossen; die ValRule blockt den Dedup-Pfad nicht'
    );
    System.assertEquals(
      true, dupAfter.Dedupliziert__c,
      'AC1: Dup-Case ist als Dup markiert'
    );
    // AC1: der geforderte Wert liegt an
    System.assertEquals(
      'KeinFehlerKeineMassnahme', dupAfter.Ursache__c,
      'AC1: applyDup setzt Ursache__c auf KeinFehlerKeineMassnahme'
    );

    Case zielAfter = [SELECT Status FROM Case WHERE Id = :ziel.Id];
    System.assertNotEquals(
      'Closed', zielAfter.Status,
      'AC1: Ziel-Case bleibt offen'
    );
  }

  // ------------------------------------------------------------------
  // AC1b: Dedup ueber gleiche ContactId + gleicher Bereich (ac5-Pfad)
  // ------------------------------------------------------------------
  @IsTest
  static void ac1_dedup_contact_bereich_sets_ursache() {
    Contact k = new Contact(
      LastName = 'T435 Kunde',
      Email = 't435' + System.currentTimeMillis() + '@example.invalid'
    );
    insert k;

    Case ziel = new Case(
      Status = 'New',
      ContactId = k.Id,
      Servicebereich__c = 'Technik',
      Subject = 'T435 Ziel Technik'
    );
    insert ziel;

    Case dup = new Case(
      Status = 'New',
      ContactId = k.Id,
      Servicebereich__c = 'Technik',
      Subject = 'T435 Dup Technik'
    );
    insert dup; // feuert SCRUM428CaseIngestTrigger -> process -> applyDup

    Case dupAfter = [
      SELECT Status, Dedupliziert__c, Ursache__c
      FROM Case
      WHERE Id = :dup.Id
    ];
    System.assertEquals(
      'Closed', dupAfter.Status,
      'AC1: Dup (gleiche ContactId + Bereich) wird geschlossen, blockt nicht'
    );
    System.assertEquals(
      true, dupAfter.Dedupliziert__c,
      'AC1: Dup-Case ist als Dup markiert'
    );
    System.assertEquals(
      'KeinFehlerKeineMassnahme', dupAfter.Ursache__c,
      'AC1: applyDup setzt Ursache__c auf KeinFehlerKeineMassnahme'
    );
  }

  // ------------------------------------------------------------------
  // Negativ-Kontrolle: SCRUM-434-ValRule ist aktiv und blockt wirklich
  // ------------------------------------------------------------------
  @IsTest
  static void neg_control_close_without_ursache_is_blocked() {
    Case c = new Case(
      Status = 'New',
      Subject = 'T435 Negativ-Kontrolle',
      Origin = 'Phone'
    );
    insert c;

    c.Status = 'Closed'; // bewusst OHNE Ursache__c
    try {
      update c;
      System.assert(
        false,
        'Negativ-Kontrolle: Schliessung ohne Ursache__c sollte von der '
        + 'SCRUM-434-ValidationRule blockiert werden (FIELD_CUSTOM_VALIDATION_EXCEPTION)'
      );
    } catch (DmlException e) {
      String m = e.getMessage().toLowerCase();
      // SCRUM-434-ValRule wirft FIELD_CUSTOM_VALIDATION_EXCEPTION.
      System.assert(
        m.contains('field_custom_validation_exception')
        || m.contains('ursache'),
        'Negativ-Kontrolle: erwarteter ValRule-Fehler, stattdessen: ' + e.getMessage()
      );
    }
  }
}
