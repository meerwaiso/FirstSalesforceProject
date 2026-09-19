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

## Stand (19.09.2026, ~19:15) — ALLES DEPLOYED + VERIFIZIERT
- Phase 1 (Commit 36d9d32): 4 Felder + PS deployed. PS SCRUM420_EskalationKunde (0PSWU00000WJ3Cf4AL) zu GEWIDMET an devops-agent@cline.test und mehrwais.osmani@resourceful-bear-6f1u4j.com — Assignment-Rücklesung OK.
- Phase 2 (Commit fc2d9d7): Trigger/Handler/Rebuilder + Haupttests. Deploy-Job 0AfWU00000bZDoH0AW Succeeded, 16/16. Rebuilder-Coverage: run(accId) + run(null) beide abgedeckt.
- Phase 3 (Commit 076e67b): Layout-Items unter Is_Overdue__c. Deploy Succeeded, UI-API record-ui: alle 4 Felder sichtbar.
- Phase 4 (Commit b7ae2b6): FLS-Test 1/1, Deploy 0AfWU00000bZEZ30AO Succeeded.
- Backfill: 5 offene Fälle mit Account ohne Stufe → 0 nach Rebuilder.run(null). 569 offene Fälle OHNE Account = Design-Mannigfaltigkeit (Kundenstufe existiert nur pro Account), wird ausgelassen, im PR-Body erwähnt.
- Werte-Readback: 500WU00002VPZPjYAP → Keine/2/0 (Matrix korrekt, H=0 in der Org).

## Bewährungs-Befunde (wenn sie nicht an der Hand sind)
- `SUM(CASE WHEN …)` in SOQL wird in dieser Org vom Compiler abgelehht → In-Apex-Zählung aus der bereits geholten Liste (bulk, identisch korrekt).
- `Limits.getNumQueries()` existiert nicht → `Limits.getQueries()` (House Pattern 384/386).
- Case.RecordTypeId wird zum Inserten in dieser Org abgelehht (kein RecordType für Case konfiguriert) → weglassen.
- Rebuilder-Deploy scheitert an <75% Coverage, wenn der Rebuilder in der Phasen-2-Manifest, aber nicht in der Test-Manifest der --tests-Liste ist.
- `Trigger` ist reserviert in SOQL → `ApexTrigger` Tooling-Objekt oder Backticks/REST.
- `sf org assign permset` Flag für den Benutzer: `-b`/`--on-behalf-of` (nicht `-u`), sonst leert der Aufruf.
