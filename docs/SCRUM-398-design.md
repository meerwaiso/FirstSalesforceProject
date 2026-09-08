# SCRUM-398 — „Eskalationsstufe“-Feld + Listenansicht „Eskalierte Fälle“ · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and ListView
> filters.** The Jira comments (SCRUM-398) are mangled by Jira's markdown
> converter (double underscores → bold, closing XML tags dropped, `+` eaten).
> Build the files from THIS doc. Do not copy names out of the Jira comment.

## Goal
Ein neuer, systemgerechneter Einstufungswert „Eskalationsstufe“ auf dem Fall
(kritisch/erhöht/normal, abgeleitet aus `Is_Overdue__c` und `Priority`)
erscheint auf dem Fall-Layout; eine Custom List View „Eskalierte Fälle“ zeigt
nur offene Fälle mit Eskalationsstufe kritisch oder erhöht — org-weit.

## Branch
`feature/SCRUM-398-eskalationsstufe` frisch von `master` abziehen.
Geteilter Tree: vor `git add` immer `git status -sb` prüfen und **nur eigene
Pfade explizit** stageen (kein `git add .` / `-A`).

## ADR

### ADR-1: Deklaratives Formelfeld über Is_Overdue__c + Priority — kein Apex, kein Trigger, kein Flow
„Eskalationsstufe“ ist eine reine 3-Verzweigung über **bereits existierende**
Felder:

- `Case.Is_Overdue__c` (Checkbox, SCRUM-390)
- `Case.Priority` (Standard-Picklist)

Es gibt keinen neuen Zustand, keinen Schreibpfad, keine Abhängigkeit, die nicht
bereits existiert:

- **Formelfeld** wird beim Lesen live errechnet und folgt `Is_Overdue__c` und
  `Priority` automatisch → AC1 ist ohne jede zusätzliche Logik erfüllt.
- **Kein Apex/Trigger** (Out-of-Scope verbietet Trigger-Änderungen).
- **Kein Flow** (problematisch für Schema-Drift/apiVersion, kein Mehrwert).
- House-Paralle: `Betreuungsstufe__c` (SCRUM-396) ist dasselbe Muster —
  abgeleitetes Einstufungsfeld.

→ Deklaratives **Picklist-Formelfeld** ist die einzig saubere Option; die
Apex-over-Flow-Default-Regel greift nicht, weil hier gar kein Apex nötig ist.

**Formelshape (verified SCRUM-394, commit bc0b57f):** Picklist-Formelfelder
nehmen KEIN `<length>`. Die `valueSetDefinition` trägt die Werte, die Formel
liefert.

**Formel (Function-Form `AND`/`IF` — kein Infix-AND, Salesforce-Regel):**
```
IF(AND(Is_Overdue__c, Priority = 'High'), 'kritisch', IF(AND(Is_Overdue__c, Priority = 'Medium'), 'erhöht', 'normal'))
```
- `AND` als Funktion (Salesforce-Regel: kein Infix-AND).
- `Priority = 'High'` und `Priority = 'Medium'` sind Picklist-Vergleiche
  (Standard-Picklist Case.Priority).
- `Is_Overdue__c` ist Checkbox → allein steht die Bedingung.

### ADR-2: FLS via Permission Set (Read-only), House-Pattern SCRUM-318/353/394
Read=true, editable=false, `hasActivationRequired=false`, Label+Description im
PS. Profile bleiben unverändert. Eskalationsstufe ist ein read-only Formelfeld
→ `editable=false` ist korrekt und systemerzwungen. Objekt-Level-Zugreich
ersetzt **kein** explizites fieldPermissions (FLS wird nie von CRUD geerbt).

### ADR-3: Custom List View mit Status-Filter für "offene Fälle"
Die Anforderung (AC3/AC4) verlangt, dass nur offene Fälle mit kritischer oder
erhöhter Eskalationsstufe erscheinen. Die Standard-Listenansicht der Case-Objekts
zeigt alle Status. Für "nur offene" muss der Filter auf `Status != 'Closed'`
wirken (oder die spezifische Picklist für geöffnete Status prüfen).

Die Custom List View `Eskalierte_Faelle` auf Case:
- **`filterScope=Everything`** (AC5: org-weit, auch fremde Inhaber)
- **Filter 1:** `Eskalationsstufe__c` IN (`kritisch`, `erhöht`)
  → Operation `includes` (List-View-Operation für mehrere Werte)
- **Filter 2:** `Status != 'Closed'`
  → Operation `notEqual`, Value `Closed`
- **Spalten:** `CaseNumber`, `Subject`, `Priority`, `Processing_Duration__c`,
  `Eskalationsstufe__c`, `Owner`

## Komponenten (exakte Dateien)

