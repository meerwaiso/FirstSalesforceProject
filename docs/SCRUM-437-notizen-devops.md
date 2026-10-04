# SCRUM-437 — DevOps-Notizen (Prod-Release, 04.10.2026)

## Ergebnis
Prod-Org (`devops-agent@cline.de`, orgId 00Dg500000DkTtzEAF) ist live.
Tag: `release/2026-10-04-SCRUM-437` auf master `83f393b`.

## Phasen (gemacht, nicht geplant)
1. **Deploy** (Job `0Afg500000FVhcjCAD`): `sf project deploy start
   --manifest manifest/scrum437-release.xml -o Prod-Org --test-level NoTestRun`
   → 11/11 Komponenten `created=True`, 0 Fehler, 0 Warnings, rollbackOnError,
   completed 2026-10-03T23:58:01Z. `checkOnly=False`.
2. **PS-Zuweisung** (`sf org assign permset ... -b <user> -o Prod-Org`
   für BEIDE PS an `meerwais.osmani.3ecaf61ebe28@agentforce.com` UND
   `devops-agent@cline.de`) → Read-Back `PermissionSetAssignment`:
   **4 rows = 2 users × 2 PS** (005g5…C38DAAS + 005g5…C4M4AAK je Read+System).
3. **Tests getrennt**: `sf apex run test --tests SCRUM437ProblemSerieTest,
   SCRUM437ProblemSerieFlsTest -o Prod-Org` → **11/11 Pass, 100%**,
   run `707g500000oPqOI`, als devops (005g5…C4M4AAK).

## Read-Back-Befunde
- ApexClass `01pg500000DthpiAAB` (Handler) Tooling-lesbar `CreatedDate=23:57:59Z`.
- **FLS-Effekt:** vor der PS-Zuweisung waren die 5 Felder für die
  devops-Session `No such column` / `Invalid field` (describe 0/5,
  COUNT-Query `field … does not support aggregation` nur bei Checkbox) —
  trotz `created=True` im Deploy-Report. Nach PS-Zuweisung: alle 5 Spalten
  via SOQL lesbar (3er-Sample: `Problemkategorie__c=None,
  Wiederkehrendes_Problem__c=False` = korrekt, ohne Kategorie keine Serie).
- Prod-Baseline: **26 Cases**, alle ohne `Problemkategorie__c` →
  kein Daten-Migration nötig, Trigger aktiv für neue/ändernde Cases.

## Fallstricke, die in dieser Org/CLI-Version gebissen haben
- `sf project deploy validate` hat **kein `NoTestRun`**
  (Enum: RunAllTestsInOrg|RunLocalTests|RunSpecifiedTests|RunRelevantTests)
  → läuft IMMER Tests. Jede Phase-1-Validation gegen Prod schoss an dem
  **fremden flaky Test** `SCRUM424FirstResponseTest.ac7_weekend_calendar_
  minutes_under_247` (Expected 2520, Actual wandert: 2000/2009/2018 →
  zeitabhängig). 3× derselbe Fehler, nie am 437-Metadaten. → Deshalb
  NoTestRun-Deploy (kompiliert + rollt zurück bei Fehler) statt validate-Gate.
- `--test-level RunSpecifiedTests` + meine 2 Tests an validate: kompiliert
  alles, scheitert dann an „Test coverage of selected Apex Class is 0%,
  required 75%" (bekannter DryRun-Deckungs-Artefakt für Neu-Klassen).
  Beweist aber: Trigger/Handler/Felder kompilieren.
- Manifest-Type ist `ApexTrigger`, NICHT `Trigger`
  („Missing metadata type definition in registry for id 'Trigger'.").
  House-Pattern: `scr421-phase2.xml` nutzt `ApexTrigger`.
- `sf data query` + Python `json.loads` auf der kompletten stdout: stderr-
  warning „update available" landet vor dem JSON → `raw[raw.find('{'):]`.
  Und `try/except` um `json.loads` **verdeckt** Fehler-JSONs (erstes
  „QUERY OK" war ein Parser-Falschpositiv).
- `sf data query` gegen `EntityDefinition`/`FieldDefinition` (Tooling):
  `FieldDefinition` verlangt einen Reified-Filter
  (`EntityDefinitionId`/`DurableId`), `TableEnumOrId` ist KEIN Feld auf
  `EntityDefinition` in dieser API-Version. `sf sobject describe` als
  Field-Präsenz-Check ist unzuverlässig bei frisch deployten Feldern
  (Cache-Lag) — SOQL-SELECT der Spalten (kompiliert vor dem Fetch) ist
  der zuverlässigere Check.
- `sf project retrieve start`: Flags sind `-m "CustomField:Case.x"` und
  `-r <dir>` (kein `--manifest`, kein `--target-dir`); Ziel MUSS im Project
  liegen.

## Drift-Beobachtung (wichtig für nächste PR)
- `SCRUM424FirstResponseTest.ac7` (Zeit-BusinessHours-Berechnung
  Fri18→Mon09) ist flaky in Prod/CI: 2520 vs. ~200x. Liegt im 424-Ticket,
  NICHT in 437. Bei rotem „Metadata, Apex & Session Smoke" auf fremdem
  PR zuerst die Test-Klassen-Namen dieses Tests prüfen.
- `validate` gegen Prod (Drift Gate) auf der ganzen force-app bleibt
  davon unabhängig grün (es validiert Metadaten, nicht Apex-Assertions
  außer via Tests).

## Artefakte
- Deploy-Manifest source of record: `manifest/scrum437-prod-release.xml`
- Phase-Split-Worktree-Manifests (nicht committet, nur für den Verlauf):
  `scrum437-phase1.xml`, `scrum437-phase2.xml`
- Feature-Branch `release/SCRUM-437-prod` (worktree, lokal) — nach Push
  entfernbar; Remote-Branch war nie vorhanden.
