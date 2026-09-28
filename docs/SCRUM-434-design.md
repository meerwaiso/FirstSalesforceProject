# SCRUM-434 — Design & Build-Spec
**Fälle: Ursache beim Schliessen erfassen (Picklist) + Auswertung je Kategorie/Zeitraum**

Survey-Basis: `origin/master` @ `5c10a07` (2026-09-28). Referenzen auf existierende
Haus- Artefakte (alle auf `origin/master` verifiziert):
- ValRule-Pattern Status-abhängige Pflicht auf Standard-Objekt: `objects/Opportunity/validationRules/LossReason_PflichtBeiClosedLost.validationRule-meta.xml` (SCRUM-381)
- Picklist-Feld-Shape: `objects/Opportunity/fields/Loss_Reason__c.field-meta.xml` (SCRUM-381)
- FLS via Permission Set: `permissionsets/SCRUM398_Eskalationsstufe.permissionset-meta.xml`
- Service-Report mit Org-Scope + timeFrameFilter + Custom-Feld-Gruppierung: `reports/Service/Erstreaktionszeit_Pro_Servicebereich.report-meta.xml`, `reports/Service/Wiedereroeffnungen_3Monate.report-meta.xml`
- Case-Layout-Section-Muster: `layouts/Case-Case Layout.layout-meta.xml` (SCRUM-420/421/424 = eigene Section vor „System Information")

## Ziel
Beim Schliessen eines Cases muss das Service-Team die Ursache aus einer festen
5er-Picklist angeben (harte Speichersperre bei leerem Feld im geschlossenen
Status); offen bleibt das Feld freiwillig. Ein Org-Report zählt die geschlossenen
Fälle je Kategorie über einen Zeitraum.

## Akzeptanz-Kriterien → Artefakt-Mapping (Review-Kontrakt)
| AC | Behauptung | Beweise (muss existieren) |
|----|-----------|--------------------------|
| AC1 | Feld existiert, Picklist mit genau 5 Werten | `.field-meta.xml` + Apex-Test (House: value-set + FLS-Tripel `SCRUM382…`-Shape) |
| AC2 | Pflicht beim Schliessen blockiert das Speichern | **ValidationRule** (keine Warnung, harte Blockade) + Apex-Insert/Update-Test: geschlossener Status ohne `Ursache__c` → `System.Exception`/DML-Rollback |
| AC3 | Offen = freiwillig | Apex-Test: Status `New`/`Working` ohne Value speichern → geht durch |
| AC4 | Report: Anzahl geschlossene Fälle je Kategorie, monats-/quartalsfilterbar | `.report-meta.xml` (grouping `Case.Ursache__c`, filter `CLOSED`, timeFrameFilter) + E2E-Spec (Report-AC, House: `SCRUM-378_….spec.ts`-Shape) |
| AC5 | Visibilität Service-Team: Case(Page Layout) + Report | PS-FLS (repo) + Layout-`layoutItem` (repo, Classic) + Lightning/Report-Folder = Org-Schritt (DevOps, non-blocking) |

## Komponenten (exakte Pfade)
1. **Custom Picklist-Feld** — `force-app/main/default/objects/Case/fields/Ursache__c.field-meta.xml`
2. **ValidationRule** (Pflicht bei geschlossenem Status) — `force-app/main/default/objects/Case/validationRules/Ursache_PflichtBeiGeschlossen.validationRule-meta.xml`
3. **Permission Set** (FLS) — `force-app/main/default/permissionsets/SCRUM434_Ursache.permissionset-meta.xml`
4. **Case-Layout-Section** — `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` (neue Section „Rückschau")
5. **Report** — `force-app/main/default/reports/Service/Faelle_Nach_Ursache.report-meta.xml`
6. **Apex-Tests** (Haus: value-set + FLS + AC2/AC3-Verhalten) — `force-app/test/classes/SCRUM434…Test.cls` (+ `-meta.xml`), Manifest `manifest/scr434-*-apextests.xml`

---

## 1. Feld `Ursache__c` (Custom Picklist auf Case)
Shape 1:1 aus `Loss_Reason__c`. `required=false` (Pflicht kommt von der ValRule,
NICHT vom Feld-Required-Flag — sonst blockte es auch offene Cases, AC3-Break).

API-Namen: alphanumerisch,camelCase, ohne Leerzeichen/Schrägstrich/Umlaut
(Haus-Pattern `ZuTeuer`, `KeinBudget`). Labels = exakt die 5 vom User am
28.09. fixierten Werte.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Ursache__c</fullName>
    <label>Ursache</label>
    <description>Grundkategorie, warum der Fall geschlossen (SCRUM-434). Fest
5 Werte, kein Freitext. Nur beim Schliessen Pflicht (ValRule
Ursache_PflichtBeiGeschlossen); solange offen freiwillig. Intern, nicht PII.</description>
    <required>false</required>
    <trackFeedHistory>false</trackFeedHistory>
    <type>Picklist</type>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value><fullName>HowToAnfrage</fullName><default>false</default><label>How-to / Anfrage</label></value>
            <value><fullName>RechnungAbrechnung</fullName><default>false</default><label>Rechnung / Abrechnung</label></value>
            <value><fullName>TechnischerFehler</fullName><default>false</default><label>Technischer Fehler</label></value>
            <value><fullName>Fehlkonfiguration</fullName><default>false</default><label>Fehlkonfiguration</label></value>
            <value><fullName>KeinFehlerKeineMassnahme</fullName><default>false</default><label>Kein Fehler / Keine Maßnahme</label></value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

**Namen-Entscheidung (API ≠ Label):** `KeinFehlerKeineMassnahme` (API, doppel-s im
API-Namen, kein Umlaut) trägt Label `Kein Fehler / Keine Maßnahme`. Die restlichen
Labels sind byte-exakt die PO-Werte. **Jira-Markup zerlegt `__c`/Umlaute in
Kommentaren — dieses File (Commit) ist die Quelle der Wahrheit, nicht der Jira-Text.**

## 2. ValidationRule — „Pflicht nur beim Schliessen" (das Herzstück)
Entscheidung: **ValidationRule, nicht Trigger/Flow.** Begründung (ADR unten).

Gate-Formel (ADR-2, **freigegeben** via Jira-Kommentar 21837 — **aktuelle Autorität ist das
deployte ValRule-File**, nicht mehr dieser Abschnitt):
```
AND( OR(IsClosed, ISPICKVAL(Status, 'Closed')), ISBLANK(TEXT(Ursache__c)) )
```
**Warum der Zusatzklausel nötig war:** `IsClosed` wertet in einer ValRule den **VOR**-Zustand
aus, nicht den Endstand, auf den die ursprüngliche ADR-2-Annahme („Endstand NACH dem Save")
baute. Auf genau der DML, die den Fall schließt (Insert oder Update auf `Status='Closed'`), ist
`IsClosed` noch `false` → die Gate blockierte dort nicht (DML-A/B bewiesen, 28.09). Der
`ISPICKVAL(Status,'Closed')`-Zweig deckt die Schließ-Aktion selbst ab, `IsClosed` bleibt als
zweite Stütze für spätere/renamed geschlossene Status. `ISBLANK(TEXT(Ursache__c))` statt
`ISBLANK(Ursache__c)` (Picklist-typ, Plattform-Regel). Org verifiziert (28.09.26): Status-
Verteilung = `New`(608) / `Working`(6) / `Closed`(38); nur `Closed` ist zu.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
  ADR-2-Autorität: das deployte ValRule-File —
  objects/Case/validationRules/Ursache_PflichtBeiGeschlossen.validationRule-meta.xml
  (formel: AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Ursache__c))))
  Beschreibung/Name/ErrorMessage in der Datei; dieser Abschnitt dokumentiert nur die Begründung.
