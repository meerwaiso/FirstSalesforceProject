# SCRUM-421 Notizen (Architect)

Befunde, die eine Kompression überleben müssen. Stand: 2026-09-20, `origin/master` 29dec0b.

## Org / Repo
- Org: Test-Org (devops-agent@cline.test, DevHub 🌳). Prod = Prod-Org. Ich deploye NICHT.
- Queue ist deploybarer Source-Typ: CLI `metadataRegistry.json` → `/types/queue {directoryName:"queues", suffix:"queue"}`. Repo hat heute KEIN `queues/`-Verzeichnis.
- **0 Queues** in der Test-Org (`Group WHERE Type='Queue'` → 0). 4 Ziel-Queues gehören zu diesem Ticket.
- **13 Custom Case Fields** — keine Kollision mit `Servicebereich__c`/`Kundenstatus__c`/`Automatische_Zuordnung__c`/`Zuordnungszeitpunkt__c` (per `sf sobject describe -s Case -o Test-Org` geprüft).

## Haus-Pattern (SCRUM-420, identische Logikshape)
- 420-PS grantet auf die 4 systemgepflegten Felder **NUR read-FLS** (`editable=false/readable=true`) — **der eigene Trigger schreibt sie trotzdem, ohne Write-FLS**. → 421: Checkbox+Zeitstempel = read-only im PS, Trigger schreibt.
- Trigger: `after insert, after update`; `without sharing`; `private static Boolean isRunning` Guard (try/finally); 1 Handler-Call/Batch; `AggregateResult` (nicht `Aggregate`).
- **Update-Filter = nur die relevanten Felder** (bei 420: Status/Priority/AccountId; bei 421: `Servicebereich__c`+`Kundenstatus__c`) → eigene Writes feuern nicht zweimal + `isRunning` als zweite Ebene.
- `update toUpdate` **nur bei `!isEmpty()`** (leerer DML-Call = Fehler, 418-Lektion).
- apiVersion: Apex Trigger/Klasse = **62.0**; Feld-/PS-/Layout-Meta = **kein** `<apiVersion>`-Element.
- Layout `Case-Case Layout.layout-meta.xml`: 420-Sektion «Eskalation (Kunde)» ab Zeile 202 (OneColumn), dann «System Information». Neue 421-Sektion «Zuordnung» **dazwischen** (nach 420, vor System).

## AK7-Reconciliation (wichtig)
- PO-Matrix „Standard + beliebig → FLS“ kollidiert mit AK7 „Servicebereich leer → nicht zuordnen“.
- Arch-Default: **SB leer ⇒ nie zuordnen** (AK7 gewinnt). Als Non-blocking-Offenpunkt an PO.

## Manifest-Phasen (Haus-Muster 420)
- phase1 = 4 Felder + PS; phase2 = 4 Queues + 2 Apex + Trigger + 2 Tests (RunSpecifiedTests); phase3 = Layout.
- **Kein Rebuilder/Backfill** (Scope = neue Fälle).

## Branch / Commit
- Worktree: `/tmp/wt-scrum-421`, Branch `feature/SCRUM-421-queue-assignment` (von origin/master).
- Build-Spec = `docs/SCRUM-421-design.md`.

## Open (Non-blocking, PO)
1. Queue-Membership leer (0 Support-Users) → Team-Mitglieder später per Org-Setup.
2. AK7-Reconciliation Default bestätigen.
