/**
 * [SCRUM-424] Wrapper-Klasse fuer CaseCommentFirstResponseTrigger mit static isRunning-Guard.
 * Guard verhindert, dass DML auf Case (update) rekursiv wieder einen CaseComment-Trigger
 * auslost, wenn ein Kommentar programmatisch erstellt wird — exakt wie SCRUM-421.
 *
 * @author developer-agent
 * @date 2026-09-22
 */
public class CaseCommentFirstResponseTrigger {
    public static Boolean isRunning = false;

    private CaseCommentFirstResponseTrigger() {}
}
