# SCRUM-390 — „Überfällige Fälle" (Case) · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and formulas.**
> The Jira comments (SCRUM-390) are mangled by Jira's markdown converter
> (double underscores → bold, closing XML tags dropped, `+` eaten — verified
> repeatedly on this project, even inside fenced code blocks). Build the files
> from THIS doc, cross-check against the in-repo reference files named below.
> Do not copy names out of the Jira comment.

## Goal
Zwei systemgepflegte, **read-only** Formelfelder auf dem Case —
„Bearbeitungsdauer (Tage)" und „Überfällig" — plus ein Bericht
„Überfällige Fälle" im neuen Berichtsordner „Service" (gruppiert nach
Priorität, mit Fallanzahl je Gruppe). Deklarativ, reines Reading: keine
Automation, kein Apex, kein Trigger, keine Flow.

## Branch
`feature/SCRUM-390-overdue-cases` frisch von `master` abziehen.
Geteilter Tree: `.cline-roles/`, `docs/SCRUM-388-design.md` und
`scr378-report-final.zip` liegen untracked — weder commiten noch löschen,
**nur explizit eigene Pfade** stageen. Niemals `git add .` / `-A`.
Committe auch DIESER Datei (`docs/SCRUM-390-design.md`) in den Branch mit.

## ADR

### ADR-1: **reine Deklaration (2 Formelfelder), NICHT Apex/Trigger/Flow**
Die Auswirkung „wie lange ist der Fall offen" ist ein **abgeleiteter Wert, der
bei jedem Lesen neu bestimmt** ist — es gibt kein Speichereignis, das ihn
triggern müsste, und keine Zustandsänderung im Zeitverlauf, die ein Trigger
nachpflegen müsste.
- **Trigger wird abgelehnt** — Scope schließt „keine Änderung an den
  bestehenden Case-Automatiken (`CaseOpenCountTrigger`, `CasePriorityTrigger`)"
  explizit aus; ein eigener Trigger wäre genau die Art von „bestehender
  Case-Automatik", die die PO aussagt, und löst „offener Fall älter als X"
  nicht (ein Trigger feuert nur bei Save/Import, nicht wenn reines Elapsed-Time
  ein Feld über die Schwelle schiebt).
- **Flow wird abgelehnt** — keine Zustands- oder Datenänderung nötig, nur
  Leselogik; Flow wäre ein Schema-/apiVersion-Risiko ohne Nutzen (Haus-Priorität
  Apex-über-Flow gilt für *nicht-triviale, evolvierende* Logik — hier ist
  deklarativ am einfachsten).
- **Apex kann nicht** einen Formelwert „bei jedem Lesen" liefern — das ist
  exakt die Domäne eines Formelfelds.
→ **Zwei `CustomField` mit `<formula>`** (House-Pattern `Customer_Since_Days__c`
/ `Lead.Is_Due__c`).

### ADR-2: API-Namen & Typen (Architect-Festlegung, PO-Labels)
| Label (PO) | API-Name | Typ | Formel-Speichertyp |
|---|---|---|---|
| Bearbeitungsdauer (Tage) | `Case.Processing_Duration__c` | Number | `formula` (read-only) |
| Überfällig | `Case.Is_Overdue__c` | Checkbox | `formula` (read-only) |

Haus-Konvention: englischer API-Name, exaktes deutsches Label als `<label>`
(`Customer_Since_Days__c` / „Kunde seit (Tage)", `Is_Due__c` / „Ist fällig").
„Überfällig" → `Is_Overdue__c` (House-Vorbild aus SCRUM-353
`Opportunity.Is_Overdue__c` — bewusst gleiches Namensmuster, anderes Objekt).
Beide `formula`-Felder sind **inherently read-only** (Create/Update/Delete
existiert nicht) → nur **Read-FLS** wird spezifiziert, kein Write-PS.

### ADR-3: Formeln