-->

**Bulk/Trigger-Proof:** eine ValRule feuert bei JEDEM DML-Pfad — UI, Trigger,
API, Bulk, Bulk API Import. Kein Umweg. (Trigger/Flow würden nur den Pfad
abdecken, auf dem sie hängen, und haben hier nachweislich Deploy/Schema-Probleme.)

## 3. Permission Set (FLS) — Haus-Pattern SCRUM398
Nur das neue Feld, Read+Edit, kein Profil-Eingriff.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>true</editable>
        <field>Case.Ursache__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM434_Ursache</label>
    <description>SCRUM-434: Read+Edit-FLS für Case „Ursache" (Service-Team).
Per PS, kein Profil. Report-Zugriff ist ein Folder-Sharing-Schritt (Org/DevOps).</description>
</PermissionSet>
```

## 4. Case-Layout — eigene Section „Rückschau" (Haus: Abgrenzungs-Muster)
Neue `layoutSection`, eingefügt **vor** `System Information` (wie SCRUM-420/421/424),
damit parallel laufende Tickets diese Datei nicht kollidieren. Verhalten `Edit`.

```xml
<!-- SCRUM-434: Rückschau / Ursache beim Schliessen (ADR-5), eigene Section. -->
<layoutSections>
    <customLabel>true</customLabel>
    <detailHeading>true</detailHeading>
    <editHeading>true</editHeading>
    <label>Rückschau</label>
    <layoutColumns>
        <layoutItems>
            <behavior>Edit</behavior>
            <field>Ursache__c</field>
        </layoutItems>
    </layoutColumns>
    <style>OneColumn</style>
