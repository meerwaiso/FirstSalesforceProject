trigger CaseEscalationKundeTrigger on Case (after update, after insert) {
    // SCRUM-420: nur nach-Phasen — der Recomputation laest den DB-Zustand, an den
    // das aktuell geaenderte Record seinen neuen Status erst ab afterUpdate liefert
    // (BEFORE wuerde den Zaelwert des eigenen Cases unterbewerten).
    if (Trigger.isAfter && Trigger.isUpdate) {
        CaseEscalationKundeTrigger.afterUpdate();
    } else if (Trigger.isAfter && Trigger.isInsert) {
        CaseEscalationKundeTrigger.afterInsert();
    }
}
