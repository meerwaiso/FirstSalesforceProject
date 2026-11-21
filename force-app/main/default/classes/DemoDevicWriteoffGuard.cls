/**
 * SCRUM-468 Lend Devices: only sales team leads may write off a device (AC9, AC9n).
 *
 * The discriminator is membership in the marker Permission Set SCRUM468_Writeoff,
 * which carries no rights at all - a Permission Set can only grant, never revoke
 * (skill salesforce-describe-first section 4), so a second grant set could never
 * make the negative test fail. The check lives in the changed-branch of a bulkified
 * guard: one PS query per save, because $User.Id is identical for every record in a
 * batch. UserInfo.getUserId() is the running user (measured in Test-Org, it compiles
 * and returns the CLI user Id); the PSA columns are AssigneeId / PermissionSetId.
 *
 * @author developer-agent
 * @date 2026-11-21
 */
public class DemoDevicWriteoffGuard {

    private static final String WRITEOFF_PS = 'SCRUM468_Writeoff';

    public static void handleBeforeUpdate(List<Demo_Devic__c> newRecords, Map<Id, Demo_Devic__c> oldMap) {
        Boolean wroteOff = false;
        for (Demo_Devic__c record : newRecords) {
            Demo_Devic__c before = oldMap.get(record.Id);
            String oldStatus = (before == null) ? null : before.Status__c;
            if (record.Status__c == 'Written_Off' && oldStatus != 'Written_Off') {
                wroteOff = true;
                break;
            }
        }
        if (!wroteOff) {
            return;
        }
        if (mayWriteOff()) {
            return;
        }
        for (Demo_Devic__c record : newRecords) {
            Demo_Devic__c before = oldMap.get(record.Id);
            String oldStatus = (before == null) ? null : before.Status__c;
            if (record.Status__c == 'Written_Off' && oldStatus != 'Written_Off') {
                record.addError('Lend Devices: only sales team leads may write off a device - this user does not hold '
                    + WRITEOFF_PS + '.');
            }
        }
    }

    private static Boolean mayWriteOff() {
        List<PermissionSet> marker = [SELECT Id FROM PermissionSet WHERE Name = :WRITEOFF_PS LIMIT 1];
        if (marker.isEmpty()) {
            return false;
        }
        Set<Id> runningUser = new Set<Id>{ UserInfo.getUserId() };
        List<PermissionSetAssignment> mine = [
            SELECT Id FROM PermissionSetAssignment
            WHERE PermissionSetId = :marker[0].Id AND AssigneeId IN :runningUser
        ];
        return !mine.isEmpty();
    }
}
