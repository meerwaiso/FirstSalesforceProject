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