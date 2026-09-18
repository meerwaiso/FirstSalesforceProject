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
