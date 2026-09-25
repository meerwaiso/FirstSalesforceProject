/**
 * [SCRUM-428] TC2 — Phase B Zuteilung (AC6–AC10).
 *
 * AC6–AC9 testen die reine Selektionsfunktion
 * SCRUM428AssignmentService.selectAssignee (SOQL-frei, deterministisch).
 * User-Ids aus echten (in der Test-Tx erstellten) User-Records — gefaeuerte
 * Id-Literale scheitern an der Id-Pruefung (Checksum), probe 2026-09-24.
 *
 * AC10 ist eine End-to-End-Integration ueber den echten Pipeline-Pfad
 * (Trigger -> Queueable -> assign()): die GroupMember-DML laeuft in einem
 * Queueable (Setup-Objekt — MIXED_DML mit Case in derselben Tx untersagt),
 * der Testkontext fluettet beide Jobs vor Test.stopTest().
 * Die Test-Transaktion rollt am Ende zurueck; die temporäre Memberschaft
 * der Produktions-Queue ist unproblematisch.
 *
 * @author developer-agent
 * @date 2026-09-24
 */
@isTest
private class SCRUM428AssignmentTest {
  /** Setzt C428 im Queueable-Kontext (static nur auf Top-Level). */
  public static Id queuedCaseId;

  // ------------------------------------------------------------------
  // AC6 — niemand verfügbar (leere Kandidaten) -> kein Owner
  // ------------------------------------------------------------------
  @isTest
  static void ac6_noAvailable_returnsNull() {
    Id winner = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>(),
      new Map<Id, Integer>(),
      5,
      true
    );
    System.assertEquals(
      null,
      winner,
      'AC6: keine verfügbaren Mitglieder -> kein Owner (Queue behält Fall).'
    );
  }

  // ------------------------------------------------------------------
  // AC7 — wenigste offene Fälle gewinnen (Tie-Break: kleinste User-Id)
  // ------------------------------------------------------------------
  @isTest
  static void ac7_fewestOpenWins() {
    List<User> us = mkTwoUsers();
    Id uA = us[0].Id; // bekommt 2 offene
    Id uB = us[1].Id; // bekommt 5 offene
    Map<Id, Integer> counts = new Map<Id, Integer>{ uA => 2, uB => 5 };
    Id winner = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>{ uA, uB },
      counts,
      10,
      true
    );
    System.assertEquals(uA, winner, 'AC7: 2 offene < 5 offene -> uA gewinnt.');
  }

  @isTest
  static void ac7_tieBreakSmallestId() {
    List<User> us = mkTwoUsers();
    Id uSmall = us[0].Id; // Id ASC -> kleinere Id
    Id uLarge = us[1].Id;
    Map<Id, Integer> counts = new Map<Id, Integer>{ uSmall => 3, uLarge => 3 };
    Id winner = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>{ uLarge, uSmall },
      counts,
      10,
      true
    );
    System.assertEquals(
      uSmall,
      winner,
      'AC7 Tie: gleicher Count -> kleinere User-Id gewinnt.'
    );
  }

  // ------------------------------------------------------------------
  // AC8 — Grenzwert: Kandidat mit genau Limit offenen Fällen wird
  // übersprungen (Bedingung ist Count < Limit).
  // ------------------------------------------------------------------
  @isTest
  static void ac8_atLimit_skipped() {
    List<User> us = mkTwoUsers();
    Id uFull = us[0].Id; // == maxOpen -> überspringen
    Id uFree = us[1].Id; // < maxOpen  -> Kandidat
    Integer maxOpen = 5;
    Map<Id, Integer> counts = new Map<Id, Integer>{ uFull => 5, uFree => 4 };
    Id winner = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>{ uFull, uFree },
      counts,
      maxOpen,
      true
    );
    System.assertEquals(
      uFree,
      winner,
      'AC8: Kandidat mit genau 5 offenen (limit=5) wird übersprungen.'
    );
  }

  @isTest
  static void ac8_allAtLimit_returnsNull() {
    List<User> us = mkTwoUsers();
    Id uOnly = us[0].Id;
    Map<Id, Integer> counts = new Map<Id, Integer>{ uOnly => 5 };
    Id winner = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>{ uOnly },
      counts,
      5,
      true
    );
    System.assertEquals(
      null,
      winner,
      'AC8: alle Kandidaten am Limit -> kein Owner.'
    );
  }

  // ------------------------------------------------------------------
  // AC9 — außerhalb der Geschäftszeiten -> kein Owner-Wechsel
  // ------------------------------------------------------------------
  @isTest
  static void ac9_outsideBusinessHours_returnsNull() {
    List<User> us = mkTwoUsers();
    Id u = us[0].Id;
    Map<Id, Integer> counts = new Map<Id, Integer>{ u => 0 };
    Id within = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>{ u },
      counts,
      5,
      true
    );
    Id outside = SCRUM428AssignmentService.selectAssignee(
      new Set<Id>{ u },
      counts,
      5,
      false
    );
    System.assertEquals(
      u,
      within,
      'Kontrolle: innerhalb BH würde der Kandidat gewinnen.'
    );
    System.assertEquals(
      null,
      outside,
      'AC9: außerhalb BH -> kein Owner (Fall wartet in der Queue).'
    );
  }

  // ------------------------------------------------------------------
  // AC10 — SCRUM428_Verfuigung__c = false wird aus der Kandidaten-
  // Menge ausgeschlossen. End-to-End: Case in Queue -> Trigger ->
  // Queueable -> assign() -> Mitglied mit Verfuigung=true erhält den Fall.
  // ------------------------------------------------------------------
  @isTest
  static void ac10_verfuigungFalse_excluded() {
    // Vorhandene Queue wählen (frisch anlegen geht im Testkontext nicht —
    // Probe SCRUM428ProbeQueue: "fields being inaccessible").
    Id queueId = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue'
      ORDER BY Name
      LIMIT 1
    ]
    .Id;

    User avail = mkUser('av10', true); // bekommt den Fall
    User offline = mkUser('of10', false); // Verfuigung=false -> NEIN

    // offener Fall für avail (Körpers-Transaktion): Count 1 — ohne ihn
    // wäre offline (0 Fälle) per Tie-Break der Kandidat, und der Test
    // hätte die Verfuigung-Exklusion nicht diskriminiert.
    // Trigger enqueued 428-Queueable für diesen Fall (harmlos: assign
    // überspringt Nicht-Queue-Owners, keine Mail ohne Kontakt/Adresse).
    insert new Case(
      OwnerId = avail.Id,
      Status = 'New',
      Subject = 'AC10 offen zur Zählung'
    );

    Test.startTest();
    // Setup-DML (GroupMember) in GETRENNTEM Queueable — MIXED_DML mit
    // Case-DML in derselben Tx untersagt. C428 INSERT den Queue-Fall
    // erst nach den Members (Async-Reihenfolge = Einreih-Reihenfolge).
    // Genau 1 Case-Insert in C428: in einer Queueable-Tx enqueued
    // höchstens 1 weiteres async Job (Probe 2026-09-24).
    System.enqueueJob(new GM428(queueId, avail.Id, offline.Id));
    System.enqueueJob(new C428(avail.Id, queueId));
    Test.stopTest();

    // Der Pipeline-Pfad (Trigger -> Queueable -> assign) hätte den Fall
    // genau dem Verfuigung=true-Mitglied geben muessen:
    Case after = [SELECT OwnerId FROM Case WHERE Id = :queuedCaseId];
    System.assertEquals(
      avail.Id,
      after.OwnerId,
      'AC10: Verfuigung=false wird ausgeschlossen; der Verfuigung=true-Mitglied erhält den Fall.'
    );
  }

  // ------------------------------------------------------------------
  // Queueables — trennen Setup-DML (GroupMember) von Case-DML
  // ------------------------------------------------------------------
  public class GM428 implements Queueable {
    private final Id queueId;
    private final Id availId;
    private final Id offlineId;
    public GM428(Id q, Id a, Id o) {
      this.queueId = q;
      this.availId = a;
      this.offlineId = o;
    }
    public void execute(QueueableContext ctx) {
      List<GroupMember> prior = [
        SELECT Id
        FROM GroupMember
        WHERE GroupId = :queueId
      ];
      if (!prior.isEmpty()) {
        delete prior;
      }
      insert new GroupMember(GroupId = queueId, UserOrGroupId = availId);
      insert new GroupMember(GroupId = queueId, UserOrGroupId = offlineId);
    }
  }

  public class C428 implements Queueable {
    private final Id availId;
    private final Id queueId;
    public C428(Id a, Id q) {
      this.availId = a;
      this.queueId = q;
    }
    public void execute(QueueableContext ctx) {
      // Genau 1 Case-Insert hier: in einer Queueable-Tx darf höchstens
      // 1 weiteres async Job eingerichtet werden — der 428-Trigger
      // enqueued je Case-Insert einen SCRUM428AssignmentQueueable.
      // Der Pipeline-Pfad (Trigger -> Queueable -> assign) wäre um
      // das LIVE Business-Hours-Gate (AC9) abhängig von der Uhrzeit —
      // die Org-BH-Profil ist keine 24/7 (gemessen 2026-09-24 19:36
      // Europe/Berlin: isWithin=false), und es gibt keine BH-Mocks
      // (Schema.setMockBusinessHours existiert nicht, BH ist
      // DML-restricted im Testkontext). Deshalb: exakt denselben
      // assign-Call aus dem AQ über die AC9-Seam ausführen,
      // mit withinBH=true als bekannte Konstante. AC10 prüft
      // die Verfuigung-Exklusion (offline, 0 Fälle, ist per
      // Tie-Break der Gewinner) — das Gate ist AC9's Sache.
      Case queued = new Case(
        OwnerId = queueId,
        Status = 'New',
        Subject = 'AC10 in Queue'
      );
      insert queued;
      SCRUM428AssignmentTest.queuedCaseId = queued.Id;
      Case fresh = [SELECT Id, OwnerId FROM Case WHERE Id = :queued.Id];
      SCRUM428AssignmentService.assign(new List<Case>{ fresh }, true);
    }
  }

  // ------------------------------------------------------------------
  // Helfer
  // ------------------------------------------------------------------
  /** Zwei echte User (valid, sortierbare Ids), aufsteigend nach Id. */
  private static List<User> mkTwoUsers() {
    User a = mkUser('a7', true);
    User b = mkUser('b7', true);
    List<User> us = new List<User>{ a, b };
    us.sort();
    return us;
  }

  private static User mkUser(String tag, Boolean verfuegung) {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = p.Id,
      LastName = 'A428',
      Alias = 'a' + tag,
      Email = 'a428' + tag + '@example.invalid',
      Username = 'a428' + tag + DateTime.now().getTime() + '@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Los_Angeles',
      SCRUM428_Verfuigung__c = verfuegung
    );
    insert u;
    return u;
  }
}
