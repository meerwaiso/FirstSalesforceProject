# SCRUM-431 — Wartungsvertrag am Kunden: Anzeige auf dem Fall + Morgen-Übersicht

Autoritative Build-Spec für den Developer-Agent. Repo-Ursprung: `origin/master` @ `260b786` (DevOps/SCRUM-430, 2026-09-25).

## Ziel
Ein Kunde (Account) trägt ein Ja/Nein „Wartungsvertrag"; dies ist read-only auf dessen Cases sichtbar (cross-object, ohne zum Account zu wechseln) und in einer sortier- und filterbaren Morgen-Übersicht der offenen Fälle dieser Vertragskunden — reine Sichtbarkeit, keine Autos.

---

## Komponenten (konkrete Pfade)

1. **Account-Feld** `force-app/main/default/objects/Account/fields/Wartungsvertrag__c.field-meta.xml` (Checkbox)
2. **Case-Anzeige-Feld** `force-app/main/default/objects/Case/fields/Wartungsvertrag_Anzeige__c.field-meta.xml` (Cross-Object-Formul-Feld, Text, read-only)
3. **Morgen-Übersicht** `force-app/main/default/reports/Service/Morgen_UEbersicht_Vertragskunden.report-meta.xml` (Tabular-Report, ReportType `CaseList`)
4. **Permission Set Service-Team** `force-app/main/default/permissionsets/SCRUM431_Wartungsvertrag_ServiceTeam.permissionset-meta.xml`
5. **Permission Set Teamleitung** `force-app/main/default/permissionsets/SCRUM431_Wartungsvertrag_Teamleitung.permissionset-meta.xml`
6. **Layout-Integration Account** `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml` (+ die Variante, die Service-User rendern: `Account-Account %28Support%29 Layout.layout-meta.xml`)
7. **Layout-Integration Case** `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` (neue Read-Only-Sektion)
8. **Manifest** `manifest/scr431-wartungsvertrag.xml` (alle 1–5 + beide Layouts oben)

---

## Exakte Artefakte

### 1. Account-Feld (Checkbox, Default Nein)

