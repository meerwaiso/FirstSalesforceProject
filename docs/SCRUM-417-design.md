# SCRUM-417 — Monatlicher Verlauf der offenen Chancen je Kunde (Architektur & Build-Spec)

Surveys-Commit: `57ee70f` (origin/master, 2026-09-15). Basiert auf SCRUM-416 (Release-
Tag `archiv/release-SCRUM-416-offene-chancen`), dessen Muster (2 systemmaintained
Account-Felder, `IsClosed = false` als Single Source of Truth, Report `AccountList`
mit `<scope>organization</scope>`, House-PS pro Ticket) wird 1:1 weiterverwendet.

## Ziel

Je Kunde je Monatsende (Januar 2026 bis heuriger Monat, nachts vollrecomputiert):
Anzahl offener Chancen + Summe der offenen Beträge als Related List, Vergleichs-
Report für 2–3 Kunden und Einbruch-Report — alles vollautomatisch, backfillt sich
selbst bei der ersten Lauf.

## Datenmodell

### Neues Custom Object `OpenOpportunityHistory__c` (Label: „Offener Chancen-Verlauf“)

`force-app/main/default/objects/OpenOpportunityHistory__c/`

| Feld | Typ | Bedeutung |
|---|---|---|
| `AccountId` | MasterDetail → Account, required | Erbt die Account-Sichtbarkeit (Standard MD-Verhalten → **keine Sharing Rules nötig**) |
| `Snapshot_Month__c` | Text(7), required | ISO `yyyy-MM` (z. B. `2026-01`). Text statt Date: sortierbar, deterministic, kein Locale-Risiko bei UNIQUE-Formula. |
| `Open_Count__c` | Number(8,0) | Anzahl offener Chancen auf Monatsende M (0 erlaubt) |
| `Open_Value__c` | Currency(18,2) | Summe der aktuellen Amounts offener Chancen auf Monatsende M (0 erlaubt) |
| `History_Key__c` | Text, Formula, **Unique** | `TEXT(AccountId) & '-' & Snapshot_Month__c` → sauberes Upsert-Key, garantiert max. 1 Zeile je (Kunde, Monat) |

Feld-XML-Form (House-Pattern `Open_Opportunity_Count__c` / `SCRUM-394`):
`Snapshot_Month__c` = `type=Text` + `<length>7</length>` + required=true;
`History_Key__c` = `type=Text` + `<formula>TEXT(AccountId) &amp; '-' &amp;
Snapshot_Month__c</formula>` + `<unique>true</unique>` + `required=false` +
`trackTrending=false` — und **kein `<length>`-Element**: Text-Formula-Felder
nehmen kein `<length>` (deploy-verifiziert SCRUM-394, `Lead.Data_Quality__c`);
Deploy lehnt es ab. Developer: exakt diese Form, Phase-1-Deploy validiert.

**Warum Custom Object statt Formula/Report-tricks:** Related List + Report +
monatsweise Zeilengranularität + systemseitige Pflege verlangen eine persistente
Ergebnistabelle. Formelfelder auf Account können nicht pro Monat aggregieren.

### Neues Account-Feld `Account.Open_Value_Drop_Last_Month__c`

`force-app/main/default/objects/Account/fields/Open_Value_Drop_Last_Month__c.field-meta.xml`

- Currency(18,2), systemmaintained (read-only in Layout, `editable=false` im PS)
- Semantik: `OffenWert(aktueller Monat, Stand letzte Nacht) − OffenWert(Monat davor)`
  — negativ = Einbruch; `null` in Januar 2026 (kein Vormonat)
- Dient als Filter-/Sortier-Spalte des Einbruch-Reports (Standard-Report
  `AccountList` — **kein Custom Report Type für den Einbruch nötig**)
- Kein zweites Count-Feld: PO definiert den Einbruch über den **Betrag**

Warum auf Account statt im Child: Der Einbruch-Report bleibt ein Standard-Report
auf Account (house: `Offene_Werte_nach_Kunde`), ohne Custom Report Type und ohne
Cross-Row-Vergleich im Report. Cross-Row-Vergleiche sind in Report-XML nicht
darstellbar (keine Report-Formula in Customizable Report Types) → Value muss
systemseitig pro Account abgelegt werden.

## Zähl-Definition (Single Source of Truth, konsistent mit SCRUM-416)

„Offen“ = `IsClosed = false` (Stage-Namen bleiben aus der Logik heraus, ADR-3 aus
SCRUM-416). Chance O zählt in Monat M bei Kontext C, wenn:

- `CreatedDate ≤ Monatsende M`, **und**
- bei `M` < aktuellem Monat: `IsClosed = false` **oder** (`IsClosed = true`
  und (`ClosedDate > Monatsende M` **oder** `ClosedDate = null`))
  → war Ende M noch offen (schloss erst danach)
