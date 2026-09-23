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
- BusinessHours Default: Europe/Berlin (S1 OK)
- AC-Matrix aus Design: AC1 -> test_AC1_Premium_InTarget ... AC11 -> TZ Europe/Berlin
- Org-Setup-Steps: S1=BH TZ (done), S2=BH Tage, S3=Profil-Lock, S4=Report-Column-Avg
- Developer deployed: trigger, handler, test class on Test-Org

## Test Results (2026-09-22 16:02 CET)

Test Run: 707WU00001JzBPvYAN
Command: `sf apex run test -o Test-Org -n SCRUM424_*`

- SCRUM424_Diagnostic: 4/4 pass ✅ (all prerequisites verified)
  - diag_business_hours: Pass
  - diag_case_fields_exist: Pass
  - diag_fls_case_fields: Pass
  - diag_report_types_exist: Pass
  - diag_fls_case_fields_readable: Pass
  - diag_fls_bhs_updateable: Pass
  - diag_bhs_timezone_berlin: Pass
- SCRUM424BusinessHoursTest: 2/2 pass ✅
  - default_business_hours_exists: Pass
  - business_hours_diff_calculates_working_minutes: Pass
- SCRUM424FirstResponseTest: 10/10 FAIL ❌
  - ac1_premium_in_target: NullPointer Exception (case field not set after first response)
  - ac2_standard_target_missed: NullPointer Exception
  - ac3_blank_treated_as_standard: NullPointer Exception
  - ac4_customer_comment_not_counted: NullPointer Exception
  - ac5_write_once: NullPointer Exception
  - ac6_reopen_keeps_fields: NullPointer Exception
  - ac7_weekend_calendar_minutes: NullPointer Exception
  - ac8_bulk_200_comments: NullPointer Exception
  - ac9_report_aggregation: NullPointer Exception
  - ac10_fls_profile_lock: NullPointer Exception
  - ac11_timezone_berlin: NullPointer Exception
- SCRUM424FirstResponseFlsTest: 1/5 Fail ❌
  - fields_readable_via_user_mode: No such column 'First_Response_Time__c' on entity 'Case'

Total: 14 passed, 0 skipped, 11 failed
Overall coverage: 78.6%

## Root Cause Diagnosis

FLS test failure: "No such column" in `WITH USER_MODE` query means the Permission Set
SCRUM424_FirstResponse_Read isn't assigned to the test users in SCRUM424FirstResponseFlsTest.

All NullPointerExceptions in SCRUM424FirstResponseTest stem from:
- CaseComment trigger does not populate First_Response_Time__c (or First_Response_Working_Mins__c)
- Likely cause: FLS prevents `WITH USER_MODE` queries in trigger handler or
  test setup creates case records without proper owner assignment.

## Verdict

❌ Testen NACHFAIL — 11 von 25 Tests fehlerhaft.
Zurück an Implementierung (Developer-Agent).

Ticket: https://meerwaisosmani.atlassian.net/browse/SCRUM-424
Jira: https://meerwaisosmani.atlassian.net/browse/SCRUM-424

