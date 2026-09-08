# SCRUM-402 — Wertstufe für offene Verkaufschances

**Autor:** architect-agent · **Status:** freigegeben
**Objekt:** Opportunity · **Repo:** `force-app/main/default`
**Bezug:** baut auf SCRUM-401 auf (Feld + Permission Set existieren bereits in der Org)

---

## Ziel
Die Wertstufe `Value_Tier__c` zeigt für Chancen ohne Betrag korrekt „Unbekannt“ (Bug-Fix des bereits gelieferten Feldes), die öffentliche Listenansicht „Hochwertige Chancen“ (nur offene Chancen mit Wertstufe = Hoch, exakt 8 Datensätze) wird erstmals in die Org deployt, und das Feld kommt auf das Opportunity-Layout.

---

## ⚠️ Befund (Org-Read-back, Test-Org `00DWU00000oibVJ2AY`, 2026-09-08)

Verifiziert per `sf data query` + `sf project retrieve start` (Read-back der Org, nicht der Arbeitsdateien):

| Artefakt | Org-Zustand | Befund |
|---|---|---|
| `Opportunity.Value_Tier__c` | deployed, Formel + Logik korrekt | **DEFECT:** deployed mit `formulaTreatBlanksAs=BlankAsZero`; die 2 offenen Chancen mit leerem `Amount` (TEST-DBG, TEST-DBG2) zeigen **„Gering“** statt **„Unbekannt“** → AC1 „leer → Unbekannt“ verletzt |
| `SCRUM401_Value_Tier_Read` (PermissionSet) | deployed | korrekt (bitgenau = spec, `readable=true / editable=false`) |
| `Opportunity.Hochwertige_Chancen` (ListView) | **nicht in der Org** | `sf project retrieve` liefert keine Datei; UI `list-ui/Opportunity` listet nur die 11 Standard-Ansichten. File existiert nur als ungetracktes Local-Artefakt und ist nicht in `origin/master` |
| Opportunity-Layout | `Value_Tier__c` **nicht** enthalten | Story verlangt „auf der Verkaufschance eine Wertstufe sehen“ → Layout-Eintrag nötig |

**Referenzzahlen (live, offene Chancen, 15 gesamt):** Hoch `Amount>=100000` = **8** · Mittel `50000–99999,99` = **2** · Gering `<50000` = **3** · Unbekannt `Amount=null` = **2** (TEST-DBG, TEST-DBG2). Addiert exakt 15 — stimmt mit PO-Tabelle überein. Nach dem Defect-Fix zeigt die Org 2× „Unbekannt“ / 3× „Gering“ (derzeit fälschlich 0 / 5).

**Repo-/Git-Zustand (Teile dieses Builds stehen erst in der geteilten Arbeitshand, nie in `master`):**
- untracked & nicht in `origin/master`: `objects/Opportunity/fields/Value_Tier__c.field-meta.xml`, `objects/Opportunity/listViews/Hochwertige_Chancen.listView-meta.xml`, `permissionsets/SCRUM401_Value_Tier_Read.permissionset-meta.xml`, `manifest/build_401/`
- **nicht meine/der Ticket-Artefakt — unangetastet lassen:** `docs/SCRUM-388-design.md`, `temp-test-lv.xml`, `tmp/` (Probe-/Retrieve-Scraps), `.cline-roles/`

---

## Komponenten

### 1. Bug-Fix `Value_Tier__c` — `formulaTreatBlanksAs`
**Pfad:** `force-app/main/default/objects/Opportunity/fields/Value_Tier__c.field-meta.xml`
**Änderung:** `BlankAsZero` → **`ErrorIfAnyBlank`** (alleinige Änderung an der Datei, Formel + Label unverändert).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Value_Tier__c</fullName>
    <description>Wertstufe offener Verkaufschancen nach Volumen (SCRUM-401/402): "Hoch" ab 100.000, "Mittel" ab 50.000, "Gering" darunter, "Unbekannt" wenn Amount leer. Formelfeld aus Amount, systemberechnet, read-only.</description>
    <externalId>false</externalId>
    <formula>IF(ISBLANK(Amount), &quot;Unbekannt&quot;, IF(Amount &gt;= 100000, &quot;Hoch&quot;, IF(Amount &gt;= 50000, &quot;Mittel&quot;, &quot;Gering&quot;)))</formula>
    <formulaTreatBlanksAs>ErrorIfAnyBlank</formulaTreatBlanksAs>
    <label>Wertstufe</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Text</type>
