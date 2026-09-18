# SCRUM-417 — Notizen (Develop-Zug 16.09., FINAL)

## Stand
- Objekt + 5 Felder + Account-Feld + Apex + PS + CRT **live**, Phase2 komplett
- Trend-Report `Sales/Offene_Werte_Verlauf`: **LIVE** (id `00OWU00000QQhGr2AL`)
- Einbruch-Report `Sales/Groesste_Einbrueche`: **LIVE** (id `00OWU00000QQhjt2AD`)
- Beide Reports in `ReportDefinition` (Tooling-API) verifiziert
- CRT lokale Datei = Org byte-identisch (RT-Deploy `changed=False`)
- refx3: 15/15 Komponenten, 194/194 Tests (RunLocalTests)
- Rebuilder midnight-Fix: `CreatedDate > :prevM` / `>= :startM`, strikte `<` gegen Folgemonats-Start

## Token-Namensräume (Lehre dieses Zugs)
Drei Namensräume tragen denselben Namen unterschiedlich — niemals durchprobieren, erst Namensraum klären.
1. **Dateiname** (Metadata): `SCRUM417_OpportunityHistory.reportType-meta.xml` — kein `__c` in `<members>`.
2. **Verweis aus Report** (Metadata): `<reportType>SCRUM417_OpportunityHistory__c</reportType>` — **MIT** `__c`.
3. **Report-Spalten-Tokens**: `<table>$<field>` (Dollar, kein Punkt), beide Hälften wörtlich aus der CRT-Datei, z. B. `OpenOpportunityHistory__c$Open_Count__c` und `OpenOpportunityHistory__c$AccountId__c.Name`.
Kein `__lookup`-Token (Analytics-REST-Namensraum).

## Review-Fix-Lauf 17.09.
- **Midnight-Fix war regressed**: `run()` hatte wieder `CreatedDate <= :asOf` / `<= :endM` — die Notiz von 16.09. war nicht die Wahrheit, die Datei schon. Date-Binds werden auf Mitternacht des Tages gecastet → alle am asOf-Tag angelegten Chancen raus. Symptom: Full-Suite (RunLocalTests im Deploy) 3× `Expected 9, Actual: 0` / `List has no rows`; isoliert liefen dieselben Tests durch, bis die Klasse live war.
  **Regel: Notizen/Stand-Zeilen beschreiben nie besser als die Datei — erst lesen.**
