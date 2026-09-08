# SCRUM-396 — „Betreuungsstufe“-Feld + Bericht „Betreuungslast nach Firma“ · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and report
> column names.** The Jira comments (SCRUM-396) are mangled by Jira's markdown
> converter (double underscores → bold, closing XML tags dropped, `+` eaten —
> confirmed on this project repeatedly). Build the files from THIS doc.
> Do not copy names out of the Jira comment.

> **Version 2.1 — 7.9. 17:10 (CORRIGENDUM II).** v2.0 (7.9. 14:20,
> Commit 84bb35d) korrigiert v1.0 (b93a2e0); v2.1 korrigiert v2.0. ADR-3 wird
> ersetzt: `<join outerJoin=true relationship=Account__r>` ist org-seitig
> widerlegt (Server validiert Join-Relationships gegen die **Child-**
> Relationships des Basis-Objekts; Contact hat keine Child-Relationship zu
> Account — Account ist Parent via `AccountId`; vier Token getestet, alle
> `No such relationship`). Ersatz = Lookup-Traversal `Account.Name` im
> Contact-Bereich ohne `<join>` — deployet grün (Probe-CR), AC4 inhärent
> erfüllt (Traversal ≠ Inner Join). Änderungen: ADR-3 + Komponente 4a
> ersetzt; 4b-Spalten-Mapping (Gruppierungstoken) ergänzt. Komponenten 1–3
> und 4b-Struktur unverändert gültig. Der Developer baut ab sofort von v2.1 —
> die Report-Dateien aus v1.0 (ContactList) und v2.0 (`<join>`-CR) sind
> **defekt** und werden ersetzt, nicht geflickt.

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
weder commiten noch löschen (Stand 7.9.: `.cline-roles/`, `Test-Org/`,
`docs/SCRUM-388-design.md`, `manifest/scr390-release-combined.xml`,
`manifest/scr394-release.xml`, `scr378-report-final.zip` — alle nicht von
SCRUM-397; unangetastet benennen, nicht löschen).

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
  und direkt gegen den Out-of-Scope-Punkt „keine Änderung an
  Open_Cases_Count__c oder den Triggern“ laufen.
- **Kein Apex/Trigger** (Out-of-Scope verbietet Trigger-Änderungen und es gibt
  keinen Persistierungsbedarf). **Kein Flow** (dokumentiert problematisch für
  Schema-Drift/apiVersion; kein Mehrwert).
- House-Parallele: `Open_Cases_Rating__c` (SCRUM-370) ist dasselbe Muster —
  abgeleitetes Einstufungsfeld über die offene-Fall-Zahl. „Betreungsstufe“
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
→ `editable=false` ist korrekt und systemerzwungen. „Alle, die Kontakt lesen,
sehen es auch“ = PS in der Org den Kontakt-lesenden Benutzern zuweisen →
@devops-agent Follow-up, blockt nicht. Objekt-Level-Zugreich ersetzt **kein**
explizites fieldPermissions (FLS wird nie von CRUD geerbt).

### ADR-3 (v2.1): Custom Report Type OHNE `<join>` + Lookup-Traversal `Account.Name` — ContactList trägt die ACs NICHT, v2.0-Join-Mechanismus existiert NICHT

**Warum v1.0 (Standard-ReportType) falsch war — drei Verifikationen (unverändert zu v2.0):**

1. **AC4 (und damit AC3) untragbar mit `ContactList`.** Der Analytics describe
   der Test-Org (7.9., `reportTypeMetadata`) trägt `hasOuterJoin: false` →
   der gejointe Account ist ein **INNER JOIN** → Kontakte ohne Account fallen
   aus dem Bericht heraus, statt eine null-Gruppe zu bilden. Das ist in dieser
   Org **der Regelfall, nicht der Edge-Case**: SOQL an der Test-Org (7.9.):
   `SELECT COUNT(Id) FROM Contact WHERE AccountId = NULL` → **508** und
   `WHERE AccountId != NULL` → **24** (532 gesamt, 95,7 % ohne Account).
   `ContactList` zeigt also 24 von 532 — AC4 „Kontakte ohne Firma erscheinen
   in einer eigenen Gruppe, nicht weggelassen“ und damit AC3 „alle Kontakte
   der Organisation“ sind verletzt.
