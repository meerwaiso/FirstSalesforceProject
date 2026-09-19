# SCRUM-419 Notizen — Developer

## Stand: 2026-09-19
Fix-Attempt 1 (statisches Re-Entry-Flag) ist deployed und unit-grün.
Externer REST/CLI-Pfad zählt weiterhin doppelt. Eskaliert (2 Self-Correction + Log-Blocker).

## Gemessen (alle Readback aus Test-Org, nicht aus Exit-Codes)

| Pfad | Count nach 1 Reopen (Closed→New) |
|------|-----------------------------------|
| Inline-Apex-`update` (A in /tmp/419_ab.py) | **1** ✅ |
| Externer CLI `sf data update record` (B in /tmp/419_ab.py) | **2** ❌ |
| Externer REST-PATCH (02:03 UTC, Case `500WU00002rbQaIYAU`) | **2** ❌ |
| Externer CLI Probe 3 (Case `500WU00002rbcZpYAI`) | **2** ❌ |

## Warum Fix-Attempt 1 nicht reicht
`CaseReactionHandler.isRecomputing` ist ein **statisches** Flag → lebt pro Transaktion/HTTP-Request-Kontext.
Die Tester-Evidenz (docs/SCRUM-418-notizen.md, Zeile ~91) sagt:
> "CaseReactionTrigger AfterUpdate feuert 4x in **2 EXECUTION_CONTEXTS**"

2 EXECUTION_CONTEXTS = 2 getrennte Transaktionen (oder 2 getrennte Trigger-Slots),
die SEQUENTIÄLL laufen, nicht re-entrant innerhalb derselben Transaktion.
Ein statisches Flag kann Kontext A (Count 0→1) vom Kontext B (Count 1→2)
nicht trennen — es ist in beiden Kontexten false, weil jeder Kontext für sich startet.

## Blocker: ApexLog-Body nicht auslesbar
- `sf api request rest /tooling/sobjects/ApexLog/<id>` bringt `LogLength=18747`
  aber KEIN `MessageLog`-Feld in der Response (getestet v62/v63/v67, plus `?fields=MessageLog`).
- `ApexLog/describe` listet als Felder: Id, LogUserId, LogLength, LastModifiedDate,
  Request, Operation, Application, Status, DurationMilliseconds, SystemModstamp,
  StartTime, Location, RequestIdentifier. **Kein MessageLog.**
- Tooling-Query `SELECT MessageLog FROM ApexLog` → INVALID_FIELD.
- Tester-Log-IDs aus SCRUM-418 (`07LWU00000Pbwhl2AB`, `07LWU00000Pbwg92AB`)
  sind retentiv gelaufen → 0 Bytes.
- Browser-Tool ist nur ein CLI-Stub, keine echte Automation.
- Folglich: kein Weg über CLI, REST oder Browser, den Log-Body in dieser
  CLI-Build zu lesen.

## Fix-Attempt 2 — umgesetzt & live-verifiziert (09:03–09:12 UTC)

| Pfad | Count nach 1 Reopen (Closed→New) |
|------|----------------------------------|
| Inline-Apex-`update` (/tmp/419_ab.py, A) | **1** ✅ |
| Externer CLI `sf data update record` (B) | **1** ✅ (vorher 2) |
| Externe Bestätigung Case `500WU00002rcDxbYAE` | **1** ✅ |

**Mechanik:** Zeifenster-Guard im Handler (Fix-Attempt 1 Flag bleibt!).
`recompute()` liest jetzt auch `Last_Reactivation__c`; liegt der DB-Wert
weniger als `REACTIVATION_GRACE_SECONDS = 5` s zurück, wird der „Reopen"
übersprungen (`continue`). Begründung: der 2. ExecutionContext desselben
Reopens liest den Stand, den der 1. Lauf gerade geschrieben hat (Tester-Log:
„2. Lauf liest ZÄHLER=1") — und damit auch das mitschreibende
`Last_Reactivation__c`. Echte Zweitreaktivierung braucht eine Closed-Phase
und liegt im Menschen-Zeitabstand (>> 5 s).

**Tests (12/12):** `SCRUM419ReentryRegressionTest` 4/4 (neu:
`graceWindow_suppressesSequentialDoubleFire`), `SCRUM418CaseReactionTest`
7/7, `SCRUM418CaseReactionFlsTest` 1/1. WICHTIG: 418- und 419-Tests mit
schneller Zweitreaktivierung (ms-Abstand) brauchen jetzt einen Backdate-Schritt
(`Last_Reactivation__c -= GRACE+1 s`) — sonst unterdrückt das Fenster die
legitime 2. Reopen. Apex kann nicht schlafen, Backdaten ist der Weg.

**Falle:** 418-Testklasse stand NICHT in `manifest/scr419-418-fix.xml` →
Deploy meldete „Succeeded", Org behielt alten Test-Body (Tooling-Readback
bewies es). Manifest-Extension + Readback von `ApexClass.Body` = Pflicht
nach jedem Test-Deploy.

**Risiko/Akzeptanz:** ein externer 2. Reopen innerhalb echter 5 s
(Extremfall, menschlich praktisch unmöglich) wäre unterzählt. Fenster ist
konstant im Handler (`CaseReactionHandler.REACTIVATION_GRACE_SECONDS`),
veränderbar ohne Org-Change.

## IDs / Artefakte
- Repro-Cases: `500WU00002ray69YAA` (VOR-FIX), `500WU00002rbQaIYAU` (REST),
  `500WU00002rbcZpYAI` (Probe 3)
- Trace-IDs: DebugLevel `7dlWU000006fYrtYAE`, TraceFlag `7tfWU00000KAj5BYAT`
  (beide in dieser Session erstellt, abgelaufen)
- User-ID Test-Org: `005WU000017tEKLYA2`
- Branch: `feature/SCRUM-419-reopen-doppelinkrement`
  (Base: `feature/SCRUM-418-reaktivierung`, PR #116)
- Manifest: `manifest/scr419-418-fix.xml`
- Tests: `SCRUM419ReentryRegressionTest.cls` (neu), 11/11 grün, Coverage 88%
- Clean-Kopien: `/tmp/419_clean_handler.cls`, `/tmp/419_clean_trigger.trigger`

## Handoff-Bereitschaft (2026-09-19, nach Fix-Attempt 2)
- Externer Pfad verifiziert: Count=1 (zweimal gemessen)
- 12/12 Tests grün (419-Reentry 4/4, 418-Reaction 7/7, 418-FLS 1/1)
- Deploy `Succeeded` + Org-Readback (ApexClass.Body) für jede Komponente
- PR + Review-Handoff (T31 → architect-agent) folgt in diesem Zug
