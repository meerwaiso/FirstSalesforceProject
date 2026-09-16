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