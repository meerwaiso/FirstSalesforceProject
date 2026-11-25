/**
 * [SCRUM-477][Tester] Tage jetzige Stage — NEGATIVE FLS proof (AC9) plus the
 * write-side for the user who CAN read it (AC8).
 *
 * What this class adds on top of SCRUM477StageDaysReadTest (Developer):
 *   the Developer proved the READ side for the real users. Nobody proved that a
 *   user who can see the Opportunity but does NOT hold SCRUM477_CurrentStageDays_Read
 *   is genuinely blocked from the number — the one criterion that separates an
 *   assigned Permission Set from a deployed-but-useless one. Absence of FLS
 *   metadata is never proof of inheritance, so this is asserted against a real
 *   session: getDescribe() AND a SOQL read of the field.
 *
 * Route: Apex System.runAs with a synthetic Standard User. This Developer Edition
 * org has two Salesforce licences, both taken by System Administrators, so a
 * second Playwright session under a reduced profile is impossible; System.runAs
 * is the house route (mkUser copied from SCRUM449OpportunityRiskFlsTest).
 *
 * @author tester-agent
 * @date 2026-11-25
 */
@isTest(SeeAllData=true)
public class SCRUM477CurrentStageDaysFlsTest {
  private static User mkUser(String alias) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    return new User(
      ProfileId = p.Id,
      LastName = 'Fls477',
      Alias = alias,
      Email = alias + '477@example.invalid',
      Username = alias + '477_' + DateTime.now().getTime() + '@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Los_Angeles'
    );
  }

  @isTest
  static void dayCounter_hiddenWithoutPermissionSet_readOnlyWithIt() {
    User u = mkUser('fls477u');
    insert u;

    boolean objectVisible = false;
    System.runAs(u) {
      objectVisible = Opportunity.SObjectType.getDescribe().isAccessible();
    }
    // Precondition, asserted outside the block (house warning SCRUM449/453:
    // an assert whose failure the block swallows would read as a pass).
    System.assert(
      objectVisible,
      'Precondition: the test user cannot see the Opportunity object — the negative asserts below would pass for the wrong reason'
    );

    // NEGATIVE (AC9): object access only, no SCRUM477 Permission Set.
    boolean fieldReadable = true;
    boolean fieldWritable = true;
    System.runAs(u) {
      fieldReadable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe()
        .isAccessible();
      fieldWritable = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe()
        .isUpdateable();
    }
    System.assertEquals(
      false,
      fieldReadable,
      'AC9: a user who can see the deal but does not hold SCRUM477_CurrentStageDays_Read could read the day counter'
    );
    System.assertEquals(
      false,
      fieldWritable,
      'AC9: that user could also write the day counter'
    );

    // The block is not only a metadata answer: a real SOQL read must fail too.
    boolean queryRejected = false;
    Integer rows = -1;
    System.runAs(u) {
      try {
        List<Opportunity> found = [
          SELECT Id, Stage_Days_In_Current_Stage__c
          FROM Opportunity
          WHERE Stage_Days_In_Current_Stage__c > 30
        ];
        rows = found.size();
      } catch (Exception e) {
        queryRejected = true;
      }
    }
    System.assertEquals(
      true,
      queryRejected,
      'AC9: SOQL served the day counter to a user without the Permission Set (rows: ' +
        rows +
        ')'
    );

    // POSITIVE: grant the deployed read-only Permission Set of this story.
    List<PermissionSet> psHits = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SCRUM477_CurrentStageDays_Read'
    ];
    System.assertEquals(
      1,
      psHits.size(),
      'the read-only Permission Set of SCRUM-477 is not in the org'
    );
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = psHits[0].Id
    );

    boolean readableWithPs = false;
    boolean writableWithPs = false;
    System.runAs(u) {
      readableWithPs = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe()
        .isAccessible();
      writableWithPs = Opportunity.Stage_Days_In_Current_Stage__c.getDescribe()
        .isUpdateable();
    }
    System.assertEquals(
      true,
      readableWithPs,
      'AC9: even with the Permission Set the counter stayed unreadable'
    );
    // AC8: nobody may edit the number, not even the user who can read it.
    System.assertEquals(
      false,
      writableWithPs,
      'AC8: the day counter was writable for a user who holds the read-only Permission Set'
    );
  }
}
