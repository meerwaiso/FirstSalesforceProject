# SCRUM-394 — „Offene Leads nach Quelle“ (Lead) · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and formulas.**
> The Jira comments (SCRUM-394) are mangled by Jira's markdown converter
> (double underscores → bold, closing XML tags dropped, `+` eaten — verified
> repeatedly on this project, even inside fenced code blocks). Build the files
> from THIS doc, cross-check against the in-repo reference files named below.
> Do not copy names out of the Jira comment.

## Goal
Ein systemgepflegtes, **read-only** Formelfeld „Datenqualität“ auf dem Lead
(„vollständig“/„unvollständig“) plus ein Bericht „Offene Leads nach Quelle“ im
bestehenden Berichtsordner „Sales“ — gruppiert nach Lead-Quelle, org-weit
(„All users“), nur offene Leads, Record Count je Quelle, Leads ohne Quelle in
eigener Blank-Gruppe. Deklarativ, reines Reading: keine Automation, kein Apex,
kein Trigger, keine Flow.

## Branch
`feature/SCRUM-394-lead-data-quality` frisch von `master` abziehen.
Geteilter Tree: `.cline-roles/`, `docs/SCRUM-388-design.md`,
`manifest/scr390-release-combined.xml` und `scr378-report-final.zip` liegen
untracked — weder commiten noch löschen, **nur explizit eigene Pfade** stageen.
Niemals `git add .` / `-A`. Committe auch DIESER Datei
(`docs/SCRUM-394-design.md`) in den Branch mit. Der Tree ist derzeit auf
`fix/SCRUM-393-prod-drift-gate` mit einer modifizierten `ci.yml` + 4 untracked
Dateien — von `master` abziehen, nichts davon mitnehmen.

## ADR

### ADR-1: **reine Deklaration (1 Formelfeld), NICHT Apex/Trigger/Flow**
„Datenqualität“ ist ein **abgeleiteter Wert, der bei jedem Lesen neu bestimmt
wird** (AC1: „Der Wert muss zum Zeitpunkt der Betrachtung der aktuellen
Ausprägung von E-Mail/Telefon/Firma entsprechen“).
- **Trigger wird abgelehnt** — der PO-Scope schließt „keine Änderung an
  LeadDuplicateGuard oder den bestehenden Lead-Feldern“ aus, und „keine
  Automatik“. Ein Persist-Feld, das ein Trigger beim Save pflegte, wäre
  (a) genau eine solche Automatik, (b) bei manueller Änderung
  E-Mail/Telefon/Firma über eine API ohne Trigger-Fire oder bei älteren Leads
  sofort alt — AC1 verlangt aber den Wert **zum Zeitpunkt der Betrachtung**.
- **Flow wird abgelehnt** — keine Zustands- oder Datenänderung nötig, nur
  Leselogik; Flow wäre ein Schema-/apiVersion-Risiko ohne Nutzen (Haus-Priorität
  Apex-über-Flow gilt für *nicht-triviale, evolvierende* Logik — hier ist
  deklarativ am einfachsten).
- **Apex kann nicht** einen Formelwert „bei jedem Lesen“ liefern — das ist
  exakt die Domäne eines Formelfelds.
→ **Ein `CustomField` mit `<formula>`** (House-Pattern `Lead.Is_Due__c`,
`Account.Customer_Since_Days__c`).

### ADR-2: API-Name & Typ (Architect-Festlegung, PO-Label)
| Label (PO) | API-Name | Typ | Formel-Speichertyp |
|---|---|---|---|
| Datenqualität | `Lead.Data_Quality__c` | Text(7) | `formula` (read-only) |