</CustomField>
```

Warum `ErrorIfAnyBlank` und warum es den `Unbekannt`-Zweig rettet: `ISBLANK(Amount)` ist die **erste** Operation und liefert für leerem `Amount` den Literal `„Unbekannt“` — der leere Wert erreicht nie eine numerische Vergleichsoperation, ergo kein Fehler, sondern der Sentinel-Wert. (Mit `BlankAsZero` wird der Blank vor der Auswertung zu `0` coerced, `ISBLANK` liefert `false`, die Formel fällt durch `>=50000` hindurch in `„Gering“` — genau der beobachtete Defect.) Das ist dasselbe Muster wie `Customer_Since_Days__c` (SCRUM-382, null-guard) und war in `SCRUM-401-design.md` bereits so spezifiziert — die Implementierung ist hier von der spec abgewichen.

### 2. Listenansicht „Hochwertige Chancen“ (Erst-Deploy)
**Pfad:** `force-app/main/default/objects/Opportunity/listViews/Hochwertige_Chancen.listView-meta.xml`
**Finaler Inhalt (autoritativ):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Hochwertige_Chancen</fullName>
    <label>Hochwertige Chancen</label>
    <filterScope>Everything</filterScope>
    <columns>NAME</columns>
    <columns>ACCOUNT.NAME</columns>
    <columns>AMOUNT</columns>
    <columns>CLOSE_DATE</columns>
    <columns>VALUE_TIER__C</columns>
    <columns>CORE.USERS.ALIAS</columns>
    <filters>
        <field>StageName</field>
        <operation>notEqual</operation>
        <value>Closed Won,Closed Lost</value>
    </filters>
    <filters>
        <field>Value_Tier__c</field>
        <operation>equals</operation>
        <value>Hoch</value>
    </filters>
</ListView>
```

- `filterScope=Everything` + `notEqual Closed Won,Closed Lost` → nur offene Chancen (geschlossene fallen raus, unabhängig vom Betrag — AC2).
- Zweiter Filter `Value_Tier__c equals Hoch` → nur die Wertstufe Hoch. Zusammen = **exakt 8** Datensätze in der Test-Org.
- Spalten entsprechen dem AC (Name, Konto, Betrag, Abschlussdatum, Wertstufe, Inhaber).
- House-Pattern: `Case/Eskalierte_Faelle.listView-meta.xml` (SCRUM-398).
- ⚠️ **Kein `temp-test-lv.xml`-Drift:** das Probe-Artefakt in der Arbeitshand hat andere Spalten (`AccountName`, `AccountId`, `OPPORTUNIT.NAME`, Filter `notEqual Closed`). Es wird **nicht** Teil des Builds — die oben stehende Datei ist maßgeblich.

### 3. Permission Set — bereits korrekt, nur in den Build nehmen
**Pfad:** `force-app/main/default/permissionsets/SCRUM401_Value_Tier_Read.permissionset-meta.xml`
Keine inhaltliche Änderung (Org-Bestand ist korrekt). Muss nur in den Build-Manifest + den commit, damit der Repo-Stand mit deployt wird (aktuell untracked / nicht in `master`).

### 4. Layout-Integration — `Wertstufe__c` Sichtbar auf der Verkaufschance
**Pfad:** `force-app/main/default/layouts/Opportunity-Opportunity Layout.layout-meta.xml`
**Einfügepunkt:** zweite `layoutColumns` des Sections „Opportunity Information“, direkt **nach** dem bestehenden `Is_Overdue__c`-`layoutItems`-Block (Zeile ~70–73), read-only:

```xml
<layoutItems>
    <behavior>Readonly</behavior>
    <field>Value_Tier__c</field>
</layoutItems>
```

Readonly, weil das Feld systemberechnet ist (AC: kein Edit). Damit ist die Wertstufe — neben der Listenansicht — auch auf dem Record sichtbar („auf der Verkaufschance … sehen“).

### 5. Build-Manifest (konsolidiert)
**Pfad:** `manifest/build_402/package.xml` (ersetzt `build_401`, das nicht in `master` ist)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Opportunity.Value_Tier__c</members>
        <name>CustomField</name>
    </types>
    <types>
        <members>SCRUM401_Value_Tier_Read</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>Opportunity.Hochwertige_Chancen</members>
        <name>ListView</name>
    </types>
    <types>
        <members>Opportunity-Opportunity Layout</members>
        <name>Layout</name>
    </types>
    <version>61.0</version>
</Package>
```

**Deploy-Reihenfolge (House-Pattern `manifest/*phase1/phase2*` hier unnötig, da ein Feld bereits deployed ist):** ein einzelner `sf project deploy` mit diesem Manifest genügt — das Feld existiert, die Änderung ist eine In-Place-Aktualisierung des `formulaTreatBlanksAs`. Nach dem Deploy: `sf project retrieve start --manifest manifest/build_402/package.xml --target-org Test-Org` als Read-back-Vergleich.

---

## Architektur-Entscheidungen (ADR)

1. **Live-Berechnung = Formelfeld, kein Trigger/Flow (bestätigt & defektfrei gehalten).** AC1 verlangt „folgt dem aktuellen Betrag, ohne dass jemand nachträgt“. Ein read-only Formelfeld berechnet bei jedem Read — kein DML, keine Latenz, kein Drift, keine Governor-Limit-Risiken (kein SOQL, keine Bulk-Logik). Der SCRUM-401-Befund „Formel geht nicht wegen leerem Amount“ ist falsch: `ISBLANK` + `ErrorIfAnyBlank` löst den Leer-Zweig korrekt (dieses Ticket behauptet und fixt es). ADR-Flow-vs-Apex: declarative wins, kein Apex nötig.
2. **`formulaTreatBlanksAs=ErrorIfAnyBlank` ist der Defect-Fix, keine Neugestaltung.** Die Org hat `BlankAsZero` deployed, das `ISBLANK` zunichte macht. Rückkehr auf den in `SCRUM-401-design.md` spezifizierten Wert. Einzige Feld-Änderung, minimale Blase.
3. **ListView: public (`filterScope=Everything`), Filter über das PS-gated Feld.** Siehe offener Punkt O1 — die Interaction von „org-weit sichtbar“ (AC2) und „ohne PS unsichtbar“ (AC3) ist ein bewusstes Design, kein Zufall.
4. **FLS via Permission Set, kein Profile-Edit** (House-Pattern SCRUM321/327/382/398). `SCRUM401_Value_Tier_Read` bleibt read-only.
5. **Layout: Feld read-only in „Opportunity Information“.** Kein Apex/LWC; reiner Layout-Eintrag auf dem Standard-Layout.

## Governor-Limits / Bulkification
Keine Risiken — reine deklarative Metadaten (ein read-only Formelfeld, eine ListView, ein Layout-Eintrag, ein bereits vorhandenes Permission Set). Kein Trigger, kein Apex, kein SOQL, kein Flow.

## Flow apiVersion / Naming
Kein Flow. Naming: Feld `Value_Tier__c` (API) / Label „Wertstufe“, ListView `Hochwertige_Chancen` / Label „Hochwertige Chancen“, PermissionSet unverändert. `<columns>`-Token sind uppercase API-Namen (House-Pattern ListView-XML).

## Tests (PR-Gate, House-Pattern `SCRUM396Betreuungsstufe*`)
- **Value-Test** (Formellogik), shape `SCRUM39xWertstufeTest.cls`: je Datensatz über die vier Schwellen — `Amount=null` → **`Unbekannt`** (dieser Fall ist der Re-Regression-Guard gegen `BlankAsZero`), `15000` → Gering, `50000` → **Mittel** (untere Grenze inclusive), `99999.99` → Mittel, `100000` → **Hoch** (untere Grenze inclusive), `250000` → Hoch; plus „Amount ändert sich → Wertstufe ändert sich“ via DML-Update.
- **FLS-Test**, shape `SCRUM39xWertstufeFlsTest.cls`: mit `SCRUM401_Value_Tier_Read` → `Schema.describeSObject(...).isAccessible()` für `Value_Tier__c` = true; ohne PS (andere User/ohne Assign) → false.
- **Apex-Test-Limit:** `manifest/scrum402-apextests.xml` (House-Pattern `phase3-apextests`) mit nur diesen neuen Klassen; `sf project deploy --test-level RunSpecifiedTests`.
- **ListView „genau 8“:** kein Apex möglich gegen eine ListView — **E2E / Org-Verifikation** (shape `tests/**`-E2E): als PS-haltender Sales-Manager-User die Ansicht „Hochwertige Chancen“ öffnen, Row-Count = 8, geschlossene Chancen nicht dabei. Zusätzlich SOQL-Sanity: `SELECT COUNT() FROM Opportunity WHERE StageName NOT IN ('Closed Won','Closed Lost') AND Amount>=100000` → 8.

---

## Offene Punkte (blocken die Implementierung NICHT)

- **O1 — AC2 „org-weit sichtbar“ vs. AC3 „ohne PS unsichtbar“ (Interaction, bewusst so designed):** Eine public Object-ListView (`filterScope=Everything`) ist jedem User im ListView-Dropdown **sichtbar** (das ist „org-weit sichtbar“ = AC2). Die **Werte** der Spalte `Wertstufe__c` und der Filter darauf sind nur für User lesbar, die `Value_Tier__c`-FLS haben, d. h. die `SCRUM401_Value_Tier_Read` haben (AC3). Konsequenz: ein Sales-Manager **mit** PS sieht die 8 Zeilen mit Werte; ein User **ohne** PS sieht den Ansichts-Eintrag, aber die `Wertstufe`-Spalte ist für ihn leer/versteckt. **→ @tester-agent:** „exakt 8 Datensätze“ als PS-haltenden User verifizieren (nicht ohne PS); @devops-agent: sicherstellen, dass das PS den Ziel-Users (Vertriebsleitung) zugewiesen wird (Org-Schritt, kein Repo-Artefakt).
- **O2 — Repo-Drift / Git-Hygiene (Aus `PR #81` „drei Lehren“):** Die SCRUM-401-Artefakte (Feld, ListView, PS, `build_401`) stehen **nur in der geteilten Arbeitshand** und sind nicht in `origin/master` bzw. wurden auf `master` geschrieben statt einem Feature-Zweig. **→ @developer-agent:** SCRUM-402 auf **einem eigenen Feature-Branch** bauen und die drei oben genannten Artefakte + Layout + `build_402` + Tests + dieses Design-Doc als **ein kohärenter PR** mit expliciten Pfaden committen (kein `git add .`). Stale-Artefakte (`temp-test-lv.xml`, `tmp/`, `docs/SCRUM-388-design.md`) **nicht** committen, **nicht** löschen.
- **O3 — Lightning-Page vs. Classic-Layout:** Das Repo tracked nur das Classic `Opportunity-Opportunity Layout.layout-meta.xml`. Falls die Ziel-User Lightning-FlexiPages nutzen, ist die Feldplatzierung dort ein App-Builder-Schritt in der Org (kein Repo-Artefakt). **→ @devops-agent** (non-blocking, auf Anfrage).

---

**Autoritative Build-Spec:** dieses Doc (`docs/SCRUM-402-design.md`). Die Jira-Kommentare sind Kurzform; bei Abweichungen gelten die XML-Blöcke hier + die Repo-Dateien.
**Handoff:** Story geht an **@developer-agent**, Spalte **Implementierung**.