2. **`<scope>org</scope>` ist bei ContactList invalid.** Lead-Report-House-Tag
   (`LeadList`) ohne Prüfung übernommen. ContactList-Scope-Picklist:
   `my/user/team/organization/scopingRule`; **`organization` = „All
   accounts“** = org-weit = AC3. (Deploy-Blocker, von @developer-agent gegen
   die Org-API verifiziert.)
3. **Inhaber-Spalte (AC6):** `OWNER_FULL_NAME` = `fqn Contact.Account.Owner.
   Name`, Label „Account Owner“ — das ist der **Account**-Inhaber, nicht der
   Kontakt-Inhaber. Der Kontakt-Inhaber ist das Feld **`Owner` des
   Basis-Objekts (Contact)** (im ContactList-Analytics-Kontext Token
   `CONTACT_OWNER` = Label „Contact Owner“, `fqn Contact.Owner.Name`).
   Beleg: Analytics describe der Test-Org (7.9.). Im Custom-ReportType-XML
   (Basisobjekt Contact) wird der Kontakt-Owner mit `<field>Owner</field>`
   aus der Contact-Sektion referenziert.

**Warum v2.0 (Custom Report Type mit `<join>`) ebenfalls falsch war — org-seitig widerlegt, 7.9. 17:00 (Developer-Deploy-Probe gegen Test-Org):**

4. **`<relationship>` validiert gegen CHILD-Relationships des Basis-Objekts —
   nicht gegen Parent-Lookups.** Der Server akzeptiert als `<relationship>`
   nur **Child-Relationship-Felder** (1-to-many von Basisobjekt zum Joinziel).
   Contact hat **keine** Child-Relationship zu Account — Account ist Contact's
   *Parent* (Access via `Contact.AccountId`). Vier Kandidaten getestet, alle
   abgelehnt: `Account`, `Contacts`, `AccountId`, `Account__r` → jeweils
   `No such relationship X on object Contact`.
   **Beleg, dass der Join-Mechanismus selbst funktioniert:** Probe-CR
   `SCRUM396_Probe_AccountContacts` mit `base=Account` +
   `<relationship>Contacts</relationship>` deployet grün — die inverse
   Richtung ist strukturell ausgeschlossen.

**Entscheidung (v2.1):**
- Custom Report Type `SCRUM396_Betreuungslast` (Basisobjekt **Contact**,
  **ohne `<join>`-Block**). Account-Daten kommen per **Lookup-Traversal**
  `<field>Account.Name</field>` direkt in der Contact-Sektion — derselbe
  Dots-Pfad-Mechanismus, den der offizielle ReportType-Schema für
  `Owner.Email` dokumentiert.
- Lookup-Traversal ist **kein Inner Join** → Kontakte ohne Account fallen NICHT
  raus, sondern liefern einen leeren `Account.Name` → **null-Gruppe entsteht
  inhärent** (AC4 ohne Join-Konfiguration). `hasOuterJoin` ist in diesem CR
  irrelevant (es beschreibt nur das `<join>`-Element, das nicht vorhanden ist).
- Contact-Sektion: vier Felder (`Name`, `Owner`, `Open_Cases_Count__c`,
  `Betreuungsstufe__c`) + `Account.Name` als Traversal; keine zweite
  Sektion.
- Report darauf mit `scope=organization`, Gruppierung über den Traversal-
  Pfad `Contact.Account.Name` (Kandidat 1 fürs Grouping; 2 = `ACCOUNT.NAME`;
  3 = retrieve-geprüftes Lookup-Token — Verify-Loop s. 4b), Sum-Aggregate
  via `<aggregateTypes>Sum</aggregateTypes>` (source-deploybar; Beleg:
  offizielles Report-Metadaten-Schema `ReportColumn.aggregateTypes` +
  `platform-report-generate`-Beispiele).