Haus-Konvention: englischer API-Name, exaktes deutsches Label als `<label>`
(`Is_Due__c` / „Ist fällig“, `Customer_Since_Days__c` / „Kunde seit (Tage)“).
**Text statt Checkbox**: die PO verlangt die **Wortwerte** „vollständig“ /
„unvollständig“ (AC1, AC5) — ein Checkbox-Feld würde nur true/false rendern.
Text-Formelfeld, `length=255`, `required=false`, `trackTrending=false`
(Shape: `Lead.Email_Norm__c` ist ein normales Text-Feld; der `<formula>`-Part
kommt von den House-Formelfeldern). Text(255) ist großzügig; der Formeloutput
ist max. „unvollständig“ (13 Zeichen) — keine Beschnitt-Risiken.
Das Feld ist **inherently read-only** (Formula → Create/Update/Delete existiert
nicht) → nur **Read-FLS** wird spezifiziert, kein Write-PS.

### ADR-3: Formel

**`Data_Quality__c`** (Text — AC1):
```
IF(AND(NOT(ISBLANK(Email)), NOT(ISBLANK(Phone)), NOT(ISBLANK(Company))), "vollständig", "unvollständig")
```
- **Strikt alle drei gefüllt** = „vollständig“ (PO: „E-Mail **und** Telefon
  **und** Firma alle gefüllt, sonst unvollständig“). Mindestens eines leer →
  „unvollständig“.
- `NOT(ISBLANK(...))` = „gefüllt“ — `NOT` rund um jedes `ISBLANK` (House-Beleg
  `Lead.Is_Due__c`: `NOT(ISBLANK(Last_Attempt_Date__c))`).
- `ISBLANK` auf den **Standardfeldern** `Email`, `Phone`, `Company` (API-Namen
  ohne `__c`, wie im House-Pattern).
- `MobilePhone` zählt **nicht** — PO nennt explizit „Telefon“ = `Phone`.
  (Offener Punkt, nicht blockierend.)
- **`AND`/`OR` NUR als Funktion** — Infix-Schreibweise `A AND B` ist stets
  Syntax-Fehler (Haus-Regel, SCRUM-353/390-Vorbild).
- **Kein XML-Escape nötig**: keine `<`/`&`/`>` in der Formel. Die deutschen
  Strings haben keine Special Characters.

**Berechnungslogik (Validierung, kein Code):**
- Alle gefüllt → `AND(TRUE,TRUE,TRUE)` = `TRUE` → „vollständig“ ✓
- Genau Email leer → `AND(FALSE,TRUE,TRUE)` = `FALSE` → „unvollständig“ ✓
- Alle leer → `AND(FALSE,FALSE,FALSE)` = `FALSE` → „unvollständig“ ✓

### ADR-4: FLS → **ein** read-only Permission Set (kein Write-PS)
Formelfeld → nur gelesen. Ein einziges PS mit `editable=false,
readable=true`. `hasActivationRequired=false`. House-Pattern
`SCRUM382_CustomerSinceDays` / `SCRUM390_OverdueCase` 1:1. Neue Felder sind
default unsichtbar für alle Profile → additive Grant genügt, **keine**
Profiländerung.

### ADR-5: Bericht — **Summary-Format + groupingDown nach `LEAD_SOURCE`**,
Filter `LEAD.IS_CONVERTED = false`
- `format=Summary`, `groupingsDown` nach `LEAD_SOURCE` → AC4 (gruppiert nach
  Lead-Quelle).
- **AC3 (org-weit)**: Report-Level Sharing auf **„All users“** — der Bericht
  zeigt damit **alle** Leads der Organisation, auch fremd-geführte
  (PO: „auch die, die anderen Mitarbeitern gehören“). Dies ist ein
  **Report-Schalter in der Org (UI: Bericht → Einstellungen → „All users“)**,
  **NICHT** im Report-Source-Metadaten speicherbar (verifiziert: das im Repo
  deployte `Lead_Nachfassliste.report-meta.xml` hat exakt 6 Elemente —
  `columns/filter/description/format/name/reportType` — kein Sharing-Element;
  Report-Sharing ist in Salesforce kein Source-Format-Feld). → **Org-Schritt
  nach Deploy** (@devops-agent), im Deploy-Order unten.
- **AC4 Blank-Gruppe**: Leads ohne `LeadSource` fallen im Summary-Report
  automatisch in die **(blank)**-Gruppe — Salesforce-Restverhau beim
  Group-by, kein Extra-Feld, kein Filter nötig.
