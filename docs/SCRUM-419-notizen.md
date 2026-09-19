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

## Offene Frage für den nächsten Fix (Fix-Attempt 2)
Ob die 2 EXECUTION_CONTEXTS aus
(a) einer **doppelten REST-Antwort** (Plattform sendet den Update zweimal),
oder
(b) einer **doppelten Trigger-Feuerung** in einer einzigen Antwort
kommen. Das ist der Unterschied, der entscheidet, welcher Fix passt:

- Fall (a): Idempotenter Handler nötig (Voll-Recompute statt Delta+1).
- Fall (b): Zeitstempel-Guard (`Last_Reactivation_Attempt__c`, 500ms-Fenster).

Beide Varianten sind ohne Log-Body nicht eindeutig belegbar.

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

## Nicht umgesetzt (bewusst zurückgehalten)
- Kein PR, kein Review-Handoff (T31 → architect-agent)
- Keine Commit-Akku­mulation jenseits des Fix-Attempt-1-Stands
- Keine 3. Runden-Iteration ohne Log-Body-Beweis oder Review-Entscheidung