- bei `M` = aktueller Monat (Stand der Nacht): `IsClosed = false`
  → exakt die Menge des SCRUM-416-Live-Feldes (AK4 folgt konstruktiv)

- `Amount` = **aktueller** `Amount` (PO-Vereinfachung: keine historische
  Rekonstruktion). Konsequenz, dokumentiert: Umwertungen heilen frühere
  Monatszeilen mit — bewusst so.
- Kunde ohne offene Chancen in M → Zeile mit 0/0 (nicht leer).
- Zeilen-Menge: alle Kontexte aus der M-Querschnitt-Query + alle Kontexte mit
  bestehenden Zeilen aus früheren Monaten (Kontinuität: ein Kunde, der seine
  Chancen kassiert, behält 0/0-Zeilen → Einbruch wird sichtbar).
- Kontexte ohne Chance seit Jahresanfang und ohne Bestand: keine Zeilen
  (Liste bleibt überschaubar).

## Komponenten

1. **`OpenOpportunityHistoryRebuilder.cls`** — `public class` (kein Batchable),
   `public static void run()` = idempotenter Vollrecompute:
   - 1 Aggregate-SOQL je Monat M in [Jan-2026, heute] (9 Queries bei 9 Monaten):
     `SELECT AccountId, COUNT(Id), SUM(Amount) FROM Opportunity
       WHERE AccountId != null AND CreatedDate <= :endeM AND <Zähl-Predicate (M)>
       GROUP BY AccountId`
   - + 1 SELECT bestehender Zeilen (`AccountId FROM OpenOpportunityHistory__c`)
     → Union der Kontexte; fehlende Monate je Kontext = 0/0-Zeile
   - DML in Chunks à 2000 (`Upsert` auf `History_Key__c`), danach
     `Account.Open_Value_Drop_Last_Month__c` setzen (Chunk-DML)
   - Governor: SOQL nie im Record-Loop; ≤ 10 Queries + 1 Upsert-Batch pro Lauf
   - **Backfill = erster Produktionslauf** (gleicher Code-Pfad: alle Monate seit
     Jahresanfang werden immer vollrecomputiert — es gibt keinen Separaten
     Backfill-Job, kein No-Code-Button, PO will nichts anstoßen)
   - `without sharing` (System-Schreiben; FLS nur bei DML des Lauf-Users relevant,
     ADR-6)
2. **`OpenOpportunityHistoryScheduler.cls`** — `Schedulable`, startet nur
   `OpenOpportunityHistoryRebuilder.run()` (House-Pattern
   `AccountReactivationScheduler`, SCRUM-388).
   - CRON-Vorschlag: `0 0 3 * * ?` (3 Uhr nachts; 2 Uhr = SCRUM-388,
     6 Uhr = SCRUM-319/414 Overdue → 3 Uhr frei; @devops-agent prüft Kollision
     in der Org)
   - ⚠️ **Org-Schritt:** `System.schedule('SCRUM-417 Offene Chancen Verlauf',
     '0 0 3 * * ?', new OpenOpportunityHistoryScheduler())` — Scheduled Jobs sind
     Laufzeit-Objekte, **kein** Deploy-Metadatum (House-Befund SCRUM-388).
3. **Permission Set `SCRUM417_OpenOpportunityHistory`** —
   `force-app/main/default/permissionsets/SCRUM417_OpenOpportunityHistory.permissionset-meta.xml`
   - `objectPermissions`: `OpenOpportunityHistory__c` ViewOnly (kein Create/Edit/
     Delete — „kein UI-Write“), keine Objekt-Power auf Account
   - `fieldPermissions` (alle mit `editable=false`):
     - `OpenOpportunityHistory__c.Snapshot_Month__c`
     - `OpenOpportunityHistory__c.Open_Count__c`
     - `OpenOpportunityHistory__c.Open_Value__c`
     - `Account.Open_Value_Drop_Last_Month__c`
   - House-Pattern `SCRUM416_OpenOpportunities` (eins pro Ticket, Read-only)
   - FLS: Read-FLS explizit je Feld (nie von Objekt-CRUD geerbt); `History_Key__c`
     ist Formula → kein `fieldPermissions`-Eintrag nötig
   - **Kein Write-PS** im Repo, solange der Lauf-User ein System-Admin ist
     (Admin-DML umgeht FLS). Falls @devops-agent in der Org einen Nicht-Admin
     als Lauf-User bestimmt: zweites PS `SCRUM417_...Write` nach
     `SCRUM388_AccountReactivationWrite` ergänzen (offener Punkt, blockiert nicht)
   - PO verteilt das PS auf die Profile (Vertrieb, Key Account, Admin) wie bei
     SCRUM-416 — in Beschreibung des PS notieren