- **AC5 Record Count je Gruppe**: Summary-Format zeigt die Anzahl pro
  Gruppenzeile automatisch (Record Count) — kein Extra-Feld (House-Beleg
  SCRUM-390 `Ueberfaellige_Faelle`, ADR-5 dort).
- **Report-Typ**: `LeadList` (verifiziert: `Lead_Nachfassliste.report-meta.xml`
  im Repo ist `LeadList`).
- **AC3 Filter**: `LEAD.IS_CONVERTED` `equals` `false` (0/f) → konvertierte
  Leads bleiben außen (Nicht-PO-Scope „Konvertierte Leads bleiben außen vor“).
- **⚠️ Report-Feldnamen verifizieren (wie SCRUM-390 ADR-5):** Standard-
  Report-Feldnamen des `LeadList`-Typs:
  - `LAST_NAME` — **verify**
  - `FIRST_NAME` — **verify** (= im Repo `Lead_Nachfassliste` vorhanden)
  - `COMPANY` — **verify** (= im Repo vorhanden)
  - `STATUS` — **verify** (= im Repo vorhanden)
  - `LEAD.IS_CONVERTED` — **verify** (Standard-Flugfeld, Format `LEAD.`-Prefix)
  - `LEAD_SOURCE` — **verify** (Standard-Report-Name; könnte `LEAD.LEAD_SOURCE`
    heißen — vor Deploy aus der Org retrieve und ablesen)
  - `LEAD.Data_Quality__c` — Custom-Feld, API-Name (kein Report-Feld-Name),
    korrekt wie House-Pattern.
  **Vor dem Report-Deploy** ein Lead-Report aus der Org retrieve
  (`sf project retrieve start --metadata "Report:Sales/Lead_Nachfassliste"`
  → falls nichts, `sf project retrieve start --metadata "Report"`) und die
  exakten `<field>`/`<column>`-Namen abgleichen.

### ADR-6: 2-Phase-Deploy (Haus-Muster SCRUM-390)
Phase 1 = nur das neue CustomField; Phase 2 = alles Referenzierende (PS,
Layout, Report). Referenz-Deploy auf ein nicht-existentes Feld → Schema-Fehler.
Version `67.0`.

### ADR-7: Lead-Layout — **im Repo vorhanden** (kein Retrieve nötig,
im Gegensatz zu SCRUM-390 Case)
`force-app/main/default/layouts/Lead-Lead Layout.layout-meta.xml` ist im Repo
(285 Zeilen, House-Layout). Die neue Section „Datenqualität“ wird **direkt
vor** „System Information“ eingefügt (nach „Dublettenprüfung“), Feld
`behavior=Readonly`. **⚠️ Lightning-FlexiPage nicht im Source Control**
(House-Befund) → die Sichtbarkeit auf der Lightning-Record-Seite ist ein
**Org-Schritt** (App Builder, @devops-agent). Tester verifiziert beides:
Classic (Repo-Layout) + Lightning (Org-Platzierung).

## Datenmodell
- 1 neues CustomField auf `Lead`: `Data_Quality__c` (Text(255), formula,
  read-only).
- 1 neues Permission Set: `SCRUM394_LeadDataQuality` (Read-FLS auf
  `Lead.Data_Quality__c`).
- 1 Layout-Change: `Lead-Lead Layout` + neue Section „Datenqualität“.
- 1 neuer Report: `Offene_Leads_nach_Quelle` im Ordner `Sales`, `LeadList`,
  Summary format, grouped by `LEAD_SOURCE`, filter `IS_CONVERTED=false`.
- **Keine Apex, keine Trigger, keine Flow, keine Validierungsregeln, kein
  neues Objekt, kein neuer Folder.**
- Sharing: **OWD Lead: unverändert** (PO-Festlegung). OWD/Sharing-Rules/
  Role-Hierarchie unberührt; das neue Feld erbt Lead-Sichtbarkeit über FLS.
  **Report-Level „All users“** = Org-Schritt (ADR-5).

## Governor Limits
Kein Apex, kein Trigger, keine Flow → **keine Governor-Limit-Risiken**.
Kein Bulkification, kein SOQL-in-Loop, keine apiVersion-Drift.