</layoutSections>
```

## 5. Report — „Fälle nach Ursache"
House-Shape aus `Erstreaktionszeit_Pro_Servicebereich` + `Wiedereroeffnungen_3Monate`.
`CaseList`, `<scope>organization</scope>` (AC4: alle Service-Teams, nicht „meine"),
grouping `Case.Ursache__c` (Count je Gruppe = „Anzahl je Kategorie"), Filter `CLOSED=true`
(AC4: nur **geschlossene** Fälle), Zeitraum via `timeFrameFilter`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>SCRUM-434 AC4: Geschlossene Fälle je Ursache-Kategorie über einen
Zeitraum (Monat/Quartal), Org-weit. Grouping: Ursache__c (Anzahl je Kategorie).
Filter: CLOSED=true (nur geschlossene). Zeitraum: timeFrameFilter (Default 1
Quartal = INTERVAL_LAST90; Nutzer kann auf Monat umschalten).</description>
    <filter>
        <criteriaItems>
            <column>CLOSED</column>
            <columnToColumn>false</columnToColumn>
            <isUnlocked>false</isUnlocked>
            <operator>equals</operator>
            <value>1</value>
        </criteriaItems>
        <language>en_US</language>
    </filter>
    <format>Summary</format>
    <groupingsDown>
        <field>Case.Ursache__c</field>
        <sortOrder>Asc</sortOrder>
    </groupingsDown>
    <name>Faelle_Nach_Ursache</name>
    <reportType>CaseList</reportType>
    <scope>organization</scope>
    <showDetails>false</showDetails>
    <showSubTotals>true</showSubTotals>
    <timeFrameFilter>
        <dateColumn>CLOSED_DATE</dateColumn>
        <interval>INTERVAL_LAST90</interval>
    </timeFrameFilter>
</Report>
```

**Deploy-Validate-Checkpoint (non-blocking, Dev-Handoff):** der Report-Spalten-
Token `CLOSED_DATE` (timeFrameFilter `dateColumn`) und die exakten
Monat-/Quartal-Intervalle sind **House-Finding SCRUM-432 / SCRUM-418**: Spalten-Tokens
werden per `sf project deploy validate` verifiziert, nicht geraten. Die reduziert
ausgelieferte `analytics/reportTypes`-Beta-Endpunkt listet `CLOSED_DATE` nicht
(nur `CREATED_DATE`/`CLOSED`/`OWNER`/`SUBJECT` + `Case.*`); der Developer validiert
das Fenster-`dateColumn` beim Deploy. `CLOSED` (Filter, boolean) ist org-verifiziert
per Analytics-API (`detailColumnInfo.CLOSED`, filterable=true). Das Grouping
`Case.Ursache__c` ist das sichere Muster (`Case.Is_Overdue__c`, `Case.Servicebereich__c`).

## 6. Apex-Tests (Gate für die PR, keine Bonus)
Haus-Shape `SCRUM382_*Test` / `*FlsTest` + E2E. Muss mindestens prüfen:
- value-set: genau 5 `PicklistEntry`-Labels wie oben
- AC2: `Case{IsClosed=true (via Status), Ursache__c=null}` → Insert/Update wirft,
  kein Rollback-leak; mit gesetztem `Ursache__c` → geht durch
