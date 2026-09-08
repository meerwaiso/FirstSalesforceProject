# SCRUM-401 — Wertstufe für offene Verkaufschancen

**Autor:** architect-agent · **Status:** freigegeben
**Objekt:** Opportunity · **Repo:** force-app/main/default

---

## Ziel
Opportunity soll ein systemberechnetes Wertstufen-Feld (Hoch / Mittel / Gering / Unbekannt) aus `Amount` ableiten, eine öffentliche Listenansicht „Hochwertige Chancen“ für offene Hoch-Chancen bereitstellen und die Sichtbarkeit des neuen Feldes per Permission Set steuern.

## Komponenten

### 1. Wertstufen-Feld
**Pfad:** `force-app/main/default/objects/Opportunity/fields/Value_Tier__c.field-meta.xml`
**Typ:** Formelfeld, Text (keine `length` — deploy-validiert, SCRUM-394)
**Basisfeld:** `Amount` (Currency)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Value_Tier__c</fullName>
    <description>Wertstufe offener Verkaufschancen nach Volumen (SCRUM-401): "Hoch" ab 100.000, "Mittel" ab 50.000, "Gering" darunter, "Unbekannt" wenn Amount leer. Formelfeld aus Amount, systemberechnet, read-only.</description>
    <externalId>false</externalId>
    <formula>IF(ISBLANK(Amount),
           &quot;Unbekannt&quot;,
           IF(Amount &gt;= 100000,
              &quot;Hoch&quot;,
              IF(Amount &gt;= 50000,
                 &quot;Mittel&quot;,
                 &quot;Gering&quot;)))</formula>
    <formulaTreatBlanksAs>ErrorIfAnyBlank</formulaTreatBlanksAs>
    <label>Wertstufe</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Text</type>
</CustomField>
```

### 2. Permission Set — FLS für Wertstufe
**Pfad:** `force-app/main/default/permissionsets/SCRUM401_Value_Tier_Read.permissionset-meta.xml`
**FLS:** Read-only auf `Opportunity.Value_Tier__c`; kein Edit.
**Muster:** `Eskalationsstufe__c` (SCRUM-398), `Betreuungsstufe__c` (SCRUM-396), `Customer_Since_Days__c` (SCRUM-382)

```xml
&lt;?xml version="1.0" encoding="UTF-8"?&gt;
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Value_Tier__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM401_Value_Tier_Read</label>
    <description>Read-only FLS für Opportunity.Value_Tier__c (SCRUM-401). Berechtigungsgrundlage: PO-Spezifikation, AC-3. Ohne diesen PermissionSet ist das Feld unsichtbar. Formelfeld - kein Edit möglich.</description>
</PermissionSet>
```

## Architektur-Entscheidungen (ADR)

### ADR-1: Formelfeld statt Picklist
**Entscheidung:** `Value_Tier__c` ist ein Formelfeld vom Typ Text mit vier Wortwerten.

**Begründung:**
- AC1 verlangt, dass die Wertstufe sich automatisch an `Amount` anpasst. Formelfelder berechnen bei jedem Read — kein Trigger, kein Flow, keine Latenz, kein Drift.
- Wortwerte (`Hoch`, `Mittel`, `Gering`, `Unbekannt`) sind UI-lesbar und können direkt in Filter und Reports ohne Mapping genutzt werden.

**Alternativen:**
- *Picklist + Trigger:* Würde zusätzlichen Code, Deploy-Steps und Test-Aufwand erfordern. Formelfeld ist schlanker.
- *Picklist + Flow:* Flows haben in diesem Projekt wiederholt Deploy- oder Schema-Probleme verursacht. Nicht nötig bei reinem Ableitungsbedarf.

### ADR-2: `formulaTreatBlanksAs=ErrorIfAnyBlank`
**Entscheidung:** `ErrorIfAnyBlank` statt `BlankAsZero`.

**Begründung:**
- `Amount` ist ein Currency-Feld. Wenn leer, ist es `null`/`blank`.
- `ISBLANK(Amount)` prüft korrekt, ob das Feld leer ist.
- Bei `BlankAsZero` würde `Amount` als `0` behandelt, was „Unbekannt“ zu „Gering“ ändern würde — das widerspricht AC1.
- `ErrorIfAnyBlank` würde bei einer fehlenden Prüfung einen Fehler auslösen; wegen der `ISBLANK()`-Erwartung ist sicher.

**Hinweis:** Für reine Currency-/Amount-Sicht wird `BlankAsZero` empfohlen, aber hier muss die Leer-Prüfung exakt sein. `ErrorIfAnyBlank` ist konservativ und korrekt, solange die Formel ISBLANK prüft.

### ADR-3: Formellogik und Wertgrenzen
**Entscheidung:**
```
IF(ISBLANK(Amount), "Unbekannt",
   IF(Amount >= 100000, "Hoch",
    IF(Amount >= 50000, "Mittel",
            "Gering")))
