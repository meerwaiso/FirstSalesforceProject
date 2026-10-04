# SCRUM-438 — Notizen (Architect-Agent)

Befunde, die Verdichtung nicht überleben dürfen. Eine Zeile = ein harter Befund.

## Survey-Basis
- origin/master @ 7c36596 (2026-10-04). Worktree: salesforce/scr438-work, Branch feature/SCRUM-438-sla-escalation.
- target-org = **Test-Org** (sf config get target-org).

## Harte Befunde (Org / Repo, verifiziert)
- **Namens-Kollision:** `Case.Eskalationsstufe__c` existiert SCHON (SCRUM-398, Formelfeld Text, Werte Kritisch/Erhöht/Normal, auf Layout Readonly). PO will neu "Eskalationsstufe" (Picklist Keine/Stufe 1/Stufe 2) → API-Must neu: `SLA_Eskalation__c`.
- **Is_Overdue__c NICHT reuse:** = Tage-Schwelle (High>2/Med>5/Low>10, SCRUM-390, Formel), ANDERE Metrik als Deadline. POs "SLA überschritten" = Zielzeit überschritten → eigenes Feld `SLA_Ueberschritten__c` (stored Checkbox).
- **Premium-Marker existiert SCHAON auf dem Case:** `Case.Kundenstatus__c` Picklist Standard/Premium (SCRUM-421, auf Layout, Edit). Keins auf dem Account → **kein neues Account-Feld**. Annahme 3 gelöst durch Reuse.
- **Case.Status in Test-Org = New / Working / Escalated / Closed.** KEIN "Warten auf Kunde" (Annahme 2). Closed-Kennung = `ClosedDate != null` (Case.IsClosed boolean existiert).
- **Priority in Test-Org = High / Medium / Low** (passt zu PO-Tabelle exakt).
- **BusinessHours "Default" = 24/7, TZ America/Los_Angeles** (Skill salesforce-describe-first §10 + SCRUM-424-Befund). `BusinessHours.diff()` behandelt Wochentage/Zeitzone. Mo–Fr-Konfig ist **kein** Deploy-Metadaten (kein registry-Typ BusinessHours) → **Org-Setup**, nicht repo.
- Case OWD: `EntitySharingRules` querybar NICHT via `sf data query` (unsupported); `sf sharing` UI-Tooling — OWD-Check als Org-Setup/DevOps-Readback notiert, nicht repo.

## Haus-Shape (origin/master, verifiziert)
- Batch: `CaseReminderBatch` (Database.Batchable<SObject> NICHT <Case>, QueryLocator, 200er-Chunks, ohne sharing, @testVisible-Konstruktor mit injectierbarem `now`).
- Scheduler: `CaseReminderScheduler` (implements Schedulable, starte nur Batch). CRON-Reservierung 01:00=436, 02:00=388, 03:00=417, 06:00=Opportunity-Overdue.
- Reactiver Trigger: `CaseCommentFirstResponseTrigger`/`CaseCommentReminderTrigger` (thin, static isRunning-Guard, try/finally, Logik im Service).
- 2 PS-Shape: `SCRUM436_CaseReminder` (Read: readable=true editable=false) + `SCRUM436_CaseReminderSystem` (Write: readable=true editable=true). Shape SCRUM388_AccountReactivationWrite.
- Test-Naming: `SCRUM436CaseReminderTest` / `SCRUM436CaseReminderFlsTest`, Manifest `manifest/scr436-{phase1-fields,phase2-referencing,apextests}.xml`, apiVersion 67.0.
- Layout: `layouts/Case-Case Layout.layout-meta.xml`. Neue Sektionen = customLabel=true, vor "System Information". Anker: SCRUM-420 "Eskalation (Kunde)" / SCRUM-421 "Zuordnung" (mit Kundenstatus__c).
- Scheduled Jobs = LAUFZEIT-Objekte, KEINE Metadata → `System.schedule(...)` ist Org-Step (DevOps), ohne es läuft der Code nie (house: CaseReminderScheduler).

## Design-Entscheidungen (ADRs in Design-Doc)
- Apex über Flow (ADR-1). Batch (1h) + reaktiver Trigger (ADR-2). BusinessHours.diff (ADR-3).
- Pause über gespeichertem Feld `SLA_Uhr_gestoppt__c` + konfigurierbarer Pause-Statusliste (ADR-4) — robust zu fehlendem "Warten auf Kunde"-Wert.
- Premium-Marker = Reuse `Case.Kundenstatus__c` (ADR-6).

## Offene Punkte (PO, blocken Implementierung NICHT)
1. Feiertagskalender ja/nein (Annahme 1: Mo-Fr ohne Feiertage als Default).
2. Pause-Status: exakter Picklist-Wert wird noch nicht existieren → Org-Step "Warten auf Kunde" anlegen + SLAConfig.DEFAULT_PAUSE_STATUSES = {'Warten auf Kunde'}.
3. Eskalations-Sprung Stufe1→2: 4 Werkstunden (Default, BusinessHours.diff) vs 4 Kalendersunden.
4. Batch-Häufigkeit: 1h (empfohlen) vs häufiger.
