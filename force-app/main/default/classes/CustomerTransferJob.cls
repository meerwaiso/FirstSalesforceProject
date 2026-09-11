/**
 * [SCRUM-410] Atomare Betreuung-Übergabe als EINER Queueable-Job in EINER
 * Transaktion (Design-ADR 2): 4 Bulk-DMLs + 1 Audit-Insert — alles oder
 * nichts, kein Teilergebnis, nichts „bleibt liegen".
 *
 * Scope (PO-Entscheidung, SCRUM-410): Accounts + alle Kontakte der abgebenden
 * Person; offene Cases (IsClosed=false) und laufende Opportunities
 * (IsClosed=false) wechseln mit. Abgeschlossene Historie wird NICHT geladen
 * und bleibt beim alten Betreuer (AC4). Es wird ausschließlich OwnerId
 * geschrieben — Status/Frist/Priorität sind dadurch unveränderbar (AC3,
 * Construct-by-Construction).
 *
 * Governor (AC7, 300 Kunden): 4 SELECTs + 4 Updates + 1 Insert, keine
 * SOQL/DML in Loops. 300 Accounts + einige tausend Child-Records liegen
 * weit unter den real-time-Limits. Dokumentierter Fallback (ADR 2): wächst
 * ein Gebiet jenseits ~5.000 betroffener Child-Records, wird die Klasse auf
 * Database.Batchable umgestellt (dann keine Atomicität mehr) — für 300
 * Kunden: Queueable.
 *
 * without sharing (bewusst, wie der Job selbst SCRUM-365-Präzedenz): Der
 * Job darf Records der abgebenden Person umschreiben, unabhängig vom Read-/
 * Update-Recht des anstoßenden Nutzers — systemischer Ownership-Wechsel,
 * kein User-edit.
 *
 * Tests: SCRUM410CustomerTransferTest (Apex, Phase 3).
 *
 * @author developer-agent
 * @date 2026-09-11
 */
public without sharing class CustomerTransferJob implements Queueable {

    /** Audit-Status bei erfolgreichem atomaren Lauf (Picklist CustomerTransfer__c.Status__c). */
    public static final String STATUS_DONE = 'Abgeschlossen';

    private final Id fromUserId;
    private final Id toUserId;

    public CustomerTransferJob(Id fromUserId, Id toUserId) {
        this.fromUserId = fromUserId;
        this.toUserId = toUserId;
    }

    public void execute(QueueableContext ctx) {
        // 4× Bulk-SOQL (je 1 Query, keine Query pro Record):
        List<Account> accounts = [SELECT Id FROM Account WHERE OwnerId = :fromUserId];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE OwnerId = :fromUserId];
        // Abgeschlossene Records werden NIE geladen => sie behalten ihren
        // alten Owner (AC4).
        List<Case> openCases = [
            SELECT Id FROM Case WHERE OwnerId = :fromUserId AND IsClosed = false
        ];
        List<Opportunity> openOpps = [
            SELECT Id FROM Opportunity WHERE OwnerId = :fromUserId AND IsClosed = false
        ];

        // 4× Bulk-DML: nur OwnerId wird geschrieben (AC3/AC4).
        for (Account a : accounts) {
            a.OwnerId = toUserId;
        }
        if (!accounts.isEmpty()) {
            update accounts;
        }
        for (Contact c : contacts) {
            c.OwnerId = toUserId;
        }
        if (!contacts.isEmpty()) {
            update contacts;
        }
        for (Case cs : openCases) {
            cs.OwnerId = toUserId;
        }
        if (!openCases.isEmpty()) {
            update openCases;
        }
        for (Opportunity o : openOpps) {
            o.OwnerId = toUserId;
        }
        if (!openOpps.isEmpty()) {
            update openOpps;
        }

        // 1× Audit-Insert, ATOMAR mit dem Transfer (gleiche Transaktion) (AC6).
        CustomerTransfer__c audit = new CustomerTransfer__c(
            From_User__c = fromUserId,
            To_User__c = toUserId,
            Transferred_At__c = System.now(),
            Accounts_Transferred__c = accounts.size(),
            Contacts_Transferred__c = contacts.size(),
            Open_Cases_Transferred__c = openCases.size(),
            Open_Opportunities_Transferred__c = openOpps.size(),
            Status__c = STATUS_DONE
        );
        insert audit;
    }
}
