# SCRUM-432 — Prod-Release Notizen (DevOps-Agent)

## Gate (beide Bedingungen gleichzeitig, vom Tracker)
- Status `Release`, Assignee `devops-agent` — `jira_get_issue` am 27.09.2026 ~21:08 (CEST).
- PO-Hinweis im Room: „Ticket 432 ist dir zugewiesen und bereit zum prod deploy" (Room-Nachricht,
  durch Tracker-Reading bestätigt — room allein wäre keine Autorisierung).
- Merge-Vorgeschichte: PR #146 (squash), Commit `28b892d` auf `origin/master`.
  Merge-Gate 4/4 dokumentiert in Jira-Kommentar 21637 (CI-Run 36338448042 auf head `fb2e3bb`,
  Architect-Approval Kommentar 21603, Tester-Sign-off Kommentar 21636).

## Deploy — Prod-Org (`devops-agent@cline.de`, OrgId 00Dg500000DkTtzEAF)
- Worktree `/tmp/scr432-prod-deploy` auf `origin/master`@`28b892d` (detoached);
  geteilter Checkout (SCRUM-424, dirty) unangetastet.
- Manifest `manifest/release-scr432-combined.xml` (targeted, Hausmuster `release-scr431-combined.xml`):
  4 CustomField qualifiziert (`Case.Wiedervorlage_Datum__c`, `Case.Wiedervorlage_Notiz__c`,
  `Case.Wiedervorlage_Von__c`, `Case.Wiedervorlage_Heute_Offen__c`),
  1 PermissionSet `SCRUM432_Wiedervorlage_ServiceTeam`,
  1 ListView `Case.Wiedervorlagen_heute_offen`,
  1 Layout `Case-Case Layout`, 2 ApexClass (Test).
  Bewusst NICHT ganze force-app (fremdes Drift nicht mitschleppen — SCRUM-417-Lektion).
- Preflight: `sf sobject describe -s Case -o Prod-Org` → 0 Wiedervorlage*-Felder (clean deploy).
  Prod-Org `PermissionSet WHERE Name LIKE 'SCRUM432%'` → 0 (clean).

### Befund — Vollsuite-Validate schlägt an fremdem Test
- `sf project deploy validate --manifest ... -o Prod-Org` (ohne Test-Scope) → **FEHLSCHLAG**:
  `SCRUM370OpenCasesRatingTest.caseEvents_deriveCorrectRatingFor0To6 -
  System.LimitException: Too many SOQL queries: 101`.
  Kein einziger 432er-Komponentenfehler — 370er-Test (Daten-abhängig, anderes Ticket) rot in Prod-Org.
  Standard checkOnly-Deploy läuft die **gesamte** Org-Suite; 432er-Komponenten sind sauber.
- Abhilfe (Hausmuster, wie SCRUM-431-Notizen): `--test-level RunSpecifiedTests
  --tests SCRUM432WiedervorlageTest SCRUM432WiedervorlageFlsTest` — Tests selbst-contained
  (erzeugen eigene Test-Daten im runAs-Kontext, laufen zurück).
- Validiert: `status: Succeeded`, 9/9 Komponenten, 0 Fehler (Validierungsjob 0Afg500000FHPm9CAH =
  die **fehlgeschlagene** Vollsuite-Validierung; die RunSpecified-Validierung lief als eigener Job).

### Real-Deploy: Job `0Afg500000FHRETCA5`
- **Status: Succeeded**, `numberComponentsDeployed` 9/9 (8 Created, 1 Layout Changed),
  `numberTestErrors` 0, **11/11 Apex-Tests pass** (RunSpecifiedTests: SCRUM432WiedervorlageTest(10)
  + SCRUM432WiedervorlageFlsTest(1)), `rollbackOnError: true`, 27.09.2026 ~19:46 UTC.

## Permission Set — Deployed AND ASSIGNED (Lektion #7, 7× wiederholt: 382/386/388/390/394/398/421)
- `sf org assign permset -n SCRUM432_Wiedervorlage_ServiceTeam -b
  meerwais.osmani.3ecaf61ebe28@agentforce.com devops-agent@cline.de -o Prod-Org` → 2/2 assigned.
- Read-Back: `PermissionSetAssignment WHERE PermissionSet.Name='SCRUM432_Wiedervorlage_ServiceTeam'`
  = **2 Zeilen** (gelesen, nicht nur zugewiesen).

## FLS-/Formel-Read-Back via realer Prod-Session (CLI-User hat PS)
- `sf data query -o Prod-Org -q "SELECT Id, CaseNumber, Wiedervorlage_Datum__c,
  Wiedervorlage_Notiz__c FROM Case LIMIT 3"` → Felder lesbar, Werte null
  (erwarteter Erstzustand: noch keine Wiedervorlagen gesetzt).
- Formel-$User-Proof (live): Probe-Case `500g5000017zvsrAAA` mit
  `Wiedervorlage_Von__c = 005g5000009C4M4` (CLI-User), `Wiedervorlage_Datum__c = 2026-09-27`
  → `Wiedervorlage_Heute_Offen__c = true` (korrekt: Von=self AND Datum≤TODAY).
  Record danach gelöscht, Verif `SELECT COUNT(Id) ... WHERE Subject='ProdReadback432'` → 0.

## Lichtung (ADR-8-Offenpunkt): Lightning-Page-Placement — N/A für dieses Release
- `sf data query -o <Org> -t -q "SELECT Id, DeveloperName FROM FlexiPage WHERE
  DeveloperName LIKE '%Case%'"` → in **Test- UND Prod-Org 0 Treffer**.
  Es existiert in keiner Org eine Lightning-Record-Page für Case (beide Orgs: nur UtilityBars +
  `BetreuungsuebergabePage` [User]). → Der ADR-8-Punkt „Lightning-Page im Org setzen" ist für
  SCRUM-432 kein Deploy-Action; Classic `Case-Case Layout` ist das einzige Layout, das
  getrackt/deployed wird. Sollte später eine Case-Lightning-Page entstehen, ist das App-Builder-
  Placement (3 Wiedervorlage-Felder, Formel DRAUSSEN) ein eigener Org-Schritt.
- Test-Org `sf project retrieve -m "FlexiPage:*"` liefert 0 Dateien — Consistent.

## Daten / Drift
- Keine Prod-Daten verändert (Probe-Case erstellt+gelöscht; Test-Rollen zurück).
- Kein neues Drift erzeugt (targeted-Manifest = exakt die 9 432er-Komponenten).
  Bestehende externe Drift (z. B. SCRUM-319/421) bleibt in Scope wie bei SCRUM-428/431.
- Bekannter fremder Prod-Defekt (kein 432-Befund): `SCRUM370OpenCasesRatingTest`
  (SOQL-Limit 101) — rot in der Vollsuite. Gilt als eigener Vorgang; bei jedem
  zukünftigen checkOnly-Deploy ohne Test-Scope wird er weiter rot.

## Release
- Tag `release/2026-09-27-SCRUM-432` → zeigt auf den Release-Notizen-Commit auf `origin/master`
  (Hausformat `release/YYYY-MM-DD-SCRUM-NNN`, NICHT unter `archiv/`).
