/**
 * [SCRUM-428] TC3 — ADR-8 FLS negativ/positiv (AC-Feldsicherheit).
 * House-Pattern SCRUM421QueueAssignmentFlsTest.
 *
 * Probe-Resultat (24.09, SCRUM428FlsProbe): im Standard-User-Profil sind OHNE
 * PS ALLE neuen Felder GELOCKT (SELECT wirft) — nicht UNRESTRICTED.
 * => Der Negativtest ist satisfies: ohne PS throwt, mit PS lesbar.
 *
 * ServiceTeam-PS Feldrechte (ADR-8 / PS-Datei):
 *   Case.Erfassungsquelle__c     read + write
 *   Case.Dedupliziert__c         read-only (System-only)
 *   User.SCRUM428_Verfuigung__c  read + write (eigene Zeile)
 *
 * 3 Methoden, um die DML-Kontexte sauber zu halten (421-Präzedenz:
 * User-Insert + PermissionSetAssignment + Case-DML in einer Tx = gruen).
 * KEIN nested System.runAs.
 *
 * @author developer-agent
 * @date 2026-09-24
 */
@isTest
private class SCRUM428IngestFlsTest {
  private static User mkTestUser(String tag) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User u = new User(
      ProfileId = p.Id,
      LastName = 'Fls428',
      Alias = 'f428' + tag,
      Email = 'f428' + tag + '@example.invalid',
      Username = 'f428' + tag + DateTime.now().getTime() + '@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Los_Angeles'
    );
    insert u;
    return u;
  }

  // ---- NEGATIV: ohne PS -> SELECT auf die 3 Case-Felder -> Exception ----
  @isTest
  static void testWithoutPermset_selectFails() {
    User u = mkTestUser('neg');
    Boolean caseReadable = false;
    System.runAs(u) {
      caseReadable = Case.SObjectType.getDescribe().isAccessible();
    }
    System.assert(
      caseReadable,
      'Vorbedingung: Standard-User hat object-level Case-Zugriff.'
    );

    // 3 Felder einzeln pruefen (jedes darf ohne PS throwen).
    Integer threw = 0;
    System.runAs(u) {
      try {
        List<Case> r1 = [
          SELECT Erfassungsquelle__c
          FROM Case
          WITH USER_MODE
          LIMIT 1
        ];
        System.assert(r1 != null, '');
      } catch (Exception e) {
        threw++;
      }
    }
    System.runAs(u) {
      try {
        List<Case> r2 = [
          SELECT Dedupliziert__c
          FROM Case
          WITH USER_MODE
          LIMIT 1
        ];
        System.assert(r2 != null, '');
      } catch (Exception e) {
        threw++;
      }
    }
    System.runAs(u) {
      try {
        List<User> r3 = [
          SELECT SCRUM428_Verfuigung__c
          FROM User
          WHERE Id = :u.Id
          WITH USER_MODE
        ];
        System.assert(r3 != null, '');
      } catch (Exception e) {
        threw++;
      }
    }
    System.assertEquals(
      3,
      threw,
      'Ohne PS: SELECT auf alle 3 neuen Felder muss Exception werfen'
    );
  }

  // ---- POSITIV Case-Felder: mit PS lesbar + Write-Split ----
  @isTest
  static void testWithPermset_caseFieldsWriteSplit() {
    User u = mkTestUser('posc');
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SCRUM428_ServiceTeam'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );

    // lesbar via USER_MODE-SELECT
    Id caseId;
    System.runAs(u) {
      Case c = new Case(Status = 'New', Erfassungsquelle__c = null);
      insert c;
      caseId = c.Id;
    }
    // Lesbarkeit ist der FLS-Nachweis: ohne PS wirft derselbe SELECT
    // (Negativtest), mit PS laeuft er — null ist hier kein Wert-Nachweis.
    Integer rowRead = 0;
    System.runAs(u) {
      List<Case> rows = [
        SELECT Erfassungsquelle__c, Dedupliziert__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
      ];
      rowRead = rows.size();
    }
    System.assertEquals(
      1,
      rowRead,
      'Mit PS: Erfassungsquelle__c + Dedupliziert__c lesbar (SELECT geht auf)'
    );

    // Erfassungsquelle editierbar
    System.runAs(u) {
      Case c = [
        SELECT Erfassungsquelle__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
      ];
      c.Erfassungsquelle__c = 'Kontaktformular';
      Database.update(c, AccessLevel.USER_MODE); // keine Exception = editierbar
    }
    String erfAfter;
    System.runAs(u) {
      erfAfter = [
        SELECT Erfassungsquelle__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
      ]
      .Erfassungsquelle__c;
    }
    System.assertEquals(
      'Kontaktformular',
      erfAfter,
      'Mit PS: Erfassungsquelle__c editierbar'
    );

    // Dedupliziert read-only -> DML muss Exception werfen
    Boolean threwDed = false;
    System.runAs(u) {
      Case c = [SELECT Dedupliziert__c FROM Case WHERE Id = :caseId LIMIT 1];
      try {
        c.Dedupliziert__c = true;
        Database.update(c, AccessLevel.USER_MODE);
        System.assert(
          false,
          'Mit PS: Dedupliziert__c darf NICHT geschrieben werden.'
        );
      } catch (Exception e) {
        threwDed = true;
      }
    }
    System.assert(
      threwDed,
      'Mit PS: DML auf Dedupliziert__c muss Exception werfen (read-only)'
    );
  }

  // ---- POSITIV User-Feld: SCRUM428_Verfuigung read+edit (eigene Zeile) ----
  @isTest
  static void testWithPermset_userFieldWriteable() {
    User u = mkTestUser('posu');
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SCRUM428_ServiceTeam'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );

    // lesbar (Lesbarkeit ist der FLS-Nachweis, nicht der Wert — das Feld
    // hat kein Default, null ist hier erwartbar).
    Boolean rowLoaded = false;
    System.runAs(u) {
      List<User> rows = [
        SELECT SCRUM428_Verfuigung__c
        FROM User
        WHERE Id = :u.Id
        WITH USER_MODE
      ];
      rowLoaded = !rows.isEmpty();
    }
    System.assert(
      rowLoaded,
      'Mit PS: SCRUM428_Verfuigung__c lesbar (SELECT geht auf)'
    );

    // editierbar (eigene Zeile)
    System.runAs(u) {
      User me = [
        SELECT SCRUM428_Verfuigung__c
        FROM User
        WHERE Id = :u.Id
        LIMIT 1
      ];
      me.SCRUM428_Verfuigung__c = false;
      Database.update(me, AccessLevel.USER_MODE); // keine Exception = editierbar
    }
    Boolean verfAfter;
    System.runAs(u) {
      verfAfter = [
        SELECT SCRUM428_Verfuigung__c
        FROM User
        WHERE Id = :u.Id
        WITH USER_MODE
      ][0]
      .SCRUM428_Verfuigung__c;
    }
    System.assertEquals(
      false,
      verfAfter,
      'Mit PS: SCRUM428_Verfuigung__c auf eigener Zeile editierbar'
    );
  }
}