## Dateien — exakte Pfade & Shapes

In-repo reference files (deployen heutzutage, kopiere Shapes):
- `force-app/main/default/objects/Lead/fields/Is_Due__c.field-meta.xml`
  (Checkbox-Formula-Shape — hier wird Text-Shape daraus abgeleitet)
- `force-app/main/default/objects/Lead/fields/Email_Norm__c.field-meta.xml`
  (Text-Shape: `length`, `required`, `trackTrending`)
- `force-app/main/default/reports/Sales/Lead_Nachfassliste.report-meta.xml`
  (Report-Shape: `<columns>`, `<filter>`, `<format>`, `<reportType>`,
  `LeadList`)
- `force-app/main/default/permissionsets/SCRUM390_OverdueCase.permissionset-meta.xml`
  (1-PS read-only Shape, `editable=false / readable=true`)
- `force-app/main/default/layouts/Lead-Lead Layout.layout-meta.xml`
  (Layout-Sek. „Dublettenprüfung“ + „System Information“ als Anker)
- `manifest/scr390-phase1-fields.xml`, `manifest/scr390-phase2-referencing.xml`
  (Manifest-Shapes für Phase 1/2)

### Phase 1 — Feld

#### 1 (NEU). `force-app/main/default/objects/Lead/fields/Data_Quality__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Data_Quality__c</fullName>
    <label>Datenqualität</label>
    <description>Abgeleitetes, read-only Datenqualitäts-Label (SCRUM-394): „vollständig“ wenn Email, Phone und Company alle gefüllt, sonst „unvollständig“. Systemberechnet.</description>
    <formula>IF(AND(NOT(ISBLANK(Email)), NOT(ISBLANK(Phone)), NOT(ISBLANK(Company))), "vollständig", "unvollständig")</formula>
    <length>255</length>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Text</type>
</CustomField>
```
(DESCRIPTION < 255 Zeichen — `wc -c` prüfen. Kein XML-Escape in der Formel.
Keine `<`/`&`/`>` in Beschreibung.)

#### 2. `manifest/scr394-phase1-fields.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-394 Phase 1: nur das neue CustomField — Layout/PS/Report referenzieren es und dürfen NACH Phase 1. -->
    <types>
        <members>Lead.Data_Quality__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```

### Phase 2 — Referenzierendes

#### 3 (NEU). `force-app/main/default/permissionsets/SCRUM394_LeadDataQuality.permissionset-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Lead.Data_Quality__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM394_LeadDataQuality</label>
    <description>Read-FLS für Lead "Datenqualität" (SCRUM-394). Systemberechnetes Formelfeld (read-only); kein Write-PS, keine Apex/DML.</description>
</PermissionSet>
```
(DESCRIPTION < 255 Zeichen.)

#### 4 (ÄNDERUNG). `force-app/main/default/layouts/Lead-Lead Layout.layout-meta.xml`
Die neue `layoutSection` einfügen: **nach** der „Dublettenprüfung“-Section
(ends ~Zeile 163), **vor** der „System Information“-Section (starts ~Zeile
164), mit `behavior=Readonly`:
```xml
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>Datenqualität</label>
        <layoutColumns>
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Data_Quality__c</field>
            </layoutItems>
        </layoutColumns>
        <style>OneColumn</style>
    </layoutSections>