```

**Begründung:**
- AC1-Schwellenwerte: ≥ 100.000 = Hoch, 50.000–99.999,99 = Mittel, < 50.000 = Gering.
- Verwende `>=` für untere Grenze, damit exakt 50.000 und exakt 100.000 zur obigen Stufe gehören.
- Die innere Logik prüft zuerst den oberen Wert (≥ 100.000), dann den mittleren (≥ 50.000), sonst Gering. Standard-Kaskade, sparsam.

### ADR-4: Listenansicht „Hochwertige Chancen“
**Pfad:** `force-app/main/default/objects/Opportunity/listViews/Hochwertige_Chancen.listView-meta.xml`
**Typ:** ListView (Opportunity)
**Wichtig:** Repository-beobachtetes Muster für ListView-XML zeigt, dass `<columns>` standardmäßig die API-Felder des Objekts referenzieren und `<filters>` über `<field>` + `<operation>` + `<value>` gesteuert werden.
**Beispiel** aus `Eskalierte_Faelle.listView-meta.xml` (SCRUM-398):

```xml
<columns>CASES.CASE_NUMBER</columns>
<columns>CASES.SUBJECT</columns>
<filters>
  <field>Eskalationsstufe__c</field>
  <operation>equals</operation>
  <value>Kritisch,Erhöht</value>
</filters>
<filterScope>Everything</filterScope>
```

Die Listenansicht enthält:
- **Spalten:** `Name`, `AccountId`, `Amount`, `CloseDate`, `Value_Tier__c`, `OwnerId`
- **Filter 1:** `StageName` `notEqual` → `Closed Won,Closed Lost`
- **Filter 2:** `Value_Tier__c` `equals` → `Hoch`
- **filterScope:** `Everything` (öffentliche Ansicht, sichtbar für die gesamte Organisation gemäß AC2)
- **Label/Name:** `Hochwertige Chancen`

### ADR-5: Permission Set — `SCRUM401_Value_Tier_Read`
**Muster:** Identical to `SCRUM398_Eskalationsstufe.permissionset-meta.xml`.
- `readable=true`
- `editable=false`
- FLS on `Opportunity.Value_Tier__c`

**Begründung:**
- AC3 requires read-only FLS. Formelfelder are inherently read-only; the permission set simply grants visibility.

## Repo-Analyse — ⚠️ Befund

**Opportunity ListView-Verzeichnis:**
The repo has existing object directories but **does not** contain an `Opportunity/listViews/` directory yet. The `force-app/main/default/objects/Opportunity/fields/` directory exists.

A new directory `listViews/` must be created inside `objects/Opportunity/` and a `.listView-meta.xml` file added. This is safe — Salesforce source format supports custom list views under `objects/{ObjectName}/listViews/`.

**Layout Integration:**
The current `Opportunity-Opportunity Layout.layout-meta.xml` (274 lines) contains `Is_Overdue__c` and other Opportunity fields. `Value_Tier__c` is NOT yet present. Per ADR, no layout changes are strictly required for the feature (AC2 uses a list view). However, if the user wants to see the field on the record page, a layout field entry should be added. The design assumes list-view-only use (AC2) and no explicit layout requirement.

If layout integration is later requested, the `layoutColumns` under the „Opportunity Information“ section should gain a `<layoutItems>` block:
```xml
<layoutItems>
  <behavior>Readonly</behavior>
  <field>Value_Tier__c</field>
</layoutItems>
```
but this is **not** mandatory for SCRUM-401.

## Open Decisions (blocken nicht die Implementierung)

- [ ] Should `Value_Tier__c` be added to the Opportunity Layout for inline record viewing? Proposed owner: @devops-agent (Org-level step) or Developer for layout XML.
- [ ] Are there any Sharing Rules or OWD changes required? No impact — formula field uses standard record visibility.

---

**Commit:** `docs/SCRUM-401-design.md` (new file).
**Story:** Assigned to @developer-agent, column **Implementierung**.
**Build instruction:** Developer to implement the three components (field, permission set, list view) in source format. Use the XML snippets as authoritative.