- Reproduziert per Apex-Skript (frisch inserted offene Chance, `IsClosed=false`, erscheint nicht im Current-Month-Aggregate; Log 07LWU00000Pa8QT2AZ).
- Fix: aktueller Monat ohne CreatedDate-Filter (exakt 416-Menge), vergangene Monate `CreatedDate < :nextMonthStart` (strikt `<` Folgemonats-Start, 16.09.-Pattern).
- `Snapshot_Month__c` required→optional (Org + Source): Plattform lehnt explizite FLS auf required Feld ab (Validate `0AfWU00000bVhUn0AK`: „You cannot deploy to a required field"). allowCreate/Edit=false, Rebuilder füllt jede Zeile, reversibel. Veto an Architekt markiert.
- Final-Deploy grün: `0AfWU00000bVv1V0AS`, 8/8 Komponenten, RunLocalTests (Full Suite) im Deploy.
- Read-Back (retrieve aus Org, nicht aus Deploy-Output): Report `Groesste_Einbrueche` Filter `lessThan 0`; PS FLS = 4 Felder readable inkl. `Snapshot_Month__c`; PS an `devops-agent@cline.test` assigned.
- `History_Key__c` steht nicht in der Tooling-`FieldDefinition`-Liste (15 Felder), aber Rebuilder kompiliert + Upsert-Idempotenz-Test grün → Feld funktional; Ursache der Nicht-Listung ungeklärt, nicht weiter pursued.

## E2E-Lauf 17.09. (Tester, ab 20:00) — Befunde aus Live-Proben, in Spec übernommen
- **Related-List-Karte auf Record-Page rendert GEKÜRZT**: max 7 Zeilen, Stand 17.09. = 6 sichtbar (2026-01..06). "Eine Zeile je Monat" ist nur auf der View-All-Seite prüfbar:
  `/lightning/r/Account/{id}/related/OpenOpportunityHistory__c/view` → 9 Zeilen (SOQL: United Oil & Gas = 9 Zeilen; 2DCF1aYAH = 9 Zeilen, 8× 0/0 + Sept 3/600).
- **View-All via API-Host war der Fehler in allen View-All-Proben**: `instanceUrl` aus `sf org display` = `*.my.salesforce.com` (API-Host) → `title=Login`, 403. Spec läuft über `baseURL` = Lightning-Host (Config) — korrekt. Kein View-All-Beweis aus den Probe-Logs gültig; AK1-ViewAll-Stufe wartet auf den grünen Test-Lauf.
- **Trend-Report rendert langsamer als 25 s**: frühere 25s-`performance.now()`-Break im Poll-Loop = Test-Artefakt (Abbruch → Assertion auf halbefülltem Puffer "2 Zeilen", kein Platform-Fehler). Grenze jetzt 60 s. (User-Hinweis 17.09.: kein Operator-Precedence-Bug in `"X" && false` — war der Parser nie das Problem.)
- **Drop-Definition**: `Wert(aktueller Monat) − Wert(Monat davor)` = 2026-09: **Sept − Aug** (kein Aug − Juli). Rebuilder-Kommentar Z4: "4) Drop-Feld je Kontext". Verifiziert 17.09. SOQL: United Oil & Gas Drop=0, Sept=Aug=4/1.340.000; 0 Accounts Drop<0 (SOQL) → AK5-Liste leer.
- AK5-Test jetzt SOQL-getrieben: Drop-Feld auf JEDEM Account = Sept−Aug aus History-Zeilen (Bulk-Query, 1 Query), UI-Zeilen = Anzahl Drop<0.
- `sf data query`: `SUM(...)`/AS-Alias wird abgewiesen (bekanntes Quirk) → Plain-Select + JS-`reduce` in Spec.
- 37 Probe-Skripte in `tests/e2e/scratch/` (2.421 Zeilen) = Ballast; Werkzeug `npm run probe` existiert bereits (scripts/probe-locators.js). Neue Erkenntnisse gehören ins Spec, nicht in Probe #38.
## E2E-Runde 2 (2026-09-18, nach Suite 4: AK2/AK4/AK5 grün, AK1 rot)
- **AK1-Reader-Fix**: Playwright-Role-Locators (`getByRole('rowheader'|'grid')`) statt hand-gemachtem Shadow-DFS — piercen das LWC-Shadow-DOM nativ. Karte = `grid` → `row`/`rowheader` "YYYY-MM"/`gridcell` (AX-Snapshot 2026-09-18, Fehlerzeitpunkt).
- **View-All-URL**: korrekt `…/related/OpenOpportunityHistoryRecords__r/view` (Relationship-Name), NICHT `OpenOpportunityHistory__c`. AX-Beleg: Karten-Heading-Link.
- **Lazy-Data-Befund AK1**: Karten-HEADER rendert sofort, Grid-DATEN kommen >45 s nach Page-Load (Parallel-Load: 4 Other-Lists gleichzeitig). Suite4: 45-s-Poll sah 0; AX-Snapshot desselben Fehlerzeitpunkts wies 2026-01..06 aus. Fix: `card.getByRole('grid').waitFor({state:'attached'})` VOR dem Poll + 90-s-Fenster + Fehldiagnose (rowheader-count, grid-count, innerText in der Fehlermeldung).
- **Fehldiagnose-Ausgang Suite5**: Article-Wait self 30000ms timeout (selbst die Karte-Heading kam nicht in 30 s) → Article-Wait auf 90 s.
- **AK2**: green seit Suite 4. Kunden-Kontext kommt aus dem Account-Link (href `/lightning/r/<acc>/view`); Gross-Gesamtwert kommt aus der Summary-Leiste (6.352.700,00 € == SOQL sum, 162 == SOQL count — verifiziert, match=True).
- Commits: d6541c0 (Role-Locators + URL + AX2-Summary), 98c181e (Grid-attached + Fehldiagnose + Link-Regex). Suite6 läuft mit 90-s Article-Wait.

## E2E-Runde 3 (2026-09-18, 03:45–04:05)
- Suite5: AK1 ✘ 30s-Wait fuer Karten-Label zu kurz (Parallel-Load). Fix: 90s.
- Suite6: AK1 ✘ accname-Quirk: Locator-Name-Filter ({name:/\d{4}-\d{2}/}) matcht
  die BERECHNETEN accnames nicht (any=6, name-match=0). Fix: alle rowheader
  holen, Filter in JS (/^\d{4}-\d{2}$/). Commit f8aeadc (Karte-Poll im
  Seitenscope: YYYY-MM-Rowheaders sind unique der History-Liste).
- Suite7: AK1 ✘ Karte: getByText/90s Timeout OBTROTZ gerendert (AX-Snapshot
  desselben Zeitpunkts zeigt Karte mit 6+ Rows). => Karten-Label-Wait verworfen,
  Monatsrowheaders als Poll-Anker.
- Suite8a: AK1 ✘ TypeError in der EIGENEN Diagnose: scope.first() existiert auf
  Page nicht (nur Locator). Diagnose war der Crash, nicht die Assertion.
- EVIDENZ Suite8a-Fehlerzeitpunkt (error-context 03:43, View-All 001WU00002DCF1aYAH):
  ARIA-Grid rendert ALLE 9 Monate (rowgroup>row>rowheader "2026-01".."2026-09")
  mit gridcells 0/0,00 € bis 2026-08 und 3/600,00 € fuer 2026-09.
  => View-All-Struktur ist IDENTISCH zur Karte (rowheader+gridcell, NICHT
  th/td); der Report-Finder reportRows() (table tr) gilt hier NICHT.
- Fix (ec5f015): Diagnose page-safe; Poll: Karte 90s (WEICH, Warnung bei 0
  Rows — View-All traegt die AK1), View-All 120s (HART, 9 Monate + Werte=SOQL).
- Suite8b laeuft (proc_01b8dac4dd8e). AK2/AK4/AK5 seit Suite4 gruen.

## E2E-Runde 4 (2026-09-18, ab 04:10)
- WURZEL-GRUND AK1-Werte (Suite9): "rowheader(any)=9, 9x textContent leer".
  View-All rendert die Monatszeilen in GESCHLOSSENER Shadow-Root.
  Accessibility-Tree (getByRole, ariaSnapshot) zeigt sie KORREKT;
  Element.textContent/allTextContents sehen nichts. KARTe = Light-DOM
  (Suite6: 6 Monate lesbar) — umgekehrtes Vertrauensprofil pro Stage.
- FIX (69a2e28, f8f6187): historyMonths = light-DOM + ariaSnapshot-Union;
  Werte Stage-2 per axMonthlyRows (1 ariaSnapshot -> Map Monat->{count,value});
  light-DOM-Fallback. Test-Timeout 480s (Org-Last 6.2 min/file).
- ariaSnapshot-Format (Playwright 1.61, doc-geprueft): YAML-ish,
  Zeile "- rowheader: \"2026-01\"" / "- gridcell: \"0,00 EUR\"".
- Browser-Use-CLI (browser_exec) ist in dieser Umgebung CLI-Wrapper,
  liefert --help statt Live-DOM — NICHT als Locator-Ground-Truth nutzbar.
  Einziges Live-Werkzeug: npm run probe (INTERAKTIVE Elemente nur,
  data-Zellen blind) + error-context.md + in-spec gridDiag.
- Suite10 (06:25, 3.5 min): AK2/4/5 GRUEN. AK1 rot an Stufe 1 (Karte): line 438
  "Karte TEST-SCRUM-416-AK1/2026-01: Zellen ohne Anzahl UND Betrag (leere Zeile)".
  Fortschritt: nicht mehr View-All (AX-Reader dort ok), sondern der light-DOM
  historyRowValues-Reader auf der KARTEN-Seite. error-context 06:25:46 (Karten-Page):
  AX-Baum hat rowheader "2026-01" + gridcell "0" + gridcell "0,00 €" voll -> der
  AX-Lesepfad ist auch hier der tragfaehige; light-DOM td/[role=gridcell] matcht
  in der Karte nichts (geschlossene Shadow-Root um die Datenzellen).
- Fix commit 1942bf0: Stufe 1 (Karte) liest jetzt wie Stufe 2 via axMonthlyRows
  (ein ariaSnapshot -> Map Monat->{count,value}), light-DOM nur Fallback.
  diag4 = AK1-alone-Lauf auf 1942bf0.
  Fallback-Logik: count undefined -> 1. parsierbare Zelle der Zeile; value -> 2.
  (Snapshot-Zeile: leer, Select-Item-Check, Anzahl, Betrag, Show Actions.)
- diag4 (07:14, 8.3 min): AK1 KARTEN-STUFE GRUEN (AX-Reader 1942bf0 ok).
  Neuer Fehler an spec.ts:489 = View-All-goto: "Test timeout of 480000ms
  exceeded" + "page.goto: Target page, context or browser has been closed"
  (record-page.ts:18). NICHT Org-Crash (free -m: 16GB frei, kein OOM in dmesg):
  das 480s-Test-Budget war erschopft, Playwright schoess den Browser per
  Timeout. Ursache: 11 aufeinanderfolgende sf-Roundtrips im Setup (pickAccount
  2 + je Monat 1 x 9); heute (Morgen-Last) ~10-20s je Aufruf -> ~3 min Vorlauf.
  error-context 07:14:14: 0 rowheaders (Seite tot, kein Live-Grid).
- Fix 53b482e: soqlByMonthFor() = 1 IN-Query statt 9 (SOQL-Pruefung: IN-Liste
  laeuft, ~1.4s bei 9 Zeilen). AK1-Budget rechnerisch: Setup ~1 min (3 SOQL
  statt 11) + Karte 90s + View-All 120s + Rand = ~5-6 min < 480s.
  diag5 = AK1-alone auf 53b482e (proc_48510822454d).
  Wenn View-All auch unter Load >120s: historyMonths-Timeout 120000 -> 180000.
