# SCRUM-396 — „Betreuungsstufe“-Feld + Bericht „Betreuungslast nach Firma“ · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and report
> column names.** The Jira comments (SCRUM-396) are mangled by Jira's markdown
> converter (double underscores → bold, closing XML tags dropped, `+` eaten —
> confirmed on this project repeatedly). Build the files from THIS doc.
> Do not copy names out of the Jira comment.

## Goal
Ein neuer, systemgerechneter Kontakt-Wert „Betreuungsstufe“ (keine/normal/hoch,
abgeleitet aus der bestehenden Zahl offener Fälle) erscheint auf dem
Kontakt-Layout; ein org-weiter Bericht „Betreuungslast nach Firma“ gruppiert
ALLE Kontakte der Org nach Account (Kontakte ohne Account in eigener Gruppe)
und zeigt je Gruppe Kontakte-Anzahl plus Summe der offenen Fälle.

## Branch
`feature/SCRUM-396-betreuungsstufe` frisch von `master` abziehen.
Geteilter Tree: vor `git add` immer `git status -sb` prüfen und **nur eigene
Pfade explizit** stageen (kein `git add .` / `-A`). Fremde untracked Files
weder commiten noch löschen.

## ADR

### ADR-1: Deklaratives Formelfeld über `Open_Cases_Count__c` — kein Apex, kein Trigger, kein Flow, kein zweites Rollup
„Betreuungsstufe“ ist eine reine 3-Verzweigung über die **bereits existierende**
Zählung `Contact.Open_Cases_Count__c` (Number, Default 0, von
`CaseOpenCountTrigger` gepflegt, SCRUM-365). Es gibt keinen neuen Zustand,
keinen Schreibpfad, keine Abhängigkeit, die nicht bereits existiert:

- **Formelfeld** wird beim Lesen live errechnet und folgt `Open_Cases_Count__c`
  automatisch → AC „aktualisiert sich, wenn sich die Anzahl offener Fälle
  ändert“ ist damit ohne jede zusätzliche Logik erfüllt (gleiche Quelle wie
  die bestehende Zählungs-Logik, wie vom PO gefordert).
- **Kein zweites Rollup über Case**: `Open_Cases_Count__c` ist die gültige
  Zählungsquelle; ein eigenes Case-Rollup würde die Bestandslogik duplizieren
  und direkt gegen den Out-of-Scope-Punkt „keine Änderung an Open_Cases_Count__c
  oder den Triggern“ laufen.
- **Kein Apex/Trigger** (Out-of-Scope verbietet Trigger-Änderungen und es gibt
  keinen Persistierungsbedarf). **Kein Flow** (dokumentiert problematisch für
  Schema-Drift/apiVersion; kein Mehrwert).
- House-Parallele: `Open_Cases_Rating__c` (SCRUM-370) ist dasselbe Muster —
  abgeleitetes Einstufungsfeld über die offene-Fall-Zahl. „Betreuungsstufe“
  ist dessen 3-verteilte Vereinfachung (0 / 1-2 / ≥3).

→ Deklaratives Text-Formelfeld ist die einzig saubere Option; die
Apex-over-Flow-Default-Regel greift nicht, weil hier gar kein Apex nötig ist.
**Formelshape (verified SCRUM-394, commit bc0b57f):** `type=Text` + `formula`
+ `required=false` + `trackTrending=false`, string-returnend — **KEIN
`<length>`** (Text-Formelfeld; deploy wirft sonst ab). Kein precision/scale
(das ist Number-only).

**Formel (Function-Form `AND`/`IF` — kein Infix-AND, Salesforce-Regel):**
```
IF(Open_Cases_Count__c >= 3, "hoch", IF(Open_Cases_Count__c >= 1, "normal", "keine"))
```
`Open_Cases_Count__c` ist Number mit Default 0 → `null`-Zweig nicht nötig,
`ISBLANK` weglassen (Checkbox-Regel, hier inapplicable).

