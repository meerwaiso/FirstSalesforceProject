# SCRUM-434 + SCRUM-435 — Prod-Release Notizen (DevOps-Agent)

Release `release/2026-09-30-SCRUM-435`, Deploy-Job `0Afg500000FPJ8TCAX`.
Beide Tickets zusammen: 435 war als Superset (434+435) per PR #151 squash-merged,
Commit `d7d8a17` auf `origin/master` — 434's PR #149 wurde als superseded
geschlossen. Prod-Org enthält beide Features erst nach diesem Deploy.

## Gate (beide Bedingungen gleichzeitig, vom Tracker)
- SCRUM-434 UND SCRUM-435: Status `Release`, Assignee `devops-agent` —
  `jira_get_issue` am 30.09.2026, beide Tickets (Room-Nachricht des Users nur
  Anstoß, Tracker-Reading hat die Autorisierung getragen).
- Merge-Gates vor dem Release: PR #151 CI 3/3 hart grün auf `31a43a3`
  (Smoke, Drift, Lint), Run 36692455214 — dokumentiert in Jira-Kommentaren
  beider Tickets.

## Preflight-Befund — Korrigierung
Frühere DevOps-Kommentare in SCRUM-435/434 (Tag-Moment) hatten behauptet, die
434-ValRule sei bereits live in Prod und der 428-Handler ungefixt. **Beides wird
hier korrigiert:** Retrieve-Proof von Prod-Org VOR dem Deploy (Probe
`/tmp/probe435.*`) zeigte:

- `Case.Ursache__c` — **nicht** gefunden
- `Case.Ursache_PflichtBeiGeschlossen` — **nicht** gefunden
- `SCRUM434_Ursache` — **nicht** gefunden
- `SCRUM428CaseIngestHandler` — vorhanden, **ohne** `Ursache` (ungefixt,
  `applyDup` schloss ohne Ursache)
- `Case-Case Layout` — vorhanden (ohne Rueckschau-Sektion)

Folge: der "live Prod-Defect" (ValRule blockiert Dup-Schliessung) war noch
**nicht** eingetreten, weil die ValRule noch nie in Prod war. Dieser Release ist
erst der eigentliche Rollout von 434+435. Kein Zeitdruck, kein Workaround;
normale 3-Phase-Gate-Logik.

## Deploy — Prod-Org (`devops-agent@cline.de`, OrgId 00Dg500000DkTtzEAF)
- Worktree `/tmp/scr435-prod` auf `origin/master`@`d7d8a17` (detached);
  geteilter Checkout (SCRUM-424, dirty) unangetastet.
- Manifest `manifest/release-scr434-435-combined.xml` (targeted, Hausmuster
  `release-scr432-combined.xml`): komplett 434/435-Diff seit Tag
  `release/2026-09-27-SCRUM-432`, 19 Komponenten:
  - 1 CustomField `Case.Ursache__c` (Picklist 5 Werte)
  - 1 ValidationRule `Case.Ursache_PflichtBeiGeschlossen` (harte Schliess-Barriere)
  - 1 PermissionSet `SCRUM434_Ursache` (FLS Read+Edit)
  - 1 Layout `Case-Case Layout` (Rueckschau-Sektion)
  - 1 Report `Service/Faelle_Nach_Ursache`
  - 14 ApexClass: 428-Handler (435-Fix), 434-Fixtures/Test, 435-Tester-Verifikation,
    10 ältere Fixture-Tests (365/367/370/390/403/410/418/419/420) — alle tragen
    seit `d7d8a17` das neue Pflichtfeld und sind Teil des Release-Scope
- Test-Scope bewusst `--test-level RunSpecifiedTests --tests
  SCRUM434UrsacheTest SCRUM435TesterVerificationTest` (Hausmuster 431/432):
  die 10 Fixture-Tests sind daten-abhängig (SCRUM-370 war vor diesem Release
  in Prod rot am SOQL-Limit) und gehören nicht in den Release-Gate.

### Validate + Deploy
1. **1. Validate versagt an meinem Aufruf selbst**: `--tests A,B` (Komma) →
   CLI warnt, dass Trennung über **Leerzeichen** erfolgt; 0 Tests laufen →
   Coverage 0% an 428-Handler + 434-Fixtures. Keine Org-Fehler, kein Retry mit
   verändertem Inhalt — Syntax korrigiert, 2. Validate: **Succeeded**,
   Job `0Afg500000FPJ6rCAH`, 19/19 Komponenten.
2. **Real-Deploy**: Job `0Afg500000FPJ8TCAX`, `rollbackOnError=true`,
   Status `Succeeded`, **19/19 Komponenten, 0 Fehler, 9/9 Apex-Tests,
   0 TestErrors** (Report `sf project deploy report --job-id 0Afg500000FPJ8TCAX`).

## Read-Backs (aus der Org gelesen, nicht behauptet)
- **PS-Assignments 2/2** (`PermissionSetAssignment`):
  `devops-agent@cline.de` + `meerwais.osmani.3ecaf61ebe28@agentforce.com`
  — Lektion #7 (7× wiederholt: 382/386/388/390/394/398/421) angewendet.
- **FLS via Live-Session**: Benutzer mit PS liest `Case.Ursache__c`
  (`SELECT Id, Subject, Ursache__c FROM Case ...`) — `No such column` nicht
  reproduzierbar; Wert `null` korrekt (neueste Fälle nie geschlossen).
- **Handler fix in Prod**: Retrieve-Probe nach Deploy — Prod-Handler Zeile 330
  `c.Ursache__c = 'KeinFehlerKeineMassnahme';` (applyDup) und Zeile 118
  `copy.Ursache__c = c.Ursache__c;`. Vor-Deploy-Probe: keine `Ursache`-Zeile.
- **Retrieve-Nachweis**: alle 6 Manifest-Komponenten-Typen erfolgreich aus
  Prod-Org geholt (success=True, keine componentFailures) — Vor-Deploy waren
  die 434er Komponenten "cannot be found".

## Restliche Drift (nicht Teil dieses Releases)
- SCRUM-370 Fixture-Test ist in Prod daten-abhängig rot (SOQL-Limit) —
  eigenständiges Ticket, nicht 434/435.
- Die 428-Drift-Signatur im CI-Drift-Gate (SCRUM319OverdueOpportunityTest)
  aus vorherigen Notizen wurde nach diesem Deploy nicht neu geprüft;
  das Gate der nächsten PRs zeigt den Stand.
