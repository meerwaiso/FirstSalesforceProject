# SCRUM-404 — SLA-Reaktionsfrist auf Case (Frist, Beleg, Alert, Konfiguration, Monatsauswert)

**Status:** Freigegeben für Implementierung (Architect). **Autoritative Build-Spec** — diese Datei ist die
Einzigkeitswahrheit für Namen, Pfade, XML und Apex-Signaturen; der Jira-Kommentar darf bei Markup abweichen
(bekannter Jira-Konverter-Vorfall). Der Developer baut von hier.

**Ticket:** [SCRUM-404](https://meerwaisosmani.atlassian.net/browse/SCRUM-404) (Sprint 68)
**Entwurf:** architect-agent, 2026-09-09

**Org-Fakten (am 2026-09-09 gegen Test-Org verifiziert, Kommando je genannt):**
- Eine `BusinessHours`-Record «Default» existiert (IsDefault=true, IsActive=true), **ohne je eine Arbeitszeit
  konfiguriert** (alle DayTime-Felder leer, TZ America/Los_Angeles) — verifiziert via
  `sf data query -q "SELECT Name, IsDefault, IsActive, TimeZoneSidKey, MondayStartTime, ... FROM BusinessHours"`.
- **Keine** `Holiday`-Records — verifiziert via `sf data query -q "SELECT Id FROM Holiday"` (0 rows).
- Priority-Werte High/Medium/Low existieren — Beweis: die **deployed** Formel `Case.Is_Overdue__c` (SCRUM-390,
  Repo-Datei `force-app/main/default/objects/Case/fields/Is_Overdue__c.field-meta.xml`) nutzt
  `ISPICKVAL(Priority,"High"|"Medium"|"Low")` und deployed.
- Auf Case laufen **3 aktive Trigger org-seitig**: `CasePriorityTrigger` (SCRUM-333, **nur Org, NICHT im Repo** —
  Drift-Bekanntes), `CaseOpenCountTrigger`, `LastCaseDateTrigger` — verifiziert via
  `sf data query -q "SELECT Name, TableEnumOrId, Status FROM ApexTrigger WHERE TableEnumOrId='Case'"`.
  Ein 4. Trigger bleibt unter dem Limit (5).
- `Task`/`Event`: 0 Records in der Test-Org (keine Umgebungs-Abhängigkeit für das Design; beide Objekte sind
  voll standardaktiv).

---

## 1. Ziel

Jeder neu angelegte Case trägt seinen Reaktionsfrist-Zeitpunkt (Business-Hours-berechnet nach Priorität), der
Zeitpunkt der ersten Reaktion wird einmalig und unveränderlich fixiert, Überfälle werden ohne Suchen sichtbar
und einmalig an die Teamleitung gemeldet, die Fristen sind ohne Deploy änderbar, und der Einhaltungsgrad in %
nach Priorität ist pro Monat auswertbar.

## 2. ADR

### ADR-1: Apex (Trigger + Batch + Queueable) statt Flow, statt native Entitlements/SLA

| Option | Bewertung |
|---|---|
| **Apex: Case-Trigger + Task/Event-Trigger + Scheduled Batch + Queueable** | **Genommen.** Hausmuster direkt vorhanden: `OpportunityOverdueService` (Bulk-Such-+Mark-Logik), `OpportunityOverdueScheduler` (Schedulable), `OpportunityOverdueNotification` (Queueable, FeedItem, `Test.isRunningTest()`-Guard), `CaseOpenCountTrigger`/`LastCaseDateTrigger` (Case-Trigger, bulkified, no-op-Schutz), FLS-Paare `SCRUM382...FlsTest`/`SCRUM390OverdueCaseTest`. Deckt alle 10 AC nativ incl. Bulk, Dedup des Alarms (AC 6) und Konfig-Readout (AC 9). |
| Native Entitlements/SLA (Milestone, EntitlementProcess) | **Verworfen** (für diese Story). Wirkt «das Richtige», bräuchte aber: Customer + EntitlementTemplate + Entitlement pro Fall, SLA-Checkbox im Setup (Org-Schritt), Milestone-Felder entstehen per Setup-UI (**nicht source-deploybar**) und bringen 5+ neue Standardfelder ins Layout. Die PO will exakt 2 sichtbare Felder + einfache Konfiguration. Dokumentiert als Ausweg: wächst die Anforderung (mehrere Fristarten, Escalation), ist native SLA die Ziel-Architektur. |
| Flow | **Verworfen.** Haus-Regel (Flow = wiederholte Deploy-/Schema-Validierungsprobleme); dazu: keine Business-Hours-Endrechnung, kein Cron-Dedup, schwer testbar. |

Kein Flow → keine Flow-apiVersion-Spezifikation nötig (Pre-Handoff-Checklist erfüllt als «nicht anwendbar»).
Alle Apex-Metadaten: **apiVersion 67.0** (Hausstandard, s. `manifest/scr403-phase2-referencing.xml`).

### ADR-2: Business Hours = Plattform-Objekt (Org-Konfiguration), Berechnung = Apex `BusinessHours.add()`

Die Arbeitszeitregelung **und** der Feiertagskalender leben in der existierenden `BusinessHours`-Record +
`Holiday`-Records (Setup-UI, **kein Deploy** — PO-Forderung «ohne Deploy» erfüllt auf Plattformebene).
Die Frist berechnet ein Apex-Trigger via **`BusinessHours.add(businessHoursId, startDateTime, ms)`** (gibt
`DateTime` zurück) — die öffentliche Apex-API, die Arbeitszeiten **und** Holidays der angegebenen
BusinessHours-Record respektiert. `nStunden` wird in Millisekunden übersetzt (`stunden * 3600 * 1000L`).

⚠️ **Berichtigung 2026-09-09 (Architekt — kompiliert & gegen Test-Org verifiziert):**
`BusinessHours.nextBusinessHours(CreatedDate, nStunden)` existiert in dieser Signatur **nicht** (Compile:
«Method does not exist or incorrect signature»). Das korrekte Primtivist ist `add()`. **Zwei verifizierte Fallen:**
1. **`add(null, …)` wirft `System.NPE: «Business Hours Id cannot be null»`** (verifiziert 17:10 org-log).
   Die Id der Default-BH-Record SOQL-holen und übergeben
   (`[SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1]`) — **nie `null`**.
2. **Unkonfigurierte Default-Record = reine Kalenderzeit** (verifiziert: Fr 16:00 + 4 h → Fr 20:00,
   überspringt SA/SO **nicht**). §8 Schritt 1 (Mo–Fr 08:00–17:00 + Holidays) ist damit
   **Voraussetzung für die Korrektheit von AC 2/3**, nicht nur Org-Politur.

Der `add()`-NPE-Fix (1) und die BH-Konfiguration (2) sind **zwei getrennte Dinge**: (1) ist Code (Id
übergeben), (2) ist Org-Setup. Deren Verwechslung hat in der 1. Testrunde 2 der 7 Fails erzeugt.

Warum nicht Formelfeld mit `nDaysAgo()`/`nHoursAgo()` (Business-Hours-Formelfunktionen): diese Funktionen
sind **nur** in SLA-/Entitlement-Kontexten erlaubt, in einem normalen Case-Formelfeld nicht compilierbar.
Warum nicht reine Formel «+1 Tag»: würde Wochenende/Feiertage verletzen (AC 2/3).

**Fristen in Business-Std, nicht Kalendertagen** (Konfig-Werte, initial):

| Priorität | Vertrag | Business-Stunden | Wert in MDT |
|---|---|---|---|
| High (dringend) | 4 Stunden | 4 | 4 |
| Medium (normal) | 1 Arbeitstag | 8 | 8 |
| Low (niedrig) | 3 Arbeitstage | 24 | 24 |

Konvention: 1 Arbeitstag = 8 Business-Stunden der konfigurierten 9h-Woche (08:00–17:00). Für den User
wechselbar über das MDT (Setup → Custom Metadata → **SLA-Konfiguration**), ohne Deploy.

**Implementierungs-Pitfalls (an den Developer, beide verifiziert):**
- **`CreatedDate` ist im before insert null** (Systemfeld, wird erst beim Commit gesetzt) → die Deadline
  wird aus `DateTime.now()` berechnet (für einen gerade eingehenden Case = derselbe Zeitpunkt,
  Subsekunden-Drift ist für eine Stunden-/Tages-SLA irrelevant). Test-Determinismus:
  `@testVisible static DateTime NOW_OVERRIDE` in `CaseSlaService` (null → `DateTime.now()`); der Test setzt
  einen Fix-Zeitpunkt und assertet den exakten Wert daraus.
- **`BusinessHours.add()` braucht die Id der Default-BH-Record** (verifiziert: `add(null, …)` → NPE).
  Die Test-Org hat genau eine (`Default`, IsDefault belegt). Richtiges Test-Setup: in der Test-Transaktion
  die org-eigene `Default`-Record **per Update** auf Mo–Fr 08:00–17:00 setzen + `Holiday`-Rows inserten;
  der Test-Rollback stellt beides her. Die `CaseSlaService` liest die Id pro Lauf (`IsDefault = true`).
  (Heutiger Zustand: Default ohne konfigurierte Zeiten — die Release-Organisation steht in §8 Schritt 1;
  ohne Konfiguration liefert `add()` reine Kalenderzeit, verifiziert.)

⚠️ **Berichtigung eines Szenario-Zielwerts (PO):** SC 2 behauptet «Freitag 16:00 + 4h → Dienstag 12:00».
Bei 08:00–17:00 Mo–Fr ist das arithmetisch nicht erreichbar in keiner Interpretation. Nach
`BusinessHours.add(bhId, Fre 16:00, 4h)` ist das Ergebnis **Montag 11:00** (Fre 16–17 = 1h,
Mo 08–11 = 3h). Das PO-Szenario selbst hedged («exakter Wert je definiert von der Arbeitszeitregel») —
**die Plattform-Semantik (`add()` ab Anlagezeitpunkt) gilt**, der Apex-Test (AC 2) assertet den
exakten Wert. PO/Tester: bitte den Szenario-Wert im Ticket bestätigen, blockiert nichts.

### ADR-3: Definition «erste Reaktion»

Zählt: **der früheste auf den Case gesetzte `Task` oder `Event`** (`WhatId = Case.Id`, unabhängig von
`IsClosed`/`Status`). Zeitpunkt = `CreatedDate` dieser Activity (systemseitig, nicht UI-änderbar —
`ActivityDate` verworfen, weil ein User sie rückdatieren könnte; PO: «Danach ändert sich daran nichts
mehr»). Explizit NICHT gezählt: Case-Statuswechsel (PO-Text), Case-Comments (intern, keine Kunde-Reaktion),
`EmailMessage` (v1-Ausschluss; Org hat heute keine Email-Activities dokumentiert — später als 3. Source
erweiterbar, Logik ist bereits `Map<Case, früheste Activity>`-shaped).

Mechanik: `CaseFirstResponseTaskTrigger on Task (after insert)` + `CaseFirstResponseEventTrigger on Event
(after insert)` rufen eine gemeinsame statik-Handler-Methode auf (Muster `CaseOpenCountTrigger.recompute`):
eine SOQL holt die betroffenen Cases **nur wenn** `Reaktionsfrist__c != null AND Erste_Rueckmeldung__c =
null` (→ AC 7: Bestand-Cases ohne Frist bleiben leer, auch wenn später Tasks darauf liegen), die DML schreibt
`Erste_Rueckmeldung__c` **nur wenn NULL** (→ einmalig). Bulkified: 1 SOQL + 1 DML pro Trigger-Batch.

### ADR-4: «Kein Hardcoding» = Custom Metadata Type (Source) + Business Hours/Holidays (Org)

- **`Sla_Konfiguration__mdt`** (source-deploybar, **Records ohne Deploy änderbar** in Setup UI):
  - Felder: `Prioritaet__c` (Picklist High/Medium/Low, leer bei Global-Zeile), `Sla_Std__c` (Number 5,0 —
    Business-Stunden), `Teamlead__c` (User), `Alert_Kanal__c` (Picklist `InApp,Email,Beides`, Default-Wert in
    Global-Zeile `Beides`).
  - Initial-Zeilen (DeveloperName = Label): `sla_high` (High, 4), `sla_medium` (Medium, 8), `sla_low` (Low,
    24), `global` (Prioritaet leer, `Teamlead__c` = **Platzhalter, open item §9**, `Alert_Kanal__c` = Beides).
  - **⚠️ Record-Namen ohne Bindestriche — verifizierter Deploy-Blocker (2026-09-09):** Der Deploy-Server
    lehnt DeveloperName mit `-` ab («can only contain underscores and alphanumeric characters»).
    `sla-high`/`sla-medium`/`sla-low` sind **ungültig**, `sla_high`/`sla_medium`/`sla_low`/`global` nicht.
    Der Apex-Readout fragt nach `Prioritaet__c`, nicht nach DeveloperName → die Umbenennung bricht nichts.
  - **File-Format (verifiziert, dry-run grün, 4/4):** Source-Format in Subverzeichnissen, nicht
    `customMetadata/<Type>.<label>.md`:

    ```
    force-app/main/default/customMetadata/Sla_Konfiguration__mdt/
      Sla_Konfiguration__mdt.sla_high.md-meta.xml
      Sla_Konfiguration__mdt.sla_medium.md-meta.xml
      Sla_Konfiguration__mdt.sla_low.md-meta.xml
      Sla_Konfiguration__mdt.global.md-meta.xml
    ```

    Inhalt je File (Shape = Repository-Anker `ChurnThreshold__mdt.Standard_Churn_Threshold.md-meta.xml`,
    SCRUM-292): Wurzelelement `CustomMetadata`, `xmlns` (metadata), `xmlns:xsi`, `xmlns:xsd`,
    `<label>`, `<protected>false</protected>`, `<values>` mit `<field>` + `<value xsi:type="xsd:string|xsd:double">`.
    **Keine** `entity`- und `fullName`-Attribute — das ist metadata-format; im Source-Format leitet die CLI
    den DeveloperName aus dem Dateinamen ab: `<Typ>.<DeveloperName>.md-meta.xml`. Das alte
    `customMetadata/<Typ>.<label>.md` mit `entity`-Attribut + `<fullName>` wird von der CLI als
    «metadata format … but the directory … is for source formatted files» **ignoriert** →
    `numberComponentsTotal: 0` + `UNKNOWN_EXCEPTION (-315522575)` (Logs #17292 + Nachvollzug 2026-09-09).
  - Apex-Readout: 1 MDT-Query pro Trigger-Lauf (MDT wird zur Compilezeit geladen — kein Governor-Thema).
- **Business Hours + Holiday**: Org-Konfiguration (Setup), §8 Org-Schritt 1.

Warum nicht Custom Settings: keine relevante Unterscheidung; MDT Records sind in dieser Org-Größe
(3 SLA-Zeilen + 1 Global-Zeile) der einfachere Editierweg für Admins und in Source versioniert.

### ADR-5: Systemgepflegt = vor-Update-Guard (silent revert), NICHT reine FLS-Lock

PO-Feldtabelle sagt für beide Felder «Create/Edit: Nein für alle (systemgepflegt)». **Reine FLS
(editable=false) ist technisch untauglich**: die Trigger schreiben in Benutzerkontext (Case-Insert durch
Service-Mitarbeiter, Task-Insert durch Service-Mitarbeiter) — mit editable=false würde jede systemseitige
Schreib-Operation als `FLSPeException` scheitern. (Das Hausmuster SCRUM-365/403 hat diesen Pfad nie unter
Standard-User-DML belastet; die FLS-Tests dort prüften nur `isAccessible`/`isUpdateable`, nie DML.)

**Lösung:** Permission Set gewährt `readable=true, editable=true`; ein **vor-Update-Guard** im neuen
Case-Trigger macht die Felder faktisch read-only:
- `Reaktionsfrist__c`: Schreibbare Transition = `null → Wert` **und nur** wenn `CaseSlaGuard.WRITING_DEADLINE`
  (gesetzt vom before-insert-Pfad) — jeder andere Update-Revers auf `Trigger.old`-Wert.
- `Erste_Rueckmeldung__c`: `null → Wert` **und nur** wenn `WRITING_RESPONSE` (gesetzt vom Task/Event-Pfad).
- `Sla_Alert_Sent__c`: nur `false → true` **und nur** wenn `WRITING_ALERT` (gesetzt vom Batch-Pfad); kein
  Manual-«zurück auf false» möglich.
- Guard-Mechanik (Exaktheitsregel): Update wird erlaubt **genau dann**, wenn `old == null` (bzw. `false`
  bei `Sla_Alert_Sent__c`) **UND** `new != null` (bzw. `true`) **UND** das zugehörige Feld-Flag ist set;
  jeder andere Change — **das includes auch ein manuelles Leeren auf null** (PO: «Danach ändert sich daran
  nichts mehr» — das Leeren würde den Fall aus der Auswertung entfernen und das Signal neu auflösen) — wird
  **stumm auf den `old`-Wert reverted**: kein Fehler, das Feld wirkt read-only (PO-Ziel «Nein für alle»).
  Der Revert passiert in `before update`, die Datenbank sieht ihn nie.
  - **before insert (gleicher Trigger):** Pre-Fills via API/Excel werden hart entfernt —
    `Erste_Rueckmeldung__c = null`, `Sla_Alert_Sent__c = false` (unbedingt, keine Flags nötig: beim Insert
    darf nur die Deadline gesetzt werden, und die setzt derselbe Trigger: `CaseSlaService.setDeadlinesForNewCases`).
  - **Transaktionale Flag-Semantik:** System-Write = Flag setzen → DML → Guard erlaubt (Batch: `WRITING_ALERT`
    → `Sla_Alert_Sent__c = true`; Task/Event-Handler: `WRITING_RESPONSE` → `Erste_Rueckmeldung__c` = Wert).
    UI-/API-/Excel-Write läuft ohne Flag → Revert.
  - **Test-Pfad:** `@testVisible static Boolean TEST_BYPASS = false` (Hausmuster
    `OpportunityOverdueService.OVERDUE_DAYS_THRESHOLD`): true erlaubt **zudem** die manuellen Changes im
    Trigger-Revert-Pfad. Rechenweg AC 5 (Frist in der Vergangenheit): `TEST_BYPASS = true; insert` eines
    Cases mit gesetzter `Reaktionsfrist__c` (before-insert erlaubt die Deadline ohne Flag, da der
    Trigger-Eigene-Write), danach `TEST_BYPASS = false` — der Guard ist wieder aktiv für die Mutagen-Tests.

**Faktisches Read-only ist ein Apex-Test-AC** (§7 AC 4/10): manuelles DML auf beide Felder → Wert unverändert.

### ADR-6: Überfällig-Alert = Scheduled Batch (15 min) + Queueable-Notification nach Hausmuster

«Sichtbar ohne Suchen»: Formelfeld `Sla_Breached__c` (read-only, live bei jedem Read; `NOW()`-basiert,
recalculiert automatisch) + **List View «SLA: Keine Reaktion»** (Hausmuster `Eskalierte_Faelle`) + Report
(§ ADR-7). «Leitung sofort informiert + kein Doppel-Alarm» (AC 5/6): ein **`Database.Batchable<Case>`**
(`CaseSlaScheduler`), **Cron alle 15 Minuten** (CronTrigger = Org-Schritt, §8; 15 min ist dokumentierte
max. Verzögerung — PO-«sofort» als ≤15 min akzeptiert, open item §9 zur Bestätigung), Such-Kriterium:
`Reaktionsfrist__c != null AND Erste_Rueckmeldung__c = null AND Reaktionsfrist__c < NOW() AND Sla_Alert_Sent__c = false`
→ `Sla_Alert_Sent__c = true` (Guard) **+** `System.enqueueJob(new CaseSlaNotification(ids))`. Dedup =
`Sla_Alert_Sent__c` (2. Batch-Lauf findet die Fälle nicht mehr). Queueable `CaseSlaNotification`
(= kopiertes `OpportunityOverdueNotification`-Muster): je nach MDT-Kanal FeedItem auf die User-Page des
Teamleads (InApp) und/oder `Messaging.SingleEmailMessage` an `Teamlead.User.Email`; Body mit Case-Nummer,
Betreff, Priorität, Frist, Org-Link. **Kein Slack/Teams** (v1: kein Integration-Setup in diesem Projekt;
Kanal-Entscheidung mit Stakeholder = open item §9, Default `Beides` = InApp+Email).

Warum nicht Platform-Event/Flow-Scheduler: Batch ist das bewiesene Organisations-Werkzeug im Repo
(`OpportunityOverdueScheduler`), volumenfest, in Tests via `Database.executeBatch` + `Test.stopTest`
deterministisch.

### ADR-7: Monatsauswert = 1 Standard-Report auf `CaseList` + 1 Number-Formelfeld `Sla_Compliance__c`

`Sla_Compliance__c` (Number 6,1, read-only Formel):
```
IF(ISBLANK(Reaktionsfrist__c), null,
  IF(ISBLANK(Erste_Rueckmeldung__c),
    IF(NOW() > Reaktionsfrist__c, 0, null),      // verletzt oder noch offen-möglich
    IF(Erste_Rueckmeldung__c <= Reaktionsfrist__c, 100, 0)))   // eingehalten 100 / verspätet 0
```
`null` = Fall zählt NICHT in den Durchschnitt (offen ohne Verletzung, oder kein Fristfeld/Bestand).
**Report (Hausmuster `Ueberfaellige_Faelle`, reportType CaseList):** Summary, geordnet nach `PRIORITY`,
Filter `Case.Reaktionsfrist__c != null` + `CREATED_DATE = LAST_MONTH` (oder THIS_MONTH — Tester wählt je
Monat; Date-Filter ist im Standard-Report ohne Deploy änderbar), Spalten `CASE_NUMBER`, `PRIORITY`,
`Case.Reaktionsfrist__c`, `Case.Erste_Rueckmeldung__c`, `Case.Sla_Compliance__c` — plus **AVG über
`Sla_Compliance__c`** je Priority-Gruppe als KPI-Spalte.
⚠️ **Unverifiziert:** ob `CaseList` (Standard-Reporttyp) eine **Custom-Summary-Zusammenfassung (AVG über
Custom Number-Formel)** erlaubt, habe ich gegen die Org **nicht** gecheckt (Analytics-API-Endpoint war
diesen Morgen nicht erreichbar — keine Vermutung als Befund). **Fallback, falls der Validator/die UI es
ablehnt:** der Report trägt `SUM(Case.Sla_Counted__c)` und `SUM(Case.Sla_Met__c)` (zwei zusätzliche binäre
Number-Formel-Felder auf Case: `Sla_Counted__c` = zählt der Fall ein? 1 für alle Fälle mit Frist, deren
Ergebnis feststeht (met oder breached), 0 sonst; `Sla_Met__c` = davon eingehalten), pro Prioritätsgruppe
angezeigt — Einhaltungsgrad = Met ÷ Counted, im Report als zwei Zählspalten. Der Developer prüft die
Custom-Summary-Option **zuerst** mit `sf project deploy validate` und nimmt den erst erfolgreichen Weg; die
Zwei-Summen-Variante ist das garantiert-deploybare Fallback und liegt bereits als Feld in §4 (s. dort:
`Sla_Counted__c`, `Sla_Met__c` **nur falls** Custom Summaries verworfen werden — Entwickler dokumentiert
den gewählten Weg in die Ticket-Implementierungsnotiz). Report-Zeile für AC 8 zählt als erfüllt, wenn
**eine** dieser beiden Varianten den %-Wert pro Priorität rendert (PO: «in % aufschlüsseln». Met/Counted als
zwei Zahlen = identische Information, 100/Met·Counted ist die Prozentrechnung des Lesers; die Custom-
Summary-Variante rendert die % direkt). `<scope>org</scope>` **im Quell-XML** (SCRUM-394-Lektion: ohne `<scope>`
wäre der Report auf «my records» beschränkt — die Monatsauswert muss org-weit sein). Report-Ebene-Sharing
(wer darf den Report ÖFFNEN) = Org-Schritt (§8), nicht source-darstellbar.

Spaltennamen: Custom Fields als `Case.<API>` (Hausreport `Ueberfaellige_Faelle` = deployed Beweis),
Standard-Spalten als Token (`CASE_NUMBER`, `PRIORITY`, `CREATED_DATE`) — exakt wie das Hausreport-File.

### ADR-8: FLS/Permission-Set-Design (explizit, kein implizit)

PS **`SCRUM404_SlaReaktion`** (House-Naming `SCRUM404_Label`; read-back bei Handoff obligatorisch —
Lektion SCRUM-382/386/388/390/394/398 «PS ohne Assignee»):

| Feld | readable | editable | Bemerkung |
|---|---|---|---|
| `Reaktionsfrist__c` | true | **true** | ADR-5: faktisch read-only via Guard; FLS-Edit nötig für die systemeigenen Trigger-Write |
| `Erste_Rueckmeldung__c` | true | **true** | dito |
| `Sla_Breached__c` | true | false | Formel (Hausmuster SCRUM390-PS: Formeln editable=false) |
| `Sla_Compliance__c` | true | false | Formel, dito |
| `Sla_Alert_Sent__c` | — | — | **keinerlei** fieldPermission-Entry → für Service-Nutzer unsichtbar (technisches Feld) |

Kein Profile-Edit (Haus-Regel). Assignees (Org-Schritt §8): alle Service-User + Teamlead-User.

### ADR-9: Kein Go-Live-Filter, kein Backfill — AC 7 ist strukturell erfüllt

Der Case-Trigger feuert **nur bei insert** des Case → jeder Case mit gesetzter Frist wurde **nach**
Deploy erstellt. Es gibt keine Recalculation, keinen Batch mit Bestandswalk, kein Go-Live-Datum-Feld:
Bestand-Cases tragen beide Felder NULL und bleiben es, auch wenn ihnen später Tasks/Events zugeordnet
werden (ADR-3-SOQL filtert `Reaktionsfrist__c != null` mit). AC 7 wird dadurch nicht implementiert,
sondern **existenziell** — der §7-Test belegt abseits Apex die Negativzählung (count = 0, Test-Org, nach
Deploy). Das ist der einfachste korrekte Mechanismus; ein Go-Live-Flag wäre zusätzliche Fehlerfläche für
denselben Effekt.

### ADR-10: Case-Trigger ist der 4. auf Case, Task/Event-Trigger je der 1.

Limits: Case 4/5, Task 1/5, Event 1/5 — dokumentiert, kein Action nötig. Der `CasePriorityTrigger`
(SCRUM-333) ist org-seitig aktiv, aber nicht im Repo (bekannte Drift, nicht dieses Tickets Aufgabe) —
dementsprechend existieren im Repo vor diesem Ticket 2 Case-Trigger-Dateien; nach Deploy 3.

## 3. Datenmodell (vor Implementierung festgeschrieben)

Neue Case-Felder (alle `required=false`, `trackTrending=false`, kein PII, intern):

| API-Name | Label | Typ | Systemgepflegt via |
|---|---|---|---|
| `Reaktionsfrist__c` | Reaktionsfrist | DateTime | `CaseSlaTrigger` before insert (ADR-2) |
| `Erste_Rueckmeldung__c` | Erste Rückmeldung | DateTime | Task/Event-Trigger (ADR-3) |
| `Sla_Breached__c` | Überfällig (Reaktion) | Checkbox **Formel** (nur) | — |
| `Sla_Compliance__c` | SLA eingehalten (%) | Number 6,1 **Formel** (nur) | — |
| `Sla_Alert_Sent__c` | Alert gesendet | Checkbox | Batch (ADR-6) |

Formeln (Salesforce-Formel, **keine Infix-AND** — nur Funktionsform `AND(a,b)`; XML-escaped per
`<formula>` wie das Hausfeld `Is_Overdue__c`):

```
Sla_Breached__c:
AND(Reaktionsfrist__c != null, ISBLANK(Erste_Rueckmeldung__c), NOW() > Reaktionsfrist__c)

Sla_Compliance__c:
IF(ISBLANK(Reaktionsfrist__c), null,
  IF(ISBLANK(Erste_Rueckmeldung__c),
    IF(NOW() > Reaktionsfrist__c, 0, null),
    IF(Erste_Rueckmeldung__c <= Reaktionsfrist__c, 100, 0)))
```

Custom Metadata Type: `Sla_Konfiguration__mdt` (Label «SLA-Konfiguration», `labelField` = MasterLabel),
Felder `Prioritaet__c` (Picklist High/Medium/Low), `Sla_Std__c` (Number 5,0), `Teamlead__c` (User),
`Alert_Kanal__c` (Picklist InApp/Email/Beides). 4 MDT-Records in Source
(`force-app/main/default/customMetadata/`), Werte wie ADR-4-Initialzeilen.

## 4. Komponenten & Pfade (Developer baut exakt diese Dateien)

1. **Custom Metadata Type + Records** (Phase 1):
   - `force-app/main/default/objects/Sla_Konfiguration__mdt/Sla_Konfiguration__mdt.object-meta.xml`
   - `force-app/main/default/objects/Sla_Konfiguration__mdt/fields/Prioritaet__c.field-meta.xml`
   - `force-app/main/default/objects/Sla_Konfiguration__mdt/fields/Sla_Std__c.field-meta.xml`
   - `force-app/main/default/objects/Sla_Konfiguration__mdt/fields/Teamlead__c.field-meta.xml`
   - `force-app/main/default/objects/Sla_Konfiguration__mdt/fields/Alert_Kanal__c.field-meta.xml`
   - `force-app/main/default/customMetadata/Sla_Konfiguration__mdt/Sla_Konfiguration__mdt.sla_high.md-meta.xml` (High, 4)
   - `.../Sla_Konfiguration__mdt.sla_medium.md-meta.xml` (Medium, 8) · `...sla_low.md-meta.xml` (Low, 24) ·
     `...global.md-meta.xml` (Teamlead = open item, Kanal Beides) — **Shape: ADR-4-Berichtigung, keine
     `entity`/`fullName`-Attribute, DeveloperName ohne Bindestrich.**
2. **Case-Felder** (Phase 1): `force-app/main/default/objects/Case/fields/{Reaktionsfrist__c,Erste_Rueckmeldung__c,Sla_Breached__c,Sla_Compliance__c,Sla_Alert_Sent__c}.field-meta.xml` (Formeln exakt aus §3; DateTime ohne `<length>`/`unique` — Hausmuster `Is_Overdue__c`/`Processing_Duration__c`). **Zusätzlich NUR wenn** die Custom-Summary-Option verworfen wird (ADR-7-⚠️): `Sla_Counted__c` + `Sla_Met__c` (Number 1,0, Formeln: `Sla_Counted__c = IF(ISBLANK(Reaktionsfrist__c), 0, IF(ISBLANK(Erste_Rueckmeldung__c), IF(NOW() > Reaktionsfrist__c, 1, 0), 1))`; `Sla_Met__c = IF(AND(Reaktionsfrist__c != null, Erste_Rueckmeldung__c != null, Erste_Rueckmeldung__c <= Reaktionsfrist__c), 1, 0)`) — in Phase 1 mitdeployen, falls gewählter Weg.
3. **Klassen** (Phase 2, je 1 `.cls` + `.cls-meta.xml`, `apiVersion 67.0`):
   - `CaseSlaService` — statik: `Map<String, Integer> slaHoursByPriority()` (liest die MDT-Zeilen,
     Priorität → Business-Stunden; Global-Zeile: Teamlead + Kanal) und `void setDeadlinesForNewCases(
     List<Case> newCases)` (vor-insert: `Reaktionsfrist__c` via
     `BusinessHours.add(businessHoursId, (NOW_OVERRIDE ?? DateTime.now()), std * 3600000L)` **setzen**
     (`businessHoursId` = SOQL `IsDefault = true`; **nie null** — ADR-2-Berichtigung), dazu die Pre-Fills von
     `Erste_Rueckmeldung__c`/`Sla_Alert_Sent__c` hart entfernen, ADR-5).
   - `CaseSlaGuard` — statik-Booleans `WRITING_DEADLINE, WRITING_RESPONSE, WRITING_ALERT`,
     `@testVisible static Boolean TEST_BYPASS = false`, statik `void guardOnUpdate(List<Case> old, List<Case> new)`
     (Revert-Regel aus ADR-5, stumm auf `old`).
   - `CaseSlaTrigger.cls` — Kompanion von `CaseSlaTrigger.trigger`: before-insert aufruft
     `CaseSlaService.setDeadlinesForNewCases(Trigger.new)` (setzt Deadline + entfernt Pre-Fills),
     **vor-update** ruft `CaseSlaGuard.guardOnUpdate(Trigger.old, Trigger.new)`.
   - `CaseSlaFirstResponseHandler` — statik `void markFirstResponses(Set<Id> caseIds, Map<Id,DateTime> caseToEarliestActivity)`
     (ADR-3-SOQL+DML, Guard-Flag `WRITING_RESPONSE` setzen/rücksetzen).
   - `CaseSlaScheduler` — `implements Database.Batchable<Case>` + innere/gleiche Klasse als
     `Schedulable`-Wrapper (Hausmuster `OpportunityOverdueScheduler`): `start()` = ADR-6-Query;
     `execute(chunk)` = Guard-Flag `WRITING_ALERT`, `Sla_Alert_Sent__c = true`, `update`;
     `finish()` = `System.enqueueJob(new CaseSlaNotification(collectedIds))` (Stateful, gesammelt über Chunks).
   - `CaseSlaNotification` — Queueable (Kopie/Adaption `OpportunityOverdueNotification`): FeedItem auf
     Teamlead-User-Page und/oder `Messaging.SingleEmailMessage` nach MDT-Kanal; `@testVisible static Integer
     feedCount, emailCount` zählen hoch (Test-AC 5/6), bei `Test.isRunningTest()` keine echte DML (Hausmuster).
   - **Nicht anfassen:** `CaseOpenCountTrigger`, `LastCaseDateTrigger`, `OpportunityOverdue*`,
     `Eskalationsstufe__c`, `Is_Overdue__c` (PO: keine Änderungen an bestehenden Felden).
4. **Trigger** (Phase 2, `.trigger` + `-meta.xml`, `apiVersion 62.0` wie in `scr403-phase2`, `Active`):
   - `CaseSlaTrigger.trigger` — `on Case (before insert, before update)`
   - `CaseSlaFirstResponseTaskTrigger.trigger` — `on Task (after insert)`
   - `CaseSlaFirstResponseEventTrigger.trigger` — `on Event (after insert)`
5. **Layout** (Phase 2): `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` —
   Sektion «Überwachung» (exists, house items `Processing_Duration__c`, `Eskalationsstufe__c`,
   `Is_Overdue__c`): **Spalte 2** erweitern (nach `Is_Overdue__c`): `Reaktionsfrist__c`,
   `Erste_Rueckmeldung__c`, `Sla_Breached__c` — je `<behavior>Readonly</behavior>` (Hausmuster Zeile 184–188).
   `Sla_Compliance__c`/`Sla_Alert_Sent__c` bleiben vom Layout aus (Report/Feld-Interna).
6. **List View** (Phase 2): `force-app/main/default/objects/Case/listViews/Sla_Keine_Reaktion.listView-meta.xml`
   — Hausmuster `Eskalierte_Faelle` (Token-Spalten `CASES.CASE_NUMBER`, `CASES.SUBJECT`, `CASES.PRIORITY`,
   `Case.Reaktionsfrist__c`, `CORE.USERS.ALIAS`; `filterScope=Everything`; Filter
   `Sla_Breached__c = true` + `CASES.STATUS notEqual Closed`); Label «SLA: Keine Reaktion».
7. **Report** (Phase 2): `force-app/main/default/reports/Service/Sla_Reaktionsfrist_Monatsauswertung.report-meta.xml`
   — Hausmuster `Ueberfaellige_Faelle` + ADR-7 (groupingsDown PRIORITY, `<scope>org</scope>`, Date-Filter
   `CREATED_DATE` = LAST_MONTH, calculated AVG über `Case.Sla_Compliance__c` als zusätzliche Spalte).
8. **Permission Set** (Phase 2): `force-app/main/default/permissionsets/SCRUM404_SlaReaktion.permissionset-meta.xml`
   (ADR-8-Tabelle, `hasActivationRequired=false`, Description ≤ 255 Zeichen — deploy-Lektion SCRUM-367).
9. **Apex-Tests** (Phase 2, laufen mit `RunSpecifiedTests` — 403-Pattern):
   - `SCRUM404CaseSlaTest` (AC 1,2,3,4,5,6,9 + Guard-ACs) — Test-BusinessHours: `insert/update` einer
     eigenen `BusinessHours` + `Holiday` in Test-Setup (Standard-SLA-Testmuster), danach `Test.startTest/
     stopTest` um Batch/Queueable zu flushen.
   - `SCRUM404SlaReaktionFlsTest` — `System.runAs` Standard-User-Paar (Muster `SCRUM382...FlsTest`)
     **plus** der in ADR-5 versprochene **DML-Weg**: innerhalb `runAs` Case-Anlage → Feld wird gesetzt;
     manuelles Update auf `Erste_Rueckmeldung__c` → revert; beide Assertions gegen `Describe.isUpdateable()`
     und den tatsächlichen Feldwert.
10. **E2E** (Tester): `tests/e2e/SCRUM-404-sla-reaktionsfrist.spec.ts` (Muster SCRUM-403/378) — Record-View
    beide UIs + List-View-Filter + Report-Rendering (AC 10, 5, 8).

11. **Manifeste** (2 Phasen, Haus-Layout):
    - `manifest/scr404-phase1-fields.xml` — CustomMetadataType + CustomField ×5 (version 67.0)
    - `manifest/scr404-phase2-referencing.xml` — ApexClass ×7 (inkl. der 2 Test-Klassen, Pattern 403) +
      ApexTrigger ×3 + Layout + ListView + Report + PermissionSet (version 67.0; ListView/Report wie im
      Haus: Report-Datei trägt kein eigenes version-Elekt im File; Manifest-Version 67.0)

## 5. Interface (Apex, Signaturen)

```apex
public without sharing class CaseSlaService {
    // ADR-2-Pitfall: CreatedDate ist im before insert null → Deadline aus NOW_OVERRIDE (null → DateTime.now())
    @testVisible public static DateTime NOW_OVERRIDE = null;
    @testVisible public static Map<String, Integer> slaHoursByPriority();   // 1 MDT-Query pro Txn
    // vor-insert: Reaktionsfrist__c = BusinessHours.add(businessHoursId, NOW_OVERRIDE ?? DateTime.now(), std * 3600000L)
    //   (businessHoursId = SOQL IsDefault=true, nie null — ADR-2)
    // je Priorität; dazu Pre-Fills von Erste_Rueckmeldung__c / Sla_Alert_Sent__c hart entfernen (ADR-5).
    public static void setDeadlinesForNewCases(List<Case> newCases);
}

public without sharing class CaseSlaGuard {
    @testVisible public static Boolean WRITING_DEADLINE = false;
    @testVisible public static Boolean WRITING_RESPONSE = false;
    @testVisible public static Boolean WRITING_ALERT = false;
    @testVisible public static Boolean TEST_BYPASS = false;
    // Vor-Update: alle nicht-gestatteten Writes auf die 3 systemgepflegten Felder reverts auf old-Wert.
    public static void guardOnUpdate(List<Case> oldList, List<Case> newList);
}

public without sharing class CaseSlaFirstResponseHandler {
    // 1 SOQL (cases mit Frist, ohne Rückmeldung) + 1 DML (nur-null-Write), bulkified.
    public static Integer markFirstResponses(Set<Id> caseIds, Map<Id, DateTime> caseToEarliestActivity);
}

public without sharing class CaseSlaScheduler implements Database.Batchable<Case> {
    public Database.QueryLocator start(Database.BatchableContext ctx);  // ADR-6-Query
    public void execute(Database.BatchableContext ctx, List<Case> scope); // Guard-Flag, update, Ids sammeln
    public void finish(Database.BatchableContext ctx);                   // enqueueCaseSlaNotification
}

public without sharing class CaseSlaNotification implements Queueable {
    @testVisible public static Integer feedCount;   // +1 pro InApp (Test-zählbar, AC 5)
    @testVisible public static Integer emailCount;  // +1 pro Email (AC 5)
    public CaseSlaNotification(List<Id> caseIds);
    public void execute(QueueableContext ctx);      // Hausmuster OpportunityOverdueNotification
}
```

Bulkbudget pro Trigger-Batch (200): SLA-Trigger before-insert: 1 MDT-Read (static cache pro Txn) + 0 extra
SOQL. Task/Event-Trigger: 1 SOQL + 1 DML. Batch: 1 SOQL (Start) + 1 DML/Chunk + 1 Queueable. **Kein SOQL in
Loops; keine governor-Risiken** (Pre-Handoff-Checklist ✓).

## 6. Sharing / Governor Limits

- **Sharing:** kein Impact (PO-Text übernommen, dokumentiert als «no impact»): keine OWD-, Sharing-Regel- oder
  Rollen-Änderung. Die Teamlead-Benachrichtigung ist ein **direkter Write** an User-Feed/Email — sie greift
  bewusst über Case-Sharing hinaus, das ist die PO-Forderung («alle Fälle der Organisation», ADR-6) und
  braucht keine Sharing-Änderung.
- **Report-Zugang (wer darf öffnen):** Org-Schritt §8.3 (Report-Sharing ist nicht source-darstellbar).
- **Trigger-Fanout:** Case 4-Trigger aktiv, alle bulkified, beide neuen mit no-op/Dedup-Schutz; keine Zyklen
  (SLA-Trigger schreibt Case im Insert-Flow; Task/Event-Trigger schreiben nur Case-Felder; Batch schreibt
  nur `Sla_Alert_Sent__c` → löst keine weiteren Trigger-Relevanz-Pfade aus, da keine ContactId/Status-Änderung —
  `CaseOpenCountTrigger` bleibt sauber ohne Relevanz, `LastCaseDateTrigger` ohne ContactId-Änderung sauber).
- Governor: §5-Budget.

## 7. Abdeckung der 10 Akzeptanzszenarien → Testartefakte

| AC | Beweis (Apex-Methode in `SCRUM404CaseSlaTest` / FlsTest / E2E) |
|---|---|
| 1 (Frist sichtbar, neuer Case, Business-Hours) | `newCase_mediumPriority_deadlineIsEightBusinessHours` — Test-BH Mo-Fr 08:00–17:00, Anlage Di 08:00 → assert `Reaktionsfrist__c == Mi 08:00` (exakter DateTime-Assert). E2E: Feld sichtbar Record-View (AC 10 teilt die E2E). |
| 2 (Arbeitszeiterfassung, Wochenende überbrückt) | `urgentFriday1600_deadlineLandsMonday1100` — exakt der ADR-2-berichtigte Wert (Fre 16:00 + 4 h → **Mo 11:00**). |
| 3 (Feiertag übersprungen) | `nationalHolidayMonday_deadlineMovesTuesday` — `insert` einer `Holiday` (Mo) im Test-Setup, High, Fre 16:00 → Di 11:00. |
| 4 (Erste Rückmeldung fixiert, einmalig) | `firstTask_setsErsteRueckmeldungAndSecondTaskDoesNotChangeIt` — Task 1 (Di 09:00) → Feld == Task1.CreatedDate; Task 2 (Mi) → unverändert. |
| 5 (Frist verpasst → Signal + sofortige Leitungsnachricht) | `schedulerMarksOverdueAndNotifiesTeamleadOnce` — `CaseSlaGuard.TEST_BYPASS`, Frist 1h zurück, `executeBatch` + `stopTest` → `Sla_Alert_Sent__c == true`, `feedCount == 1` (und `emailCount` je MDT-Kanal). E2E: List View «SLA: Keine Reaktion» zeigt den Case (AC 5 Sichtbarkeit). |
| 6 (kein Doppel-Alarm) | `secondSchedulerRun_doesNotNotifyAgain` — Batch läuft 2× → `feedCount` bleibt 1. |
| 7 (Bestand bleibt unangetastet) | **Strukturell (ADR-9)** — kein Apex-Test nötig; Test-Org-Datencheck nach Deploy: `SELECT COUNT(Id) FROM Case WHERE Reaktionsfrist__c != null AND CreatedDate < <DeployZeitpunkt>` = **0** (devops/tester, Zählung mit Datum in Ticket — Lektion SCRUM-394/398 «carry the numbers forward»). |
| 8 (Monatsauswert Einhaltsgrad-% nach Priorität) | Report-File (`Sla_Reaktionsfrist_Monatsauswertung`) + E2E: Report rendert, AVG-Spalte je Priority-Gruppe sichtbar; Formel-Regression in Apex: `complianceFormula_lateResponseIsZeroEarlyResponseIsHundredStillOpenIsExcluded` (3 Cases: pünktlich=100, verspätet=0, offen=null aus AVG). |
| 9 (Konfiguration ohne Deploy greift, bestehende Fristen fixiert) | `mdtChange_lowPriorityNewDeadlineAppliesExistingFristUntouched` — MDT-Zeile Low 24→40 in Test upserten, neuer Low-Case → 40-Business-h-Frist; altem Case bleibt seine Frist (kein re-compute existiert). |
| 10 (Sichtbar Lightning + Classic, FLS) | Classic: Layout-Edit (§4.5) + E2E Record-View. Lightning: **Org-Schritt §8.2** (FlexiPage Placement — FLS allein reicht NICHT, Hausbefund). FlsTest: ohne PS nicht readable; mit PS readable + faktisch read-only (DML-Revert-Assert, ADR-5). |

**Zur Review (Pflicht):** «live run + read-back» ist Evidenz, **kein** Test — jede Zeile oben hat ein
benanntes Artefakt; AC 7 trägt bewusst ein Datencheck- statt Apex-Test-Artefakt (strategisch, ADR-9) und
muss mit Zählung + Deploy-Zeitstempel im Ticket dokumentiert werden.

## 8. Deploy-Phasen & Org-Schritte

**Deploy (Developer/DevOps, Reihenfolge):** Phase 1 (CMT + 5 Felder, `validate` mit `NoTestRun`) →
Phase 2 (Trigger + Klassen + **RunSpecifiedTests der eigenen Test-Classes** +
Layout + List View + Report + PS; AGENTS.md-Guardrail: Test-Org erlaubt 1 breiten
Apex-Lauf gleichzeitig — eigene Klassen, nie `RunAllTestsInOrg`).
**Warum AC1/AC2 aktuell rot sind (2026-09-09, verifiziert via Apex-Read-back in Test-Org):**
die zwei roten Tests (AC1 `10 h ab Mo 10:00`, AC2 `4 h ab Fr 16:00`) scheitern, weil der
**Business-Hours-Default-Record der Org unkonfiguriert** ist — alle Tage `00:00:00`,
`TimeZoneSidKey = America/Los_Angeles`. `BusinessHours.add(bhId, …)` liefert daraus dann
keine echten Business-Time-Inkremente (Read-back: `addBusinessHours(Mo 10:00, 2 h)` = `Mo 10:00`,
`(…, 10 h)` = `Mo 18:00` — Kalendernäherung statt 9h/Tag Mo–Do). **Root-Cause = Org-Setup
§8.1** (Default Mo–Fr `08:00–17:00`, TZ `Europe/Berlin` auf dem **Business-Hours-Record**,
plus ≥1 zukünftiger `Holiday`) — **kein Code-Bug, kein Zeitzonen-Drift.** `DateTime.now()` ist
CEST (`Europe/Berlin`), keine Pacific-Versatz; das `America/Los_Angeles` ist nur das
`TimeZoneSidKey`-Feld des unkonfigurierten BH-Records. AC1/AC2-Expected-Werte bleiben calendar-
korrekt gegen einen 9h Mo–Do-Tag; Testlauf erst **nach** §8.1 wiederholen.

**Org-Schritte (blocken die Implementierung NICHT — Owner @devops-agent beim Release):**
1. **Business Hours konfigurieren**: `Default`-Record Mo–Fr **08:00–17:00**, TimeZone **Europe/Berlin**
   (Setup → Business Hours). **Holidays anlegen**: DE-Feiertage 2026 (mind. ein zukünftiger für E2E-AC 3,
   z. B. 03.10.2026). → blockiert die **E2E-Validierung** (AC 2/3), nicht den Code.
2. **Lightning FlexiPage Case**: `Reaktionsfrist__c`, `Erste_Rueckmeldung__c`, `Sla_Breached__c` in den
   Service-Sichtbereich legen (haus-bekannt: Lightning ist nicht im Repo). → AC 10 Lightning-Seite.
3. **Cron erstellen**: `System.schedule('SCRUM-404 SLA Scan', '0 */15 * * * ?', new CaseSlaScheduler.Cron())`
   (Schedulable-Wrapper, wie `OpportunityOverdueScheduler` deployed). → AC 5 «sofort».
4. **PS `SCRUM404_SlaReaktion` an Service-User + Teamlead-User ASSIGN + read-back** (`select * from
   PermissionSetAssignment` + ein Feld-Read durch die Session — Haus-Lektion, s.o.).
5. **MDT `global`-Zeile: Teamlead-User setzen** (Stakeholder-Entscheidung, open item) — Alert bleibt
   inaktiv, bis gesetzt (deterministisch: kein Teamlead → Notification Queueable wird nicht enqueuet).
6. **Report-Sharing**: `Sla_Reaktionsfrist_Monatsauswertung` so teilen, dass Service-Leitung +
   Report-sichtbare User ihn öffnen (nicht source-darstellbar).

## 9. Offene Punkte (blocken die Implementierung NICHT)

- [x→] **Teamlead-User** für `Teamlead__c` (MDT-`global`-Zeile): Name/Account-ID → **@user / @po-agent**
      (Open Item des PO «Kanal-Bestimmung mit Stakeholder»). Placeholder leer = Alert inaktiv.
- [x→] **Kanal-Bestätigung** (Default InApp-Feed + E-Mail; Slack/Teams = Out-of-Scope v1, keine
      Integration im Projekt) → **@user**.
- [x→] **AC 2-Zielwert** (PO «Dienstag 12:00» ist arithmetisch inkonsistent; Plattform-Wert Mo 11:00, ADR-2)
      → **@po-agent** Bitte um Korrektur des Gherkin-Werts (kein Deploy-Impact).
- [x→] **Max. 15 min Alert-Verzögerung** als Interpretation von «sofort» → **@user**.
- [ ] Business Hours + Holidays + Cron + Lightning + PS-Assignment + Report-Sharing → **@devops-agent** (§8).
- [ ] E2E beider UIs + Report-Rendering + AC-7-Datencheck (Zählung!) → **@tester-agent**.

---

## 10. Für den Menschen (ohne Apex-Worte)

Jeder neue Fall bekommt beim Anlegen automatisch einen konkreten Zeitpunkt: **bis wann wir uns melden
müssen**, berechnet aus Priorität und unseren echten Arbeitszeiten (Wochenende und Feiertage zählen nicht).
Sobald jemand den Fall zum ersten Mal bearbeitet (Anruf/Meeting im System), wird der Zeitpunkt dafür
gespeichert — und zwar für immer, man kann ihn weder ändern noch zurückdatieren; alle manuellen Änderung
versuche werden stumm verworfen. Läuft die Frist ab, ohne dass sich jemand gemeldet hat, steht der Fall in
der neuen Liste **«SLA: Keine Reaktion»** und die Teamleitung bekommt sofort eine Meldung (app-intern +
E-Mail), genau eine einzige. Am Monatsende zeigt der Report **«SLA-Reaktionsfrist Monatsauswertung»** je
Prioritätsstufe einen Prozent-Wert: wie oft wir unser Versprechen gehalten, wie oft verletzt haben.
Alles lässt sich bei Vertragsänderungen in den Settings nachsteuern, ohne dass wir Code deployen.
Alte Fälle (vor Go-Live) bleiben unberührt — es wird nichts nachgerechnet.

---

## 11. Review 2026-09-09 — REJECTED (b9784f5)

Architektur-Verifizierung gegen die Test-Org vor Freigabe (alle Befunde live nachgelesen, kein
Vertrauen auf Handoff-Darstellungen):

- **MDT-Records: IN DER ORG.** `SELECT ... FROM Sla_Konfiguration__mdt` → 4/4 Zeilen
  (`global`, `sla_high`=4, `sla_medium`=8, `sla_low`=24, alle `Alert_Kanal__c=Beides`),
  korrekte Shapes. Der Tester-Befund «cannot be found» stammt aus einem **type-level
  `sf project retrieve --metadata CustomMetadata:Sla_Konfiguration__mdt` (Succeeded, 0 Files)** —
  das ist NICHT der korrekte Record-Read-Back für CustomMetadata-Instanzen (typischerweise
  `CustomMetadata:Sla_Konfiguration__mdt.<name>` oder Tooling/SOQL). **Hold-Prämisse fällt weg.**
- **8/10 reproduziert** (synchronous `-n CaseSlaSlaTest`): grün AC3, AC4, AC5, AC6, AC7, AC9,
  AC10, notification_noTeamlead; rot AC1, AC2. Root-Cause verifiziert via Apex-Read-back:
  Default-BusinessHours `01mWU00000InFl7YAF` ist unkonfiguriert (alle Tage `00:00:00`,
  `TimeZoneSidKey=America/Los_Angeles`) → `BusinessHours.add()` liefert Kalendernäherung statt
  Business-Time. **§8.1-Setup (Mo–Fr 08:00–17:00, TZ Europe/Berlin, ≥1 zukünftiger Holiday) ist
  für AC1/AC2-Grünläufigkeit zwingend — kein Code-Fix, kein TZ-Drift.**
  (`DateTime.now()` = CEST; das `America/Los_Angeles` ist nur ein Feld des unkonfigurierten
  BH-Records.)

### Pflicht-Rework (blockiert die Freigabe)

1. **PR öffnen.** Zum Zeitpunkt der Review existierte **kein PR** mit
   `head=feature/scr404-sla-reaktionsfrist` (`gh pr list --state all` → leer). Der
   Entwickler-Claim «PR → Review» war verfrüht. PR auf `develop` öffnen, dann Review-Endorsement.
2. **SC 8: Report liefert den %** (`SLA_Monatsbericht.report-meta.xml`). Aktuell nur
   `Record Count` nach `PRIORITY` — das ist NICHT «Einhaltungsgrad je Prioritätsstufe in %», wie
   die Gherkin-AC es verlangt. Der Report muss `Sla_Compliance__c` als **Custom Summary AVG**
   (`<field>Case.Sla_Compliance__c</field>` + `<customLabel>` + `Avg`-Aggregation) tragen.
   Fallback (falls AVG nicht deploybar, SCRUM-394-Schema): SUM-Spalten `Sla_Met__c` /
   `Sla_Counted__c` im Report, KPI = Met/Counted.
3. **SC 8: Report-Scope.** Das File hat **kein `<scope>`-Element** (identisch zum SCRUM-394-Bug:
   house reports `Offene_Leads_nach_Quelle` = `<scope>org</scope>`,
   `Betreuungslast_nach_Firma` = `<scope>organization</scope>` — beide org-weit). Ohne
   `<scope>` defaultet Salesforce auf «My Records» → Dienstleitung sieht ≈ ihre eigenen Cases,
   nicht die Monatsauswertung. **Pflicht: `<scope>org</scope>` im Quell-XML** (Haus-Präfix).
4. **PS FLS korrigieren (ADR-5/ADR-8-Konflikt).** Das PS `SCRUM404_SLA_Reaktionsfrist` trägt
   aktuell `Sla_Alert_Sent__c` mit `editable=true` — das widerspricht ADR-8 („keinerlei
   fieldPermission-Entry, unsichtbar für Service-Nutzer") **und** der ADR-5-Auslegung („die
   Trigger schreiben in Benutzerkontext; mit editable=false würde jeder systemseitige
   Schreib-Versuch als `FLSPeException` scheitern"). ADR-5-konforme Lösung: `Reaktionsfrist__c`
   **und** `Erste_Rueckmeldung__c` → `readable=true, editable=true` (der vor-Update-Guard macht
   sie faktisch read-only), `Sla_Alert_Sent__c` → **kein `fieldPermissions`-Entry** (Batch/Trigger
   schreiben als Admin/Queueable; kein Service-User braucht die Sicht). `Sla_Breached__c` /
   `Sla_Compliance__c` bleiben Formel-Read-only (`editable=false`). `description` aktualisieren —
   ist veraltet („kein FLS" bei Alert_Sent/Sla_Breached/Sla_Compliance). **FlsTest**
   (`SCRUM404SlaReaktionFlsTest`) fehlt komplett im Repo — §7 AC10 fordert „ohne PS nicht
   readable; mit PS readable + faktisch read-only (DML-Revert-Assert)". Nach dem PS-Fix: FlsTest
   neu anlegen, gegen die SCRUM-394/388/390-Hauspatterns schreiben, Deploy + Test-Run grüner.
5. **Gherkin-AC-Abdeckung schließen (Pflicht: „every criterion has a named artefact").**
   Aktuelle Lücke (10 SCs → Test-Artefakte):

   | SC | Gherkin-THEMA | Test im Repo? |
   |---|---|---|
   | 1 | Case mit gesetzter Frist (Servicezeit, Feiertag überspringt) | Teilgewisse (AC1 direct) |
   | 2 | Fr 16:00 → Mo 11:00 | AC2 (rot, §8.1-Blocker) |
   | 3 | Feiertag überspringt | ❌ **kein Test** (Holiday insert via TestContext, ADR-3-SOQL-Holiday-Limit) |
   | 4 | Erste Rückmeldung einmalig | AC7 (Task-Pfad; Event-Pfad ❌) |
   | 5 | Frist verpasst → **Alert feuert + dedup** | AC6 (dedup) — ❌ **Alert-Auslösung** (Batch-executeBatch +
     `CaseSlaNotification.feedCount`/`emailCount` Assert) fehlt |
   | 6 | Kein Doppel-Alarm | AC6 ✓ |
   | 7 | Bestand nicht angefasst | **Strukturell (ADR-9)**: Org-Datencheck mit
     Zählung + Deploy-Zeitstempel (devops/tester); kein Apex-Test nötig. |
   | 8 | Monatsauswertung in % | ❌ **kein Apex-Formeltest** (pünktlich=100, verspätet=0, offen=null
     → AVG); Report selbst liefert aktuell keine % (Punkt 2). |
   | 9 | Konfigurierbarkeit (MDT 3→5) ohne Deploy | ❌ **kein Test** (MDT-Zeile upsert, alter Case
     bleibt unverändert, neuer Case = neue Frist). |
   | 10 | FLS via PS | ❌ **FlsTest fehlt** (Punkt 4) + Lightning-FlexiPage §8.2 = Org-Schritt. |

   Mindest-Paket für die Re-Review: SC3, SC5-Alert, SC8-Formel, SC9 + FlsTest.

### Nicht-Blocker, vermerken (in der Re-Review mitnehmen)

- `CaseSlaSlaTest`-Header-Kommentar (Zeilen 4-6) ist **stark veraltet** und falsch: er behauptet
  «The MDT records are NOT deployed via CLI (known SF CLI 2.139 defect). They will be created via
  DevOps after deployment.» — beides **falsch**: die 4 Records sind via CLI im Org
  (SOQL nachgelesen, siehe oben), und der #17292-Defekt war File-Format, kein CLI-Defekt.
  Nach dem #17325-Shape-Fix hat der Header nichts mehr zum DML-Vorgang zu sagen und ist zu
  löschen oder durch den aktuellen Stand zu ersetzen (SSoT = dieses Review-§, nicht der
  Header-Kommentar).