House-Form: `Is_Inactive__c` (nur `fullName/label/description/defaultValue/type`, kein `length`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Wartungsvertrag__c</fullName>
    <label>Wartungsvertrag</label>
    <description>Kunden-Attribut (SCRUM-431): Ja = Kunde hat einen Wartungsvertrag und dementsprechend ein schnelleres Reaktionsversprechen. Gilt für ALLE Fälle dieses Kunden. Default Nein. Nur Teamleitung editiert (FLS via PS); Service-Team read-only.</description>
    <defaultValue>false</defaultValue>
    <type>Checkbox</type>
</CustomField>
```

### 2. Case-Anzeige-Feld (Cross-Object-Formel, Ja/Nein als Text)

Declarative Cross-Object-Formel auf `AccountId`. **Typ = Text-Formel mit `required=false`, `trackTrending=false` und KEINEM `length`** (deploy-validiertes House-Shape, SCRUM-394). Formel liefert Wort-Werte `Ja`/`Nein` — entspricht exakt der AC-Wortung („Wartungsvertrag: Ja / Nein sichtbar").

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Wartungsvertrag_Anzeige__c</fullName>
    <label>Wartungsvertrag (Kunde)</label>
    <description>SCRUM-431: Read-only-Anzeige, abgeleitet vom zugehörigen Account (Kunde). Leitet sich live vom Account.Wartungsvertrag__c ab; nicht editierbar, kein Write.</description>
    <formula>IF( Account.Wartungsvertrag__c , &quot;Ja&quot; , &quot;Nein&quot; )</formula>
    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

Hinweis für den Developer: Die Formel referenziert das Account-Feld über den lookup-namen `AccountId` → `Account.Wartungsvertrag__c`. `formulaTreatBlanksAs` ist bei boolean-Quellwerten irrelevant, wird aber vom Validator erwartet; `unique=false` + `required=false` sind Pflicht-Attribute für Text-Formeln. **Nichts davon raten**: falls der Validator etwas anderes erwartet, nach dem House-Shape `Lead.Data_Quality__c` (SCRUM-394) korrigieren.

### 3. Morgen-Übersicht (Tabular-Report, CaseList)

House-Form: `reports/Sales/Lead_Nachfassliste` (Tabular + Filter auf Custom-Feld) und `reports/Service/Ueberfaellige_Faelle` (Tabular/Summary + `criteriaItems`). Format = `Tabular` (Liste, keine Gruppierung).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns><field>CASE_NUMBER</field></columns>
    <columns><field>&lt;ACCOUNT-NAME-COLUMN&gt;</field></columns>
    <columns><field>SUBJECT</field></columns>
    <columns><field>&lt;OFFEN-SEIT-COLUMN&gt;</field></columns>
    <filter>
        <criteriaItems>
            <column>Account.Wartungsvertrag__c</column>
            <operator>equals</operator>
            <value>1</value>
        </criteriaItems>
        <criteriaItems>
            <column>IsClosed</column>
            <operator>equals</operator>
            <value>0</value>
        </criteriaItems>
    </filter>
    <format>Tabular</format>
    <name>Morgen_UEbersicht_Vertragskunden</name>
    <reportType>CaseList</reportType>
</Report>
```

**Spalten + Filter-Spalten per Analytics-API bestimmen, nicht raten** (Rule: `salesforce-describe-first`). Befehl für den Developer:
`sf api request rest /services/data/v62.0/analytics/reportTypes/CaseList`
gibt je Spalte API-Name + Label + Typ. Die Platzhalter so auflösen:

| Platzhalter | Gewünschte Bedeutung | Erwarteter Kandidat (zu verifizieren!) |
|---|---|---|
| `<ACCOUNT-NAME-COLUMN>` | Kunde (Name des verknüpften Accounts) | `ACCOUNT` (CaseList standardmäßig) — verifizieren |
| `<OFFEN-SEIT-COLUMN>` | Alter/Eröffnungsdatum des Falls | `CREATED_DATE` (Datum, sortierbar) bzw. `AGE_NUMBER` (Tage als Zahl) |
| Filter `IsClosed` | „offen" = nicht abgeschlossen/geschlossen | `IsClosed` (Case-Standardfeld, boolean) — verifizieren |

- **Sortierung älteste zuerst**: im Report auf `<OFFEN-SEIT-COLUMN>` aufsteigend sortieren. Bei `CREATED_DATE`: `<groupingsDown><field>CREATED_DATE</field><sortOrder>Asc</sortOrder></groupingsDown>` (Tabular: Sorting-Element analog; House-Shape `groupingsDown` FLAT, NICHT verschachtelt). Falls `AGE_NUMBER` verwendet wird, Asc auf dem Number-Feld. Die endgültige Sort-Darstellung (Datum vs. Alter-Tage) wählt der Developer an der AC „offen seit (Alter des Falls)" aus — beides erfüllt; Datum ist lesbarer, Alter-Tage ist kürzer.
- **Warum `IsClosed` und nicht Status-Liste**: PO definiert „Offen = jeder nicht abgeschlossene/geschlossene Fall-Status". `IsClosed=False` deckt das Status-agnostisch ab, ohne je einen Status-Wert zu hard-coden (vermeidet die SCRUM-398 „Priority High existiert gar nicht"-Kopplung an einen konkreten Wert).

### 4. Permission Set — Service-Team

House-Form `SCRUM421_Zuordnung`: explizite `fieldPermissions`, `editable`/`readable` pro Feld, KEIN Objekt-CRUD.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>SCRUM-431: Service-Team. Read Account.Wartungsvertrag__c, Read Case.Wartungsvertrag_Anzeige__c (read-only). Kein Edit, kein Objekt-CRUD.</description>
    <fieldPermissions>
        <editable>false</editable>
        <field>Account.Wartungsvertrag__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Case.Wartungsvertrag_Anzeige__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM431_Wartungsvertrag_ServiceTeam</label>
