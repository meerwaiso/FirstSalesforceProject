# SCRUM-382 — „Kunde seit (Tage)" auf Account Layout · Authoritative Build-Spec

> **This file is the source of truth for the exact XML and API names.**
> The Jira comments (SCRUM-382) are mangled by Jira's markdown converter
> (double underscores → bold, closing XML tags dropped — verified on this
> project 2026-08-30, re-confirmed 2026-08-31/09-01). Build the files from
> THIS doc, cross-check against the in-repo reference files named below.
> Do not copy names out of the Jira comment.

## Goal
Auf dem Layout „Account Layout" zeigt das neue Formelfeld „Kunde seit (Tage)"
die Anzahl ganzer Tage seit der Anlage des Accounts; bei heute angelegtem
Account steht 0.

## Branch
`feature/SCRUM-382-customer-since-days` frisch von `master` abziehen.
Geteilter Tree: `.cline-roles/` und `scr378-report-final.zip` liegen untracked —
weder commiten noch löschen, nur explizit eigene Pfade stageen.

## ADR

### ADR-1: Deklaratives Formelfeld — kein Apex, kein Trigger, kein Flow
`Kunde seit (Tage)` ist eine reine, auf jeden Read neu berechnete Tagesdifferanz
aus dem Systemfeld `CreatedDate`. Es gibt keinen Zustand, keinen Bulk-Kontext,
keine ÄNDER-LOGIK und keine Abhängigkeit von anderen Objekten:
- **Formelfeld** wird beim Lesen live errechnet → der Wert veraltet nie,
  governor-limit-frei, ohne Deploy-Zeitfenster.
- Apex/Trigger wäre hier Over-Engineering (kein Persistierungsbedarf,
  kein Schreibpfad). Flow wäre der dokumentiert problematische Weg
  (Schema-Drift / apiVersion) für einen Use Case ohne Logik.
→ Deklarativ (Formelfeld) ist die einzig saubere Option für diese Anforderung;
  die Apex-over-Flow-Default-Regel greift, weil Apex hier schlicht nicht nötig ist.

### ADR-2: FLS via Permission Set (House-Pattern SCRUM-318/319/321/365)
Read=true, editable=false, `hasActivationRequired=false`, Label+Description im
PS selbst. Profile bleiben unverändert (Out-of-Scope: „keine
Berechtigungssteuerung" heißt: für alle sichtbar → PS in der Org allen
Benutzern zuweisen, @devops-agent-Follow-up, blockt nicht).
Formelfelder sind ohnehin nicht benutzereditierbar; `editable=false`
dokumentiert das explizit.

### ADR-3: Exakt-ganzzahlige Tagesdifferanz über `DATEVALUE`
Formel `TODAY() - DATEVALUE(CreatedDate)`:
- `DATEVALUE(CreatedDate)` streicht die Uhrzeit ( DateTime → Datum um Mitternacht),
  daher ist das Ergebnis eine exakte ganze Tagezahl ohne Zeitbruch.
- **AC „heute → 0" deterministisch:** ein Account, heute um 07:00 ODER 23:00
  angelegt, liefert `TODAY() - TODAY() = 0`.
  (Ohne `DATEVALUE` wäre `TODAY() - CreatedDate` ein Dezimalwert mit
  Zeitbruch; ein 23:00-Uhr-Neuantrag würde als 1 gerundet erscheinen → AC-Fehler.)

## Komponenten

1. **Formelfeld (neu, Phase 1):**
   `force-app/main/default/objects/Account/fields/Customer_Since_Days__c.field-meta.xml`
   — Repo hat aktuell KEINE `objects/Account/`-Struktur (kein Account-Object-Meta);
   das leere Verzeichnis `objects/Account/fields/` entsteht mit dieser Datei.
   Einzige Komponente der Phase 1 — wird ZUERST deployed, weil Layout/PS darauf
   referenzieren. Referenzstil: `objects/Lead/fields/Is_Due__c.field-meta.xml`.

2. **Layout-Integration (Phase 2):**
   `force-app/main/default/layouts/Account-Account Layout.layout-meta.xml`
   — Section „Additional Information" (zweite `<layoutColumns>`, nach dem
   `UpsellOpportunity__c`-Item, vor `</layoutColumns>`). Readonly.
   Die anderen drei Account-Layouts (Sales, Marketing, Support) bleiben
   **byte-identisch** (Out-of-Scope) — git diff darf nur diese eine
   Layoutdatei zeigen.

3. **FLS-Permission Set (Phase 2):**
   `force-app/main/default/permissionsets/SCRUM382_CustomerSinceDays.permissionset-meta.xml`
   — Referenzstil: `SCRUM365_OpenCasesCount.permissionset-meta.xml`.

4. **Deploy-Set (House-Pattern, Manifeste je Phase):**
   `manifest/scr382-phase1-fields.xml` und `manifest/scr382-phase2-referencing.xml`
   — Referenzstil: `manifest/scr381-phase1-fields.xml` /
   `manifest/scr381-phase2-referencing.xml`, `<version>67.0</version>`.

## Exakte XML

