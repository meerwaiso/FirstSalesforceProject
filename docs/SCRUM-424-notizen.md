# SCRUM-424 Notizen

## Messwerte (2026-09-21, Test-Org, self-verified)
- `BusinessHours.diff(bhId, 2026-09-18T16:00Z, 2026-09-21T07:00Z)/60000` = **3780 min** (Kalenderminuten — Org 24/7)
- `BusinessHours.isWithin(bhId, ...)` = true; `bhId`-Prefix `01m`, `IsDefault=true`, TZ `America/Los_Angeles`
- `TimeZone.getTimeZone('America/Los_Angeles').getOffset(Datetime.now())` = **-25200000** (Signatur: getOffset(Datetime), NICHT Long)
- `Math.mod(17,7)` = 3 — **% und System.mod existieren in Apex nicht; Math.mod schon**
- `ServicePresence`/`WorkingHours`: NICHT verfügbar („Variable does not exist“/„Invalid type“, Deploy-Compile)
- `BusinessHours:Default` Retrieve: `RegistryError` — **BusinessHours ist kein Source-Metadaten-Typ** (kein directoryName) → Setup + SOQL-Read-back, NICHT Deploy
- `sf project retrieve start -w <pfad>` existiert nicht (das ist --wait); Zielverzeichnis nur im Projektlayout

## Befunde
- `origin/master` = 40ac174 (21.09.); Branch `feature/SCRUM-424-first-response` darauf
- 127 Case-Felder, `First_Response_Time__c`/`First_Response_Working_Mins__c`/`First_Response_Target_Missed__c` kollisionsfrei
- Report-Hausform `Ueberfaellige_Faelle`: `reportType=CaseList`, Filter = `<filter><criteriaItems><column><operator>(leer für null)</criteriaItems></filter>`, Standardfelder als TOKEN (CASE_NUMBER, PRIORITY) nicht Case.X
- Layout-Insertion: nach 421-Sektion „Zuordnung“ (Zeil ~227), vor „System Information“
- 421-Folge: Profil-Lock VOR FLS-Test (sonst Negativ-Test rot, 1 Runde Verlust)
- Org hat 0 Flows; PO „Flow-WorkWeek“ = klassische BusinessHours (Org-Fakt dokumentiert)

## Org-Hygiene
- 3 Probe-Klassen in Test-Org: SCRUM424_ProbeObj, SCRUM424_ProbeRunner, SCRUM424_ModProbe (@IsTest, inaktiv, nicht im Manifest, Org-Delete verboten → bleiben)
