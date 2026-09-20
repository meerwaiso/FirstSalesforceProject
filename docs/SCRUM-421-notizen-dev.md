# SCRUM-421 Notizen Dev (developer-agent)

Stand: 2026-09-20. Build-Spec: `docs/SCRUM-421-design.md` (Architect, Commit e5db185). Basis origin/master 29dec0b.

## Worktree / Branch
- Worktree: `/tmp/scr421-wt`, Branch `feature/SCRUM-421-queue-assignment` (e5db185, von origin/master).
- Geteilter Checkout steht auf `feature/SCRUM-418-reaktivierung` (NICHT anfassen).

## Org-Zustand (Test-Org, verifiziert)
- `sf org display -o Test-Org`: devops-agent@cline.test, scratch=false, alias `Test-Org`, DevHub `Test-Org`.
- 0 Queues vor Deploy (Group WHERE Type='Queue') — 4 Queues gehören zu diesem Ticket.
- 13 Custom Case Fields, 0 Kollision mit den 4 Kandidaten.

## Haus-Pattern (1:1 SCRUM-420/398, im Repo verifiziert)
- Feld-Meta: KEIN `<apiVersion>`; Picklist = `<valueSet><valueSetDefinition>`, Checkbox = `<type>Checkbox</type><defaultValue>false</defaultValue>`, DateTime ohne Default → null.
- PS-Meta: KEIN `<apiVersion>`; nur die 4 `fieldPermissions`, `hasActivationRequired=false`.
- Apex Trigger/Klasse/Test-Meta: `<apiVersion>62.0</apiVersion><status>Active</status>`.
- FLS-Test = House-Pattern 420/398: `System.runAs(user)` + `Case.X__c.getDescribe().isAccessible()/isUpdateable()` — NICHT rohe SELECT (rohe SELECT auf unvergebenem Feld = "No Such Column"-Wall, Memory). AK10 (negativ + positiv + write-split) damit erfüllt.
- Bulk-Budget: 1 Group-SOQL (static Cache) + 1 DML pro Batch, keine Case-SOQL (nur Trigger.new/old gelesen).
- Manifest version: Phase 1 = 67.0 (Feld/PS, Muster 420-phase1), Phase 2/3 = 62.0.

## Architektur-Entscheidung (TC3/AK3 "simuliert")
- 4 Queues = deploybare SOURCE → existieren nach Phase 2 alle 4 in der Org. End-to-end "Ziel-Queue fehlt" ist daher NICHT darstellbar, ohne eine reale Queue zu löschen (Tabu).
- Lösung: Fallback-Kette als reines statisches `resolveQueueId(targetName, map)` + `resolveTargetName(status, sb)` — TC3 = reine Fallback-Testung (Ziel fehlt→FLS; FLS fehlt→null). Ende-zu-Ende-Zuordnung (OwnerId=Queue) wird in TC1/TC2 über die DEPLOYTEN Queues belegt (Test liest deren Ids per SOQL und vergleicht).
- TC4/AK4 "manuell vorzuweisen": eigener Standard-User als OwnerId ≠ Creator → nicht eligibel.
- TC6: erst Auto-Zuordnung, dann Owner auf User, dann SB-Änderung → nicht eligibel (Owner=User, weder Creator noch Queue).

## Offene (Non-blocking, an PO/Architect im Handoff)
- AK7-Reconciliation (leer⇒nie zuordnen) + Queue-Membership (leer, 0 Support-Users) — schon vom Architect als PO-Offenpunkte markiert.
