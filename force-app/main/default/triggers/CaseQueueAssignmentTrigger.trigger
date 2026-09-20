trigger CaseQueueAssignmentTrigger on Case (after insert, after update) {
    // [SCRUM-421] Queue-Zuordnung: nur after-Phasen — die neuen Werte stehen erst
    // nach der Persistenz (Haus-Folge 420/365). Der Trigger filtert NICHT; der
    // Handler ruft die Aenderungs-Logik aus (nur bei SB/KS-Wechsel bei Update) und
    // den isRunning-Guard im Wrapper.
    if (Trigger.isAfter && Trigger.isInsert) {
        CaseQueueAssignmentTrigger.afterInsert();
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        CaseQueueAssignmentTrigger.afterUpdate();
    }
}
