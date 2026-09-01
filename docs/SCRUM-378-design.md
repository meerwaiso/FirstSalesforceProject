# SCRUM-378 — Nachfassliste für Leads · Authoritative Build-Spec

> **This file is the source of truth for the exact XML and API names.**
> The Jira comments (SCRUM-378 / SCRUM-379) are mangled by Jira's markdown
> converter (double underscores → bold `**`, closing XML tags dropped, `+`
> eaten — verified on this project 2026-08-30/31). Build the files from THIS
> doc, cross-check against the in-repo reference files named below. Do not
> copy names out of the Jira comment.

## Goal
Offene Leads, die seit dem manuell eingetragenen Datum „Letzter Versuch“ länger
als 14 Tage nicht kontaktiert wurden, werden automatically read-only-flagged
(`Is_Due__c`) und erscheinen auf einer vorgefilterten Lead-Liste
(`Nachfassliste`) — Feld-Sichtbarkeit nur für Lead-Worker über Permission Set
(FLS, nie Profile).

## ADR — `Is_Due__c` als Formula Checkbox (kein Apex, kein Trigger, kein Flow)
Die Fälligkeits-Logik ist ein **reiner, stateless Boolean über drei Felder des
gleichen Records** (Datum, Status, TODAY): kein Cross-Object, keine Seiteneffekte,
keine Recursion, kein Asynchron. Formula ist für genau diesen Fall optimal und
wird bewusst VOR dem Apex/Trigger-Default gewählt:

- Formula ist **von Natur aus read-only** → „nicht von Hand änderbar“ ist
  garantiert (stärker als ein Trigger-gesetztes Checkboxfeld, das versehentlich
  über UI/API gesetzt werden könnte).
- Formula **reagiert automatisch** bei jeder Lese → kein Batch, kein Timing,
  keine Governor-Limit-Risiken (keine SOQL in Loops, keine Bulkification nötig).
- **Kein Deploy-/Test-Flächen-Zuwachs**: keine Apex-Klasse, kein Trigger-File,
  kein Flow-XML mit apiVersion-Drift / xmllint-Schemafehlern — genau die
  Fehler, die Apex/Flow hier zu Risky machen würden.

Apex/Trigger wären nur nötig bei Multi-Object, Time-Trigger oder Seiteneffekten
— keines davon gilt hier. Flow: verworfen (Schema-Drift, siehe oben).

## Status-Werte in Test-Org (live verifiziert)
`sf data query -o Test-Org -q "SELECT Status, COUNT(Id) c FROM Lead GROUP BY Status"`
liefert exakt 4 Werte:

| Value | Count | Offen? |
|---|---|---|
| `Open - Not Contacted` | 36 | ja |
| `Working - Contacted` | 12 | ja |
| `Closed - Converted` | 3 | nein |
| `Closed - Not Converted` | 4 | nein |

„Abgeschlossen“ = die beiden `Closed …`. Die Formel schließt beide explicit aus.

## Die 6 Dateien (exact XML below)

In-repo reference files to copy shapes from (read these, they deploy today):
- `force-app/main/default/objects/Lead/fields/Interesting__c.field-meta.xml`
- `force-app/main/default/objects/Opportunity/fields/Is_Overdue__c.field-meta.xml`
- `force-app/main/default/objects/Contact/validationRules/NewsletterConsent_DatumKeineZukunft.validationRule-meta.xml`
- `force-app/main/default/objects/CaseRebuildRun__c/listViews/Letzte_Laeuve.listView-meta.xml`
- `force-app/main/default/objects/Contact/listViews/Kritische_Kontakte.listView-meta.xml`
- `force-app/main/default/permissionsets/SCRUM319_OverdueOpportunity.permissionset-meta.xml`
- `force-app/main/default/layouts/Lead-Lead Layout.layout-meta.xml`

---