**`Processing_Duration__c`** (Number, ganz — AC2):
```
IF(ISBLANK(ClosedDate), TODAY(), DATEVALUE(ClosedDate)) - DATEVALUE(CreatedDate)
```
- Offen (`ClosedDate` leer) → `TODAY() - DATEVALUE(CreatedDate)` = Tage Anlage→heute.
- Geschlossen (`ClosedDate` gesetzt) → `DATEVALUE(ClosedDate) - DATEVALUE(CreatedDate)` = Tage Anlage→Abschluss.
- `DATEVALUE` streicht die Zeitkomponente → **ganzzahlig** (PO-Festlegung „gerundet nach unten"); „heute angelegt" → `0`.
- **Keine XML-Escapes nötig** (keine `<`/`&`).

**`Is_Overdue__c`** (Checkbox, Boolean — AC3):
```
AND(
  NOT(ISBLANK(ClosedDate)),
  OR(
    IF(ISPICKVAL(Priority, "High"),   Processing_Duration__c > 2,  FALSE),
    IF(ISPICKVAL(Priority, "Medium"), Processing_Duration__c > 5,  FALSE),
    IF(ISPICKVAL(Priority, "Low"),    Processing_Duration__c > 10, FALSE)
  )
)
```
- **Erster Operand `NOT(ISBLANK(ClosedDate))` = „offene Fälle"**: geschlossener
  Fall → `false`, also **niemals überfällig** (AC3, „eindeutigst"). Da `AND`/`OR`
  in Salesforce **nicht** short-circuiten, wird `OR(...)` dennoch evaluiert —
  das Ergebnis ist aber durch das `false` des `AND` unabhängig davon `false`.
- **Strikte `>` (Haus-Pattern `daysAfter > threshold`)** = „über der Grenze":
  exakt High=2 → `2>2=false` → **nicht** überfällig; High=3 → `true`. (AC3,
  PO-Interpretation „nur *über* überfällig".)
- **`AND`/`OR` NUR als Funktion** — Infix-Schreibweise `A AND B` ist stets
  Syntax-Fehler (Haus-Regel, SCRUM-353-Vorbild; kein `Is_Overdue__c`-Style-Mix).
- **Ungenannte/leere `Priority`** → alle drei `IF` → `false` → **nicht**
  überfällig (konkretes, sicheres Default: AC legt nur High/Medium/Low fest).
- **XML-Escapes**: `>` → `&gt;` im `<formula>`-Element (House-Beleg
  `Lead.Is_Due__c`). Keine `<` in der Formel.

**Berechnungslogik (Validierung, kein Code):**
- Offen, High, `Processing_Duration__c`=3  → `AND(TRUE, OR(TRUE,FALSE,FALSE))` = `true` ✓
- Offen, High, `=2`                        → `AND(TRUE, OR(FALSE,...))` = `false` ✓ (Grenze)
- Offen, Medium, `=6`                      → `AND(TRUE, OR(FALSE,TRUE,FALSE))` = `true` ✓
- Geschlossen (irgendwie), Priority High   → `AND(FALSE, *)` = `false` ✓ (nie überfällig)

### ADR-4: FLS → **ein** read-only Permission Set (kein Write-PS)
Im Gegensatz zu SCRUM-388 (Batch brauchte **Update**-FLS, deshalb Write-PS)
gibt es hier **keine Apex/DML** — die Formelfelder werden nur gelesen.
→ Ein einziges PS mit `editable=false, readable=true` für beide Felder.
Neue Felder sind default unsichtbar für alle Profile → additive Grant genügt,
**keine** Profiländerung, **keine** Revocation. `hasActivationRequired=false`.
House-Pattern `SCRUM382_CustomerSinceDays` (1 PS, beidseitig `false/true`).

### ADR-5: Bericht — **Summary-Format + grouping nach `Priority`**, Filter `Is_Overdue__c = true`
- `format=Summary`, `groupingsDown` nach `PRIORITY` → AC4 (nur die überfälligen
  Fälle, gruppiert nach `Case.Priority`).
- **Filter** `Case.Is_Overdue__c equals 1/true` listet **nur** überfällige
  Fälle; da `Is_Overdue__c` für geschlossene Cases immer `false` ist,
  sind geschlossene Cases damit automatisch ausgeschlossen (AC: „keine
  Auswertung geschlossener Fälle").
- **AC5 (Anzahl je Prioritätsgruppe)**: Im Summary-Format zeigt Salesforce
  **Record Count** pro Gruppenzeile automatisch — kein Extra-Feld nötig.
- Report-Typ: **`CaseList`** (natural Lead→`LeadList`-Parallel aus
  `Lead_Nachfassliste` im Repo).
- **⚠️ Report-Feldnamen verifizieren (höchste Unsicherheit, kein In-Repo-Cover):**
  Standard-Cases-Felder des `CaseList`-Report-Typs werden im Report-XML über
  deren **Report-Feld-Namen** (kleine Schreibweise, underscores) referenziert —
  `CASE_NUMBER`, `SUBJECT`, `PRIORITY`, `OWNER_NAME` (analog `FIRST_NAME` /
  `LAST_NAME` / `STATUS` im Lead-Report). Custom-Feld über API-Name
  `Case.Processing_Duration__c`. **Vor dem Report-Deploy** ein beliebiges
  bestehendes Case-Report aus der Org retrieve und die exakten `<field>`-Namen
  abgleichen — die Error-Nachricht beim Deploy benennt das Feld, wenn ein Name
  falsch ist (1 Retrieve-Command, kein Zeitverschwendung).

### ADR-6: 2-Phase-Deploy (Haus-Muster SCRUM-381/382/388)
Phase 1 = nur die zwei CustomField-Definitionen; Phase 2 = alles, was
referenziert (PS, Case-Layout, ReportFolder, Report). Referenz-Deploy auf
ein nicht-existentes Feld → Schema-Fehler, daher die Reihenfolge.
Version `67.0` (House-Muster `scr382-phase2-referencing.xml` / `scr388-*`).

### ADR-7: Case-Layout muss **erst aus der Org retrieve** werden
Es gibt **keine `objects/Case/`** und **kein `layouts/Case-*.layout-meta.xml`**
im Repo (verifiziert: `ls force-app/main/default/objects/` = Account,
CaseRebuildRun__c, Contact, Lead, Opportunity). Der Developer retrieve die
primäre Case-Layout (in der Regel „Case-Case Layout") in den Repo, fügt dann
die neue Section ein. **Lightning FlexiPages liegen nicht im Source Control**
(House-Befund) → die Platzierung auf der Lightning-Record-Seite ist ein
**Org-Schritt** (App Builder, @devops-agent). Tester verifiziert beides:
Classic (Repo-Layout) + Lightning (Org-Platzierung).

## Datenmodell
- 2 neue CustomFields auf `Case`: `Processing_Duration__c` (Number, formula),
  `Is_Overdue__c` (Checkbox, formula).
- 1 neues Permission Set: `SCRUM390_OverdueCase` (Read-FLS auf beide Felder).
- 1 neuem ReportFolder: `Service` (Public).
- 1 neuer Report: `Ueberfaellige_Faelle` im Ordner `Service`, `CaseList`,
  Summary format, grouped by `PRIORITY`, filter `Is_Overdue__c=true`.
- 1 Layout-Change: die retrieve-te „Case-Case Layout" + neue Section
  „Überwachung" mit beiden Feldern `Readonly`.
- **Keine** Apex, **keine** Trigger, **keine** Flow, **keine**
  Validierungsregeln, **kein** neues Objekt.
- Sharing: **keine Änderung** (PO-Festlegung). OWD/Rules/Role-Hierarchie
  unberührt; Felder erben Case-Sichtbarkeit über FLS.

## Governor Limits
Kein Apex, kein Trigger, keine Flow → **keine Governor-Limit-Risiken**.
Kein Bulkification, kein SOQL-in-Loop, keine apiVersion-Drift (keine Flow).

## Dateien — exakte Pfade & Shapes

In-repo reference files (deployen heutzutage, kopiere Shapes):
- `force-app/main/default/objects/Account/fields/Customer_Since_Days__c.field-meta.xml` (Number-Formula-Shape, precision 10 / scale 0)
- `force-app/main/default/objects/Lead/fields/Is_Due__c.field-meta.xml` (Checkbox-Formula-Shape + `&gt;`-Escape + `AND/OR/IF/ISPICKVAL`)
- `force-app/main/default/reports/Sales/Lead_Nachfassliste.report-meta.xml` (Report-Shape: `<columns>`, `<filter>`, `<format>`, `<reportType>`)
- `force-app/main/default/reports/Sales.reportFolder-meta.xml` (ReportFolder-Shape)
- `force-app/main/default/permissionsets/SCRUM382_CustomerSinceDays.permissionset-meta.xml` (1-PS read-only Shape)
- `manifest/scr382-phase1-fields.xml` (Phase 1 Manifest-Shape, 2 CustomFields)
- `manifest/scr382-phase2-referencing.xml` (Phase 2 Manifest-Shape: PermissionSet + Layout)
- (neues) `manifest/scr390-phase1-fields.xml`, `manifest/scr390-phase2-referencing.xml`

### Phase 1 — Felder

#### 1 (NEU). `force-app/main/default/objects/Case/fields/Processing_Duration__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Processing_Duration__c</fullName>
    <label>Bearbeitungsdauer (Tage)</label>
    <description>Ganze Tage Bearbeitungsdauer eines Cases (SCRUM-390): offen = heute minus Anlage, geschlossen = Abschluss minus Anlage. Formelfeld, systemberechnet, read-only. Kein PII.</description>
    <type>Number</type>
    <precision>10</precision>
    <scale>0</scale>
    <unique>false</unique>
    <formula>IF(ISBLANK(ClosedDate), TODAY(), DATEVALUE(ClosedDate)) - DATEVALUE(CreatedDate)</formula>
</CustomField>
```
(DESCRIPTION < 255 Zeichen — `wc -c` prüfen.)

#### 2 (NEU). `force-app/main/default/objects/Case/fields/Is_Overdue__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Is_Overdue__c</fullName>
    <label>Überfällig</label>
    <description>Überfällig-Flag für einen Case (SCRUM-390): offen und Bearbeitungsdauer über der Prioritäts-Grenze (High &gt; 2, Medium &gt; 5, Low &gt; 10 Tage). Geschlossener Case ist nie überfällig. Systemberechnet, read-only.</description>
    <type>Checkbox</type>
    <formula>AND(NOT(ISBLANK(ClosedDate)), OR(IF(ISPICKVAL(Priority, "High"), Processing_Duration__c &gt; 2, FALSE), IF(ISPICKVAL(Priority, "Medium"), Processing_Duration__c &gt; 5, FALSE), IF(ISPICKVAL(Priority, "Low"), Processing_Duration__c &gt; 10, FALSE)))</formula>
</CustomField>
```
(DESCRIPTION < 255 Zeichen — `wc -c` prüfen. Die `<`/`>`-Escapes im
`<description>` sind korrekt; nur `&gt;` im `<formula>` ist die
Formel-Escape, die House-Pattern `Lead.Is_Due__c` bestätigt.)

#### 3. `manifest/scr390-phase1-fields.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-390 Phase 1: nur die zwei neuen CustomFields — Layout/PS/Report referenzieren sie und dürfen NACH Phase 1. -->
    <types>
        <members>Case.Processing_Duration__c</members>
        <members>Case.Is_Overdue__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```

### Phase 2 — Referenzierendes

#### 4 (NEU). `force-app/main/default/permissionsets/SCRUM390_OverdueCase.permissionset-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Case.Processing_Duration__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Case.Is_Overdue__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM390_OverdueCase</label>
    <description>Read-FLS für Case "Bearbeitungsdauer (Tage)" und "Überfällig" (SCRUM-390). Beide systemberechnete Formelfelder (read-only); kein Write-PS, keine Apex/DML.</description>
</PermissionSet>
```
(DESCRIPTION < 255 Zeichen — `wc -c` prüfen. Ein PS ohne Write-PS: hier gibt
keinen Prozess, der in DML schreiben müsste — im Gegensatz zu SCRUM-388.)

#### 5 (RETRIEVE, dann ÄNDERUNG). `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml`
1. **Retrieve** aus der Org: `sf project retrieve start --metadata "Layout:Case-Case Layout"` (oder der in der Org primäre Case-Layout-Name, falls anders; die Liste: `sf project retrieve start --metadata "Layout"` und die Case-Variante wählen). In den Repo landet das unter dem Pfad oben.
2. **Ändern**: eine neue `layoutSection` mit beiden Feldern `Readonly` einfügen.
   Position: direkt nach der Standard-Sektion (vor „System Information"),
   damit „Überfällig" nah an `Priority` bleibt (PO-„anordnung"):
```xml
    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>Überwachung</label>
        <layoutColumns>
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Processing_Duration__c</field>
            </layoutItems>
        </layoutColumns>
        <layoutColumns>
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Is_Overdue__c</field>
            </layoutItems>
        </layoutColumns>
        <style>TwoColumnsLeftToRight</style>
    </layoutSections>
```
(`behavior=Readonly` zeigt die systembelegten Felder ab, wie House-Pattern bei
`Customer_Since_Days__c`. Die Section-Label „Überwachung" ist vorgegeben —
devops/developer kann sie bei Bedarf in eine bestehende Section integrieren /
umbenennen; die Felder selbst müssen auf jedem Case-Layout stehen, das Service
benutzt, falls es mehrere gibt.) **Achtung:** Nur die primäre Case-Layout
ändern — die anderen Case-Layouts, falls vorhanden, bleiben unverändert,
außer die PO verlangt „alle". (PO-AC1: „Auf dem Case-Layout" — Singular,
primäre reicht.)

#### 6 (NEU). `force-app/main/default/reports/Service.reportFolder-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ReportFolder xmlns="http://soap.sforce.com/2006/04/metadata">
    <accessType>Public</accessType>
    <name>Service</name>
</ReportFolder>
```
(House-Pattern `Sales.reportFolder-meta.xml` 1:1. `accessType=Public` =
wer den Ordner sehen darf sieht den Bericht — PO-„Zugriffsprofil analog zu
Serviceleiter" via Public-Folder + Report-Zugriffsrecht, keine Einzel-PS-Nuance
im Repo.)

#### 7 (NEU). `force-app/main/default/reports/Service/Ueberfaellige_Faelle.report-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns><field>CASE_NUMBER</field></columns>
    <columns><field>SUBJECT</field></columns>
    <columns><field>PRIORITY</field></columns>
    <columns><field>Case.Processing_Duration__c</field></columns>
    <columns><field>OWNER_NAME</field></columns>
    <filter>
        <criteriaItems>
            <column>Case.Is_Overdue__c</column>
            <operator>equals</operator>
            <value>1</value>
        </criteriaItems>
    </filter>
    <format>Summary</format>
    <groupingsDown>
        <groupings>
            <field>PRIORITY</field>
            <sortOrder>Asc</sortOrder>
        </groupings>
    </groupingsDown>
    <description>Überfällige Cases, gruppiert nach Priorität (SCRUM-390). Filter: Is_Overdue__c=true (nur offene Fälle; geschlossene sind nie überfällig). Anzeige: Fallnummer, Betreff, Priorität, Bearbeitungsdauer (Tage), Inhaber. Record Count je Prioritätsgruppe = automatisch im Summary-Format.</description>
    <name>Ueberfaellige_Faelle</name>
    <reportType>CaseList</reportType>
</Report>
```
**Vor dem Deploy verifizieren (ADR-5):** die Standard-Report-Feldnamen
`CASE_NUMBER` / `SUBJECT` / `PRIORITY` / `OWNER_NAME` für den `CaseList`-Report-Typ.
Ein bestehendes simples Case-Report aus der Org retrieve und die `<field>`-Namen
abgleichen. Die Custom-Feldreferenz `Case.Processing_Duration__c` ist der API-Name
(kein Report-Feld-Name) und korrekt wie im House-Pattern.

#### 8. `manifest/scr390-phase2-referencing.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-390 Phase 2: referenzierende Komponenten — NACH Phase 1 (Felder müssen existieren). -->
    <types>
        <members>SCRUM390_OverdueCase</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>Case-Case Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>Service</members>
        <name>ReportFolder</name>
    </types>
    <types>
        <members>Service/Ueberfaellige_Faelle</members>
        <name>Report</name>
    </types>
    <version>67.0</version>
</Package>
```
(Report-Member-Format `Folder/Name` für Reports in einem Under-Folder —
verifizieren per `sf` wenn der Deploy auf den Pfad zickt; die House-Muster
`Sales/Lead_Nachfassliste.report-meta.xml` im Repo folgen demselben Muster.)

## Test-Kriterien (Architect-Definition, zusätzlich zu den PO-ACs)
- **TC1 (AC2 offen):** Case, `CreatedDate = TODAY()-3`, `ClosedDate` leer,
  Priority beliebiger Wert → `Processing_Duration__c = 3`.
- **TC2 (AC2 geschlossen):** Case, `CreatedDate = TODAY()-9`, `ClosedDate = TODAY()-5`
  → `Processing_Duration__c = 4`.
- **TC3 (AC2 exakt, null-Fall):** `CreatedDate = TODAY()` (offen)
  → `Processing_Duration__c = 0`.
- **TC4 (AC3 offen, über Grenze):** High → `=3` → `Is_Overdue__c = true`; Medium → `=6`
  → true; Low → `=11` → true.
- **TC5 (AC3 exakt an Grenze):** High = 2, Medium = 5, Low = 10 → `Is_Overdue__c = false`
  (alle drei).
- **TC6 (AC3 geschlossen, egal was):** Case, `ClosedDate` gesetzt, `Processing_Duration__c`
  würde `> threshold` ergeben (z. B. High, 5 Tage seit Anlage, 3 Tage vor
  Closure geschlossen) → `Is_Overdue__c = false`.
- **TC7 (AC3 andere/leere Priority, offen):** Priority leer oder ein Wert
  außer High/Medium/Low, offen, `Processing_Duration__c=30` → `Is_Overdue__c = false`
  (safe default, dokumentiert in ADR-3).
- **TC8 (AC4 report filter):** Report `Ueberfaellige_Faelle` zeigt **nur** Cases
  mit `Is_Overdue__c=true`; ein geschlossener Fall mit `Is_Overdue__c=false`
  erscheint nicht.
- **TC9 (AC5 report group count):** 2 Cases mit Priority High + 1 mit Medium,
  alle überfällig → Report zeigt Gruppe „High" mit Record Count 2 und „Medium"
  mit Record Count 1.
- **TC10 (AC1 layout, Classic):** Beide Felder sichtbar auf der Case-Record in
  Classic (Repo-Layout), `Readonly` (grau).
- **TC11 (AC1 layout, Lightning):** Beide Felder sichtbar auf der Lightning-
  Record-Seite — **Org-Schritt** (App Builder), ADR-7. Tester verifiziert nach
  @devops-agent's Placement.

## Offene Punkte (blockt die Implementierung NICHT)

- **Case-Layout-Name** — wenn die Org eine andere primäre Case-Layout-Label
  verwaltet als „Case-Case Layout" (z. B. „Case-Case Default Layout"), ist der
  Retrieve-Name entsprechend anzupassen. @developer-agent bestimmt das beim
  initialen Retrieve (`sf project retrieve start --metadata "Layout"` zeigt
  die vorhandenen Case-Layouts).
- **Lightning-Platzierung** — @devops-agent, App Builder, nach dem Deploy
  (ADR-7). Blockt den PR nicht, blockt aber die AC1-Lightning-Verifikation
  von @tester-agent.
- **Report-Feldnamen-Verifikation** — @developer-agent, vor dem Report-Deploy
  (ADR-5). 1 Retrieve-Command.
- **Report-Folder-Zugriff** — `accessType=Public` wie House-Pattern `Sales`;
  falls die Org „Service-Leiter-only" Zugang statt Public will, ist das ein
  Org-Schritt, kein Repo-Änderung. @po-agent kann das bei Fragen klären.

## Deploy-Order (für @devops-agent)
1. `sf project deploy start -f manifest/scr390-phase1-fields.xml` — beide Felder.
2. `sf project deploy start -f manifest/scr390-phase2-referencing.xml` — PS, Layout, ReportFolder, Report.
3. **Org-Schritt** (nicht per Deploy): Lightning FlexiPage platzieren
   (ADR-7), ggf. Report-Zugriffsrecht auf den „Service"-Ordner verfeinern.
4. Verify: `sf data query --query "SELECT CaseNumber, Is_Overdue__c, Processing_Duration__c FROM Case LIMIT 5"`
   (Feld-Read-Back, ADR-3 Formeln stimmen in der Org).
