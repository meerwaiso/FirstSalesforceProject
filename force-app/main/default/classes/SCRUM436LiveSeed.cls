// SCRUM-436 Tester-Live-Seed: pflanzt backdated offene + 1 geschlossenen Case,
// berechnet exakte Werktag-Zaehler mit CaseReminderService.workingDaysBetween
// (public) und liest den Ausgangszustand zurueck. Admin-Modus = volle FLS.
public class SCRUM436LiveSeed {
    public class Spec {
        public String label;
        public String status;
        public String priority;
        public Integer targetWd;
        public Spec(String l, String s, String p, Integer t) {
            this.label = l; this.status = s; this.priority = p; this.targetWd = t;
        }
    }

    public static void run() {
        DateTime asOf = System.now();
        Id myId = UserInfo.getUserId();
        String suffix = String.valueOf(System.now().getTime());

        List<Spec> specs = new List<Spec> {
            new Spec('std5',  'Working',  'Medium', 5),   // > 3  -> FLAG
            new Spec('std1',  'Working',  'Medium', 1),   // <= 3 -> nein
            new Spec('high2', 'Working',  'High',   2),   // > 1  -> FLAG
            new Spec('high0', 'New',      'High',   0),   // = 0  -> nein
            new Spec('new5',  'New',      'Medium', 5),   // monitored, >3 -> FLAG
            new Spec('esc5',  'Escalated','Medium', 5),   // monitored, >3 -> FLAG
            new Spec('clsd5', 'Closed',   'Medium', 5)    // closed -> nie
        };

        List<Case> toInsert = new List<Case>();
        for (Spec s : specs) {
            DateTime start = null;
            for (Integer back = 0; back <= 30; back++) {
                DateTime cand = asOf.addDays(-back);
                if (CaseReminderService.workingDaysBetween(cand, asOf) == s.targetWd) {
                    start = cand; break;
                }
            }
            if (start == null) {
                System.debug('SEED-FAIL no start for ' + s.label);
                continue;
            }

            Case c = new Case(
                Subject  = 'SCRUM436T_' + s.label + '_' + suffix,
                Origin   = 'Phone',
                Status   = s.status,
                Priority = s.priority,
                Last_Relevant_Update__c = start
            );
            if (s.status == 'Closed') {
                c.Ursache__c = 'TechnischerFehler'; // Org-Validierung (Dev-Befund)
            }
            c.OwnerId = myId;
            toInsert.add(c);
            System.debug('SEED ' + s.label + ' ' + s.status + '/' + s.priority
                + ' start=' + start);
        }
        insert toInsert;   // admin-Modus, volle FLS

        // Read-back des Anfangszustands (LIKE ohne Backslash = kein Escape-Problem).
        for (Case c : [SELECT Subject, Status, Priority,
                             Last_Relevant_Update__c, Reminder_Required__c,
                             Reminder_Due_Date__c, Reminder_Count__c
                       FROM Case WHERE Subject LIKE 'SCRUM436T%'
                       ORDER BY Subject]) {
            if (c.Subject.endsWith(suffix)) {
                System.debug('INIT ' + c.Subject + ' ' + c.Status + '/' + c.Priority
                    + ' flag=' + c.Reminder_Required__c
                    + ' due=' + c.Reminder_Due_Date__c
                    + ' count=' + c.Reminder_Count__c
                    + ' lru=' + c.Last_Relevant_Update__c);
            }
        }
        System.debug('SEED-DONE suffix=' + suffix);
    }
}