### ADR-2: FLS via Permission Set (Read-only), House-Pattern SCRUM-318/353/394
Read=true, editable=false, `hasActivationRequired=false`, Label+Description im
PS. Profile bleiben unverändert. Betreuungsstufe ist ein read-only Formelfeld
→ `editable=false` ist korrekt und systemerzwungen (User kann es nicht ändern,
PO-Matrix „Edit — nicht erlaubt“). „Alle, die Kontakt lesen, sehen es auch“
= PS in der Org den Kontakt-lesenden Benutzern zuweisen → @devops-agent
Follow-up, blockt nicht. Objekt-Level-Zugreich ersetzt **kein** explizites
fieldPermissions (FLS wird nie von CRUD geerbt).

### ADR-3: Standard-ReportType `ContactList`, `scope=org` — kein Custom Report Type
- **ReportType `ContactList`** („Contacts & Accounts“): Contact als Primär-
  Objekt, Account als Joined Relation. Genau das, was AC2-AC6 braucht — und
  derselbe Mechanismus, mit dem die beiden vorhandenen `reports/Sales/*`
  Reports (`LeadList`/`Offene_Leads_nach_Quelle`) bereits org-weit deployed
  sind. **Kein Custom Report Type nötig** (keine `reporttypes/`).
  - *Verified live (Analytics describe `.../analytics/report-types/ContactList`):*
    sowohl `Open_Cases_Count__c` als auch das neue `Betreuungsstufe__c` stehen
    zur Verfügung (in `reportTypeMetadata.objects[]`, Contact-Objekt).
    `scopeInfo` trägt `organization` = „All accounts“; der Deploy-Tag
    `<scope>org</scope>` (LeadReport-House-Tag) liefert die org-weite Sicht.
- **AC3 (alle Kontakte der Org):** `<scope>org</scope>` — org-wide, nicht auf
  den aktuellen User beschränkt (gleicher Tag wie `Offene_Leads_nach_Quelle`
  für „alle offenen Leads der Org“, AC3 dort).
- **AC4 (Kontakte ohne Account, eigene Gruppe):** Primärkontakt + gejoined
  Account → Kontakt ohne Account liefert `null` in der Account-Gruppierung
  → erscheint automatisch in der leeren/„Keine Firma“-Gruppierung, nicht
  weggelassen. **⚠️ Deploy-Checkpoint:** nach Live-Deploy per
  `record-ui`/Bericht öffnen prüfen, dass die null-Gruppe sichtbar ist
  (Join-Typ des Standard-CR; fällt sie aus, Fallback = Custom Report Type —
  ADR-3b, blockt die Implementierung NICHT).
- **AC5 (Summe offener Fälle je Gruppe):** `Open_Cases_Count__c` als
  numerische Report-Spalte ist als **Aggregate (Sum)** wählbar → im Report
  als „Sum“ je Gruppierung. (Haus-Reports zeigen bisher nur Record Count;
  dies ist der erste Sum-Aggregate in dem Ordner — deploy-verify im
  Checkpoint.)
- **Ordner:** `force-app/main/default/reports/Sales/` = der vorhandene
  „Sales“-Ordner (die zwei dortigen Reports sind dort in der Org). Kein neuer
  Ordner (AC2). Report-level Sharing: Zugriff erbt der Ordner; die beiden
  Bestandsreports sind dort sichtbar → neuer Report ebenfalls. `scope=org`
  regelt die DATENBREITE (alle Kontakte), keine ordnerseitige Sharing-Regel
  nötig. (Verifizierung, dass der Serviceleiter den Ordner sieht, = @tester.)

## Komponenten (exakte Dateien)

### 1. Formelfeld `Betreuungsstufe` auf Contact
`force-app/main/default/objects/Contact/fields/Betreuungsstufe__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Betreuungsstufe__c</fullName>
    <description>Abgeleitete Betreuungseinstufung aus der Anzahl offener Faelle (SCRUM-396): 0 = keine, 1-2 = normal, 3 oder mehr = hoch. Quelle: Open_Cases_Count__c (CaseOpenCountTrigger, SCRUM-365); systemgerechnet, von Hand nicht aenderbar.</description>
    <externalId>false</externalId>
    <formula>IF(Open_Cases_Count__c &gt;= 3, &quot;hoch&quot;, IF(Open_Cases_Count__c &gt;= 1, &quot;normal&quot;, &quot;keine&quot;))</formula>
    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
    <label>Betreuungsstufe</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Text</type>
</CustomField>
```
- `Open_Cases_Count__c` verweist korrekt auf das **Contact-eigene** Feld
  (eigene Objektfelder: ohne Präfix im Formel-Editor; XML-Quelle zeigt
  `Open_Cases_Count__c` in `Open_Cases_Rating__c`/Bewertungsformeln).
