/**
 * [SCRUM-428] Phase B Zuteilung (ADR-3 Schritt 7, AC6–AC10).
 *
 * Wählt pro Case aus den verfügbaren Mitgliedern der aktuellen Queue (Owner
 * = Queue) das Teammitglied mit den wenigsten offenen Fällen, unter
 * Einhaltung des konfigurierbaren Limits (MDT, Default 5) und des Business-Hours-Gates.
 *
 * Reine Logik als injizierbare Selektionsfunktion (selectAssignee) — das ist
 * die Test-Same. Business-Hours: die Org steht auf 24/7, in Test-Kontext ist
 * BusinessHours DML-restrikt und es gibt keinen Mock — also wird das Gate als
 * Boolean in selectAssignee injiziert (AC9: "außerhalb → kein Owner" ist so
 * testbar, End-to-End auf der 24/7-Org nicht — wie AC7 SCRUM-424).
 *
 * Bulk: 1 SOQL je Schritt (Mitglieder, offene Fälle), MDT-Limit 1×, 1 DML.
 * without sharing (Automation-Kontext — Haus-Pattern SCRUM-420/398/421).
 *
 * @author developer-agent
 * @date 2026-09-24
 */
public without sharing class SCRUM428AssignmentService {

    /** Fallback-Limit, falls MDT „Standard" leer/fehlend. */
    public static final Integer DEFAULT_LIMIT = 5;

    /**
     * Reine Selektionsfunktion — SOQL-frei, damit AC6–AC10 unit-testbar sind.
     *
     * @param availableUserIds  verfügbare Queue-Mitglieder (aktiv + Verfuigung=true) — AC10
     * @param openCounts        offene Fälle je User (Status != 'Closed') — AC8
     * @param limit             max. offene Fälle, Kandidat nur bei count < limit — AC8
     * @param withinBusinessHours AC9 — false => kein Owner-Wechsel
     * @return UserId des Gewinners oder null (AC6: niemand qualifiziert / AC9: außerhalb)
     */
    public static Id selectAssignee(Set<Id> availableUserIds,
                                    Map<Id, Integer> openCounts,
                                    Integer limit,
                                    Boolean withinBusinessHours) {
        if (!withinBusinessHours) {
            return null; // AC9: außerhalb der Geschäftszeiten -> kein Owner-Wechsel
        }
        if (availableUserIds == null || availableUserIds.isEmpty()) {
            return null; // AC6: niemand verfügbar -> verbleibt in der Queue
        }
        if (limit == null) {
            limit = DEFAULT_LIMIT;
        }
        Id best = null;
        Integer bestCount = null;
        for (Id uid : availableUserIds) {
            Integer c = (openCounts != null && openCounts.containsKey(uid)) ? openCounts.get(uid) : 0;
            if (c >= limit) {
                continue; // AC8: limit erreicht -> überspringen
            }
            if (best == null || c < bestCount || (c == bestCount && uid < best)) {
                // wenigste gewinnt; Tie-Break: kleinstes User.Id (deterministisch)
                best = uid;
                bestCount = c;
            }
        }
        return best;
    }

    /**
     * Wendet die Zuteilung auf eine Liste von Cases an. Liest die aktuelle
     * OwnerId (muss eine Queue sein), holt Mitglieder + offene Falls counts,
     * wählt je Case und schreibt in genau 1 DML.
     *
     * @param cases  Cases, die neu angelegt/zugeordnet wurden (Phase A liefert)
     * @return Anzahl tatsächlich neu zugeordneter Cases
     */
    public static Integer assign(List<Case> cases) {
        return assign(cases, isWithinBusinessHours());
    }

    /**
     * Wie {@link #assign(List<Case>)}, aber mit injiziertem Business-Hours-Gate
     * (Test-Seam für AC9: die Test-Org steht auf 24/7 und BusinessHours ist im
     * Test-Kontext DML-restrikt — ein End-to-End-Nachweis „außerhalb → kein
     * Owner\" ist nicht möglich, wohl aber die Logik über diese Seam).
     */
    public static Integer assign(List<Case> cases, Boolean withinBusinessHours) {
        if (cases == null || cases.isEmpty()) {
            return 0;
        }
        // Nur Cases, deren Owner aktuell eine Queue ist, sind zuordenbar.
        Set<Id> ownerIds = new Set<Id>();
        for (Case c : cases) {
            if (c.OwnerId != null) {
                ownerIds.add(c.OwnerId);
            }
        }
        if (ownerIds.isEmpty()) {
            return 0;
        }

        // 1 SOQL: welche dieser Owner-Ids sind Queues?
        Map<Id, String> queueNameById = new Map<Id, String>();
        for (Group g : [SELECT Id, Name FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']) {
            queueNameById.put(g.Id, g.Name);
        }
        if (queueNameById.isEmpty()) {
            return 0; // kein Case in einer Queue -> nichts zu tun
        }

        Integer limit = loadLimit();

        // 1 SOQL: verfügbare Mitglieder aller relevanten Queues, als je-Queue-Map
        // (kein SOQL-in-Loop — ein Durchlauf baut queueId -> memberIds).
        Map<Id, Set<Id>> membersByQueue = new Map<Id, Set<Id>>();
        Set<Id> allMembers = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId, GroupId
            FROM GroupMember
            WHERE GroupId IN :queueNameById.keySet()
              AND UserOrGroupId IN (
                    SELECT Id FROM User WHERE IsActive = true AND SCRUM428_Verfuigung__c = true
              )
        ]) {
            if (gm.UserOrGroupId != null && gm.GroupId != null) {
                allMembers.add(gm.UserOrGroupId);
                if (!membersByQueue.containsKey(gm.GroupId)) {
                    membersByQueue.put(gm.GroupId, new Set<Id>());
                }
                membersByQueue.get(gm.GroupId).add(gm.UserOrGroupId);
            }
        }
        Map<Id, Integer> openCounts = new Map<Id, Integer>();
        if (!allMembers.isEmpty()) {
            // 1 SOQL: offene Fälle je verfügbarem Mitglied (Status != Closed, AC8).
            for (AggregateResult r : [
                SELECT OwnerId, COUNT(Id) cnt
                FROM Case
                WHERE OwnerId IN :allMembers AND Status != 'Closed'
                GROUP BY OwnerId
            ]) {
                openCounts.put((Id) r.get('OwnerId'), (Integer) r.get('cnt'));
            }
        }

        List<Case> toUpdate = new List<Case>();
        for (Case c : cases) {
            if (!queueNameById.containsKey(c.OwnerId)) {
                continue; // Owner keine Queue (z.B. schon User) -> überspringen
            }
            // Kandidaten sind genau die verfügbaren Mitglieder DIESER Queue.
            Set<Id> queueMembers = membersByQueue.get(c.OwnerId);
            if (queueMembers == null) {
                queueMembers = new Set<Id>(); // leere Queue -> AC6
            }
            Id winner = selectAssignee(queueMembers, openCounts, limit, withinBusinessHours);
            if (winner == null) {
                continue; // AC6/AC9: kein Owner-Wechsel
            }
            if (c.OwnerId != winner) {
                Case u = new Case(Id = c.Id,
                        OwnerId = winner,
                        Automatische_Zuordnung__c = true,
                        Zuordnungszeitpunkt__c = System.now());
                toUpdate.add(u);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }

    /** Limit aus MDT „Standard" (Default 5, Fallback bei leerer Zeile). */
    public static Integer loadLimit() {
        for (SCRUM428_CaseLimitConfig__mdt md : [
            SELECT MaxOffene__c
            FROM SCRUM428_CaseLimitConfig__mdt
            WHERE DeveloperName = 'Standard'
            LIMIT 1
        ]) {
            if (md.MaxOffene__c != null) {
                return (Integer) md.MaxOffene__c;
            }
        }
        return DEFAULT_LIMIT;
    }

    /** Business-Hours-Gate (AC9) via Default-Profil der Org. */
    public static Boolean isWithinBusinessHours() {
        List<BusinessHours> bhs = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];
        if (bhs.isEmpty()) {
            return true; // kein Profil -> nicht gate-blockieren (24/7-Default)
        }
        return BusinessHours.isWithin(bhs[0].Id, System.now());
    }
}
