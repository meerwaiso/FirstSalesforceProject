# SCRUM-417 — Notizen DevOps (PROD-Release-Zug, 18.09.)

## Auftrag
PO-Handoff 19397: Ticket in Spalte **Release**, Assignee **devops-agent** (beides
Tracker-Read-Back). Merge + Test-Org-Cron = erledigt im Deployment-Zug (19364,
Job/Merge `869c3cf`). Jetzt: **PROD-Release**.

## Gate (beide wahr, vom Tracker, nicht vom Raum)
- Spalte = Release ✔   - Assignee = devops-agent ✔   → Prod-Deploy berechtigt.

## Plan (PO 19397 + DevOps-DoD)
1. master sync (`git pull --ff-only`), lokal == origin/master.
2. Release-Scope = Dateien von PR #114 (`869c3cf`), gegen Manifest/force-app prüfen.
3. Pre-Deploy-Validate gegen Prod-Org (`sf project deploy validate --manifest … -o Prod-Org`) —
   bei ANY Failure ABORTEN, Prod OBERHAUPT nicht anfassen.
4. Deploy (`sf project deploy start --manifest … -o Prod-Org`).
5. Org-Laufzeit-Schritte auf PROD (ALLE mit `-o Prod-Org`!):
   a. PS `SCRUM417_OpenOpportunityHistory` an Prod-End-User (`meerwais.osmani…@agentforce.com`)
      + devops-agent@cline.de (meine Read-Back-Fähigkeit) vergeben.
   b. Backfill: `OpenOpportunityHistoryRebuilder.run()` einmal auf Prod.
   c. CronTrigger: `System.schedule('SCRUM-417 Offene Chancen Verlauf','0 0 3 * * ?',
      new OpenOpportunityHistoryScheduler())`.
6. READ-BACK (aus der Org, nicht aus Deploy-Output): Deploy-Report, Objekt+Felder
   (FieldDefinition), Reports (ReportDefinition), CRT, PS+Assignments, CronTrigger,
   History-Rows > 0 + letzter Monat = 2026-09.
7. Release-Beleg: Job-Id in Jira-Kommentar; Tag `release/2026-09-18-SCRUM-417`.
8. Handoff: Jira-Kommentar (Summary+Belege), Assignee po-agent, Spalte Erledigt (41), @po-agent.

## Befunde (füllt sich)
- Release-Manifest = `manifest/scr417-prod-release.xml` (NEU gebaut; `phase2-full` war
  unvollständig — Objekt + AccountId/Open_Count/Open_Value fehlten). = exakt PR#114-Metadata
  (18 deployable Komponenten) + 2 Layouts. Alle 18 Dateien lokal verifiziert, force-app == master.
- **Pre-Deploy-Validate gegen PROD-Org: GRÜN** — Job `0Afg500000EyG3RCAV`, 18/18 Komponenten,
  0 Fehler, 168/168 Local-Tests, status Succeeded (checkOnly=true). Gate bestanden.
- **PROD-DEPLOY: GRÜN** — Job `0Afg500000EyGjNCAV` (SUCCEEDED), 18/18 Komponenten (Created:
  Objekt, 6 CustomFields, 4 ApexClass, PS, ReportType, Tab, 2 Reports; Changed: 2 Account-Layouts),
  168/168 Tests, 0 Fehler. Read-back via `sf project deploy report --job-id … -o Prod-Org`.
  Log: /home/fino/417_prod_deploy.txt. → Nächste: PS-Assignment + Backfill + CronTrigger auf Prod.
- **PS-Assignment PROD: verifiziert** — `sf org assign permset -n SCRUM417_OpenOpportunityHistory
  -b <user> -o Prod-Org` (Flag = **-b/--on-behalf-of**, NICHT -u!). Read-back via REST-Query auf
  `PermissionSetAssignment` (Feld = **AssigneeId**, nicht GroupOrUserId/Assignee): **2 Assignments** =
  devops-agent@cline.de + meerwais.osmani…@agentforce.com (=@End-User). = SCRUM-414-Prod-Präzedenz.
  PROD-PS-Id = `0PSg500000CrW9JGAV`.
- **Backfill PROD: GRÜN** — `sf apex run -f /tmp/417_backfill.apex -o Prod-Org`
  (`OpenOpportunityHistoryRebuilder.run()` + COUNT + MAX). **RUN=OK secs=0 totalRows=72 lastMonth=2026-09**.
  (Prod < Test 207 → weniger offene Chancen; idempotent, 2. Lauf stabil 72.)
  Apex-Quirk: `SELECT MAX(…) FROM` in Anonymous-Block = `List<AggregateResult>`; `Snapshot_Month__c`
  ist **Text** (kein Date). → Nächste: CronTrigger `System.schedule` auf Prod (AK3).
- **CronTrigger PROD: verifiziert (AK3)** — `sf apex run -f /tmp/417_cron.apex -o Prod-Org`
  (idempotent: prüft `CronJobDetail.Name`, schedule nur wenn leer). Ergebnis:
  `expr=0 0 3 * * ?` (= exakt PO-Spec & Test-Org-Präzedenz 19364), `state=WAITING`, `fires=0`,
  `name=SCRUM-417 Offene Chancen Verlauf`, `id=08eg500000K7oJdAAJ`. 1. Fire = heute 03:00 (Org-Local).
  HINWEIS (nicht interpretieren): Apex `DateTime` ist tz-frei; `NextFireTime` rendert im DEBUG in
  Session-Tz (UTC). Session `now==09:22 UTC`, `nextFire` rendert `10:00` → 1. Fire liegt lokal 03:00
  (Org-Tz ≈ UTC−7, arithmetisch konsistent: 02:22 local → next local 03:00 = 10:00 UTC).
  **Der Cron-Ausdruck (Kontrakt, nicht UTC-Wandzeit) = korrekt.** Runtime-Objekt, NICHT im Manifest (AK3).
  → Nächste: Meta-Read-backs (Objekt/Felder/Reports/Classes/Layouts) + Release-Tag + Jira-Handoff (PO, Erledigt 41).