4. **Layout-Integration (Classic):** Related List `OpenOpportunityHistory__c`
   + Readonly-Item `Open_Value_Drop_Last_Month__c` (in die SCRUM-416-Sektion)
   in `Account-Account Layout` + `Account-Account (Sales) Layout` — genau die
   beiden Layouts, die die 416er Felder tragen (Marketing/Support Layouts
   tragen sie nicht, werden nicht angefasst).
   - ⚠️ **Lightning:** Die Account-FlexiPage liegt in der Org (keine FlexiPage
     für Account im Repo) → Related List + Drop-Feld dort via App Builder
     platzieren = Org-Schritt @devops-agent (House-Befund „Auf allen Layouts“)
5. **Report `Offene_Werte_Verlauf`** —
   `force-app/main/default/reports/Sales/Offene_Werte_Verlauf.report-meta.xml`
   - Basis: **Custom Report Type** `SCRUM417_OpportunityHistory`
     (`reporttypes/SCRUM417_OpportunityHistory.reportType-meta.xml`,
     `baseObject=OpenOpportunityHistory__c`, House-Pattern
     `SCRUM396_Betreuungslast`) mit Sektionen: Zeilen-Felder (Count, Value,
     `Snapshot_Month__c`) + `Account.Name`
   - Format `Summary`, `groupingsDown` (flach!): `Account.Name` +
     `OpenOpportunityHistory__c.Snapshot_Month__c`, Sort Asc →
     **eine Zeile je Kunde je Monat** (Tabelle/Kurvenpunkt-Basis, AK1/AK2)
   - Spalten: `Open_Count__c`, `Open_Value__c` (Sum), <scope>organization</scope>
   - AK2 (2–3 Kunden): interaktiver Report-Filter auf `Account.Name` in der
     UI — kein extra Artefakt; Kurven statt Tabelle = Chart im Report (UI-Klick,
     kostenlos, kein Scope-Delta)
6. **Report `Groesste_Einbrueche`** —
   `force-app/main/default/reports/Sales/Groesste_Einbrueche.report-meta.xml`
   - Standard `AccountList`-Report Type (keiner Custom!), Spalten
     `ACCOUNT.NAME`, `Account.Open_Opportunity_Value__c`,
     `Account.Open_Value_Drop_Last_Month__c`
   - Filter `Account.Open_Value_Drop_Last_Month__c < 0` (Report-Filter im XML),
     `sortColumn` = Drop-Spalte, `sortOrder` `Asc` (stärkster Einbruch ob
     en = tiefster Negativwert zuerst), <scope>organization</scope>
   - AK5: „Top 5“ = die obersten fünf Zeilen (alle Kontexte mit Rückgang sind
     gelistet; exakt 5 Zeilen sind im Standard-Report nicht ausdrückbar —
     dokumentierte Vereinfachung, vgl. ADR-7)
7. **Apex Tests** (PR-Gate, House-Pattern `SCRUM416_*Test`):
   - `SCRUM417OpenOpportunityHistoryTest` — Zähl-Definition, 0/0-Zeilen,
     Idempotenz (2× `run()` → gleiche Werte, keine Duplikate), Drop-Feld
     (inkl. `null` im Januar), AK4-Konsistenz (letzte Zeile ==
     `Account.Open_Opportunity_Count__c` / `Open_Opportunity_Value__c`),
     Alt-Chance (angelegt 2025, geschlossen Feb-2026 → zählt in Januar,
     nicht in Februar)
   - `SCRUM417OpenOpportunityHistoryFlsTest` — House-FLS-Pattern
     (`SCRUM416OpenOpportunityFlsTest`): Ohne PS kein Read; mit PS Read ja,
     Write nein
8. **Manifests** (House-Pattern `manifest/scrNNN-phase*.xml`, Version 67.0):
   - `manifest/scr417-phase1-fields.xml`: `CustomObject OpenOpportunityHistory__c`,
     `CustomField` (4 Felder des Objects + `Account.Open_Value_Drop_Last_Month__c`)
   - `manifest/scr417-phase2-referencing.xml`: `ApexClass` (2),
     `PermissionSet`, `CustomReportType`, `Report` (2), `Layout` (2)

## Architektur-Entscheidungen

1. **Apex Scheduled Job statt Flow/Trigger.** Monatliche Snapshots sind
   Zeitpunktbasierte Vollrecomputes — weder ein Ereignis (kein Trigger
   semantisch passend: eine Schließung Mitte Februar muss Dezember, Januar
   und Februar gleichzeitig korrekt neu bewerten) noch ein Flow (House-Regel:
   Apex bei nicht-trivialer Logik; Flow hat hier wiederholt deploy-/Schema-
   Probleme gemacht). Vollrecompute statt Delta = driftfrei, idempotent,
   heilt jede manuelle Reparatur selbst (House-Pattern SCRUM-367/388/416).