### 1. Formelfeld `Customer_Since_Days__c`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Customer_Since_Days__c</fullName>
    <label>Kunde seit (Tage)</label>
    <description>Anzahl ganzer Tage seit der Anlage des Accounts (SCRUM-382). Formelfeld, systemberechnet, read-only: TODAY() - DATEVALUE(CreatedDate). Heute angelegter Account = 0.</description>
    <type>Number</type>
    <precision>10</precision>
    <scale>0</scale>
    <unique>false</unique>
    <formula>TODAY() - DATEVALUE(CreatedDate)</formula>
</CustomField>
```

- API-Name `Customer_Since_Days__c` (House-Konvention: englischer API-Name),
  Label exakt **„Kunde seit (Tage)"** wie vom User vorgegeben.
- Number(10,0) — ganzzahlig, kein `&lt;`, keine Escape-Falle im XML.
- Formel validiert als Function-Fundament ohne `AND`/`OR` — keine
  Infix-AND-Falle (die bekannte Salesforce-Formula-Syntax-Gefahr).

### 2. Layout-Eintrag (einzige Änderung an der Layoutdatei)

In `Account-Account Layout.layout-meta.xml`, Section „Additional Information",
zweites `<layoutColumns>`, nach dem `UpsellOpportunity__c`-Block:

```xml
            <layoutItems>
                <behavior>Readonly</behavior>
                <field>Customer_Since_Days__c</field>
            </layoutItems>
```

### 3. Permission Set `SCRUM382_CustomerSinceDays`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Account.Customer_Since_Days__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM382_CustomerSinceDays</label>
    <description>Read-only FLS für Account.Customer_Since_Days__c (SCRUM-382). Formelfeld (systemberechnet) - kein User-Edit. PO-Festlegung: für alle sichtbar, daher PS allen Benutzern zuweisen, Profile unverändert.</description>
</PermissionSet>
```

### 4. Manifest `manifest/scr382-phase1-fields.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-382 Phase 1: nur das neue Formelfeld (wird ZUERST deployed, da Layout/PS darauf referenzieren). -->
    <types>
        <members>Account.Customer_Since_Days__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```

### 5. Manifest `manifest/scr382-phase2-referencing.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-382 Phase 2: referenzierende Komponenten (gelangen ERST NACH Phase 1). -->
    <types>
        <members>SCRUM382_CustomerSinceDays</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>Account-Account Layout</members>
        <name>Layout</name>
    </types>
    <version>67.0</version>
</Package>
```

## Sharing / Governor Limits
- **Sharing:** keine Änderung — Formelfeld ohne eigene Sharing-Logik, folgt
  dem Account. Keine Sharing-Rules, keine OWD-Änderung.
- **Governor Limits:** nicht relevant — kein Apex, kein Trigger, keine
  Flow-Elemente, keine SOQL. Formelfeld wird pro Read berechnet.

## Datenmodell
- 1 neues Feld: `Account.Customer_Since_Days__c` (Formula-Number, read-only).
- 1 neue Permission Set: `SCRUM382_CustomerSinceDays`.
- 1 Layout gechanged: `Account-Account Layout` (ein Readonly-Item).
- Keine Record-/Field-Art-Typ-Änderung, keine Beziehungen, kein Objekt-Meta.

## Technische Acceptance-Kriterien (zusätzlich zu den PO-AC)
- [ ] `Customer_Since_Days__c` ist Number(10,0), Read-only, Formel
      `TODAY() - DATEVALUE(CreatedDate)` — verifiziert per
      `sf query`/describe in der Test-Org nach Phase-1-Deploy.
- [ ] **AC „heute → 0" deterministisch belegt:** Test-Accounts, heute um
      zwei Morgen-unterschiedene Uhrzeiten (je >1h Abstand) angelegt,
      zeigen beiderseits 0 — nicht nur 1 Probe um Mitternacht nah.
- [ ] Feld Readonly auf „Account Layout" (Additional Information); die
      anderen drei Account-Layouts sind byte-identisch (git diff).
- [ ] PS `SCRUM382_CustomerSinceDays`: FLS read=true / editable=false,
      `hasActivationRequired=false`; kein Profil-Ansatz.
- [ ] Kein Apex/Trigger/Flow im Deploy; kein Impact auf bestehende
      Komponenten (git diff: nur die 5 eigenen Dateien).
- [ ] Deploy-Ordnung: Phase 1 validate+deploy → Read-Back (Feld in Org
      vorhanden, Wert auf frischem Account = 0) → erst dann Phase 2.

## ⚠️ Befund (Repo-Analyse, blockt NICHT)
1. **Repo trackt nur Classic-Layouts.** `Account-Account Layout.layout-meta.xml`
   ist das Classic Page Layout. Die Lightning Record Page für Account lebt in
   der Org (kai FlexiPage im Repo); sollte im UI-Test der Lightning-Record-View
   das Feld fehlen, ist der App-Builder-Platz + ggf. LWP-Visibility ein
   Org-Schritt für @devops-agent (FLLS ist via PS bereits vorhanden).
2. **PS-Zuweisung in der Org:** „für alle sichtbar" erreicht, das PS in der
   Org den Benutzern zugeordnet ist (`sf org assign permset`). Org-Schritt für
   @devops-agent nach dem Deploy — blockt die Implementierung nicht.
