# SCRUM-418 Notizen — Developer (verifizierte Befunde)

## Deploy-Stand (Test-Org `devops-agent@cline.test`, Org `00DWU00000oibVJ2AY`)
- **Phase 1 (Felder) DEPLOYED:** `Reactivation_Count__c` (Number 3/0, default 0), `Last_Reactivation__c` (DateTime). Verifiziert per `sf sobject describe -s Case` + SOQL-Read beider Felder.
- **Phase 2 DEPLOYED:** Trigger `CaseReactionTrigger` + `CaseReactionHandler` + PS `SCRUM418_Reactivation` + Layout „Überwachung“ + beide Test-Klassen.
- **Report DEPLOYED:** `Service/Wiedereroeffnungen_3Monate` = `00OWU00000QSeUz2AL` (Deploy Job `0AfWU00000bXwG10AK` Succeeded).
- **PS ZUWEISEN (notwendig!):** 0PS-Exists `0PSWU00000WIZPt4AP`, per `sf org assign permset` an `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com` vergeben. **Vor handoff war sie an NIEMANDEN vergeben** → FLS-Wall: describe/SOQL zeigen Felder erst NACH Assignment.
- **Tests:** `SCRUM418CaseReactionTest` + `SCRUM418CaseReactionFlsTest` = beide **Passed** (früherer Lauf: 8/8, 100 % Coverage der neuen Klassen).

## CLI-Default = Test-Org (korrigiert)
- `sf config list`: `target-org = Test-Org`. Frühere Befürchtung „Default=PROD“ war STALE. Alle Deploy/Reads ohne `-o` gingen in die Test-Org. Trotzdem: Reads mit explizitem `-o devops-agent@cline.test` für Klarheit.

## Apex-Fixes (in `CaseReactionHandler.cls`, seit 0533ed4)
1. **Custom Number = `Decimal`** (nicht `Integer`) in Apex. `stored.intValue()`-Kaskade entfernt.
2. **`Trigger.new[i]` ist in `after update` DML-read-only** → frische `Case`-Instanz (Id + neue Werte) bauen und die updaten. Vorher: „Record is read-only“.

## Test-Fixes (`SCRUM418CaseReactionTest.cls`)
- AK4: NICHT `== System.now()` (now wandert); stattdessen `!= null` + Zeitfenster `>= start - 120s && <= now`.
- bulk200: **KEIN Einzel-Read-Loop** (200× `read(id)` = 200 SOQLs > Governor Limit). Stattdessen 1× `readAll(ids)` per SOQL-Map, Setup + Verifikation je 1 Query.

## Report-Form (ADR-5 — per Dry-Run + Org-Metadata VERIFIZIERT)
Das Design-Report (Zeilen 123–144) war **Platzhalter**; die echte, deploybare Form:
- **`<exqlast90days>` / `<exqlast*>` existiert NICHT** im `FilterOperation`-Enum (org reportType-Metadata: date/datetime haben nur 6 Operatoren `equals/notEqual/lessThan/greaterThan/lessOrEqual/greaterOrEqual`; auch `@salesforce/types` Report-Typ bestätigt — nur 12 Vergleichs-/Contains-Operatoren).
- **`<standardDateFilter>` ist KEIN Report-Element** (SDR: „invalid at this location“). Relatives Fenster = **`<timeFrameFilter>`** mit `<dateColumn>` + `<interval>INTERVAL_LAST90</interval>` (UserDateInterval `INTERVAL_LAST90` vorhanden).
- **Design-OR (Erstellt ODER Reaktiviert in 3 M) NICHT darstellbar**: timeFrameFilter trägt genau 1 dateColumn. Entscheiden für **`Last_Reactivation__c`** (Report = Wiedereeröffnungen der letzten 3 M; neu, nie geöffnet = NULL → fällt korrekt raus). **GAP für Review/PO.**
- Spalten-Token (reportType-Metadata `detailColumnInfo`): `ACCOUNT.NAME` (nicht `ACCOUNT`!), `SUBJECT`, `CREATED_DATE`, `OWNER`. **`CONTACT` im Base-ReportType `CaseList` NICHT verfügbar** (nur CaseContactRole-ReportType). Design: „Kunde = primär ACCOUNT“.
- **`<reportType>CaseList</reportType>`** (Groß C — Haus-Muster `Ueberfaellige_Faelle`), nicht `caseList`.
- **Grouping-Feld nicht auch in `<columns>`** („can't include groupings in columns list“) → `Case.Reactivation_Count__c` nur in `groupingsDown` (Desc = AK2-Sortierung).
- **`<scope>` Picklist** (Org scopeInfo): `user`(Default)/`organization`/`useronly`/`queue`/`genericteam`/`team`/`scopingRule`. `allusers`/`everything` ungültig → hier `organization` (All cases).
- Report `<description>` ≤ 255 Zeichen.

## Org-Metadaten-Quellen (wiederverwendbar)
- Relative-Fenster-Werte / Spalten-Keys / scope: `sf api request rest /services/data/v67.0/analytics/report-types/CaseList` → `reportTypeMetadata` (`standardDateFilterDurationGroups`, `scopeInfo`) + `reportExtendedMetadata.detailColumnInfo` (Spalten-Keys wie `ACCOUNT.NAME`).
- `FilterOperation`-Enum: ebenda `dataTypeFilterOperatorMap` (Date/DateTime).

## Nicht-Backfill (bewusst)
Bestehende Cases haben `Reactivation_Count__c = null` (Feld ex post, Trigger feuert nur auf künftige DML). AK3 gilt für **neu angelegte** Cases (Zähler 0 / Datum leer) — im Test abgesichert. Kein Rebuilder nötig (im Gegensatz zu SCRUM-416 Rollup).