- **KEIN `<length>`** (Text-Formelfeld — see ADR-1). XML: `>=` als `&gt;=`,
  String-Literal als `&quot;`.

### 2. Layout-Integration
`force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`
Im bestehenden Abschnitt **„Offene Faelle“** (der schon
`Open_Cases_Count__c` + `Open_Cases_Rating__c` trägt) als drittes Readonly-
Element einhängen — neue `<layoutColumns>` in dem TwoColumns-Section:

```xml
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Betreuungsstufe__c</field>
            </layoutItems>
```
Einfügeort: innerhalb `<label>Offene Faelle</label>`→`<layoutSections>`,
als zweite `<layoutColumns>` oder Anhang der bestehenden — neben
`Open_Cases_Rating__c` logisch. Genau eine `layoutItems`-Stelle.

### 3. Permission Set (Read-FLS)
`force-app/main/default/permissionsets/SCRUM396_Betreuungsstufe.permissionset-meta.xml`
(Shape 1:1 zu `SCRUM394_LeadDataQuality`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Contact.Betreuungsstufe__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM396_Betreuungsstufe</label>
    <description>Read-FLS für Contact "Betreuungsstufe" (SCRUM-396). Systemgerechnetes Formelfeld (read-only); kein Write-PS, keine Apex/DML.</description>
</PermissionSet>
```
Zuweisung an die Kontakt-lesenden Benutzer in der Org = @devops-agent
Follow-up (blockt nicht).

### 4. Bericht „Betreuungslast nach Firma“
`force-app/main/default/reports/Sales/Betreuungslast_nach_Firma.report-meta.xml`
(Structur-Shape 1:1 zu `Offene_Leads_nach_Quelle.report-meta.xml`,
`reportType=ContactList`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns><field>LAST_NAME</field></columns>
    <columns><field>FIRST_NAME</field></columns>
    <columns><field>NAME</field></columns>
    <columns><field>COMPANY</field></columns>
    <columns><field>Contact.Betreuungsstufe__c</field></columns>
    <columns><field>Open_Cases_Count__c</field></columns>
    <columns><field>OWNER</field></columns>
    <format>Summary</format>
    <groupingsDown>
        <field>COMPANY</field>
        <sortOrder>Asc</sortOrder>
    </groupingsDown>
    <name>Betreuungslast_nach_Firma</name>
    <description>Betreuungslast je Firma: ALLE Kontakte der Organisation (scope org, AC3), primär gruppiert nach Account (Firma); Kontakte ohne Account in null-/&quot;Keine Firma&quot;-Gruppe, nicht weggelassen (AC4). Zeigt Kontakte-Anzahl (Record Count) UND Summe offener Faelle je Gruppe (AC5); Detail: Name, Firma, Betreuungsstufe, offene Faelle, Inhaber (AC6).</description>
    <reportType>ContactList</reportType>
    <scope>org</scope>
    <showDetails>true</showDetails>
    <showGrandTotal>true</showGrandTotal>
    <showSubTotals>true</showSubTotals>
</Report>
```
Spalten-Mapping (AC6) → ReportTyp-`ContactList`-Spaltentoken:
- Name → `NAME` (Contact-Vollname)
- Firma → `COMPANY` (gejointer Account)
- Betreuungsstufe → `Contact.Betreuungsstufe__c`
- Anzahl offener Fälle → `Open_Cases_Count__c`
- Inhaber → `OWNER` (Contact-Owner)
- **Summe offene Fälle je Gruppe:** `Open_Cases_Count__c` zusätzlich als
  **Aggregate „Sum“** je Gruppierung setzen (im Report-UI auf „Sum“ umstellen;
  Record Count kommt von der Grouping automatisch für AC5/Kontakte-Anzahl).
  ⚠️ *Deploy-Checkpoint:* exakte Spaltentoken (`NAME`/`COMPANY`/`OWNER` vs.
  `ACCOUNT.NAME`) und die Sum-Aggregate-Einstellung nach Live-Deploy per
  Report-Erzeugnis verifizieren — die Tokens stammen aus dem ContactList-Desc
  (House-Reports nutzen die Kurzform, z. B. `LEAD_SOURCE`/`COMPANY`/`OWNER` in
  LeadList). Weicht ein Token ab, Report re-retrieve und exakt übernehmen.

⚠️ **Repo-Abdeckung:** Repo trackt Classic `.report-meta.xml`; der Bericht
selbst ist source-deploybar (`reportType` + `scope` + `groupingsDown` sind
Source-Elemente, verified SCRUM-394). Report-level „All users“-Sharing ist
org-seitig (Ordner), aber der „Sales“-Ordner zeigt die Bestandsreports
bereits org-weit → kein zusätzlicher Schritt erwartet. FLEXI/Lightning-Sicht
des Feldes = FLS (repo) + App-Builder-Placement (Org, @devops) — Classic-
Layout im Repo deckt AC1 (Standard-Kontakt-Layout) ab.

## Governor Limits / Bulk
- Formelfeld: read-time berechnung, kein Governor-Limit-Risiko, keine DML,
  kein Trigger. Report: Plattform-seitige Aggregation, kein eigener Code.
  → **Kein Risiko, keine Bulk-Sorge.**

## Definition of Done / Technische AC
- [ ] Feld deployed, `type=Text` ohne `<length>` (deploy validiert Formel).
- [ ] Feld zeigt „keine“/„normal“/„hoch“ korrekt je Anzahl offener Fälle
      (Read-back je Kontext: 0 / 1-2 / ≥3 offene Fälle) — E2E, nicht nur
      „deployed“.
- [ ] Feld auf dem Standard-Kontakt-Layout (Sektion „Offene Faelle“).
- [ ] PS Read-FLS deployed; Feld via record-ui sichtbar, nicht editierbar.
- [ ] Report im Ordner Sales, `reportType=ContactList`, `scope=org`.
- [ ] Report zeigt ALLE Kontakte der Org (auch fremde) → Scope-Verify.
- [ ] Primäre Gruppierung nach Firma; Kontakte ohne Firma in eigener
      (null-)Gruppe, nicht weggelassen → AC4-Verify.
- [ ] Je Gruppe: Record Count (Kontakte) UND Sum offene Fälle → AC5-Verify.
- [ ] Detailspalten: Name, Firma, Betreuungsstufe, offene Fälle, Inhaber.
- [ ] **Tests (PR-Gate, House-Pattern SCRUM382/394):** Apex-Test-Paar
      (House-Value-Fall + FLS-Read-Verify, `v67.0` Manifest,
      Shape `SCRUM382*Test`/`*FlsTest`) + E2E-Spec für die Report-ACs
      (Shape `SCRUM-378_*.spec.ts`). „Deployed + einmal im Bericht 62/62
      gesehen“ ist EVIDENZ, kein Test → PR ohne Automatisierung ablehnen.
- [ ] Keine Änderung an `Open_Cases_Count__c` oder den Triggern (Out-of-Scope).
- [ ] Shared-Tree-Regel: nur eigene Pfade stageed, `git status -sb`/
      `git diff --cached --name-only` vorCommit.

## Offene Punkte (blocken die Implementierung NICHT)
- [ ] ⚠️ Fallback, falls der null/„Keine Firma“-Gruppenfall im
      Standard-`ContactList`-CR ausfällt (Join-Typ): Custom Report Type
      anlegen + `reporttypes/` im Repo. Owner: @developer-agent (erst nach
      dem Deploy-Checkpoint).
- [ ] Report-Spaltentoken + Sum-Aggregate exakt nach Live-Deploy
      verifizieren. Owner: @developer-agent (Deploy) / @tester-agent (Sicht).
- [ ] PS-Zuweisung an die Kontakt-lesenden Benutzer in der Org (Org-Schritt).
      Owner: @devops-agent.
- [ ] Lightning-FlexiPage-Placement des Feldes (Org/App Builder), falls der
      Serviceleiter über Lightning zugreift. Owner: @devops-agent.
