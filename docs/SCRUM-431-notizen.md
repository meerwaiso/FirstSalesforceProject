# SCRUM-431 — Notizen (Developer)

## Namen (byte-exakt aus Design-Doc 1ea9dc4 extrahiert, NICHT tippen)
- Account-Feld: `Wartungsvertrag__c` (mit s!), Label `Wartungsvertrag`, Checkbox, default false
- Case-Feld: `Wartungsvertrag_Anzeige__c`, Label `Wartungsvertrag (Kunde)`, Text-Formel
- PS: `SCRUM431_Wartungsvertrag_ServiceTeam`, `SCRUM431_Wartungsvertrag_Teamleitung`
- Report: `Service/Morgen_UEbersicht_Vertragskunden` (CaseList)
- Manifest: `manifest/scr431-wartevertrag.xml`
- Jira-Kommentar 21298 enthaelt den Tippfehler "Wartungsvertrag" (ohne s) — Design-Doc ist korrekt (Kommentar 21331 weist darauf hin).

## Test-Org
- Alias `Test-Org`, Username `devops-agent@cline.test`, Default target-org, verbunden.
- API-Version 67.0 (`sf org display`).
- Branch/Worktree: `feature/SCRUM-431-wartevertrag` → `/home/fino/Desktop/SoftwareProjects/Salesforce/FirstSalesforceProject_scr431`.
- Geteilter Checkout `/home/fino/Desktop/SoftwareProjects/Salesforce/FirstSalesforceProject` lauft auf `feature/SCRUM-424-first-response` mit uncommitted Resten — NICHT anfassen, eigene Worktree nutzen.

## Report-Spalten (Analytics-API v67 /services/data/v67.0/analytics/reportTypes/CaseList)
- Kunde = `ACCOUNT.NAME` (entity Account.Name)
- offen seit = `CREATED_DATE` (entity Case.CreatedDate, datetime) — gewählt (AC "offen seit", lesbarer als AGE)
- Betreff = `SUBJECT` (Case.Subject), Fallnummer = `CASE_NUMBER` (House-Report Ueberfaellige_Faelle belegt CASE_NUMBER als gueltige CaseList-Spalte)
- Filter: `IsClosed` equals `0` (entity Case.IsClosed, boolean) + `Account.Wartungsvertrag__c` equals `1`
- **Scope**: defaultValue=user! CaseList-Wert fuer "All cases" = `organization`. Haus-Reports (Unverteite_Faelle, Wiedereroeffnungen_3Monate) setzen `<scope>organization</scope>` — ich auch (sonst nur eigene Cases, SCRUM-394-Fehlerklasse).
- Sortierung: Tabular + `<groupingsDown><field>CREATED_DATE</field><sortOrder>Asc</sortOrder></groupingsDown>` (House-Shape Ueberfaellige_Faelle).

## Haus-Formen (deportiert/im Repo, deploygueltig)
- Checkbox: `Account.Is_Inactive__c` (fullName/label/description/defaultValue/type, kein length).
- Text-Formel: `Lead.Data_Quality__c` (externalId=false, required=false, unique=false, KEIN length, KEIN formulaTreatBlanksAs).
  - MEIN Feld referenziert einen Lookup (Account.Wartungsvertrag__c) → `formulaTreatBlanksAs=BlankAsZero` BEIHALTEN (bei Cross-Object wird es erwartet; Data_Quality hat keinen Lookup). Im Dry-run verifizieren.
- Case-Layout Read-only-Sektion: SCRUM-424 "Erste Reaktion" (customLabel=true, detailHeading, OneColumn) — vor "System Information" eingefuegt.
- Account-Layout Default+Support: Feld in "Account Information" mit behavior=Edit (Bearbeitbarkeit läuft ueber FLS, nicht ueber Layout-behavior).
- Layout-Manifest-Member: exakt die layout-Labels inkl. `%28Support%29` (House: fix-rypplepost-account-layouts.xml).

## Deploy-Plan (CLI 2.139.6, help verifiziert)
- `sf project deploy start -m <typ:name>... -o Test-Org -l NoTestRun` (NoTestRun existiert hier, im Gegensatz zu meiner alten Notiz ueber validate).
- Reihenfolge: 1) CustomFields (Account + Case) → 2) PermissionSets → 3) Report → 4) Layouts. (Report-Filter referenziert das Account-Feld; Layouts referenzieren beide Felder.)
- Danach: PS zuweisen an `devops-agent@cline.test` UND `meerwais.osmani@resourceful-bear-6f1u4j.com`, ein Feld via Session zuruecklesen.
- Apex-Integrationstest (runAs + PS, FLS-negativ-Test nur wenn Profil spaerrt — hier Formelfeld, read-only baubedingt; Coverage >=85% auf neue Klassen).

## Stuetzpunkte
- `sf api request rest /services/data/v67.0/analytics/reportTypes/CaseList` (JSON in cache/scratch/caselist.json)
- `sf org display --json` → apiVersion 67.0
- House-Reports: reports/Service/Ueberfaellige_Faelle.report-meta.xml (CASE_NUMBER, groupingsDown, scope organization)
