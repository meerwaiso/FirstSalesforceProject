# SCRUM-420 — Notizen (Developer)

Stand: 2026-09-19, Branch `feature/SCRUM-420-escalation-kunde`, Worktree `/tmp/scr420-wt`.
Spec: `docs/SCRUM-420-design.md` (Commit 06bfb6e, Architect).

## Org-Fakten (geprüft 2026-09-19, Test-Org)
- ApexClass: `CaseOpenCountTrigger`, `CaseOpenCountRebuilder` existieren; `CaseEscalationKunde` NICHT vorhanden → Klassenname nach Design verwendbar.
- ApexTrigger: OpportunityOverdueReset, CasePriorityTrigger, CaseOpenCountTrigger, AccountLockGuard, LeadDuplicateGuard, LastCaseDateTrigger, LastRealContactDateTrigger, CaseReactionTrigger → `CaseEscalationKunde.trigger` frei.
- 4 Felder kollisionsfrei (Design bestätigt + git ls-tree origin/master).
- 398-Feld `Eskalationsstufe__c` = Formula String, bleibt unangetastet.
- `Trigger` ist SOQL-Reserviertwort → Tooling: `SELECT Name FROM ApexTrigger`.
- Case anlegbar mit nur Subject+Status (418-Demo). Account: Name (Standard).
- Profile 'Standard User' existiert (FLS-Test-Muster 418/403); `LanguageLocaleKey=de_DE` wird in dieser Org abgelehnt → `en_US`, `TimeZoneSidKey=America/Los_Angeles`.

## House-Muster
- Trigger+Handler: `CaseOpenCountTrigger.trigger`/`.cls` (365) — Set<Id>-Sammeln, 1× recompute.
- Handler: 1× Aggregate-SOQL (GROUP BY, `AggregateResult`!), 1× Zustands-SOQL, diff → `update toUpdate` nur wenn nicht leer.
- Rebuilder: 367 `CaseOpenCountRebuilder` (Batchable<SObject>, Stateful) — HIER ABER: ohne Log-Objekt (ADR 5), Call an `CaseEscalationKunde.recompute(accountIds)`.
- PS: `SCRUM398_Eskalationsstufe.permissionset-meta.xml` (nur fieldPermissions, hasActivationRequired=false).
- Feld-XMLs: `Open_Cases_Rating__c` (Picklist), `Open_Cases_Count__c` (Number default 0), `FinishedAt__c` (DateTime, kein defaultValue).
- Meta: alles apiVersion 62.0.
- Manifest: Version 67.0 (388-Muster). Phase1 = nur CustomField; Phase2 = Referenzierer.
- Test-Muster FLS: `SCRUM418CaseReactionFlsTest.cls` (runAs + getDescribe().isAccessible/isUpdateable, Standard-User-Profil).

## PO-Offen-Punkte (Architect-Defaults gelten, da keine PO-Antwort bis Handoff)
1. Rebuilder: JA, vor Test-Start 1× laufen lassen.
2. Geschlossene Cases: letzter Wert bleibt (kein Reset).
3. Zeitstempel bei erneuter Kritisch-Phase: alter Wert bleibt (nur null→set).
→ Im Handoff-Kommentar dokumentieren.

## Build-Reihenfolge
1. Phase 1 XML: 4 Felder + PS → validate → deploy (Test-Org) → PS zuweisen (CLI-User + meerwais.osmani@resourceful-bear-6f1u4j.com) → Read-Back per SOQL als PS-User. Commit.
2. Phase 2: Trigger + CaseEscalationKunde.cls + SCRUM420EscalationKundeRebuilder.cls + 2 Test-Klassen + Layout-Sektion → validate → deploy mit RunSpecifiedTests. Commit.
3. Rebuilder 1× via Apex (executeBatch) → SOQL-Nachweis Bestandsdaten.
4. Regression: SCRUM418CaseReactionTest, SCRUM418CaseReactionFlsTest, SCRUM419ReentryRegressionTest, SCRUM365OpenCasesCountTest (365/370 heißt es im design: SCRUM365OpenCasesCountTest — NENNNÜTIG VOREM LAUFEN PRÜFEN).
5. PR auf origin/master, Jira-Handoff T31 → architect-agent.

## Befunde während der Arbeit
- (leer)
