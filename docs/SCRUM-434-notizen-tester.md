# SCRUM-434 Notizettel (TESTER)

## Status: TESTBESTANDEN — 5/5 AK, alle Pfade grün

## Auftrag
Testen: 5 ACs gegen Test-Org. PR #149, branch `feature/SCRUM-434-ursache` @ 79ef57e.
Architect approved 3. Durchgang (Kommentar 22040): "Monat/Quartal-Auswahl ist
UI-Interaktion auf dem Zeit-Filter → gehört in deinen E2E-Lauf."

## Org-Fakten (read-back, mit Befehlsname)
- Test-Org Alias: `Test-Org` (devops-agent@cline.test),
  `sf org display` → resourceful-bear-6f1u4j-dev-ed.trailblaze.my.salesforce.com
- Report `Faelle_Nach_Ursache`, ID `00OWU00000QcH452AF`, ReportType CaseList,
  scope organization, Filter CLOSED=1, timeFrameFilter CLOSED_DATE,
  Grouping Case.Ursache__c (aus Report-XML in Repo)
- ValRule `Ursache_PflichtBeiGeschlossen`:
  `AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Ursache__c)))` (aus Meta-XML)
- PS `SCRUM434_Ursache` deployed + assigned (Dev-Read-back: devops-agent, Meerwais Osmani)
- `sf sobject describe -s Case` → Status picklistValues: New/Working/Escalated/Closed,
  alle `validFor=None`, restrictedPicklist=null
- ClosedDate: `updateable=false, creatable=false` (describe) → kein historisches Backdating

## AK-Mapping (final, mit Beleg)
- **AK1** `picklistUrsacheExists` + layoutContainsUrsacheColumn + FLS-POS: 5 Werte
  (TechnischerFehler/RechnungAbrechnung/HowToAnfrage/ProduktProblem/Anderes),
  Feld in Case-Layout, API+FLS lesbar
- **AK2** `testValidationRuleBlocksSaveWithoutUrsache` (API-Satz Status=Closed ohne
  Ursache → DML Exception, Fehlermeldung enthält 'Ursache') +
  `testValidationRuleAllowsSaveWithUrsache` (mit Ursache → sauberes Speichern)
- **AK3** `testFLSWithoutPermissionSet` (runAs ohne PS: isAccessible false) +
  `testFLSWithPermissionSet` (mit PS: true)
- **AK4** `SCRUM-434-ac4-report.spec.ts` (E2E): Report rendert, Total 23,
  4 Gruppe-Kacheln, Range-Filter 90→30 Tage wirkt (23→21), UI-Zahlen == SOQL je Kategorie
- **AK5** layoutContainsUrsacheColumn (Feld in Page-Layout) + FLS-POS-Test
  (createable/updateable/readable)

## Messergebnisse (SOQL-Ground-Truth, Befehl unten)
- 90 Tage: 23 geschlossene Cases → 20 leer + 1 je Ursache (3 eigene Test-Cases)
- 30 Tage: 21 geschlossene Cases → 18 leer + 1 je Ursache
- `sf data query -o devops-agent@cline.test --use-tooling-api -q "SELECT CASE WHEN
  IsNull(...) THEN '(leer)' ELSE Cause END AS k, COUNT(Id) ..."`

## Testdaten in Org (zur Cleanup)
- 3 Cases, Subject-PREFIX `TEST-SCRUM-434-AC4`: …-TechnischerFehler, …-RechnungAbrechnung, …-HowToAnfrage
- 1 offen Case: `SCRUM434-AC2-UI-Priority: Medium` Subject, Id `500WU00002tcSCHYA2` (Offen, ohne Ursache)
- Alle Closed-Cases: ClosedDate=2026-09-30 (heute, platform-setzt automatisch)

## VERIFIZIERTE LOCATOR-PFAD-Erkenntnisse (2026-09-30, alle in eigener Session gemessen)
1. **Report Page** `/lightring/r/Report/…` rendert in cross-doc iframe (src /analytics/report/…).
   Locator: `frame.locator('li.table-row[aria-label]').first()`. Total-Zeile: `/X Records/.`
2. **Record Page Case**: Feld-Kachel = `li.rsList` mit Text `Status: ` bzw. `Ursache: `
   (kein aria-label am li — Text-Match nötig: `li.rsList:has-text("Status:")`).
3. **Inline-Edit**: `button "Edit Status"` / `"Edit Ursache"` (getByText exakt) →
   öffnet Kombobox-Edit, Dropdown mit `role=option`.
4. **Case-Status-Picklist in Sales-App-Record-Page zeigt 4 Werte**
   (None/New/Working/Escalated) — **Closed fehlt in der UI**, ist aber API-gültig
   (describe: validFor=None; API-Satz Status=Closed → ClosedDate automatisch + IsClosed=true).
   Scroll-Probe: saubere 4-Element-Liste (scrollHeight=clientHeight=72) → kein Verpassen.
   **Bewertung: KEIN SCRUM-434-Defekt** (Diff des Tickets = nur `Ursache__c` + PS + Report + ValRule).
   Org-/App-Quirk, als Befund dokumentiert (s. Jira-Kommentar). AK2 bleibt über API+Apex belegt.
5. **Range-Picklist (Report-Filter)**: `li.sectionable-table-row` mit Text `Date/Time Closed`,
   Klick → Range-Combobox `[class*=custom-range-picklist] [aria-haspopup=listbox]`
   (klassenloser Button, aria-expanded wird true). Optionen: `frame.locator('[role=option]')`
   mit HAS-TEXT-Substring 'Last 30 Days' / 'Last 90 Days'. Nach Klick: Wert-Verifikation
   über `.slds-show:has-text("Last 30 Days")` + neu gerenderte Total-Zeile (`expect.poll`).

## CLI-Quirks diese Org (VERIFIZIERT 2026-09-30)
- `sf data query` in CLI 2.150: keine Aggregation/JOIN/AS-Verb mit SOQL über Standard-Alias,
  aber `--use-tooling-api` erlaubt COUNT/AS-COUNT/JOIN auf Standard-Objects (Case) → das ist
  der Weg für die Observed-Zahlen.
- `sf apex run test` async ohne `-y` → liefert nur testRunId, `sf apex run test get` leer
  in dieser Org. Sync-Run: `sf apex run test --tests SCRUM434UrsacheTest -t Test-Org --wait 5 -y --json`
  (exit 0, alle 6 Tests PASS, 3022 ms).
- `sf sobject describe -s Case` liefert picklistValues direkt (kein Tooling-Query nötig).

## Handoff
- HTML-Report: `test-report/index.html` (533 KB, 3/3 grün: 2 Smoke + 1 AC4-E2E)
- Alle 5 AK belegt (s. Coverage-Tabelle im Jira-Kommentar)