```
(Analog House-Section „Dublettenprüfung“ direkt drüber — `OneColumn`, eine
Feld-Einlage, `Readonly`.)

#### 5 (NEU). `force-app/main/default/reports/Sales/Offene_Leads_nach_Quelle.report-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns><field>LAST_NAME</field></columns>
    <columns><field>FIRST_NAME</field></columns>
    <columns><field>COMPANY</field></columns>
    <columns><field>STATUS</field></columns>
    <columns><field>LEAD.Data_Quality__c</field></columns>
    <columns><field>LEAD.Owner</field></columns>
    <filter>
        <criteriaItems>
            <column>LEAD.IS_CONVERTED</column>
            <operator>equals</operator>
            <value>false</value>
        </criteriaItems>
    </filter>
    <format>Summary</format>
    <groupingsDown>
        <groupings>
            <field>LEAD_SOURCE</field>
            <sortOrder>Asc</sortOrder>
        </groupings>
    </groupingsDown>
    <description>Offene Leads (IsConverted=false) der gesamten Organisation, gruppiert nach Lead-Quelle, Record Count je Quelle; Leads ohne Quelle in (blank)-Gruppe. Org-weiter Datenbereich via Report-Level „All users“ (Org-Schritt, nicht im Source).</description>
    <name>Offene_Leads_nach_Quelle</name>
    <reportType>LeadList</reportType>
</Report>
```
**⚠️ Vor Deploy verifizieren (ADR-5):**
- `LEAD_SOURCE` oder `LEAD.LEAD_SOURCE` — vor Deploy Retrieve abgleichen.
  (Das Standard-Report-Feld-Name könnte mit oder ohne `LEAD.`-Prefix sein —
  aus `sf project retrieve start --metadata "Report"` lesen.)
- `LEAD.Owner` oder `OWNER_ID` / `OWNER_NAME` — vor Deploy abgleichen.
  (Im Lead-Report ist es meist `LEAD.Owner` oder `OWNER_ID`; `OWNER_ID` zeigt
  die Owner-Name, `LEAD.Owner` zeigt ebenfalls die Namen.)
- `LEAD.IS_CONVERTED` — Standardfeld, Format `LEAD.`-Prefix + `IS_CONVERTED`.
  (Falls Deploy fehlschlägt: `IS_CONVERTED` ohne Prefix versuchen oder aus
  Retrieve lesen.)
- `LEAD.Data_Quality__c` — Custom-Feld, API-Name korrekt (kein Report-
  Feld-Name), wie House-Pattern.

#### 6. `manifest/scr394-phase2-referencing.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-394 Phase 2: referenzierende Komponenten — NACH Phase 1 (Feld muss existieren). -->
    <types>
        <members>SCRUM394_LeadDataQuality</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>Lead-Lead Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>Sales/Offene_Leads_nach_Quelle</members>
        <name>Report</name>
    </types>
    <version>67.0</version>