### 1. Formelfeld `Eskalationsstufe` auf Case
`force-app/main/default/objects/Case/fields/Eskalationsstufe__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Eskalationsstufe__c</fullName>
    <description>Abgeleitete Eskalationsstufe aus Überfälligkeits-Status und Prioritaet (SCRUM-398): \"kritisch\" wenn ueberfaellig UND Prioritaet High, \"erhoeht\" wenn ueberfaellig UND Prioritaet Medium, sonst \"normal\". Quelle: Is_Overdue__c + Priority; systemgerechnet, von Hand nicht aenderbar.</description>
    <externalId>false</externalId>
    <formula>IF(AND(Is_Overdue__c, Priority = &apos;High&apos;), &apos;kritisch&apos;, IF(AND(Is_Overdue__c, Priority = &apos;Medium&apos;), &apos;erhoeht&apos;, &apos;normal&apos;))</formula>
    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
    <label>Eskalationsstufe</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>kritisch</fullName>
                <default>true</default>
                <label>kritisch</label>
            </value>
            <value>
                <fullName>erhöht</fullName>
                <default>false</default>
                <label>erhöht</label>
            </value>
            <value>
                <fullName>normal</fullName>
                <default>false</default>
                <label>normal</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```
- `Is_Overdue__c` verweist korrekt auf das **Case-eigene** Feld (eigene
  Objektfelder: ohne Präfix im Formel-Editor).
- **KEIN `<length>`** (Picklist-Formelfeld — see ADR-1).
- XML: Strings als `&apos;` oder `&quot;` (beides valid).

### 2. Layout-Integration
`force-app/main/default/layouts/Case-Case Layout.layout-meta.xml`
Im bestehenden Abschnitt **„Überwachung“** (der schon `Is_Overdue__c` +
`Processing_Duration__c` trägt) als drittes Readonly-Element einhängen:

```xml
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Eskalationsstufe__c</field>
            </layoutItems>
```
Einfügeort: innerhalb `<label>Überwachung</label>` → `<layoutSections>`,
neben `Is_Overdue__c` logisch. Genau eine `layoutItems`-Stelle.

### 3. Permission Set (Read-FLS)
`force-app/main/default/permissionsets/SCRUM398_Eskalationsstufe.permissionset-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Case.Eskalationsstufe__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM398_Eskalationsstufe</label>
    <description>Read-FLS für Case "Eskalationsstufe" (SCRUM-398). Systemgerechnetes Formelfeld (read-only); kein Write-PS, keine Apex/DML.</description>
</PermissionSet>
```
Zuweisung an Case-lesende Benutzer in der Org = @devops-agent Follow-up.

### 4. Custom List View `Eskalierte_Faelle`
`force-app/main/default/objects/Case/listViews/Eskalierte_Faelle.listView-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>CaseNumber</columns>
    <columns>Subject</columns>
    <columns>Priority</columns>
    <columns>Processing_Duration__c</columns>
    <columns>Eskalationsstufe__c</columns>
    <columns>Owner</columns>
    <filters>
        <field>Eskalationsstufe__c</field>
        <operation>includes</operation>
        <value>kritisch, erhöht</value>
    </filters>
    <filters>
        <field>Status</field>
        <operation>notEqual</operation>
        <value>Closed</value>
    </filters>
    <fullName>Eskalierte_Faelle</fullName>
    <filterScope>Everything</filterScope>
    <label>Eskalierte Fälle</label>
</ListView>
```
- **`filterScope=Everything`** = org-weit (AC5).
- **Zwei Filter:**
  1. `Eskalationsstufe__c IN kritisch, erhöht` → Operation `includes`
  2. `Status != Closed` → Operation `notEqual`
- **6 Spalten** wie in AC6 gefordert.

## Governor Limits / Bulk
- Formelfeld: read-time Berechnung, kein Governor-Limit-Risiko, keine DML, kein
  Trigger.
- List View: Plattform-seitig, kein eigener Code → **Kein Risiko.**

## Definition of Done / Technische AC
- [ ] Feld deployed, `type=Picklist` mit Formel, ohne `<length>`.
- [ ] Feld zeigt „kritisch“/„erhöht“/„normal“ korrekt je nach
      Is_Overdue__c + Priority (Read-back: E2E, nicht nur „deployed“).
- [ ] Feld auf dem Standard-Case-Layout (Sektion „Überwachung“).
- [ ] PS Read-FLS deployed; Feld via `record-ui` sichtbar, nicht editierbar.
- [ ] **List View `Eskalierte_Faelle` deployed**, filtert korrekt.
- [ ] **Keine Änderung** an `Is_Overdue__c` oder `Processing_Duration__c`
      (Out-of-Scope).
- [ ] **Tests (PR-Gate, House-Pattern SCRUM382/394):** Apex-Test-Paar
      (House-Value-Fall + FLS-Read-Verify, `v67.0` Manifest, Shape
      `SCRUM398*Test`/`*FlsTest`) + E2E-Spec für List-View-ACs
      (Shape `SCRUM-398_*.spec.ts`).
- [ ] Shared-Tree-Regel: nur eigene Pfade stageed, `git status -sb` /
      `git diff --cached --name-only` vor Commit.

## Open points (blocking the PR-Gate, nicht das Design)
- [ ] **List View deployen** — die Custom List View erfordert einen separaten
      Deploy-Step (sie ist nicht automatisch mit dem Feld dabei).
      Owner: @developer-agent.
- [ ] **PS-Zuweisung an die Case-lesenden Benutzer** in der Org.
      Owner: @devops-agent.
- [ ] **Lightning-FlexiPage-Placement des Feldes** (App Builder), falls der
      Serviceleiter über Lightning zugreift. Owner: @devops-agent.
      (Classic-Layout im Repo deckt AC2 an; Lightning-Sicht ist ein separater
      Follow-up, nicht in diesem Ticket gefordert.