- **Deploy-Reihenfolge:** erst ReportType, dann Report (sonst "unknown
  reportType" im Schema-Check).
- Probe-CRs (`SCRUM396_Probe_AccountContacts`, `SCRUM396_Probe_NoJoin`) sind
  befristete Artefakte der Verifikation und werden beim finalen Deploy des
  Product-CRs (Manifest `scr396-delete-probes.xml`) gelöscht.

**Ordner/Sharing (AC2):** unchanged zu v1.0 — `force-app/main/default/
reports/Sales/` = vorhandener „Sales“-Ordner; Ordner-sharing wie die beiden
Bestandsreports. `scope=organization` regelt die Datenbreite (alle Kontakte),
keine ordnerseitige Regel. (Verifizierung, dass der Serviceleiter den Ordner
sieht = @tester.)

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
  (eigene Objektfelder: ohne Präfix im Formel-Editor).
- **KEIN `<length>`** (Text-Formelfeld — see ADR-1). XML: `>=` als `&gt;=`,
  String-Literal als `&quot;`.

### 2. Layout-Integration
`force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`
Im bestehenden Abschnitt **„Offene Faelle“** (der schon
`Open_Cases_Count__c` + `Open_Cases_Rating__c` trägt) als drittes Readonly-
Element einhängen — neue `<layoutItems>` in dem TwoColumns-Section:

```xml
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Betreuungsstufe__c</field>
            </layoutItems>
```
Einfügeort: innerhalb `<label>Offene Faelle</label>` → `<layoutSections>`,
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

### 4a. Custom Report Type `SCRUM396_Betreuungslast` (v2.1 — **ohne `<join>`**, Lookup-Traversal)
`force-app/main/default/reporttypes/SCRUM396_Betreuungslast.reportType-meta.xml`
(Ersatz für die v2.0-`<join>`-Variante, die der Server verwirft — s. ADR-3 #4.
Die Probe `SCRUM396_Probe_NoJoin` hat diesen no-join-Traversal-Shape gegen die
Test-Org deployet: grün. `Account.Name` im Contact-Bereich = derselbe
Dotted-Path-Basis wie `Owner.Email` im offiziellen Schema.)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ReportType xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>SCRUM396_Betreuungslast</fullName>
    <label>Betreuungslast nach Firma</label>
    <description>SCRUM-396: ALLE Kontakte der Org (inkl. ohne Account — Lookup-Traversal, AC3/AC4) mit Betreuungsstufe und offenen Faelle; Gruppierung nach Account.</description>
    <deployed>true</deployed>
    <category>other</category>
    <baseObject>Contact</baseObject>
    <sections>
        <columns>
            <checkedByDefault>true</checkedByDefault>
            <field>Name</field>
            <table>Contact</table>
        </columns>
        <columns>
            <checkedByDefault>true</checkedByDefault>
            <field>Owner</field>
            <table>Contact</table>
        </columns>
        <columns>
            <checkedByDefault>true</checkedByDefault>
            <field>Open_Cases_Count__c</field>
            <table>Contact</table>
        </columns>
        <columns>
            <checkedByDefault>true</checkedByDefault>
            <field>Betreuungsstufe__c</field>
            <table>Contact</table>
        </columns>
        <columns>
            <checkedByDefault>true</checkedByDefault>
            <field>Account.Name</field>
            <table>Contact</table>
        </columns>
        <masterLabel>Kontakte</masterLabel>
    </sections>
</ReportType>
```
- **KEIN `<join>`-Block** — `Contact.AccountId` ist ein Lookup auf den
  Parent-Account; `<relationship>` akzeptiert nur Child-Relationships (ADR-3 #4).
  Account-Name kommt per Lookup-Traversal `<field>Account.Name</field>` im
  Contact-Bereich.
- AC4 inhärent: Lookup-Traversal ≠ Inner Join — Kontakte ohne Account
  liefern einen leeren `Account.Name`, der als null-Gruppe in den Bericht
  geht (508 von 532 Zeilen).
- `category=other` (es gibt kein `contacts`-Attribut für CRs; unkritisch).
- `fullName`/`label` dürfen in einer Org nicht kollidieren — bei Name-
  Kollision im Deploy: `fullName` bleibt wie oben, `label` kann gekürzt
  werden; die Struktur bleibt unverändert.
- **Wichtig für 4b:** Die Firma-Spalte gehört NICHT in `<columns>` des Reports,
  sondern ausschließlich in `groupingsDown` über das Traversal-Feld
  `Contact.Account.Name` (Kandidat 1 — see 4b Token-Tabelle). Die v2.0
  Variante mit separate Account-Section kann nicht verwendet werden, da
  die Account-Table ohne `<join>` nicht existiert.

### 4b. Bericht „Betreuungslast nach Firma“
`force-app/main/default/reports/Sales/Betreuungslast_nach_Firma.report-meta.xml`

**Spalten-Mapping (AC6) → Spalten im Custom Report Type** (Basisobjekt
Contact, gejoint Account):

| AC-Anforderung | Spalte im CR | Status |
|---|---|---|
| Name | Contact `Name` (Basisobjekt) | ⚠️ Token unverified, s. u. |
| Firma | Contact `Account.Name` (Lookup-Traversal, **nur in `groupingsDown`**) | ⚠️ Token unverified (Kandidat 1 = `Contact.Account.Name`; 2 = `ACCOUNT.NAME`; 3 = retrieve-geprüfter Lookup-Name). Darf NICHT zusätzlich in `<columns>` stehen. |
| Inhaber | Contact `Owner` = **Kontakt-Owner**; ⚠️ NICHT Account-Owner | ✅ Semantik verifiziert (Analytics describe: `CONTACT_OWNER` = Label „Contact Owner“, `fqn Contact.Owner.Name`, vs. `OWNER_FULL_NAME` = Label „Account Owner“, `fqn Contact.Account.Owner.Name`); Token im CR-XML unverified, s. u. |
| Offene Fälle | Contact `Open_Cases_Count__c`, **zusätzlich** als Sum-Aggregate (AC5) | ✅ Feld + Aggregate source-deploybar (Schema `ReportColumn.aggregateTypes`; vgl. offizielle Beispiele mit `<aggregateTypes>Sum</aggregateTypes>`); Token im CR-XML unverified, s. u. |
| Betreuungsstufe | Contact `Betreuungsstufe__c` | ⚠️ Token unverified, s. u. |
| Anzahl Kontakte je Gruppe | Record Count — automatisch pro Gruppe, **nicht** manuell setzen | ✅ |

**⚠️ UNVERIFIED — Report-Spaltentokens im Custom-Report-Type-Kontext:**
Die exakte Token-Notation im Report-XML für **Custom Report Types** ist in
diesem Projekt NICHT bisher verifiziert (alle drei House-Reports nutzen
Standard-ReportTypes: `LeadList`, und `ContactList` im ersten Versuch).
Drei Kandidaten je Spalte (in Priorität, aus dem Analytics describe der
Test-Org abgeleitet):

| Spalte | Kandidat 1 | Kandidat 2 | Kandidat 3 |
|---|---|---|---|
| Name | `Contact.Name` | `NAME` | `FIRST_NAME` + `LAST_NAME` |
| Betreuungsstufe | `Contact.Betreuungsstufe__c` | `Betreuungsstufe__c` | `CONTACT_BETREUUNGSSTUFE__C` |
| Offene Fälle | `Contact.Open_Cases_Count__c` | `Open_Cases_Count__c` | `CONTACT_OPEN_CASES_COUNT__C` |
| Inhaber | `Contact.Owner` | `OWNER` | `CONTACT_OWNER` |

**Vorgehen (Pflicht, nicht optional):** den Report mit den Kandidaten-1-
Tokens deployen → `sf project retrieve` (Report-Datei) → im
abgerufene XML stehen die Tokens, die die Org akzeptiert hat; wenn ein
Token verworfen wurde (Feld fehlt im retrieved XML), Kandidat 2/3 testen.
**Dies ist derselbe Verify-Loop, der für die Feld-API-Namen in ADR-1 bereits
erfolgreich war.** Vor dem deploy: **Report-Erzeugnis öffnen (UI oder
Analytics `report/run`) und die Spaltengruppe + die null-Gruppe + die Sum-
Spalte visuell confirmen** — ein retrieved XML ohne `<field>`-Element zeigt
leer, nicht falsch; das Report-Erzeugnis zeigt, was gerendert wurde.

**Report-XML (Kandidaten-1-Tokens; vor-Deploy-Verify-Loop o. obig gilt):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <name>Betreuungslast_nach_Firma</name>
    <description>Betreuungslast je Firma (SCRUM-396): ALLE Kontakte der Organisation (scope organization, AC3), primär gruppiert nach Account (Firma); Kontakte ohne Account in null-/“Keine Firma“-Gruppe, nicht weggelassen (AC4, outer join im CR). Je Gruppe: Record Count UND Summe offener Faelle (AC5); Detail: Name, Firma, Betreuungsstufe, offene Faelle, Inhaber (AC6).</description>
    <reportType>SCRUM396_Betreuungslast</reportType>
    <scope>organization</scope>
    <format>Summary</format>
    <columns>
        <field>Contact.Name</field>
    </columns>
    <columns>
        <field>Contact.Betreuungsstufe__c</field>
    </columns>
    <columns>
        <field>Contact.Open_Cases_Count__c</field>
        <aggregateTypes>Sum</aggregateTypes>
    </columns>
    <columns>
        <field>Contact.Owner</field>
    </columns>
    <groupingsDown>
        <field>ACCOUNT.NAME</field>
        <sortOrder>Asc</sortOrder>
    </groupingsDown>
    <showDetails>true</showDetails>
    <showGrandTotal>true</showGrandTotal>
    <showSubTotals>true</showSubTotals>
</Report>
```

- **Gruppierung `ACCOUNT.NAME`:** verifiziert im ContactList-Kontext; im CR-
  Kontext (Basisobjekt Contact, gejoined Account) ist der dotted path
  `Account.Name` (Sektion-Name im CR = „Firma“, Tabelle = `Account`) die zu
  erwartende Notation — falls `ACCOUNT.NAME` im CR-Report abgelehnt wird,
  `Account.Name` als Kandidat 2 im Verify-Loop.
- **`scope=organization`:** Contact-CR-Scope-Picklist `my/user/team/
  organization/scopingRule`; `org` ist der Lead-Report-Tag, **invalid** bei
  Contact (Deploy-Blocker, org-seitig verifiziert 7.9.).
- **Record Count pro Gruppe** (AC5, Anzahl Kontakte je Firma) = automatic
  Grouping-Property, **nicht** in `<columns>`/`<groupingsDown>` explizit
  setzen.
- **Kein `<buckets>` im groupingsDown** (v1.0-Entwurf hatte es, Schema-
  Prüfung 7.9.: `ReportGrouping` enthält KEIN Bucket-Element; Bucket-Felder
  sind top-level in `<Report>` mit anderer Struktur) — statt dessen: null-
  Gruppe rendert mit leerem Label. AC4 („eigene Gruppe, nicht weggelassen“)
  ist damit erfüllt; die E2E-Spec prüft Sichtbarkeit **und** dass die Gruppe
  leer-Label-trägt (nicht ein Label „Keine Firma“ — das wäre ein
  Bucket-Feature und hier NICHT gefordert).

## Governor Limits / Bulk
- Formelfeld: read-time Berechnung, kein Governor-Limit-Risiko, keine DML,
  kein Trigger. Report + CR: Plattform-seitige Aggregation (SUM ist eine
  native Report-Summary-Funktion, kein eigener Code). → **Kein Risiko, keine
  Bulk-Sorge.**
- OUTER JOIN in Report-CRs: Plattform-limits, nicht in Governors (keine
  eigener Code). Bei sehr großen Kontaktpopulationen kann der Report langsamer
  werden — unkritisch für diese Org (532 Kontakte).

## Definition of Done / Technische AC
- [ ] Feld deployed, `type=Text` ohne `<length>` (deploy validiert Formel).
- [ ] Feld zeigt „keine“/„normal“/“hoch“ korrekt je Anzahl offener Fälle
      (Read-back je Kontext: 0 / 1-2 / ≥3 offene Fälle) — E2E, nicht nur
      „deployed“.
- [ ] Feld auf dem Standard-Kontakt-Layout (Sektion „Offene Faelle“).
- [ ] PS Read-FLS deployed; Feld via `record-ui` sichtbar, nicht editierbar.
- [ ] **ReportType `SCRUM396_Betreuungslast` deployed** (CR zuerst!); via
      Metadata-API read-back: keine `<join>`-Section im ReportType (v2.1
      verifiziert — s. ADR-3), `scopeInfo` enthält `organization`.
- [ ] **Report `Betreuungslast_nach_Firma` deployed** (nach CR), `reportType=
      SCRUM396_Betreuungslast`, `scope=organization`, im Ordner Sales.
- [ ] **AC4 hard (NICHT „wäre schön“):** SOQL `SELECT COUNT(Id) FROM Contact
      WHERE AccountId = NULL` (Test-Org, 7.9.: **508**) muss im Bericht als
      eine Gruppe erscheinen (empty/„Keine Firma“), nicht weggelassen sein.
- [ ] **AC3 hard:** Anzahl der Kontakt-Zeilen im Bericht (Summe aller
      Gruppe-Anzahlen) = `SELECT COUNT(Id) FROM Contact` der Test-Org
      (7.9.: 532) — nicht 24 (das wäre inner-join-Verhalten, Fehlschlag).
- [ ] **AC5:** Je Gruppe: Record Count (Kontakte) UND Sum offene Fälle
      sichtbar; im Deployed-XML `<aggregateTypes>Sum</aggregateTypes>` (kein
      Org-UI-Schritt).
- [ ] **AC6:** Detailspalten exakt: Name (Contact.Name), Firma (Account.Name
      grouping), Betreuungsstufe (Contact.Betreuungsstufe__c), offene Fälle
      (Contact.Open_Cases_Count__c), Inhaber (**Contact.Owner**, NICHT
      Account-Owner).
- [ ] **Tests (PR-Gate, House-Pattern SCRUM382/394):** Apex-Test-Paar
      (House-Value-Fall + FLS-Read-Verify, `v67.0` Manifest, Shape
      `SCRUM382*Test`/`*FlsTest`) + E2E-Spec für die Report-ACs
      (Shape `SCRUM-378_*.spec.ts`). „Deployed + einmal im Bericht gezählt“
      ist EVIDENZ, kein Test → PR ohne Automatisierung ablehnen.
- [ ] Keine Änderung an `Open_Cases_Count__c` oder den Triggern (Out-of-Scope).
- [ ] Shared-Tree-Regel: nur eigene Pfade stageed, `git status -sb` /
      `git diff --cached --name-only` vor Commit.

## Open points (blocking the PR-Gate, nicht das Design)
- [ ] **CR + Report deployen** (Reihenfolge: CR zuerst, dann Report).
      Owner: @developer-agent. (Deploy-Reihenforderung oben.)
- [ ] **PS-Zuweisung an die Kontakt-lesenden Benutzer** in der Org.
      Owner: @devops-agent.
- [ ] **Lightning-FlexiPage-Placement des Feldes** (App Builder), falls der
      Serviceleiter über Lightning zugreift. Owner: @devops-agent. (Classic-
      Layout im Repo deckt AC1 für die Standard-Kontakt-Layout an; Lightning-
      Sicht ist ein separater Follow-up, nicht in diesem Ticket gefordert.)