</PermissionSet>
```

### 5. Permission Set — Teamleitung

Unterschied nur beim Account-Feld: **Edit**. Das Case-Anzeige-Feld bleibt read-only (es ist ein Formel-Feld, Write ist physikalisch ausgeschlossen; explizit `editable=false` hält).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>SCRUM-431: Teamleitung. Read+Edit Account.Wartungsvertrag__c, Read Case.Wartungsvertrag_Anzeige__c (read-only).</description>
    <fieldPermissions>
        <editable>true</editable>
        <field>Account.Wartungsvertrag__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Case.Wartungsvertrag_Anzeige__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM431_Wartungsvertrag_Teamleitung</label>
</PermissionSet>
```

FLS-Design vollständig gegen die CRUD/FLS-Tabelle des Tickets abgedeckt:
- Account.Wartungsvertrag__c: Service Read (PS1), Teamleitung Read+Edit (PS2) ✓
- Case.Wartungsvertrag_Anzeige__c (abgeleitet): Read-only für beide, kein Write ✓
- **Kein Profile-Edit, nur Permission Sets** ✓ (House-Regel)
- FLS wird pro Feld explizit grantet — NICHT von Objekt-CRUD „vererbt" (FLS erbt nie) ✓

### 6. Layout-Integration — Account

`force-app/main/default/layouts/Account-Account Layout.layout-meta.xml` (und die Support-Variante, die Service-User rendern): ein `<layoutItems>` mit `<behavior>Edit</behavior>` + `<field>Wartungsvertrag__c</field>` in die passende Sektion (z. B. „Additional Information" / eine eigene kleine Sektion „Vertrag"). Behavior `Edit` ist korrekt, weil die **Bearbeitbarkeit über FLS** gesteuert wird (Service-Team `editable=false` → zeigt es read-only; Teamleitung `true` → editierbar). Nicht pro-User hard-coden.

> Developer: prüfe, welches Account-Layout die Service-Profile/Teamleitung rendert (Default vs. `Account (Support)`), und lege das Feld dort an. Minimum: das Layout, das im Normalfall die Service-User sehen.

### 7. Layout-Integration — Case Record

`force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` — **neue Read-Only-Sektion**, exakt House-Muster SCRUM-420/421/424 (jede eigene Sektion, `customLabel=true`, `detailHeading=true`, `style=OneColumn`), bewusst vor „System Information" platziert:

```xml
<!-- SCRUM-431: Wartungsvertrag (Kunde) — read-only, abgeleitet vom Account. -->
<layoutSections>
    <customLabel>true</customLabel>
    <detailHeading>true</detailHeading>
    <editHeading>true</editHeading>
    <label>Wartungsvertrag</label>
    <layoutColumns>
        <layoutItems>
            <behavior>Readonly</behavior>
            <field>Wartungsvertrag_Anzeige__c</field>
        </layoutItems>
    </layoutColumns>
    <style>OneColumn</style>
</layoutSections>
```

> ⚠️ Lightning-Record-Page (FlexiPage) Platzierung = Org-Schritt (devops). Repo trägt dieses `Case-Case Layout`. Das ist exakt so, wie SCRUM-420/421/424 geliefert haben.

### 8. Manifest — `manifest/scr431-wartungsvertrag.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Wartungsvertrag__c</members>
        <name>CustomField</name>
    </types>
    <types>
        <members>Wartungsvertrag_Anzeige__c</members>
        <name>CustomField</name>
    </types>
    <types>
        <members>SCRUM431_Wartungsvertrag_ServiceTeam</members>
        <members>SCRUM431_Wartungsvertrag_Teamleitung</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>Service/Morgen_UEbersicht_Vertragskunden</members>
        <name>Report</name>
    </types>
    <types>
        <members>Account-Account Layout</members>
        <members>Case-Case Layout</members>
        <name>Layout</name>
    </types>
    <version>62.0</version>
