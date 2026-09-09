/**
 * SCRUM-404: CaseSlaScheduler — 15-min Schedulable-Wrapper für den Batch.
 * ADR-6: Such-Kriterium = Frist gesetzt, KEINE erste Rückmeldung,
 * Frist < NOW(), Alert noch nicht gesendet.
 * Hausmuster: OpportunityOverdueScheduler (Schedulable → Service).
 */
public without sharing class CaseSlaScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new CaseSlaAlertBatch(), 200);
    }
}