</Package>
```
(Report-Member `Folder/Name`-Format — House-Muster `Sales/Lead_
Nachfassliste.report-meta.xml` im Repo; kein neuer `ReportFolder`, der
Ordner „Sales“ existiert bereits.)

## Test-Kriterien (Architect-Definition, zusätzlich zu den PO-ACs)
- **TC1 (AC1 vollständig):** Lead mit gefülltem `Email`, `Phone`, `Company`
  → `Data_Quality__c = „vollständig“`.
- **TC2 (AC1 unvollständig, nur Email leer):** `Email=null`, `Phone`+`Company`
  gefüllt → `Data_Quality__c = „unvollständig“`.
- **TC3 (AC1 unvollständig, alle leer):** alle drei `null`
  → `Data_Quality__c = „unvollständig“`.
- **TC4 (AC1 live-Update):** Lead „vollständig“ → `Email` leeren (per API,
  kein Trigger nötig) → sofort beim nächsten `SELECT`/UI-Read:
  `Data_Quality__c = „unvollständig“` (Formelfeld rechnet live — kein
  Persist, kein Refresh-Schritt).
- **TC5 (AC2 report existiert):** Bericht `Offene_Leads_nach_Quelle` im
  Ordner `Sales`, auf `LeadList`, format Summary.
- **TC6 (AC3 org-weit):** als Benutzer mit Bericht-Zugriff geöffnet → zeigt
  **alle** `IsConverted=false` Leads der Org, inkl. Leads **anderer**
  User. Report-Level Sharing = „All users“ (Org-Schritt, ADR-5).
  **Verifikation**: als Benutzer ohne Ownership über fremde Leads den Bericht
  öffnen und zählen, dass auch fremde Leads sichtbar sind (Playwright oder
  `sf reports run`).
- **TC7 (AC3 konvertiert außen):** 1 konvertierter Lead (`IsConverted=true`)
  → erscheint **nicht** im Bericht.
- **TC8 (AC4 Blank-Gruppe):** Lead mit leerer `LeadSource` → erscheint in der
  **(blank)**-Gruppe im Summary, mit Count ≥ 1.
- **TC9 (AC4 Record Count):** 2 offene Leads mit Quelle „Website“ + 1 ohne →
  Gruppe „Website“: Count 2, Gruppe (blank): Count 1.
- **TC10 (AC5 Spalten):** Berichtsrow zeigt: Name (Last+First), Firma
  (`COMPANY`), Status, Datenqualität, Inhaber (Owner).
- **TC11 (AC1 Layout Classic):** Feld `Data_Quality__c` sichtbar auf dem
  Lead-LAYOUT in Classic, `Readonly` (grau), in Section „Datenqualität“.
- **TC12 (AC1 Layout Lightning):** Feld sichtbar auf der Lightning-Record-
  Seite — **Org-Schritt** (App Builder), ADR-7. Tester verifiziert nach
  @devops-agent's Placement.
- **TC13 (AC1 FLS negativer Fall):** Benutzer **ohne** das Permission Set
  `SCRUM394_LeadDataQuality` → Feld **nicht sichtbar** (Classic + Lightning).
  Read-Back via `sf data query` als eingeschränkter User
  → `NO_VIEWABLE_ROWS` auf das Feld.

## Offene Punkte (blockt die Implementierung NICHT)
- **Lightning-Platzierung** — @devops-agent, App Builder, nach dem Deploy
  (ADR-7). Blockt den PR nicht, blockt aber die AC1-TC12-Verifikation
  von @tester-agent.
- **Report-Level „All users“** — @devops-agent, Org-Schritt, nach PR-Merge
  (ADR-5). Blockt nicht den PR; für AC3-TC6 (org-weit) Pflicht.
- **Report-Feldnamen `LEAD_SOURCE` / `LEAD.Owner`** — @developer-agent,
  vor dem Report-Deploy (ADR-5). 1 Retrieve.
- **„Telefon“ = `Phone` vs. `Phone` oder `MobilePhone`?** — Default:
  `Phone` (PO-Text, AC1: „Telefon“). Falls @po-agent `MobilePhone`
  inklusive meint → ADR-3 um 1 `NOT(ISBLANK())` erweitern. Blockiert
  nicht die Implementierung.
- **Layout-Sektion position:** „vor System Information“ (ADR-7). Falls
  @po-agent eine andere Position will → trivial, 1 XML-Bewegung.

## Deploy-Order (für @devops-agent)
1. `sf project deploy start -f manifest/scr394-phase1-fields.xml`
   — `Data_Quality__c`.
2. `sf project deploy start -f manifest/scr394-phase2-referencing.xml`
   — PS, Lead-Layout, Report.
3. **Org-Schritte** (nicht per Deploy):
   a. **Report-Level Sharing**: Bericht in der Org öffnen → Einstellungen →
      „Access/Shared With“ → **„All users“** (Report-Level, nicht Folder-
      Level). (AC3, ADR-5.)
   b. **Lightning Placement**: App Builder, Lead-Record-Page, Feld
      `Data_Quality__c` in Section „Datenqualität“ (oder eine passende
      Standard-Section) platzieren. (AC1, ADR-7.)
   c. **PS aktivieren**: `SCRUM394_LeadDataQuality` für die relevanten
      Vertriebs-/Sales-Nutzer (oder Rollen/Profile) aktivieren.
      (AC1 FLS; ohne Aktivierung bleibt das Feld für nicht-SystemAdmins
      unsichtbar — negative-Test TC13 hängt davon ab.)
4. **Verify**:
   - `sf data query --query "SELECT Id, Data_Quality__c FROM Lead LIMIT 3"`
     (Field-Read-Back, Formel berechnet korrekt in der Org).
   - `sf reports run -r <reportId> --json` als eingeschränkter User →
     org-weite Zeilen inkl. fremd-geführter Leads sichtbar
     (AC3, „All users“ gesetzt).
