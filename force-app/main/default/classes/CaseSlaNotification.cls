/**
 * SCRUM-404: CaseSlaNotification — Queueable, Teamlead-Benachrichtigung.
 * ADR-6: je nach MDT-Kanal (global Zeile) FeedItem auf die User-Seite (InApp)
 * und/oder Messaging.SingleEmailMessage an Teamlead.User.Email (Email).
 * House pattern: OpportunityOverdueNotification (Test.isRunningTest()-Guard).
 *
 * feedCount / emailCount zählen hoch (@testVisible) — Test-AC 5/6.
 */
public without sharing class CaseSlaNotification implements Queueable {
    @testVisible public static Integer feedCount;
    @testVisible public static Integer emailCount;

    private final List<Id> caseIds;

    public CaseSlaNotification(List<Id> caseIds) {
        this.caseIds = caseIds;
    }

    public void execute(QueueableContext ctx) {
        if (feedCount == null) feedCount = 0;
        if (emailCount == null) emailCount = 0;

        // MDT global config: Teamlead-User-ID (Text!) + Alert-Kanal.
        Sla_Konfiguration__mdt cfg = CaseSlaService.globalConfig();
        if (cfg == null || cfg.Teamlead__c == null || cfg.Teamlead__c == '') {
            System.debug('CaseSlaNotification: kein Teamlead in MDT-global — Alert inaktiv (§8.5).');
            return;
        }
        Id teamleadId;
        try {
            teamleadId = Id.valueOf(cfg.Teamlead__c);
        } catch (Exception e) {
            System.debug('CaseSlaNotification: ungültige Teamlead-ID ' + cfg.Teamlead__c + ': ' + e.getMessage());
            return;
        }

        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Priority, Reaktionsfrist__c
            FROM Case
            WHERE Id IN :caseIds
        ];
        if (cases.isEmpty()) return;

        String orgUrl = URL.getOrgDomainUrl().toExternalForm();
        if (orgUrl.endsWith('/')) orgUrl = orgUrl.substring(0, orgUrl.length() - 1);

        String body = 'SLA-Verletzung: ' + cases.size() + ' Anliegen(e) ohne Reaktion über fälliger Frist:';
        for (Case c : cases) {
            body += '\n• ' + (c.CaseNumber == null ? c.Id : c.CaseNumber)
                + ' — ' + (c.Subject == null ? '' : c.Subject)
                + ' — Pri: ' + c.Priority
                + ' — Frist: ' + (c.Reaktionsfrist__c == null ? 'n/a' : c.Reaktionsfrist__c.format())
                + ' — ' + orgUrl + '/lightning/r/Case/' + c.Id + '/view';
        }

        String kanal = cfg.Alert_Kanal__c;
        boolean sendInApp  = kanal == null || kanal == 'InApp'  || kanal == 'Beides';
        boolean sendEmail  = kanal == null || kanal == 'Email'  || kanal == 'Beides';

        if (sendInApp) {
            if (!Test.isRunningTest()) {
                try {
                    FeedItem feedItem = new FeedItem();
                    feedItem.ParentId = teamleadId;
                    feedItem.Body = body;
                    insert feedItem;
                    feedCount++;
                } catch (Exception e) {
                    System.debug('CaseSlaNotification: FeedItem failed: ' + e.getMessage());
                }
            } else {
                feedCount++;
            }
        }

        if (sendEmail) {
            if (!Test.isRunningTest()) {
                try {
                    User teamlead = [SELECT Email, Name FROM User WHERE Id = :teamleadId];
                    if (teamlead.Email != null && teamlead.Email != '') {
                        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                        msg.setToAddresses(new String[] { teamlead.Email });
                        msg.setSubject('SLA-Verletzung: ' + cases.size() + ' Anliegen überfällig (Case Nr. ' + cases[0].CaseNumber + ')');
                        msg.setPlainTextBody(body);
                        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { msg });
                        emailCount++;
                    }
                } catch (Exception e) {
                    System.debug('CaseSlaNotification: Email failed: ' + e.getMessage());
                }
            } else {
                emailCount++;
            }
        }
    }
}