</Package>
```

(Version = aktueller Org-API des Targets; Developer an die Test-Org-API ausrichten. Layout-`members` = Layout-LABEL ohne Dateiendung; bei der Support-Layout-Variante entsprechend ergänzen.)

---

## Architektur-Entscheidungen

1. **Case-Anzeige = Cross-Object-Formel-Feld, kein Rollup, kein Trigger, kein gespeicherter Wert.**
   - „Abgeleitet vom verknüpften Account, read-only, 1:1" ist ein klassisches parent→child Cross-Object-Formel-Szenario. Rollup wäre Aggregation child→parent (Zählen/Summen) — passt hier nicht (es gibt kein „mehrere Cases" zu aggregieren, nur „dieser Account hat Ja/Nein").
   - Formel-Feld ist **dynamisch**: wird bei jedem Lesen neu berechnet → ein später auf `Ja` gesetzter Account ändert alle bestehenden Cases sofort, ohne Rebuild/Batch. Damit entfällt die SCRUM-417 „Bestandsdaten bleiben NULL"-Problematik komplett; kein *Rebuilder*-Klasse nötig.
   - **Kein Apex, kein Flow** → kein Governor-Limit-Risiko, nichts, was beim Deploy/Schema-Validierung scheitern kann. Default-Regel „Apex vor Flow" greift hier nicht, weil die deklarative Lösung die sauberste ist (keine Verzweigung, keine Bulk-Logik, keine Evolution erwartet — reine Sichtbarkeit).
2. **Morgen-Übersicht = Tabular-Report (keine ListView, kein Apex).** ListView filtert nicht zuverlässig auf dem **verwandten** Account-Feld und sortiert nicht auf „offen seit". Report (CaseList) kann cross-object filtern (`Account.Wartungsvertrag__c`), filtern auf `IsClosed=False`, Spalten auswählen und sortieren — deckt die „sortier- und filterbare Liste" exakt ab. Reuse House-Reports `Lead_Nachfassliste` / `Ueberfaellige_Faelle`.
3. **„Offen" als `IsClosed=False`, nicht als Status-Whitelist.** PO: „jeder nicht abgeschlossene/geschlossene Fall-Status" → `IsClosed` ist Status-agnostisch und koppelt an keinen konkreten Status-Wert (vermeidet SCRUM-398-Fehlerklasse „wählt einen Wert aus, der 0 Records matcht").
4. **FLS via 2 Permission Sets, explizit pro Feld, kein Objekt-CRUD, kein Profile-Edit.** House-Regel; Case-Anzeige-Feld read-only in beiden PS (kein Write) — explizit, nicht „vererbt".
5. **Ja/Nein als Text-Formel („Ja"/„Nein") statt Checkbox-Formel.** Die AC formulieren wörtlich „Wartungsvertrag: Ja / Nein sichtbar" — Text liefert genau diese Wortwerte, im Read-only-Kontext unmissverständlich; Checkbox-Formeln rendern als Haken ohne Label.
6. **Sharing-Modell: keine Änderung.** Das Feld ist ein Attribut des Accounts; bestehende Account-Sharing-/OWD-Regeln gelten unverändert. Sichtbarkeit läuft ausschließlich über die zwei Permission Sets (FLS). Kein Sharing-Rule, keine OWD-Änderung, keine OWD-Profile-Edit — exakt PO-Forderung.

---

## Governor-Limit-Risiken

**Keine.** Keine Apex-Klasse, kein Trigger, kein Flow. Ein deklaratives Cross-Object-Formel-Feld und ein Report stoßen an keine Governor Limits. Die Default-Regel „Apex über Flow für nicht-triviale Logik" ist hier irrelevant, weil die Logik trivial ist (ein IF auf einem boolean) und deklarativ am saubersten abbildbar. Bulk- / SOQL-in-Loop-Risiko: ausgeschlossen, da kein dazwischenliegendes Code.

---

## Flow apiVersion / Naming-Konvention

Kein Flow in dieser Story. N/A. (Für künftige Erweiterungen: v62.0, Haus-Pfade `force-app/main/default/flows/`, Namenskonvention `<SCRUM>-<Kurzname>`.)

---

## Offene Punkte (blockieren die Implementierung NICHT)

- [ ] **Exakte Report-Spalten-/Sort-Kolumnen-Namen über Analytics-API bestätigen** (ReportType `CaseList`). Platzhalter `<ACCOUNT-NAME-COLUMN>` und `<OFFEN-SEIT-COLUMN>` sind in der Build-Spec als Kandidaten benannt; der Developer führt `sf api request rest /services/data/v62.0/analytics/reportTypes/CaseList` aus, setzt die Werte ein und belegt in der Handoff-Kommentar die gewählten Namen. (Owner: @developer-agent, 2 Minuten Aufwand beim ersten Commit.)
- [ ] **Welches Account-Layout die Service-User rendert — Default oder Support-Variante.** Developer prüft kurz im Org/Profile, legt das Feld dort an und nennt es im Commit. Minimum-Abdeckung: das Layout, das die Service-User tatsächlich sehen. (Owner: @developer-agent.)
- [ ] **Lightning-Record-Page (FlexiPage) Platzierung des Case-Felds** — Org-Schritt im App Builder; Repo trägt das Classic-Layout `Case-Case Layout`. Tester verifiziert beide Oberflächen (Classic-Layout per Repo, Lightning per App-Builder/Screenshot). (Owner: @devops-agent für App-Builder-Platzierung, @tester-agent für Verifikation.)

---

## ⚠️ Relevanter Befund (Repo-Analyse)

- Das Repo trackt **Classic-Layouts** (`Case-Case Layout.layout-meta.xml`) als aktives Case-Detail-Vehicle — jede jüngere Story (420/421/424) hat dort ihre Read-Only-Sektion ergänzt. Die Lightning-Record-Page (FlexiPage) liegt NICHT im Repo; dort ist die Platzierung ein App-Builder-Org-Schritt. Genau so wie SCRUM-420/421/424 geliefert.
- Der Account hat **4 Layout-Varianten** im Repo (Default, Marketing, Sales, Support). Die Case-Anzeige-Funktion braucht das, was die Service-User im Normalfall sehen — der Developer legt es auf dem korrekt rendertenden Layout an (Open Punkt oben). Minimum ist erfüllt, sobald das Service-typische Account-Layout das Feld trägt.
- **Report-Spaltennamen für `CaseList` sind NICHT geraten** in der Build-Spec: `<ACCOUNT-NAME-COLUMN>` und `<OFFEN-SEIT-COLUMN>` sind markierte Platzhalter mit Kandidaten; der Developer bestimmt sie verbindlich per Analytics-API (`sf api request rest .../reportTypes/CaseList`) und belegt die Werte im Commit. `IsClosed` ist das standardmäßige Case-Boolean, aber auch hier gilt: per `sf sobject describe -s Case` bestätigen, falls der Validator meckert.

---

## Mandatory Pre-Handoff Checklist

- [x] Datenmodellanänderungen dokumentiert (Account-Wartungsvertrag__c Checkbox; Case-Wartungsvertrag_Anzeige__c Text-Formel)
- [x] Permission-Set-/FLS-Design dokumentiert (2 PS, explizit pro Feld, kein CRUD/Profile)
- [x] Sharing-Modell-Impact dokumentiert (kein Impact, explizit ADR-6)
- [x] Governor-Limit-Risiken dokumentiert (keine — deklarativ)
- [x] Flow apiVersion/Naming spezifiziert (N/A, kein Flow)

Autoritative Build-Spec: `docs/SCRUM-431-design.md` (Commit folgt).
Story wird an @developer-agent übergeben.