- AC3: `Status='New'`/`'Working'` ohne `Ursache__c` → Insert geht durch
- FLS: Read+Edit im `SCRUM434_Ursache`-PS

## Architektur-Entscheidungen (ADRs)
1. **ValidationRule, kein Trigger/Flow** (Pflicht-beim-Schliessen). House-Pattern
   `LossReason_PflichtBeiClosedLost`/`LockReason_PflichtBeiGesperrt`; ValRule deckt
   jeden DML-Pfad ab (UI/Trigger/API/Bulk) und umgeht die wiederholten
   Deploy/Schema-Validierungsfehler von Flow. → Default „Apex/Declarativ über
   Flow"; hier ist die **declarative ValRule** die robusteste Option.
2. **Gate über `IsClosed` ODER `Status='Closed'`** (erweitert, ADR-2 freigegeben per Jira-Kommentar
   21837). Ursprünglich reine `IsClosed`-Gate — lokalitäts-/rename-sicher, kanonischer
   Standard-Boolean (4 Haus-Formeln), deckt alle geschlossenen Status ab. **Korrektur nach
   DML-A/B-Beweis (28.09):** `IsClosed` wertet die Vor-Transaktion aus → auf der schließenden DML
   selbst ist es noch `false` und blockierte nicht. Deshalb `OR(IsClosed, ISPICKVAL(Status,'Closed'))`.
   Die **aktuelle ADR-2-Autorität ist das deployte ValRule-File** (
   `objects/Case/validationRules/Ursache_PflichtBeiGeschlossen.validationRule-meta.xml`); dieser
   Doc-Abschnitt ist nur noch die Begründung.
3. **Feld `required=false`, Pflicht ausschließlich via ValRule.** Sonst blockte
   `required=true` auch offene Saves (AC3-Break). House-Konsistenz mit Loss_Reason.
4. **FLS via Permission Set, kein Profil** (SCRUM398/321/327/329). Feld-FELS wird
   explizit vergeben, nie von Object-CRUD vererbt.
5. **Report Org-Scope + CLOSED-Filter + Custom-Feld-Grouping.** `<scope>organization</scope>`
   ist source-persistierbar (ADR-5a/5b, SCRUM-394) — kein Org-Schritt für den Scope.
   CLOSED-Filter + timeFrameFilter liefern die Zeitfenster-Semantik.
6. **Kein Auto-clear / keine Ableitung** (Scope-Grenze @user): bewusst kein Trigger,
   der `Ursache__c` bei Neueröffnung leert oder aus der Kategorie abgleitet.

## ⚠️ Befund (Repo-Org-Gaps → Org-Schritte, non-blocking)
- **Lightning (FlexiPage) liegt nicht im Repo** — nur klassische `.layout-meta.xml`.
  AC5 „auf dem Case sichtbar" wird im Repo über die Classic-Layout-Section erfüllt;
  die Lightning-Platzierung ist ein **App-Builder-Schritt (Org)** → Owner @devops-agent.
  (House-Finding, SCRUM-394.)
- **Report-Zugriff für das Service-Team** ist Folder-Sharing in der Org (wer den
  Report öffnen darf), nicht ein PS-`fieldPermission` → @devops-agent, read-back.

## Offene Punkte (blocken Implementierung NICHT)
- [ ] Report `timeFrameFilter.dateColumn` (`CLOSED_DATE`) + Monat/Quartal-Intervalle per Deploy-Validate verifizieren → @developer-agent (House SCRUM-432/418)
- [ ] Lightning-FlexiPage-Platzierung + Report-Folder-Sharing als Org-Schritt dokumentieren → @devops-agent
- [ ] PS-Zuweisung an die Service-Team-Rollen in der Org → @devops-agent

## Review-Kontrakt für mich (Architect, PR-Review)
Jede Zeile der AC-Mapping-Tabelle braucht ein **benanntes Artefakt + Test**, bevor
ich freigeben. „Deployed + einmal live gelaufen" ist Evidenz, **kein** Test —
AC2/AC3 brauchen reale `@isTest`-Methoden, AC4 eine E2E-Spec. Subtask-Done ≠ Beweis.
