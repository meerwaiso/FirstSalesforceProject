# SCRUM-424 Notizen (developer-agent)

## Befunde (mit Befehl)

- **BusinessHours TZ**: Default-Profile = `GMT` (Id 0120V0000003Q2wQAE), Periods:
  Mo–Fr 9:00–17:00 (`LocalEndTime=17:00`), Saturday/Sunday keine Periods.
  (Befehl: `sf data query -o Test-Org -q "SELECT ... FROM BusinessHours" -r csv`)
  → **S1 (AC11, TZ Europe/Berlin) offen**: TZ nur via UI-API (Metadata-API ohne
  BusinessHours-TZ) oder CLI-Setup. Prüfen, ob CLI `sf org...`/SOQL `UPDATE`
  TimeZoneSidKey lässt. Wenn nicht: als Open Point im PR dokumentieren (S1 =
  Setup-Klick, kein Metadata-File).
- **Read-back 2 (gemessen, nach Phase-1-Deploy)**: FieldPermissions der 3 424-Felder
  = exakt 3 Zeilen, alle Parent=SCRUM424_FirstResponse_Read, IsOwnedByProfile=false,
  read=true, edit=false. **Keine Profilzeile** — ADR-6/S3-Prämisse bestätigt sich als
  falsch (wie 421 Cycle 2). → Kein Profil-Lock, FLS-Negativtest läuft per USER_MODE.
- **Read-back 3**: BusinessHours Default TZ = `America/Los_Angeles` (S1 offen, DevOps).
  AC11-Test dokumentiert gemessenen Stand, S1 als Open Point (kein rotes Assert auf
  eine Vorbedingung, die ich nicht erledigen darf).
- **Read-back 1 (FeldDefinition Data API)** lieferte leer, FieldPermissions belegt
  Feld-Existenz (Reihenfolge: erst Read-back 2, dann 1). Phase-1-Deploy 0AfWU00000bbV5x0AE
  Status Succeeded, 4/4 Created, NoTestRun (Probe-Klasse SCRUM424_ProbeRunner
  crash-throwt im FullSuite-Testlauf → RunLocalTests/RunAllTests blockiert).

## 424-Artefakte (Stand)

- Phase 1: 3 Felder (Erste_Antwort_Zielzeit__c Number pick-Form,
  Erste_Antwort_Zeitpunkt__c DateTime pick-Form,
  Erste_Antwort_Erbringt__c Checkbox pick-Form) + PS SCRUM424_FirstResponse
  (label "SCRUM424 First Response").
- Phase 2: CaseCommentFirstResponse.cls (Handler) + CaseCommentFirstResponseTrigger
  (Wrapper+isRunning, 421-Form) + SCRUM424FirstResponseTest.cls (bulk, AC-Matrix).
  TRIGGER LÄUFT AUF **CaseComment** (ADR-1), NICHT auf Case.
  Name des Test = SCRUM424FirstResponseTest (CI auto-scope: branch hat SCRUM-424
  → muster ^SCRUM424[A-Za-z0-9_]*Test.cls$).
  BUG IM DESIGN-PSEUDOCODE (ADR-4): 2 Kommentare auf denselben Case im selben
  Batch → 2. überschreibt 1. (c bleibt im Map, Nicht-null). Fix im Handler:
  `if (c.First_Response_Time__c != null) continue;` (Write-once in-Batch).
- S1–S4 SIND DevOps/Setup-Schritte (Design-Tabelle), NICHT mein Metadata.
  Guardrail "kein Setup-Klick / kein Profil-Edit" → ich mache S1–S4 NICHT.
  ADR-6/S3 (Profil-Lock) = dieselbe Prämisse, die 421 Cycle 2 widerlegte
  (0 Profilzeilen, USER_MODE allein grün). → NACHT Phase-1 Deploy MEGEN:
  FieldPermissions der 3 neuen 424-Felder + BusinessHours-TZ. Danach Test-Logik
  an Realität ausrichten (AC1–AC8 funktional, AC7 Kalendeminuten, AC10 FLS an
  gemessenem Profil-Stand, AC11 TZ-Readback dokumentiert).
- Phase 3: Report retrieve → clone → mod (421-Lektion), Layout-Sektion
  "Erste Antwort", Manifest/CI (scr424-ci.xml), PS assign + FLS read-back.

## Deploy-Reihenfolge (421-Lektion)

1. Phase 1 (3 Felder + PS) — CustomField + PermissionSet in EINEM Manifest
   (PS referenziert die Felder).
2. Phase 2 (2 Apex) — ApexClass-Manifest.
3. Phase 3 (Report + Layout) — Report + Layout in EINEM Manifest
   (421: Report + Layout zusammen deployt).
   Layout = `layouts/Case-Case Layout.layout-meta.xml` (top-level — 421-Lektion:
   NIEMALS `objects/OBJ/layouts/`).
4. BusinessHours-TZ (S1): Setup-Klick, kein File.

## Branch / PR

- Branch: feature/SCRUM-424-first-response (remote, von 575a111 = 424-Design
  Commit). PR auf master (master hat 421 + 420, also Basis vorhanden).
- `gh pr create` erst NACH Phase 1-Deploy (Push-before-Handoff, aber PR-Body
  soll den Stand zeigen; Design sagt: erst alle 3 Phasen deployed, dann PR).

## Offene Punkte

- [ ] S1 BusinessHours TZ: CLI-fähig? (Prüfen)
- [ ] ADR-6: Profile rows existieren für 424-Felder? (Nach Phase 1 messen)
- [ ] Report retrieve (421-Lektion: nie from scratch)
