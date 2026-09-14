# SCRUM-414 — „Sehen, welche Verkaufschancen ihren Abschlusstermin überschritten haben" · Authoritative Build-Spec

> **This file is the source of truth for the exact XML, API names and formulas.**
> The Jira comments (SCRUM-414) are mangled by Jira's markdown converter
> (double underscores → bold, closing XML tags dropped, `+` eaten — verified
> repeatedly on this project, even inside fenced code blocks). Build the files
> from THIS doc, cross-check against the in-repo reference files named below.
> Do not copy names out of the Jira comment.

## Goal

An jeder offenen Opportunity sofort sehen, dass ihr `CloseDate` überschritten
ist („Überfällig (Abschluss)"), inklusive aller Bestand-Records, filter- und
sortierbar über die neue List View „Überfällige Chancen". Deklarativ, reines
Reading: keine Automation, kein Apex, kein Trigger, keine Flow.

---

## ADR

### ADR-1: **reine Deklaration (2 Formelfelder), NICHT Apex/Trigger/Flow**

„Abschlusstermin überschritten?" ist ein **abgeleiteter Wert, der bei jedem
Lesen neu bestimmt** ist: er hängt nur von `CloseDate` + `StageName` + heute
ab. Es gibt kein Speicherevent, das nachpflegen müsste, und der Bestand ist
per Formel **automatisch** abgedeckt (keine Backfill-Migration, kein
Scheduler) — das löst die AC „Bestand sofort" mit null Aufwand.

- **Trigger abgelehnt** — feuert nur bei Save/Import; würde den Bestand nicht
  markieren (AC „Bestand: sofort alle"), und wäre ein vierter Handler im
  bestehenden `OpportunityOverdueReset.trigger` (Scope-Kollision SCRUM-319/381/384).
- **Flow abgelehnt** — keine Zustands- oder Datenänderung nötig, nur Leselogik;
  Schema-/apiVersion-Risiko ohne Nutzen.
- **Apex abgelehnt** — kein „bei jedem Lesen" in Apex ohne Custom-Lightning oder
  getriggertes Schreiben; Formel ist die exakte Domäne.
- House-Pattern: **SCRUM-390** (`Case.Is_Overdue__c` + `Processing_Duration__c`,
  beide `<formula>`, 2-Phase-Deploy, read-only PS) wird 1:1 wiederverwendet.

### ADR-2: **Namen — neues Feld + Rename des Bestehenden**

Die PO-Feldnamen (`Is_Overdue__c`, `Days_Overdue__c`) **kollidieren** mit
`Opportunity.Is_Overdue__c`, das seit SCRUM-319 in Org und Repo existiert
(Checkbox, **inaktives** Feld: > 14 Tage ohne Änderung, geschrieben vom
Apex-Stack `OpportunityOverdueService` / `OpportunityOverdueResetHandler` /
`OpportunityOverdueNotification`, FLS in `SCRUM319_OverdueOpportunity`,
Layout-Item im Opportunity-Layout). Die Semantik ist eine **andere**
(Inaktivität ≠ überfälliger Abschlusstermin) — zwei Felder mit gleichem
Namen und derselben Label-Art wären im UI unauflösbar.

**Architekten-Entscheidung:**

| Feld (SCRUM-414, NEU) | API-Name | Label | Typ |
|---|---|---|---|
| neue Checkbox | `Is_Close_Date_Overdue__c` | Überfällig (Abschluss) | `formula` |
| neue Zahl | `Days_Close_Date_Overdue__c` | Tage überfällig (Abschluss) | `formula` |
| SCRUM-319-Feld, **umbenannt** | `Is_Inactive__c` (war `Is_Overdue__c`) | Inaktiv | `Checkbox`, unchanged otherwise |

- ⚠️ **`sf field rename -r` existiert NICHT** (verifiziert 2026-09-14:
  CLI 2.139.6 und aktuellste 2.150.6 — `Command field:rename not found`).
  Die Test-Org hatte `Opportunity.Is_Overdue__c` ohnehin nicht (Read-Back
  Phase 1) → das SCRUM-319-Feld wurde unter dem Endnamen `Is_Inactive__c`
  als neues Feld deployt, alle Referenzen per API-Namen mitgezogen
  (realisierte Form). `OpportunityOverdueScheduler`/`-Notification`
  referenzieren das Feld nicht (Repo-Scan) und bleiben daher unangetastet.
- `Is_Close_Date_Overdue__c` statt `Is_Overdue__c`/`Is_Close_Due__c`: eindeutig
  gegenüber `Is_Inactive__c`, kein API-Kollisions-Risiko, Haus-Konvention
  (englische API-Namen, exakte deutsche Labels).
- `Days_Close_Date_Overdue__c` statt `Days_Overdue__c`: Kollisionsfreiheit +
  Gleichnamigkeit zur Checkbox (gleiche Domäne).
- **Impact des Renames (vollständig, verifiziert per Repo-Scan):**
  - `classes/OpportunityOverdueService.cls` (SOQL + DML)
  - `classes/OpportunityOverdueResetHandler.cls` (Guard-Logik)
  - `classes/OpportunityOverdueNotification.cls` (falls referenziert — prüfen;
    Name im File-Header deutet auf Log-Nutzung hin)
  - `classes/SCRUM319OverdueOpportunityTest.cls`
  - `permissionsets/SCRUM319_OverdueOpportunity.permissionset-meta.xml`
  - `layouts/Opportunity-Opportunity Layout.layout-meta.xml` (bestehendes
    `Is_Overdue__c`-Item → `Is_Inactive__c`)
  - `objects/Opportunity/fields/Is_Overdue__c.field-meta.xml` →
    `Is_Inactive__c.field-meta.xml` (File-Rename + `<fullName>`)
  - `triggers/OpportunityOverdueReset.trigger` (nur Kommentar, Logik unverändert)
  - `reports/Service/Ueberfaellige_Faelle.report-meta.xml` — **nicht betroffen**
    (referenziert `Case.Is_Overdue__c`, anderes Objekt)
  - **Case-Objekt nicht betroffen** — `Case.Is_Overdue__c` (SCRUM-390) bleibt
    unverändert, eigener API-Name.
  - **Kein Layout-/Report-/Formelbezug außerhalb** der oben genannten Dateien
    (Repo-weiter Scan: `Eskalationsstufe__c.formula` belegt `Case.Is_Overdue__c`,
    nicht das Opportunity-Feld).
- **ADR-2-PROD (Stand 2026-09-14, nach roter Prod-Valid 0Afg500000EpnkzCAB):**
  Prod trägt den SCRUM-319-Stack **live auf `Is_Overdue__c`** (altes Feld +
  alter Trigger `OpportunityOverdueReset` + alte Classes + PS, unverändert).
  Prod wird in 414 **NICHT** umbenannt und **NICHT** überschrieben:
  1. `sf field rename -r` existiert nicht (s. oben) — ein Rename bräuchte
     Retrieve + File-Edit + Deploy, also ein SCRUM-319-Scope außerhalb von
     414.
  2. SCRUM-319 ist `Erledigt` **ohne Prod-Release** — sein aktiver Prod-Stack
     ist `Is_Overdue__c`-basiert. Das 414-Deployment darf ihn nicht
     durchbrechen.
  → **414 deployt seine eigene Komponente daneben** (SCRUM-390-Pattern):
     `manifest/scr414-prod-release.xml` enthält NUR die reinen 414-Artefakte
     (2 Formelfelder, PS `SCRUM414_CloseDateOverdue`, ListView
     `Ueberfaellige_Chancen`, Test `SCRUM414CloseDateOverdueTest`) —
     **kein** `Is_Inactive__c`-Bezug, kein Layout, kein Trigger, keine
     SCRUM-319-Klassen/PS. Damit sind in Prod: `Is_Overdue__c` (SCRUM-319,
     lebt weiter mit seiner eigenen Logik) + die 414-Felder — zwei Felder,
     zwei Labels, keine Kollision. **Repo-Follow-up (nicht blockierend für
     414-Prod):** Master/Prod-Drift beim SCRUM-319-Stack (Repo sagt jetzt
     `Is_Inactive__c`, Prod `Is_Overdue__c`) + `Is_Inactive__c` fehlt in
     Master-Test-Layout → eigener Cleanup-Tick

### ADR-3: **Formeln**

**`Is_Close_Date_Overdue__c`** (Checkbox, Boolean):
```
IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), N(CloseDate) < N(TODAY()), FALSE)
```
- `NOT(MEMBER(...))` = „offen" (AC: „gewonnene und verlorene … werden **niemals**
  markiert, egal wie alt"). `MEMBER` ist die saubere House-Alternative zu
  `StageName = 'Closed Won' || StageName = 'Closed Lost'`.
- `N(CloseDate) < N(TODAY())`: **strikte** Vergangenheit — heute = nicht
  überfällig (House-Pattern `> threshold`, SCRUM-390).
- **Leeres `CloseDate`:** `N(CloseDate) = 0` → falsches `true` wenn `CloseDate`
  leer und offen — **ABWEHREN durch Guard:**
  ```
  IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), IF(ISBLANK(CloseDate), FALSE, N(CloseDate) < N(TODAY())), FALSE)
  ```
  Offene Chance ohne `CloseDate` → **nicht** überfällig (keine Annahme;
  konkretes, sicheres Default — AC definiert nur „mit `CloseDate` < heute").

**`Days_Close_Date_Overdue__c`** (Number, precision 10, scale 0):
```
IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), MAX(0, N(TODAY()) - N(CloseDate)), NULL)
```
- **Offen + CloseDate in Vergangenheit** → `TODAY() - CloseDate` (ganzzahlig,
  `N()` auf Date-Wert; `MAX(0, …)` sichert gegen Edge-Cases).
- **Offen + CloseDate in Zukunft oder leer** → `MAX(0, negativ/0) = 0`.
  (PO-AC: „0 bzw. leer, wenn nicht überfällig" — `0` ist die konkrete Wahl;
  `NULL` wäre auch valid, `0` ist filter-bar und sortierbar zuverlässiger.)
- **Geschlossen** → `NULL` (leer) — „da interessiert mich das Datum nicht
  mehr" (PO-Formulierung); leeres Feld ist im UI klarer als `0`.
- `DATEVALUE(CloseDate)` statt `N(CloseDate)`: äquivalent; `N()` auf Date ist
  erlaubt und kürzer — House-Beleg `Processing_Duration__c` nutzt
  `DATEVALUE`; hier beides valid. **Festlegung: `DATEVALUE`**, House-Konsistenz:
  ```
  IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), MAX(0, DATEVALUE(TODAY()) - DATEVALUE(CloseDate)), NULL)
  ```
  (Achtung: `DATEVALUE` auf leerem `CloseDate` → `DIV`-Error; der Guard
  `ISBLANK(CloseDate) → 0` ist **vor** dem `DATEVALUE`:
  ```
  IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), IF(ISBLANK(CloseDate), 0, MAX(0, DATEVALUE(TODAY()) - DATEVALUE(CloseDate))), NULL)
  ```
  Das ist die **endgültige** Formel für `Days_Close_Date_Overdue__c`.)

**Berechnungs-Tabelle (AC-Validierung):**

| Stage | CloseDate | `Is_Close_Date_Overdue__c` | `Days_Close_Date_Overdue__c` |
|---|---|---|---|
| offen | gestern | `true` | `1` |
| offen | heute | `false` | `0` |
| offen | morgen | `false` | `0` |
| offen | leer | `false` | `0` |
| Closed Won | vor 100 Tagen | `false` | NULL |
| Closed Lost | vor 100 Tagen | `false` | NULL |

### ADR-4: **FLS → ein read-only Permission Set (kein Write-PS)**

Keine Apex/DML — Formelfelder werden nur gelesen → ein einziges PS
`SCRUM414_CloseDateOverdue` mit `editable=false, readable=true` für beide
neuen Felder. House-Pattern `SCRUM390_OverdueCase` (1 PS, `false/true`).
**Kein** neues Write-PS, **keine** Profiländerung, **keine** Revocation.
`Is_Inactive__c` (rename) behält seine FLS aus `SCRUM319_OverdueOpportunity` —
die wird **mit umbenannt** (gleiche FLS-Metadaten, neues Feld-Namen-Attribut).

### ADR-5: **Opportunity-Layout — direkt änderbar (kein Retrieve nötig)**

Die `force-app/main/default/layouts/Opportunity-Opportunity
Layout.layout-meta.xml` ist **bereits im Repo** (im Gegensatz zu SCRUM-390
Case-Layout, ADR-7 dort). Änderung:
- Bestehendes `<field>Is_Overdue__c</field>` (aktuell
  `<behavior>Readonly</behavior>`) → `<field>Is_Inactive__c</field>`
  (behavior `Readonly` bleibt — jetzt korrekt, siehe ADR-2).
- **Neue** `layoutSection` „Überschrittene Abschlüsse" direkt **nach** der
  „Opportunity Information" Section (bevor „Other Information"):
  ```xml
  <layoutSections>
      <customLabel>true</customLabel>
      <detailHeading>true</detailHeading>
      <editHeading>true</editHeading>
      <label>Überschrittene Abschlüsse</label>
      <layoutColumns>
          <layoutItems>
              <behavior>Readonly</behavior>
              <field>Is_Close_Date_Overdue__c</field>
          </layoutItems>
      </layoutColumns>
      <layoutColumns>
          <layoutItems>
              <behavior>Readonly</behavior>
              <field>Days_Close_Date_Overdue__c</field>
          </layoutItems>
      </layoutColumns>
      <style>TwoColumnsLeftToRight</style>
  </layoutSections>
  ```
- **Lightning:** Das Repo hält eine FlexiPage (SCRUM-410/411:
  `objects/User/flexiPages/BetreuungsuebergabePage.flexipage-meta.xml`) →
  Lightning-Seiten sind **source-controllable** (House-Befund von SCRUM-390 gilt
  nicht mehr — verifiziert 2026-09-14 gegen aktuelles `origin/master`).
  **Keine** Opportunity-FlexiPage liegt bisher im Repo → @developer-agent
  retrieve die primäre Opportunity-Lightning-Record-Page aus der Org per
  `sf project retrieve start --metadata "FlexiPage"` und fügt die zwei
  Felder ein (Manifest-Typ `FlexiPage`, House-Shape `manifest/scr411-recordpage.xml`).
  **Fallback:** Falls die Standard-Page nicht retrievbar ist (404/leer) →
  Lightning-Placement als **Org-Schritt** (@devops-agent, App Builder).
  @tester-agent verifiziert beides (TC11).

### ADR-6: **Custom List View „Überfällige Chancen"**

Neue Datei `force-app/main/default/objects/Opportunity/listViews/
Ueberfaellige_Chancen.listView-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Ueberfaellige_Chancen</fullName>
    <columns>OPPORTUNITY.NAME</columns>
    <columns>ACCOUNT.NAME</columns>
    <columns>OPPORTUNITY.CLOSE_DATE</columns>
    <columns>Is_Close_Date_Overdue__c</columns>
    <columns>Days_Close_Date_Overdue__c</columns>
    <columns>CORE.USERS.ALIAS</columns>
    <filterScope>Everything</filterScope>
    <filters>
        <field>OPPORTUNITY.STAGE_NAME</field>
        <operation>notEqual</operation>
        <value>Closed Won,Closed Lost</value>
    </filters>
    <filters>
        <field>Is_Close_Date_Overdue__c</field>
        <operation>equals</operation>
        <value>true</value>
    </filters>
    <label>Überfällige Chancen</label>
</ListView>
```
- House-Pattern `Hochwertige_Chancen` 1:1: `OPPORTUNITY.CLOSE_DATE` (nicht
  `CLOSE_DATE` — korrekt wie im Vorbild), Custom Fields mit API-Name.
- **⚠️ Sort:** List-View-XML hat **keine** `sortOrder`-Eigenschaft (verifiziert
  per metadata registry — nur `columns`, `filters`, `filterScope`, `label`).
  „die schlimmsten zuerst" = `Days_Close_Date_Overdue__c` **absteigend** in
  der **UI** anwenden — als AC im Design-Kommentar als „manueller UI-Schritt"
  (kein Deploy-Schritt, kein Org-Schritt) dokumentiert. @tester-agent verifiziert
  per UI, nicht per Code.

### ADR-7: **2-Phase-Deploy** (House-Muster SCRUM-381/382/388/390)

- **Phase 0 (Org-Schritt, @devops-agent — NUR wenn das Feld existiert in der
  Org):** `sf field rename -r -f
  force-app/main/default/objects/Opportunity/fields/
  Is_Overdue__c.field-meta.xml --field ApiName:Opportunity.Is_Overdue__c --new-api-name Is_Inactive__c`
  (genau: `sf field rename -r -f <path> --new-api-name Is_Inactive__c` —
  Developer prüft `sf field rename --help`). Falls das SCRUM-319-Feld in der
  Test-Org noch nicht existiert → Phase 0 überspringen, Phase 1 deployt
  das **neu** benannte Feld.
- **Phase 1 (Felder):** `manifest/scr414-phase1-fields.xml` —
  `Opportunity.Is_Close_Date_Overdue__c`,
  `Opportunity.Is_Close_Date_Overdue__c`, `Opportunity.Days_Close_Date_Overdue__c`,
  `Opportunity.Is_Inactive__c` (falls neu; sonst überspringt Phase 1 nach
  Phase 0). **Reihenfolge:** `Is_Inactive__c` (Rename/Neu) **vor** den
  Phase-2-Referenzen.
- **Phase 2 (Referenzen):** `manifest/scr414-phase2-referencing.xml` —
  PermissionSet, Layout, ListView, **alle Apex-Klassen** (Service, Handler,
  Test, Notification), Trigger (nur Kommentar-Change, kein Code-Change →
  kann übersprungen werden, aber sicher: deployt).
- Version `67.0` (House-Muster).
- **Apex-Test-Lauf (PR-Gate, nicht Bonus):** Phase 2 deployt
  `SCRUM319OverdueOpportunityTest` (renamed API) → Tests müssen grün sein
  (House-Regel: „deployed + live run" ist kein Test).

### ADR-8: **Kein Report in Scope**

Die PO-ACs nennen „in Standard-Listen-Views filtern und sortieren" —
keine Report-Erwähnung. Die List View (ADR-6) deckt das vollständig.
Ein Report „Überfällige Chancen" ist eine mögliche Folge-Story, aber
**nicht** Teil von SCRUM-414. (Vergleich: SCRUM-390 hatte Report-ACs;
SCRUM-414 nicht.)

### ADR-9: **Sharing — keine Änderung**

PO-Festlegung: „Keine Änderung. Die Felder werden aus Daten abgeleitet,
die der User bereits an der Opportunity sieht." Keine neuen Sharing Rules,
OWD, Profile. Felder erben Opportunity-Sichtbarkeit über FLS. — Bestätigt,
kein org-step needed.

---

## Datenmodell

- **2 neue CustomFields** auf `Opportunity`:
  `Is_Close_Date_Overdue__c` (Checkbox, formula, read-only),
  `Days_Close_Date_Overdue__c` (Number 10/0, formula, read-only).
- **1 rename** bestehendes Feld: `Is_Overdue__c` → `Is_Inactive__c`
  (API-Name-Wechsel, `sf field rename -r`).
- **1 neues Permission Set:** `SCRUM414_CloseDateOverdue` (1 PS, read-only,
  beide neuen Felder).
- **1 Layout-Änderung:** `Opportunity-Opportunity Layout.layout-meta.xml`
  (bestehende Datei im Repo — kein Retrieve needed).
- **1 neue ListView:** `Ueberfaellige_Chancen.listView-meta.xml`.
- **7 Apex-Dateien angepasst** (API-Namen-Rename `Is_Overdue__c` → `Is_Inactive__c`
  in SOQL, DML, Guards, Tests; 1 Datei evtl. ohne Bezug: `Notification` —
  Developer prüft per `grep -r Is_Overdue__c force-app`).
- **Keine** Validation Rule, **kein** Trigger-Change (Logik), **kein** Report,
  **kein** neues Objekt, **keine** Sharing-Änderung.

## Governor Limits

Kein Apex-Change (nur API-Namen-Rename), kein neuer Trigger, keine Flow →
**keine Governor-Limit-Risiken**. Keine Bulkification, kein SOQL-in-Loop.
Der bestehende SCRUM-319-Stack (Service/Handler) läuft unverändert weiter —
kein Governor-Drift durch diesen Ticket.

## Test-Kriterien (Architect-Definition, zusätzlich zu den PO-ACs)

**Neu (SCRUM-414, Formel + FLS):**
- **TC1 (AC1 offen, überfällig):** Opportunity, `StageName='Qualification'`,
  `CloseDate=TODAY()-3` → `Is_Close_Date_Overdue__c=true`,
  `Days_Close_Date_Overdue__c=3`.
- **TC2 (AC4 nicht überfällig):** `StageName='Proposal'`, `CloseDate=TODAY()+5`
  → `Is_Close_Date_Overdue__c=false`, `Days_Close_Date_Overdue__c=0`.
- **TC3 (Grenze heute):** `StageName='Qualification'`, `CloseDate=TODAY()`
  → `Is_Close_Date_Overdue__c=false` (strikte `<`, nicht `<=`),
  `Days_Close_Date_Overdue__c=0`.
- **TC4 (AC3 Closed Won, egal wie alt):** `StageName='Closed Won'`,
  `CloseDate=TODAY()-100` → `Is_Close_Date_Overdue__c=false`,
  `Days_Close_Date_Overdue__c=NULL`. (AC: „gewonnene und verlorene … **niemals** markiert".)
- **TC5 (AC3 Closed Lost, egal wie alt):** analog TC4.
- **TC6 (offen, leerer CloseDate):** `StageName='Qualification'`,
  `CloseDate=NULL` → `false`, `0` (ADR-3 Guard, kein `true`).
- **TC7 (AC5 Bestand):** Existierende Opportunity (per SOQL `CreatedDate <
  TODAY()-30`, offen) → `Is_Close_Date_Overdue__c=true`, `Days>30`.
  (Kein Backfill-Schritt — Formel liest `TODAY()` bei jedem Read.)
- **TC8 (FLS):** PS `SCRUM414_CloseDateOverdue` → `Is_Close_Date_Overdue__c`
  readable, `Days_Close_Date_Overdue__c` readable, beide `editable=false`.
  (APX: `Schema.DescribeSObjectField` + `FieldLevelSecurity` — House-Shape
  `SCRUM382FlsTest` / `SCRUM390OverdueCaseFlsTest`.)
- **TC9 (ListView-Filter):** `Ueberfaellige_Chancen` zeigt nur offene,
  überfällige Opportunities; Closed Won/Lost excluded, Nicht-überfällige
  offen excluded (per `sf data query` + UI).
- **TC10 (Layout Classic):** `Is_Close_Date_Overdue__c` +
  `Days_Close_Date_Overdue__c` Readonly (grau) auf der Opportunity-Record
  in Classic (Repo-Layout). `Is_Inactive__c` (rename) ebenfalls Readonly.
- **TC11 (Layout Lightning):** Beide Felder sichtbar auf der Lightning-
  Record-Seite — **Org-Schritt** (@devops-agent, ADR-5). Tester verifiziert
  nach Placement.

**Rename-Regression (SCRUM-319-Stack muss unverändert funktionieren):**
- **TC12:** `OpportunityOverdueService.findAndMarkOverdueOpportunities()`
  markiert inaktive Opportunities (`LastModifiedDate > 14 Tage`,
  `StageName != Closed*`) → `Is_Inactive__c=true` (renamed API).
- **TC13:** `OpportunityOverdueResetHandler` resettet
  `Is_Inactive__c` bei Update (rename-Aware).
- **TC14:** `SCRUM319OverdueOpportunityTest` (renamed API) — alle bestehenden
  Tests grün, Test-Klasse deployt mit Phase 2.

## Offene Punkte (blockt die Implementierung NICHT)

- **Existiert `Opportunity.Is_Overdue__c` in der Test-Org?** @devops-agent
  prüft per `sf field rename --help` + `sf project deploy start --dry-run
  -f manifest/scr414-phase1-fields.xml` **vor** Phase 1 deployt (1 Command).
  Falls ja → Phase 0 (rename), dann Phase 1+2. Falls nein → Phase 1 deployt
  `Is_Inactive__c` als neue Checkbox, Phase 2 alles restliche.
  *Blockt nicht den PR* — nur die sequenzielle Deploy-Reihenfolge.
- **Lightning-Platzierung:** @devops-agent, App Builder, nach dem Deploy
  (ADR-5). Blockt den PR nicht, blockt aber die TC11-Verifikation von
  @tester-agent.
- **Sort in List View:** Kein XML-Support (ADR-6, verifiziert). „Die
  schlimmsten zuerst" = manueller UI-Schritt. @tester-agent verifiziert
  per UI, nicht per Code.
- **Notification-Klasse-Bezug:** @developer-agent prüft per
  `grep -r Is_Overdue__c force-app/main/default/classes/` ob
  `OpportunityOverdueNotification.cls` das Feld referenziert (Nomenklatur
  im File-Header deutet auf Log-Nutzung hin); falls ja → in ADR-2-Liste
  aufnehmen und mit rename.

## Deploy-Order (für @devops-agent)

1. **Vor-Check:** Existiert `Opportunity.Is_Overdue__c` in Test-Org?
   (`sf describe sObject -s Opportunity | grep -i overdue` oder retrieve
   das Feld per API). → Phase 0 nur wenn ja.
2. **Phase 0 (Optionell):** `sf field rename -r` — `Is_Overdue__c` →
   `Is_Inactive__c` (Test-Org).
3. **Phase 1:** `sf project deploy start -f manifest/scr414-phase1-fields.xml`
   — neue Formelfelder + `Is_Inactive__c` (falls neu).
4. **Phase 2:** `sf project deploy start -f manifest/scr414-phase2-referencing.xml`
   — PS, Layout, ListView, ApexKlassen, Trigger.
   **Apex-Tests (TC12–14 + SCRUM-414-FLS/Value-Tests) müssen grün sein.**
5. **Org-Schritt (nicht per Deploy):** Lightning-Placement (ADR-5, @devops-agent).
6. **Verify:** `sf data query --query "SELECT Name, Is_Close_Date_Overdue__c, Days_Close_Date_Overdue__c, Is_Inactive__c FROM Opportunity WHERE Is_Close_Date_Overdue__c=true LIMIT 5"`
   (Read-Back, ADR-3 Formeln in der Org).

---

## In-repo Reference Files (deployen heutzutage, kopiere Shapes)

- `objects/Case/fields/Is_Overdue__c.field-meta.xml` (Checkbox-Formula-Shape, `AND/OR/IF/ISPICKVAL`)
- `objects/Case/fields/Processing_Duration__c.field-meta.xml` (Number-Formula-Shape, `precision 10 scale 0`)
- `permissionsets/SCRUM390_OverdueCase.permissionset-meta.xml` (1-PS read-only)
- `objects/Opportunity/listViews/Hochwertige_Chancen.listView-meta.xml` (ListView-Shape, `OPPORTUNITY.CLOSE_DATE`)
- `layouts/Opportunity-Opportunity Layout.layout-meta.xml` (Opportunity-Layout, existiert)
- `manifest/scr390-phase1-fields.xml` / `scr390-phase2-referencing.xml` (Manifest-Shapes)
- **Neu:** `manifest/scr414-phase1-fields.xml`, `manifest/scr414-phase2-referencing.xml`

### Phase 1 — Felder

#### 1 (NEU). `objects/Opportunity/fields/Is_Close_Date_Overdue__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Is_Close_Date_Overdue__c</fullName>
    <label>Überfällig (Abschluss)</label>
    <description>Überfällig-Flag für Open Opportunity (SCRUM-414): offen und CloseDate in der Vergangenheit. Geschlossene Chance (Closed Won/Lost) ist nie überfällig. Leer CloseDate → nicht überfällig. Systemberechnet, read-only (Formel, kein DML).</description>
    <type>Checkbox</type>
    <formula>IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), IF(ISBLANK(CloseDate), FALSE, N(CloseDate) &lt; N(TODAY())), FALSE)</formula>
</CustomField>
```
(DESCRIPTION < 255 Zeichen — `wc -c` prüfen. `<` im `<formula>` → `&lt;`.)

#### 2 (NEU). `objects/Opportunity/fields/Days_Close_Date_Overdue__c.field-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Days_Close_Date_Overdue__c</fullName>
    <label>Tage überfällig (Abschluss)</label>
    <description>Tage seit CloseDate für offene Opportunities (SCRUM-414): heute minus CloseDate, wenn offen und in der Vergangenheit, sonst 0 (offen, CloseDate leer oder Zukunft) bzw. NULL (geschlossen). Formelfeld, systemberechnet, read-only.</description>
    <type>Number</type>
    <precision>10</precision>
    <scale>0</scale>
    <unique>false</unique>
    <formula>IF(NOT(MEMBER('Closed Won', 'Closed Lost', StageName)), IF(ISBLANK(CloseDate), 0, MAX(0, DATEVALUE(TODAY()) - DATEVALUE(CloseDate))), NULL)</formula>
</CustomField>
```
(DESCRIPTION < 255 Zeichen. Kein `<`/`&` in der Formel — kein Escape nötig.)

#### 3 (RENAME — nur wenn Phase 0 skipped). `objects/Opportunity/fields/Is_Overdue__c.field-meta.xml` → `Is_Inactive__c.field-meta.xml`
- File-Rename (`git mv`), `<fullName>` → `Is_Inactive__c`, `<label>` →
  „Inaktiv". **Keine** anderen Änderungen (Beschreibung, Default,
  `trackFeedHistory` bleiben).

#### 4. `manifest/scr414-phase1-fields.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-414 Phase 1: zwei neue CustomFields + (falls nötig) Is_Inactive__c (Rename). -->
    <types>
        <members>Opportunity.Is_Close_Date_Overdue__c</members>
        <members>Opportunity.Days_Close_Date_Overdue__c</members>
        <members>Opportunity.Is_Inactive__c</members>
        <name>CustomField</name>
    </types>
    <version>67.0</version>
</Package>
```
(`Is_Inactive__c` **entfernt** aus dem Manifest, falls Phase 0
already deployed das rename in der Org durchgeführt hat — sonst
Deploy-Fehler „field already exists". @developer-agent entscheidet
nach Phase-0-Ergebnis.)

### Phase 2 — Referenzen

#### 5 (NEU). `permissionsets/SCRUM414_CloseDateOverdue.permissionset-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Is_Close_Date_Overdue__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <fieldPermissions>
        <editable>false</editable>
        <field>Opportunity.Days_Close_Date_Overdue__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM414_CloseDateOverdue</label>
    <description>Read-FLS für Opportunity "Überfällig (Abschluss)" und "Tage überfällig (Abschluss)" (SCRUM-414). Beide systemberechnete Formelfelder (read-only); kein Write-PS, keine Apex/DML.</description>
</PermissionSet>
```

#### 6 (ÄNDERUNG). `layouts/Opportunity-Opportunity Layout.layout-meta.xml`
- Bestehendes `<field>Is_Overdue__c</field>` → `<field>Is_Inactive__c</field>`
  (`<behavior>Readonly</behavior>` bleibt).
- **Eine neue** `layoutSection` „Überschrittene Abschlüsse" nach
  „Opportunity Information" (vor „Other Information") — exaktes XML in ADR-5.

#### 7 (NEU). `objects/Opportunity/listViews/Ueberfaellige_Chancen.listView-meta.xml`
— exaktes XML in ADR-6.

#### 8 (ÄNDERUNG) — 7 Apex-Dateien, API-Namen-Rename
`Is_Overdue__c` → `Is_Inactive__c` in:
- `classes/OpportunityOverdueService.cls` (SOQL `SELECT`, `WHERE`, DML `update`)
  — **alle** Referenzen, inkl. `Is_Overdue__c = false` im `WHERE`.
- `classes/OpportunityOverdueResetHandler.cls` (3 Referenzen: `oldOpp.Is_Overdue__c`,
  `opp.Is_Overdue__c`, DML `opp.Is_Overdue__c = false`).
- `classes/OpportunityOverdueNotification.cls` — **prüfen** mit `grep`;
  falls referenziert → rename.
- `classes/SCRUM319OverdueOpportunityTest.cls` (alle `Is_Overdue__c` →
  `Is_Inactive__c`; **test logik unverändert** — nur API-Namen-Change).
- `permissionsets/SCRUM319_OverdueOpportunity.permissionset-meta.xml`
  (`<field>Opportunity.Is_Overdue__c</field>` → `Is_Inactive__c`).
- `triggers/OpportunityOverdueReset.trigger` — **nur** Kommentar-Zeile
  („SCRUM-319 … Is_Overdue__c" → „Is_Inactive__c"); keine Code-Änderung.
- **Kein** anderer Bezug (Repo-weiter Scan verifiziert, ADR-2).

#### 9. `manifest/scr414-phase2-referencing.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <!-- SCRUM-414 Phase 2: referenzierende Komponenten — NACH Phase 1. -->
    <types>
        <members>SCRUM414_CloseDateOverdue</members>
        <name>PermissionSet</name>
    </types>
    <types>
        <members>Opportunity-Opportunity Layout</members>
        <name>Layout</name>
    </types>
    <types>
        <members>Opportunity:Ueberfaellige_Chancen</members>
        <name>ListView</name>
    </types>
    <types>
        <members>OpportunityOverdueService</members>
        <members>OpportunityOverdueResetHandler</members>
        <members>OpportunityOverdueNotification</members>
        <members>SCRUM319OverdueOpportunityTest</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>OpportunityOverdueReset</members>
        <name>Trigger</name>
    </types>
    <version>67.0</version>
</Package>
```
(List-View-Member-Format `Object:ApiName` — verifiziert per `scrum390`
/ House-Manifests; falls `sf` auf das Format zickt: `sf project deploy
start --dry-run` zeigt die korrekte Member-Syntax.)

## Branch

`feature/SCRUM-414-close-date-overdue` frisch von `master` abziehen.
Master ist 22 Commits hinter `origin/master` → **zuerst** `git pull --ff-only
origin/master`, dann abziehen (House-Regel: eigener Arbeitsbaum statt
geteiltem). Geteilter Tree: untracked `docs/SCRUM-388-design.md`,
`manifest/build_401/`, `tmp_*.sh` liegen im Tree — **weder commiten noch löschen**,
nur explizit eigene Pfade stageen. **Committe auch DIESER Datei**
(`docs/SCRUM-414-design.md`) in den Branch mit.
