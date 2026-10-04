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

---

## Tester-Agent Befunde (2026-10-04, Test-Org verifiziert via CLI)

### Deploy-Verifikation (Org-Lese-Readback)
- 7 SLA-Felder auf Case deployed (FieldDefinition LIKE 'SLA_%'):
  SLA_Zielzeit/SLA_Status/SLA_Eskalation/SLA_Ueberschritten/SLA_Last_Checked/SLA_Uhr_gestoppt/
  SLA_Akkumulierte_WorkingMins. (ALTES `SLAViolation__c` existiert daneben — NICHT SCRUM-438.)
- 2 Permission Sets deployed: SCRUM438_SLA_Read (editable=false ×7), SCRUM438_SLA_System (editable=true ×7).
- PSA 2×2: beide PS an `devops-agent@cline.test` + `meerwais.osmani@...` (beide System Admin).
  → DoD "PS vorhanden UND zugewiesen" erfüllt.
- 4 Apex-Klassen + Trigger deployed: SLAService/SLAConfig/SLAJobBatch/SLAJobScheduler/CaseSLATrigger.

### Kritische Lücken für PO-Szenarien
- **CronTrigger: 0 Records in Test-Org** → SLAJobScheduler als Scheduled Job NIE angelegt.
  → PO-Szenario 11 "periodische Bewertung über alle offenen Cases" läuft LIVE nie.
  Batch-LOGIK bleibt via `Database.executeBatch(new SLAJobBatch())` in Test prüfbar (AC8).
  = DevOps-Setup-Point (b), Architect: "nicht blockierend" — aber es ist der Kern der Skalierungs-AC.
- **Case.Status Picklist = New/Working/Escalated/Closed** (describe) → KEIN "Warten auf Kunde".
  SLAConfig.PAUSE_STATUSES = leer (bestätigt im Code).
  → PO-Szenario 3 (Pause) und 4 (Resume) NICHT testbar in der Org. DevOps-Setup-Point (a).

### Testplan
- Apex: `sf apex run test -o Test-Org -l RunSpecifiedTests -t SCRUM438SLATest,SCRUM438SLAFlsTest`
  (kein --async; -t = --tests; -l RunSpecifiedTests). Erwartet 8+1 = 9 Tests (Developer: 9/9).
- E2E (Playwright): AC12 — "SLA"-Layout-Sektion auf Case-UI sichtbar, 4 primäre Felder + Letzter_Lauf,
  alle READONLY (kein Inline-Edit). Vorher: smoke, dann Locator probe.
- FLS-negatives (AC13) = in SCRUM438SLAFlsTest via System.runAs (2nd UI-Session unnötig).

### AC ↔ PO-Szenario-Korrektur (PO zählt 12 Szenarien, Design 14 ACs)
PO-SZ → Design-AC: S1=AC2, S2=AC2(Premium), S3=AC5[GAP], S4=AC5[GAP], S5=AC3, S6=AC3,
S7=AC4, S8=AC4, S9=AC7, S10=AC6, S11=AC8[GAP Live-Scheduler], S12=AC2(Werktag), +FLS=AC13.
AC1(Felder)/AC9(Trigger)/AC10(Read)/AC11(System)/AC12(Layout-UI) sind zusätzlich.

---
## Tester-Sektion — Befund 2026-10-04 (21:40 UTC)

### Kritischer Defekt (PROD-Auswirkung)
`SLAJobBatch.execute` Line 90 ruft `SLAService.evaluate(c, asOf)` (TWO-ARG-Overload)
-> intern `bhId()` pro ROW. Bei Chunk=200, >100 offene Cases ->
`System.LimitException: Too many SOQL queries: 101` (Run 707WU00001M0Y7l, 11.290 ms).

**Ursache:** Die Stateful-Member `bh` (gesetzt Line 75 im 1. execute-Aufruf)
wird NICHT an evaluate übergeben. Korrekt: `SLAService.evaluate(c, asOf, bh)`.

**Auswirkung:** Der stündliche Batch-Job scheitert in Prod immer, wenn
>99 offene Cases existieren. Heute latent (CronTrigger=0), bei Scheduling
sofort produktionsrelevant.

**Test-Nachweis:** `SCRUM438SLAScaleTest` (420 Cases, 3 Chunks, 200er-Batch),
beide Tests FAILen mit LimitException — reproduzierbar.

### Apex-Suite (SCRUM438SLATest + SCRUM438SLAFlsTest): 9/9 GRÜN (Run 707WU00001M062C)
### E2E (SCRUM-438-sla-layout.spec.ts): 3/3 GRÜN + Smoke 2/2
  AC12a: SLA-Sektion im Layout sichtbar (5 Felder)
  AC12b: Alle 5 Felder + Labels korrekt (SLA-Zielzeit/Status/Eskalation/überschritten/letzter Lauf)
  AC12c: Live-Case 500WU00002uFVFCYA4 — Werte gefüllt (Status=Im Zeitplan, Zielzeit gesetzt)
  AC12d: NICHT separater Test — Readonly-Enforcement für Restricted-User ist in
         AC13 (SCRUM438SLAFlsTest, System.runAs) abgedeckt. SA-User (Session) hat edit
         FLS via SCRUM438_SLA_System -> Edit-Buttons in Lightning korrekt.
### Live-Init: Case 500WU00002uFVFCYA4 — before-Trigger initialisiert alle 7 SLA-Felder
### Org-Befunde:
  - 7/7 SLA-Felder deployed
  - 2 Permission Sets (Read + System) existieren, je 2×2 Assigned
  - CronTrigger = 0 (Scheduled Job nie aktiviert — DevOps-Setup-Punkt)
  - PAUSE_STATUSES = [] und Picklist-Wert "Warten auf Kunde" NICHT in Org (S3/S4 nicht testbar)