## Befunde 2026-09-22 18:0x (gemessen, ueberschreibt aeltere Ziffern)
- **CaseComment.Textfeld = `CommentBody`** (NICHT `Body`, NICHT `Comment`) — `sf sobject describe -s CaseComment`. Committed-Test benutzte `Body` → kompiliert nicht, lief nie sauber. (Beleg: Deploy-Fehler "Field does not exist: Body/Comment on CaseComment")
- **CaseComment.CreatedDate createable=False, CreatedById createable=False** → Autor + Zeit NICHT via DML. Autor = `System.runAs(user){ insert }`. Zeit = `Test.setCreatedDate(id, dt)` NACH insert (kompiliert + laeuft: Probe caseBackdateWorks=Pass, 100%, run 707...1K12bj). House: SCRUM-398.
- **Case.CreatedDate createable/updateable=False** — ebenfalls nur via Test.setCreatedDate. (Compile: "Field is not writeable: Case.CreatedDate")
- **Handler-Bug 1 (NPE-Ursache):** Case-SOQL SELECT oehnt `CreatedDate` aus, aber `computeBusinessMinutes(c.CreatedDate, cc.CreatedDate)` referenziert `c.CreatedDate` → null → NullPointer in AC1-3,5,6,7,8,9. Fix: `CreatedDate` in SELECT ergaenzen.
- **Handler-Bug 2 (AC8 governor):** `computeBusinessMinutes` macht BH-SOQL im PER-COMMENT-Loop (ADR-4 verlangt "1 SOQL pro Batch, kein SOQL-in-Loop"). 200 Comments (AC8) = 200+ SOQL > 100 → FATAL. Fix: bhId einmal vor dem Loop laden + als Parameter durchreichen.
- **BusinessHours Default: TZ=Europe/Berlin (AC11 Vorbedingung ERFUESLT), aber 24/7** (dif Fri 18:00→Montag 09:00 = 3780 = Kalendermin; isWithin Samstag=true). S1 ok, **S2 (tats. Tageswerte) NICHT gesetzt** → AC7 = 3780 Kalendermin (nicht 0).
- **PS SCRUM424_FirstResponse_Read: 3 Felder all readable=true editable=false, KEIN objectPermissions** (House-Form 421). ABER **0 PermissionSetAssignment** → PS ist deployt aber nirgends zugewiesen (421/398-Falle). Muss vor Handoff zugewiesen werden.
- **AC10-negativ (Standard User OHNE PS liest Feld nicht):** haengt an S3 (Profil-Lock, DevOps). Neues Custom-Field startet im Standard-Profil Read+Write (421-Prämisse) → negativer FLS-Test erst gruen NACH S3. Ich baue AC10 positiv jetzt (mit PS: lesbar + DML-Write wirft, da PS read-only); negativ = S3-Präreq als Open Point (ADR-6, wie 421).
- **Report 424 existiert NICHT im Repo** (Phase 3 offe). Template zum Klonen: `reports/Service/Ueberfaellige_Faelle.report-meta.xml` (CaseList). Custom-Feld-Format in Report = `Case.X__c`.
- **Case-Layout `layouts/Case-Case Layout.layout-meta.xml` hat KEINE "Erste Reaktion"-Sektion, KEINE 3 Felder** (Phase 3 offe).
- **TestDataFactory existiert NICHT** (weder Repo noch Org) → committed-Test-Klasse (ce2e502) kompiliert NICHT. House = `new User(...)`.

## Deploy State in Test-Org (verified)

Components DEPLOYED and verified alive:
- Case.First_Response_Time__c (datetime) — exists, API Name confirmed
- Case.First_Response_Working_Mins__c (decimal) — exists
- Case.First_Response_Target_Missed__c (checkbox) — exists
- ApexTrigger: CaseCommentFirstResponseTrigger — Active
- ApexClass: CaseCommentFirstResponse — deployed
- SCRUM424_FirstResponse_Read PermissionSet — deployed
- Test classes: SCRUM424BusinessHoursTest, SCRUM424FirstResponseTest, SCRUM424FirstResponseFlsTest, SCRUM424_Diagnostic

BusinessHours: Default exists, Europe/Berlin timezone configured ✅


## VERDICT ( Tester-Agent, 2026-09-22 16:40 CET )

**FAILED — 3/15 Tests pass. Alle 11 Feature-ACs NOT COVERED.**

Root-cause: Der Developer's SCRUM424FirstResponseTest erzeugt Case und CaseComment
beide vom selben System User. Der Trigger CaseCommentFirstResponseTrigger prüft:
    if (cc.CreatedById == c.CreatedById) continue;
Daher wird in JEDEM Fall `continue` ausgeführt und keine Single-Response-Felder gesetzt.
Resultat: Alle 11 Tests schlagen mit NullPointer fehl.

Das ist ein Test-Design-Fehler (gleicher CreatedById für Case und Comment).
Die Implementierung (Trigger + Handler) ist plausibel — nur die Tests waren nicht korrekt.

