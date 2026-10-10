/**
 * CaseSatisfactionTrigger — SCRUM-442: one Trigger per object (house
 * SCRUM-440/319/381/416), after update + after insert.
 *
 * after update: the closing path (Status -> Closed or IsClosed -> true via
 * console UI, REST/CLI, queue paths SCRUM-421/422, Apex). The ValRule
 * Customer_Satisfaction_PflichtBeiClosed already rejected a score-less closing
 * on the end-state, so every closed Case reaching here carries a score.
 *
 * after insert: a Case created already closed (data import) — the ValRule
 * applies there too; the handler only reacts to a low score.
 *
 * Governor: 0 SOQL, 0 DML here — all logic in SatisfactionTaskHandler, one
 * call per operation.
 *
 * @author developer-agent
 * @date 2026-10-10
 */
trigger CaseSatisfactionTrigger on Case (after update, after insert) {
    if (Trigger.isUpdate) {
        SatisfactionTaskHandler.handle(Trigger.new);
    } else if (Trigger.isInsert) {
        SatisfactionTaskHandler.handle(Trigger.new);
    }
}
