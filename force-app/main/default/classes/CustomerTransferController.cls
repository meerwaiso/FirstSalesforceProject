/**
 * [SCRUM-410] Controller für die LWC `betreuungsuebergabe` (Quick Action auf User).
 *
 * Drei read-only Aufgaben, keine davon mit DML:
 *   - preview(fromUser, toUser): AC1 — Zählung, was bei einer Übergabe den
 *     Owner wechseln würde (Accounts, Kontakte, offene Cases, laufende Opps).
 *   - launch(fromUser, toUser): AC2 — validiert und enqueues den atomaren
 *     Queueable-Job CustomerTransferJob. Der Audit-Insert passiert IM Job,
 *     damit Audit + Transfer eine Transaktion sind (Design-ADR 2).
 *   - availableUsers(excludeUser): Picker-Optionen für „Übernimmt".
 *
 * without sharing (bewusst, SCRUM-365-Präzedenz): Die Vorschau zählt die
 * vollständige Betreuungslast der abgebenden Person — die Teamleitung, die den
 * Job anstößt, muss nicht selbst Read-Zugriff auf jede einzelne der 300
 * Accounts haben (OWD-Private). Sonst wäre die Vorschau OWD-abhängig falsch.
 *
 * @author developer-agent
 * @date 2026-09-11
 */
public without sharing class CustomerTransferController {

    @AuraEnabled
    public static Map<String, Object> preview(Id fromUserId, Id toUserId) {
        validateUsers(fromUserId, toUserId);
        Map<String, Object> result = new Map<String, Object>();
        result.put('accounts',
            [SELECT COUNT(Id) cnt FROM Account WHERE OwnerId = :fromUserId][0].get('cnt'));
        result.put('contacts',
            [SELECT COUNT(Id) cnt FROM Contact WHERE OwnerId = :fromUserId][0].get('cnt'));
        result.put('openCases',
            [SELECT COUNT(Id) cnt FROM Case WHERE OwnerId = :fromUserId AND IsClosed = false][0].get('cnt'));
        result.put('openOpportunities',
            [SELECT COUNT(Id) cnt FROM Opportunity WHERE OwnerId = :fromUserId AND IsClosed = false][0].get('cnt'));
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> launch(Id fromUserId, Id toUserId) {
        validateUsers(fromUserId, toUserId);
        Id jobId = System.enqueueJob(new CustomerTransferJob(fromUserId, toUserId));
        Map<String, Object> result = new Map<String, Object>();
        result.put('jobId', jobId);
        return result;
    }

    /**
     * Name des User-Records, auf dem die Quick Action geöffnet wurde.
     * Kleiner Ersatz für den lightning/schema-Import, dessen Modul-Reference
     * das LWC-Compile scheitern lässt.
     */
    @AuraEnabled
    public static String userName(Id userId) {
        if (userId == null) {
            return null;
        }
        for (User u : [SELECT Name FROM User WHERE Id = :userId LIMIT 1]) {
            return u.Name;
        }
        return null;
    }

    /**
     * Wählbare aktive Nutzer für den „Übernimmt"-Picker. Der Nutzer des
     * aktuellen User-Records (der „gibt ab") wird ausgeschlossen — die
     * from==to-Validierung bleibt als Sicherheitsnetz in validateUsers().
     */
    @AuraEnabled
    public static List<Map<String, Object>> availableUsers(Id excludeUserId) {
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        for (User u : [
            SELECT Id, Name FROM User
            WHERE IsActive = true AND Id != :excludeUserId
            ORDER BY Name
            LIMIT 1000
        ]) {
            Map<String, Object> opt = new Map<String, Object>();
            opt.put('value', u.Id);
            opt.put('label', u.Name);
            options.add(opt);
        }
        return options;
    }

    /**
     * Gemeinsame Validierung für preview/launch: beide Ids gesetzt, verschieden,
     * vorhanden und aktiv. Wirft AuraHandledException mit deutscher Meldung
     * (wird in der LWC als Toast/Inline-Text angezeigt).
     */
    private static void validateUsers(Id fromUserId, Id toUserId) {
        if (fromUserId == null || toUserId == null) {
            throw new AuraHandledException(
                'Bitte beide Personen wählen: wer gibt ab und wer übernimmt.'
            );
        }
        if (fromUserId == toUserId) {
            throw new AuraHandledException(
                'Die abgebende und die übernehmende Person müssen verschieden sein.'
            );
        }
        Set<Id> ids = new Set<Id>{fromUserId, toUserId};
        Map<Id, User> byId = new Map<Id, User>();
        for (User u : [SELECT Id, IsActive FROM User WHERE Id IN :ids]) {
            byId.put(u.Id, u);
        }
        if (!byId.containsKey(fromUserId) || !byId.containsKey(toUserId)) {
            throw new AuraHandledException(
                'Für mindestens eine der gewählten Personen wurde kein Nutzer in der Org gefunden.'
            );
        }
        if (!byId.get(fromUserId).IsActive) {
            throw new AuraHandledException('Die abgebende Person ist ein inaktiver Nutzer.');
        }
        if (!byId.get(toUserId).IsActive) {
            throw new AuraHandledException('Die übernehmende Person ist ein inaktiver Nutzer.');
        }
    }
}