2. **Custom Object als Ergebnis-Speicher** statt Formelfeld/Report-on-Fly:
   Related Lists, Reports und Einbruch-Filter brauchen zeilenweise,
   persistente Daten; Formelfelder auf Account können nicht pro Monat
   aggregieren. MD auf Account → Sharing erbt die Account-Sichtbarkeit
   (PO: „erben die Sichtbarkeit“, keine Sharing Rules).
3. **Text(7) `yyyy-MM` statt Date** für den Monat: deterministisches Sortieren,
   sichere Text-Unique-Key-Formula ohne Locale-Risiko; `unique`-Formula
   = erzwingen der 1:1-(Kunde, Monat)-Garantie direkt in der DB (Upsert
   wird dadurch kollisionsfrei).
4. **Einbruchwert auf Account (`Open_Value_Drop_Last_Month__c`)** statt
   Cross-Row-Report-Logik: Customizable Report Types haben keine Report-
   Formula → „letzter Monat vs. Vorgänger“ muss systemseitig abgelegt sein.
   Einbruch-Report bleibt dadurch Standard `AccountList` (weniger Artefakte,
   House-Pattern 416).
5. **Backfill ohne separaten Job:** `run()` recompute immer alle Monate seit
   Jahresanfang → der erste Produktionslauf backfillt automatisch (PO:
   „Rückblick seit Jahresanfang“, „nichts anstoßen“).
6. **FLS via Permission Set, kein Profil-Edit** (House-Regel, SCRUM-314/327/
   329/416); System-Write ohne UI-Write: nur Read-PS breit, Write nur für
   Lauf-User (nur nötig, wenn Lauf-User kein Admin ist — Org-Check @devops).
7. **Vollautomatik via 24-nächtlichem Scheduled Job** statt Trigger + Job:
   ≤ 24 h garantiert; eine einzige Ausführung pro Nacht → kein
   Governor-Druck während Arbeitszeit, kein Doppel-Lauf bei Massenevents.
8. **Governor-Limits:** 1 Aggregate-SOQL je Monat (200k-Zeilen-Limit der
   Aggregat-Query als bekannte Grenze — Org-Volumen laut SCRUM-416-Baseline
   weit darunter; @devops-agent verifiziert vor dem ersten Lauf über
   `SELECT COUNT(Id) FROM Opportunity`, bei > 150k: Kontext-chunkweise
   Query statt Monats-Query), DML in 2000er-Chunks, kein SOQL im Record-Loop.

## ⚠️ Befunde / Org-Schritte (blocken die Implementierung NICHT)

1. **System.schedule muss in der Org gesetzt werden** (CRON `0 0 3 * * ?`,
   Kollisions-Check) → @devops-agent
2. **Lightning-FlexiPage** (Account) erhält Related List + Drop-Feld per
   App Builder; Classic-Layouts 2× im Repo → @devops-agent
3. **Lauf-User:** Admin? Falls nein → zweites Write-PS ergänzen → @devops-agent
4. **Data Volume-Check** (Opportunity-Zeilen < 200k/Aggregat-Query) →
   @devops-agent (eine Zähl-Query vor dem ersten Lauf)

## Offene Punkte (nicht blockierend)

- [ ] „Top 5“ exakt 5 Zeilen vs. „alle mit Rückgang, Top 5 ob en“ → PO-
      Bestätigung (Empfehlung: wie implementiert — mehr Information, kein Aufwand)
- [ ] Lauf-User + CRON-Slot → @devops-agent
- [ ] PS-Verteilung auf Ziel-Profile → PO/@devops-agent (wie bei SCRUM-416)

## Technische Akzeptanzkriterien (zusätzlich zu AK1–AK5)

- TA1: `run()` erzeugt je Kontext mit Aktivität seit Jahresanfang je Monat
      Jan→heute exakt eine Zeile (Unique-Key hält); 0/0-Zeilen wo keine offenen
      Chancen
- TA2: Idempotenz — zweiter Lauf ändert Werte von Monaten mit stabilen
      Ausgangsdaten nicht, erzeugt keine Duplikate
- TA3: `Account.Open_Value_Drop_Last_Month__c` = Wert(akt. Monat) −
      Wert(Monat davor); `null` im Januar 2026
- TA4: AK4-Konsistenz — letzte Verlaufs-Zeile == SCRUM-416-Live-Felder
      (gleiche Chancengemenge, gleicher `Amount`-Standard)
- TA5: FLS — ohne PS: kein Read; mit PS: Read ja, UI-Create/Edit/Delete nein
- TA6: Report `Groesste_Einbrueche` enthält exakt die Kontexte mit
      Drop < 0, absteigend sortiert nach Drop-Größe
- TA7: Deploy in zwei Phasen (Fields → referencing Artefakte) validiert —
      `sf project deploy validate` grün für beide Manifests