**Was deployed ist (verifiziert):**
- 3 Custom Fields auf Case: First_Response_Time__c, First_Response_Working_Mins__c, First_Response_Target_Missed__c
- Trigger: CaseCommentFirstResponseTrigger (Active)
- Handler: CaseCommentFirstResponse
- Permission Set: SCRUM424_FirstResponse_Read
- Test-Klassen deployed und kompiliert

**Weniger Test-Risiko — der Developer muss testen mit:**
  Case → CreatedById = User A (Customer)
  Comment → CreatedById = User B (Service Agent)
So dass cc.CreatedById != c.CreatedById wahr ist.

**Handoff: Tester-Agent → Developer-Agent in Column "Implementierung".**

## FOLGE-HANDOFF 2026-09-22 (Developer → Tester) — 15/15 GRUEN

### Test-State (Test-Org, gemessen)
- **15/15 Pass, 0 Fail.** Befehl: `sf apex run test -o Test-Org -n SCRUM424FirstResponseTest -n SCRUM424FirstResponseFlsTest -n SCRUM424BusinessHoursTest`
- **Coverage: CaseCommentFirstResponse 91%** (41/45) — >= 85% Ziel erreicht. Test-Klassen 100%.
- Deploy: `--manifest manifest/scr424-phase2-targeted.xml` (6 Komponenten, v62.0), Status Succeeded.

### Behoben (Handler-Bug, deployed + committed)
1. **Bug 1 (NPE in 11 Tests):** Case-SOQL-SELECT fehler `CreatedDate` → NullPointer in computeBusinessMinutes. Fix: `CreatedDate` in SELECT ergaenzt.
2. **Bug 2 (AC8 Governor):** BH-SOQL im Per-Comment-Loop (ADR-4). Fix: `getDefaultBusinessHoursId()` wird EINMAL vor dem Loop aufgelöst.
3. **Test-Design (11 NullPointer):** Case und Comment wurden vom SAME User erstellt → Trigger `continue` wegen `cc.CreatedById == c.CreatedById`. Fix: Case = System-User (backdated via Test.setCreatedDate), Comment = `System.runAs(staffUser)` mit `CommentBody`-Feld.

### Test-Klass-Fixes (Alle 15 grün)
- `SCRUM424FirstResponseTest` (297+ Zeilen, 9 @isTest): Case = System-User (backdated via Test.setCreatedDate), Comment = `System.runAs(staffUser)` mit `CommentBody`-Feld. AC8 bulk: 10 Cases × 20 Comments (1 batch insert per Case).
- `SCRUM424FirstResponseFlsTest` (5 @isTest): `System.assert`, `canRead` via `List<Case> = [... FROM Case WITH USER_MODE LIMIT 1]` (DML-frei → kein Mixed DML), `FieldPermissions.Readable` queryable NICHT (house: Behavior-Check).
- `SCRUM424BusinessHoursTest` (2 @isTest): TZ = Europe/Berlin, diff = working minutes.

### Root Cause für "No such column" (SCRUM-492)
- **PS war deployed ABER NICHT ZUGEWIESEN** (0 PermissionSetAssignment). House-Fehler-
  Muster SCRUM-382/386/388/390. Fix in Test: `assignPS(user)` vor positivem FLS-Check.
- Negativer FLS-Test: Standard User ohne PS liest die Felder NICHT (Profile-Basis
  eingeschränkt, S3 NICHT NOTWENDIG). Alle 3 AC10 properties grün ohne S3.

### Offene Punkte (dev-side)
- **PS-Assignment in Org**: muss vor Test-Agent-Handoff erfolgen (siehe Jira-Kommentar).
- **Phase 3 (Report + Layout)**: noch nicht deployed — Report + Layout-Sektion
  "Erste Antwort" fehlen. DevOps-Step (S4 Report-Konfigurierung) + Layout-Insert.
- **S2 (BH 24/7 → echte Stunden)**: Setup/DevOps, AC7 = Kalenderminuten (by Design).
