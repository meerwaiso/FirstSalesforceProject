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

### 4. `force-app/main/default/objects/Lead/listViews/Nachfassliste.listView-meta.xml`
Pre-filtered, exactly 4 columns, only open+due leads.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>Name</columns>
    <columns>Company</columns>
    <columns>Status</columns>
    <columns>Lead.Last_Attempt_Date__c</columns>
    <filters>
        <field>Is_Due__c</field>
        <operation>equals</operation>
        <value>true</value>
    </filters>
    <fullName>Nachfassliste</fullName>
    <filterScope>Everything</filterScope>
    <label>Nachfassliste</label>
</ListView>
```

**Column-syntax note (verify on phase-2 deploy, don't guess):**
- Standard own-object fields (`Name`, `Company`, `Status`) are **unprefixed**.
  The known failure ("Could not resolve list view column") is for *relationship*
  columns like `Account.Name` — not for own fields.
- The custom column is object-prefixed `Lead.Last_Attempt_Date__c` to match the
  in-repo custom-column convention (`Contact.Open_Cases_Count__c`). If the deploy
  rejects the object prefix on an own field, retry unprefixed
  `Last_Attempt_Date__c`. Test against the `Letzte_Laeuve` deploy.
- `filterScope=Everything`: the ACs place **no ownership restriction** — every
  open lead that is due belongs.

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
