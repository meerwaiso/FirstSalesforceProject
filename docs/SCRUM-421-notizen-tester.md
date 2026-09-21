# SCRUM-421 — Tester-Notizen (Zwischensstand)

Worktree: /tmp/scr421-wt, Branch feature/SCRUM-421-queue-assignment, Head 576f627.
Shared-Checkout (418) NICHT angefasst. node_modules = Symlink aus Shared-Checkout.
Org: Test-Org (dev-ed host resourceful-bear-6f1u4j-dev-ed). Parse-ENV: FORCE_COLOR=0 NO_COLOR=1.

## Testurteil (eigene Runs)
- Apex, eigener Run: `sf apex run test --class-names SCRUM421QueueAssignmentTest,SCRUM421QueueAssignmentFlsTest -o Test-Org`
  -> Run `707WU00001JigBl`, 12/12 pass (0 fail/0 skip).
- Playwright Smoke: `npm run test:e2e:smoke` -> 2/2 pass [SMOKE].
- 11/11 AK gedeckt ueber die 2 Dev-Testklassen (tc1-9 = AK1-9, FLS-Test = AK10+AK11).

## Kernbefund Live-Abweichung (NICHT 421-Code)
- In @isTest / Apex-Create liest man nach dem Handler zurueck: Owner = Queue (tc1 gruen, belegt).
- Im LIVE/REST-Create-Weg (sf data create, wie bei Import/Integration) landen einige
  Cases am Ende mit Owner = User `meerwais` (005WU000017tBhRYAU), NICHT der gerouteten
  Queue (00GW...L392AF). Automatische_Zuordnung__c = true in beiden (Handler lief).
- Signatur: synchron, nur im live/REST-Weg, nicht unter @isTest.

## Ausschluss (verifiziert)
- Einzige OwnerId-Schreib-Quelle im Repo (421-Branch) UND in origin/master:
  `CaseQueueAssignment.cls` (routet nur auf Queue-Ids). grep bestaetigt.
- Kein Flow/Workflow/Reactive-Process, keine Assignment-Rule-Referenz in Apex,
  keine Queueable/Batch-Jobs, keine Queue-Membership.
- Deployed-Bodies aller Case-Triggers + 81 Apex-Classes per Tooling-Query gecheckt:
  kein meerswais-Literal (005...BhRYAU), kein zweiter OwnerId-Writer.

## Wurzelursache-Kandidat (Org-State, NICHT im Repo)
- Aktive Case Assignment Rule "Standard" (active=true) per `sf project retrieve`
  geholt: 5 RuleEntries, ALLE assignedTo = `meerwais.osmani@resourceful-bear-6f1u4j.com`
  (User), Kriterien auf Account.Type/SLA__c/BillingCountry.
- DIESE RULE IST NICHT im 421-Branch UND NICHT in master (git ls-tree leer, keine
  *.assignmentRules im Repo). = vorgefunden, fremd, Org-Drift/anderes Feature.
- Offener Rest: Account-Lose Cases enden teils auch bei meerwais -> reine
  Account-Kriterien der Rule erklaren nicht alles. Genau-Mechanismus NICHT final
  geklaert (Eskalation, kein sturischer Loop). Debug-Log lief nicht sauber ab
  (TraceFlag-Felder/Picklist; CLI 2.139.6).

## Test-Cases in Org (Evidenz)
- 500WU00002risLJYAY (Premium/Technik) -> mehrwais, auto=true  [Abweichung zu tc1]
- 12 neuste Cases: Mix aus meerwais(005..) und Queue(00GW..), auto=meist true.

## Handoff
- Kein Code-Defekt in 421. Deliverable korrekt + getestet.
- Live-Anomalie = Org-Config, fuer Tester nicht loesbar (kein Org-Config-Change by Tester).
- Bug-Ticket angelegt + an 421 verlinkt. Urteil in Raum. Entscheidung = team-seitig.