### 1. `force-app/main/default/objects/Lead/fields/Last_Attempt_Date__c.field-meta.xml`
Date, manuell befüllt, kein PII. Shape = `ConsentDate__c` (Lead-feld without
history-attrs, like `Interesting__c`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Last_Attempt_Date__c</fullName>
    <label>Letzter Versuch</label>
    <description>Letzter Kontaktversuch am Lead, manuell vom Vertrieb eingetragen (SCRUM-378, Nachfassliste). Operatives Datum, kein PII.</description>
    <type>Date</type>
    <required>false</required>
</CustomField>
```

### 2. `force-app/main/default/objects/Lead/fields/Is_Due__c.field-meta.xml`
Formula Checkbox. The formula inside `<formula>` uses XML entities:
`&lt;&gt;` = `<>`, `&gt;` = `>`. Logic = NOT(ISBLANK(date)) AND not-closed AND
(days-since &gt; 14). Inner `IF` keeps the subtraction null-safe.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Is_Due__c</fullName>
    <label>Ist fällig</label>
    <description>Abgeleitetes, read-only Fälligkeits-Flag (SCRUM-378): true, wenn „Letzter Versuch“ &lt;&gt; blank, Lead nicht abgeschlossen und seit dem Datum &gt; 14 Tage vergangen. Systemberechnet.</description>
    <formula>AND(NOT(ISBLANK(Last_Attempt_Date__c)), Status &lt;&gt; "Closed - Converted", Status &lt;&gt; "Closed - Not Converted", IF(ISBLANK(Last_Attempt_Date__c), 0, TODAY() - Last_Attempt_Date__c) &gt; 14)</formula>
    <type>Checkbox</type>
</CustomField>
```

Formula in readable form (sanity, NOT to copy — entities matter in XML):
```
AND(
  NOT(ISBLANK(Last_Attempt_Date__c)),
  Status <> "Closed - Converted",
  Status <> "Closed - Not Converted",
  IF(ISBLANK(Last_Attempt_Date__c), 0, TODAY() - Last_Attempt_Date__c) > 14
)
```

### 3. `force-app/main/default/objects/Lead/validationRules/Letzter_Versuch_KeineZukunft.validationRule-meta.xml`
Blocks future dates. House pattern = `NewsletterConsent_DatumKeineZukunft`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ValidationRule xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Letzter_Versuch_KeineZukunft</fullName>
    <active>true</active>
    <description>SCRUM-378: „Letzter Versuch“ darf keine Zukunft sein. Greift nur, wenn ein Datum eingetragen ist.</description>
    <errorConditionFormula>NOT(ISBLANK(Last_Attempt_Date__c)) AND Last_Attempt_Date__c &gt; TODAY()</errorConditionFormula>
    <errorMessage>„Letzter Versuch“ darf nicht in der Zukunft liegen. Bitte ein heutiges oder früheres Datum wählen.</errorMessage>
</ValidationRule>
```

## ADR-2 (2026-09-01) — Träger der „Nachfassliste“: **Report**, nicht Custom List View

> **Träger-Wechsel, löst SCRUM-380.** Die AC „Liste zeigt genau Name · Firma ·
> Status · Letzter Versuch“ wird ab sofort aus einem **Lead-Bericht**
> (`force-app/main/default/reports/…`) erfüllt, nicht aus der Custom List View.
> ADR-1 (Formula `Is_Due__c`) bleibt unverändert — dieser ADR ersetzt nur den
> **Träger des 4-Spalten-AC**.

**Warum die Custom List View scheitert (verifiziert, nicht angenommen):**
1. Ein deklarierter `<columns>`-Satz **ersetzt** den Default-Spaltensatz statt
   ihn zu ergänzen. Dreifach belegt (Tester-Komm 15261):
   - list-ui-API `/ui-api/list-ui/Lead/Nachfassliste` → `displayColumns = [Last_Attempt_Date__c]`
   - deploytes ListView-XML (retrieve) → genau **ein** `<columns>`-Eintrag
   - Lightning-DOM → genau ein Spalten-Sort-Button; UI selbst: „…needs at least
     one row and two columns“
   - Beweis-ListView auf `feature/SCRUM-378-lead-nachfassliste`:
     `force-app/main/default/objects/Lead/listViews/Nachfassliste.listView-meta.xml`
     Zeile 3 = einziger `<columns>`-Eintrag `Lead.Last_Attempt_Date__c`
2. Standard-Spalten sind über diesen SFDX/Source-Deploy-Pfad **nicht
   deklarierbar**: `Name`, `Company`, `Status` — und als Kontrollversuch selbst
   `LastModifiedDate` — scheitern am `deploy validate` mit „Could not resolve
   list view column“ (mit und ohne `Lead.`-Präfix).
→ Variante (a) „Defaults + Custom“ ist damit **ausgeschlossen**; (c)
“Feld-Wrapper” (`Lead_Name__c` o. ä.) dupliziert Standard-Felder und wird
verworfen.

**Warum Report:** ein Report hat keinen „Default-Set, der ersetzt wird“ — alle
Spalten sind explizit, Standard- und Custom-Felder sind dort die Norm. Die 4
AC-Spalten sind also prinzipiell und **ohne Workaround** darstellbar; voll
source-controlbar (`.report-meta.xml`).

**Auswirkungen (bewusst minimal):**
- **Keine** Feld-, Formula-, Validierungs- oder Permission-Set-Änderung.
  `Last_Attempt_Date__c`, `Is_Due__c`, `SCRUM378_LeadNachfassung`, Validierung
  bleiben exakt wie ADR-1/DoD — die übrigen 7 AC bleiben grün (Tester-Befund).
  Der Report nutzt dieselben Felder; FLS greift auch im Report, Standard-Felder
  sind Lead-Workern bereits sichtbar.
- **Neue Datei:** `force-app/main/default/reports/Sales/Lead_Nachfassliste.report-meta.xml`
  — ReportType `Lead`, Spalten `Name`, `Company`, `Status`,
  `Last_Attempt_Date__c`, Filter `Is_Due__c = TRUE`.
  **⚠️ Exact XML VOR dem Deploy gegen die Test-Org validieren
  (`sf project deploy validate`), nicht raten** — Reports sind Greenfield in
  diesem Repo (keine `reports/`-Präzenz); `reportType` + Feldnamen gegen Org
  prüfen. Fällt die Report-Deployment auf Standard-Spalten zurück (wie der
  ListView-Pfad), ist das ein **Deploy-Pfad-Befund → @devops-agent**, kein
  weiterer Architektur-Turn.
- **Custom List View `Nachfassliste`:** bleibt als Convenience-Quick-Filter
  (filtert korrekt auf `Is_Due__c=true`, rendert 1 Spalte). Sie ist **nicht**
  der getestete AC-Träger. Developer entscheidet nach ADR, ob sie bleibt oder
  entfernt wird; das Re-Test prüft **den Report**.
- **Manifest:** Phase 2 trägt zusätzlich `Report:Sales.Lead_Nachfassliste`
  (Ordnungs-+Dateiname wie die Validierung bestätigt).

### 4 (SUPERSEDED) `force-app/main/default/objects/Lead/listViews/Nachfassliste.listView-meta.xml`
**Träger des 4-Spalten-AC → ADR-2 (Bericht).** Diese Custom List View rendert in
der Org **nur 1 Spalte** (Standard-Spalten sind hier nicht deklarierbar, s.
ADR-2) und dient daher maximal als Convenience-Quick-Filter. Sie ist **nicht**
mehr Teil des getesteten 4-Spalten-Acceptance-Kriteriums.

**Deploybare Form (so, wie sie in der Org live ist — 1 Custom-Spalte):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>Lead.Last_Attempt_Date__c</columns>
    <filters>
        <field>Is_Due__c</field>
        <operation>equals</operation>
        <value>1</value>
    </filters>
    <fullName>Nachfassliste</fullName>
    <filterScope>Everything</filterScope>
    <label>Nachfassliste</label>
</ListView>
```

**Warum keine 4 Spalten hier (vorhergehende Annahme KORRIGIERT):**
- ~~`Name`/`Company`/`Status` unprefixed deklarierbar, das Resolve-Fehler sind nur
  für Beziehungsspalten~~ → **FALSCH.** Alle drei Standard-Spalten — und als
  Kontrollversuch selbst `LastModifiedDate` — werden vom `deploy validate` mit
  "Could not resolve list view column" abgelehnt (mit und ohne `Lead.`-Präfix).
- Ein deklarierter `<columns>`-Satz **ersetzt** den Default-Satz (Beweis:
  `displayColumns=[Last_Attempt_Date__c]`, 1 Sort-Button im DOM). Daher: nur
  das eine Custom-Feld gerendert, keine Standard-Spalten "dazu".
- Boolescher Filter-Wert = `1` (nicht `true`).
- `filterScope=Everything`: ACs verlangen keine Ownership-Schränkung.

### 5. `force-app/main/default/layouts/Lead-Lead Layout.layout-meta.xml`
Insert a new layout section „Nachfassung“ holding both fields adjacent.
Add it as its own `layoutSection` (style TwoColumnsTopToBottom or OneColumn),
placed after „Additional Information“:

```xml
<layoutSections>
    <customLabel>true</customLabel>
    <detailHeading>true</detailHeading>
    <editHeading>true</editHeading>
    <label>Nachfassung</label>
    <layoutColumns>
        <layoutItems>
            <behavior>Edit</behavior>
            <field>Last_Attempt_Date__c</field>
        </layoutItems>
        <layoutItems>
            <behavior>Readonly</behavior>
            <field>Is_Due__c</field>
        </layoutItems>
    </layoutColumns>
    <style>OneColumn</style>
</layoutSections>
```

> ⚠️ **Lightning:** repo tracks **Classic** layouts only. The Lightning record
> page lives in the org (App Builder). After the Classic deploy, place both
> fields on the Lightning Lead record page so they sit together in Lightning
> too — this is an org step → @devops-agent. @tester-agent verifies **both** UIs.

### 6. `force-app/main/default/permissionsets/SCRUM378_LeadNachfassung.permissionset-meta.xml`
FLS only, no object CRUD (PO: existing Lead access stays unchanged).
House pattern = `SCRUM319_OverdueOpportunity`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Lead.Last_Attempt_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Lead.Is_Due__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM378_LeadNachfassung</label>
</PermissionSet>
```

`Last_Attempt_Date__c` read+write; `Is_Due__c` **read-only** (editable=false).
All other users: both fields stay invisible (new fields are invisible to every
profile by default — additive grant is enough, no revocation needed, no PII to
revoke).

## Sharing model
No impact. OWD, sharing rules, role hierarchy unchanged on Lead. Only
field-visibility changes, via Permission Set (FLS) — never Profile.

## Governor-limit risks
None. No Apex/Trigger/Flow; the formula is a per-record in-place computation.

## Deploy (2-phase, house pattern)
- **Phase 1 (fields + validation rule):**
  `manifest/scrum378-phase1-fields.xml` →
  `Lead.Last_Attempt_Date__c`, `Lead.Is_Due__c`,
  `Lead.Letzter_Versuch_KeineZukunft`
- **Phase 2 (referencing):**
  `manifest/scrum378-phase2-referencing.xml` →
  `ListView:Lead.Nachfassliste`, `Layout:Lead-Lead Layout`,
  `PermissionSet:SCRUM378_LeadNachfassung`

### ⚠️ Coverage gate (known repo issue)
Test-Org deploy requires 75% org-wide coverage; the org sits at ~37%. A full
validate **can fail on coverage** regardless of this change. Before deploying,
check coverage status; if it is the blocker, inform @devops-agent. Do not read a
failed validate as a defect in this metadata.

## Definition of Done
- [ ] Both fields present in Test-Org (verify: `sf data query ... FieldDefinition` / describe).
- [ ] `Is_Due__c` read-only in UI (Lead-Worker & non-Worker), value recomputes on read.
- [ ] Future date blocked with the German error message (validation rule active).
- [ ] `Nachfassliste` list view shows exactly Name · Company · Status · Letzter Versuch, only open+due leads; closed and dateless leads excluded.
- [ ] Both fields adjacent on the Lead page (Classic verified in repo; Lightning via App Builder step).
- [ ] Permission set: Lead-Worker sees+edits `Last_Attempt_Date__c`, read-only `Is_Due__c`; restricted user sees neither (negative-access test).
- [ ] Both deploys (phase 1 + phase 2) green on Test-Org; coverage status documented.
