# SCRUM-438 — Design & Build-Spec
**Automatische SLA-Eskalation für lange offene Cases (Zielzeit, SLA-Status, Eskalationsstufe)**

Survey-Basis: `origin/master` @ `7c36596` (2026-10-04). Target-Org = **Test-Org**.
Referenzen auf existierende Haus-Artefakte (alle auf `origin/master` + Test-Org verifiziert):
- 5 neue Case-Felder, von denen 3 **storable** + **2** als Formelfelder der SCRUM-390/398-Welt analog
- Batch + Scheduler + Config + Service: `CaseReminderBatch` / `CaseReminderScheduler` / `CaseReminderConfig` / `CaseReminderService` (SCRUM-436)
- Reaktiver thin-Trigger: `CaseCommentFirstResponseTrigger` (SCRUM-424), `CaseCommentReminderTrigger` (SCRUM-436)
- 2-PS-FLS-Shape: `permissionsets/SCRUM436_CaseReminder.permissionset-meta.xml` (Read) + `SCRUM436_CaseReminderSystem.permissionset-meta.xml` (Write)
- Case-Layout-Section-Muster: `layouts/Case-Case Layout.layout-meta.xml` (SCRUM-420 / 421 / 424 = eigene Section vor „System Information")
- Manifests: `manifest/scr436-phase1-fields.xml` + `scr436-phase2-referencing.xml` + `scr436-apextests.xml` (apiVersion 67.0)
- Apex-Tests: `force-app/main/default/classes/SCRUM436CaseReminderTest.cls` + `…FlsTest.cls`

---

## Ziel

Offene Cases sollen automatisch erkennen, wann ihre SLA-Zielzeit fällt, in welchem Status (Im Zeitplan / Gefährdet / Überschritten) sie stehen und auf welcher Eskalationsstufe (Keine / Stufe 1 / Stufe 2) — reaktiv bei Anlage/Änderung **und** periodisch über den gesamten offenen Bestand, so dass keine Eskalation durch einen fehlenden Einzel-Trigger verloren geht.

---

## ⚠️ Befund — zwei Kollisionen, die das Design zwingen (Repo + Org, verifiziert)

**1. `Case.Eskalationsstufe__c` existiert SCHON** (SCRUM-398). Formelfeld `Text`, Werte `Kritisch`/`Erhöht`/`Normal` (geleitet aus `Is_Overdue__c` + `Priority`), auf dem Case-Layout schon als Readonly eingebunden. Die PO-Karte will ein Feld namens „Eskalationsstufe" als **Picklist** `Keine`/`Stufe 1`/`Stufe 2`.
→ **Kein Deploy von einem zweiten Feld mit demselben API-Namen möglich.** Das neue Feld trägt daher einen eigenen API-Namen (ADR-5): `Case.SLA_Eskalation__c`, Label `SLA-Eskalationsstufe`. Das SCRUM-398-Feld `Eskalationsstufe__c` bleibt unverändert (anderes Kriterium: Tage-Überfälligkeit, nicht Deadline).

**2. `Case.Is_Overdue__c` (SCRUM-390) ist NICHT das Feld „SLA überschritten".** Es ist eine Formel auf *Bearbeitungs-Tage*-Schwellen (High>2 / Medium>5 / Low>10 Tage) — eine andere, gröbere Metrik als die SLA-Zielzeit (High 4 h). Wiederverwendet würde die PO-Logik „Zielzeit überschritten" gegen die falsche Definition laufen.
→ Das neue `Case.SLA_Ueberschritten__c` ist ein **storable** Checkbox-Feld (wird vom Prozess gesetzt, ist keine Formel), semantisch getrennt von `Is_Overdue__c`.

**3. Premium-Marker: kein neues Account-Feld nötig.** Die PO fragt unter „Betroffene Objekte" nach `Account (Kennzeichnung „Premium-Kunde", falls Feld nicht vorhanden)`. Verifiziert: **`Case.Kundenstatus__c`** trägt genau diese Kennzeichnung als Picklist `Standard`/`Premium` (SCRUM-421, auf dem Case-Layout, `editable` für das Service-Team). Am `Account` existiert **kein** Premium-Feld (Repo `objects/Account/fields/*`, Org-SK). → ADR-6: Reuse von `Case.Kundenstatus__c`, kein neues Account-Feld, kein Account-Read-PS-Segment (Feld ist schon lesbar, wo Case lesbar ist).

**4. Org-„Case.Status" = `New`/`Working`/`Escalated`/`Closed` — es gibt keinen „Warten auf Kunde"**-Wert (Annahme 2, verifiziert via `sf sobject describe`). `ClosedDate != null` kennzeichnet den geschlossenen Fall (`IsClosed` ist ein abgeleiteter standardboolean). → Die Pause-Logik darf nicht auf einen konkreten Picklist-Wert hartcodiert werden; ADR-4 macht die Pause-Statusliste konfigurierbar, Default leer, mit Org-Setup-Step „Picklist-Wert `Warten auf Kunde` ergänzen" (non-blocking).

**5. BusinessHours = Org-Setup, kein Deploy.** Die Default-BusinessHours der Org ist `24/7`, `America/Los_Angeles` (Skill `salesforce-describe-first` §10 + SCRUM-424-Befund). `BusinessHours.diff()` behandelt Wochentage, Tagesfenster und Sommerzeit — dafür ist keine eigene Rechenmaschine nötig. Die *Mo–Fr*-Konfiguration (Annahme 1) ist **kein** deploybarer Metadaten-Typ (kein `BusinessHours` in der CLI-Registry) → **Org-Setup-Step** (DevOps, Test-Org beim Deploy + Prod-Org beim Release), kein repo-Artefakt.

---

## Akzeptanz-Kriterien → Artefakt-Mapping (Review-Kontrakt)

| AC | Behauptung | Beweise (muss existieren) |
|----|-----------|--------------------------|
| AC1 | 5 neue SLA-Felder auf Case vorhanden (API-Namen unten) | 3× `.field-meta.xml` (storable) + 2× Formel? NEIN: alle 5 **storable**, weil vom Prozess beschrieben werden (Zielzeit, Status, Eskalation, Letzter Lauf, Ueberschritten) + 1 internes storable `SLA_Uhr_gestoppt__c` + 1 internes `SLA_Akkumulierte_WorkingMins__c` |
| AC2 | Zielzeit = Creation + Prioritätszeitraum (Premium −25 %), Mo–Fr | `SLAService.computeDeadline(Case)` + Apex-Test (High/Medium/Low × Standard/Premium = 6 Assertions) |
| AC3 | SLA-Status: ≥ 20 % verbleibend = Im Zeitplan; < 20 % = Gefährdet; Zielzeit überschritten = Überschritten | `SLAService.evaluate(Case, now)` + Apex-Test mit 3× `@testVisible`-Zeitinject |
| AC4 | Eskalation: Keine→Stufe 1 bei Zielzeitüberschreitung; Stufe 1→Stufe 2 nach weiteren 4 h | `SLAService.evaluate` + Apex-Test (2 Stufen, idempotent bei zweitem Lauf) |
| AC5 | Pause/Resume: Case in Pause-Status → Uhr steht; Rückkehr in Bearbeitungsstatus → Uhr läuft fort; Eskalationsstufe bleibt bei Pause erhalten | `SLAService.evaluate` + `SLAConfig.getPauseStatuses()` + Apex-Test (gestoppt → Resume → Akkumulation korrekt) |
| AC6 | Geschossener Case: keine weitere Bewertung/Eskalation | Batch-SOQL-Filter `ISNULL(ClosedDate)` + Apex-Test (geschlossener Case wird nicht getackert) |
| AC7 | Prioritätswechsel: Zielzeit neu berechnet, verstrichene Arbeitszeit angerechnet | `SLAService.onPriorityChange(Case)` + Apex-Test (neu = old + (neuGesamt − verstrichen)) |
| AC8 | Periodische Bewertung über ALLE offenen Cases (Bulk, kein Timeout) | `SLAJobBatch` (QueryLocator, 200er-Chunks, ohne sharing, @testVisible-`now`) + Batch-Skalierungs-Test (house: `SCRUM367OpenCasesRebuildScaleTest`-Shape) |
| AC9 | Reaktive Bewertung bei Anlage / bei Prioritätswechsel / bei Statuswechsel | thin-Trigger `CaseSLATrigger` auf `Case` (after insert, after update) → `SLAService.evaluate`; Reentrance-Guard (house ADR-1, `isRunning`-static) |
| AC10 | Service-Mitarbeiter: nur Read auf allen 6 SLA-Felder (keine manuelle Edit) | `SCRUM438_SLA_Read`-PS (`readable=true, editable=false` × 6) + negativer FLS-Test (`SCRUM438SLAFlsTest`) |
| AC11 | Automatischer Prozess: ReadEdit auf allen 6 | `SCRUM438_SLA_System`-PS (`readable=true, editable=true` × 6) |
| AC12 | Layout: eigene Sektion „SLA" mit Zielzeit, Status, Eskalation, Ueberschritten (primär) + Letzter Lauf (Detail) | Neue `<layoutSection>` in `Case-Case Layout.layout-meta.xml` vor „System Information" (house: SCRUM-430/436-Section-Shape) |
| AC13 | Negativer FLS-Zugriffstest (Service-Mitarbeiter kann nicht editieren) | `SCRUM438SLAFlsTest` (house: `SCRUM390OverdueCaseFlsTest`-Shape, `System.runAs(userWithoutPS)`) |
| AC14 | Alle 12 PO-Test-Szenarien + FLS grün | Apex-Tests + Batch-Skalierungs-Test + FLS-Test (siehe Manifest) |

---

## Komponenten (exakte Pfade, auf `origin/master` verifiziert)

1. **6 neue Case-Felder** (alles **storable**, `type` unten) — `force-app/main/default/objects/Case/fields/…`
   - `SLA_Zielzeit__c` · `DateTime` — absolute Deadline (AC1)
   - `SLA_Status__c` · `Picklist` — `Im Zeitplan` (default) / `Gefährdet` / `Überschritten`
   - `SLA_Eskalation__c` · `Picklist` — `Keine` (default) / `Stufe 1` / `Stufe 2` (ADR-5, kein API-Namenkonflikt mit SCRUM-398)
   - `SLA_Ueberschritten__c` · `Checkbox` — `false` initial; wird `true`, wenn Zielzeit überschritten (AC4)
   - `SLA_Last_Checked__c` · `DateTime` — Zeitstempel des letzten Erfolgslaufs
   - `SLA_Uhr_gestoppt__c` · `Checkbox` — intern, `true` wenn Case in Pause-Status
   - `SLA_Akkumulierte_WorkingMins__c` · `Number(16,0)` — intern, kumulierter Business-Minuten bis Zielzeit (für Prioritätswechsel, AC7)

   *(Die PO spricht von 5 Feldern; die internen 2 für Laufzeit-Buchung sind ausdrücklich erlaubt („Weitere interne Felder … Entscheidung beim Architekt").)*

2. **Batch** (periodisch, AC8) — `force-app/main/default/classes/SLAJobBatch.cls`
   House-Shape 1:1 `CaseReminderBatch`: `implements Database.Batchable<SObject>, Database.Stateful`, `start()` liefert `Database.QueryLocator` über **alle offenen** Cases (`ISNULL(ClosedDate)`), 200er-Chunks, `without sharing`, `@testVisible`-Konstruktor mit injectierbarem `now` + `batchSize`. Pro Chunk: 1 SOQL (QueryLocator) + 1 konditionales Bulk-DML (nur geänderte Rows, Idempotenz).

3. **Scheduler** (AC8) — `force-app/main/default/classes/SLAJobScheduler.cls`
   House-Shape `implements Schedulable`, startet nur den Batch. CRON-Vorschlag: `0 * 0 ? * *` = **stündlich** (house: 01:00 = SCRUM-436, 02:00 = SCRUM-388, 03:00 = SCRUM-417, 06:00 = Opportunity-Overdue); **Org-Schritt**: `System.schedule('SCRUM-438 SLA', '0 0 * ? * *', new SLAJobScheduler());` — ohne läuft der Code nie (ADR-2).

4. **Service** (Kernlogik, AC2–AC9) — `force-app/main/default/classes/SLAService.cls`
   Pure static methods, bulkified (`Map<Id, Case>`-Bündel), **keine DML** (DML bleibt im Batch/Trigger), `now` als `@testVisible`-Parameter injizierbar:
   - `computeDeadline(Case c, DateTime now): DateTime` — ADR-3 (BusinessHours.diff), ADR-7 (Premium−25 %)
   - `onPriorityChange(Case oldRec, Case newRec, DateTime now): void` — AC7
   - `evaluate(Case c, DateTime now): void` — AC3 / AC4 / AC5 / AC6 / AC9

5. **Config** — `force-app/main/default/classes/SLAConfig.cls`
   - `DEFAULT_DEADLINE_MINUTES_BY_PRIORITY = Map<String,Integer>{ 'High'=>240, 'Medium'=>480, 'Low'=>1440 }`
   - `PREMIUM_DISCOUNT = 0.25` (ADR-7, PO: −25 %)
   - `ESCALATION_LEVEL2_AFTER_MINUTES = 240` (ADR-8, PO: +4 h nach Stufe 1)
   - `DANGER_THRESHOLD = 0.2` (PO: <20 % = Gefährdet, ADR-9)
   - `DEFAULT_PAUSE_STATUSES = Set<String>{}` (leer, ADR-4) — **Org-Setup-Step** ergänzt den exakten „Warten auf Kunde"-Wert
   - `getPauseStatuses(): Set<String>` und `isCaseInPause(Case c): Boolean`

6. **Reaktiver Trigger** (AC9) — `force-app/main/default/triggers/CaseSLATrigger.trigger`
   `after insert, after update on Case`. Thin, static-`isRunning`-Guard (ADR-1, house SCRUM-436), `try/finally`. Fire-Bedingungen (im Service geprüft, nicht im Trigger): `after insert` (Zielzeit setzen) ODER `after update` mit `Priority`-Wechsel (AC7) ODER `Status`-Wechsel (Pause-Resume/Stopp, AC5/6). Governor im Trigger: 0 SOQL, 0 DML.
   **Nicht** auf `Status`-Änderungen feuern, die nur den Status setzen und weder Pause noch Priorität betreffen (im Service per `getPauseStatuses()`-Differenz-Check).

7. **Permission Sets (2)** (AC10/AC11) — `force-app/main/default/permissionsets/…`
   - `SCRUM438_SLA_Read` — `readable=true, editable=false` × 6 Felder (house: `SCRUM436_CaseReminder`, `Shape 1:1` — nur `fieldPermissions`, kein Objekt-CRUD)
   - `SCRUM438_SLA_System` — `readable=true, editable=true` × 6 Felder (house: `SCRUM436_CaseReminderSystem`, `Shape 1:1 SCRUM388_…Write`)

8. **Case-Layout** (AC12) — `force-app/main/default/layouts/Case-Case Layout.layout-meta.xml`
   Neue `<layoutSection>` mit `customLabel=true`, `detailHeading=true`, `editHeading=true`, `label=SLA`, **vor** der „System Information"-Sektion (house: SCRUM-430/436-Section-Shape). Items: `SLA_Zielzeit__c`, `SLA_Status__c`, `SLA_Eskalation__c`, `SLA_Ueberschritten__c` (alle `behavior=Readonly`, **primary**); `SLA_Last_Checked__c` (`Readonly`, **Detail**). `SLA_Uhr_gestoppt__c` und `SLA_Akkumulierte_WorkingMins__c` bewusst **nicht** auf dem Layout (intern).

9. **Apex-Tests** (AC14) — `force-app/main/default/classes/…` + `manifest/…`
   - `SCRUM438SLATest.cls` — AC1–AC9, house-Shape `SCRUM436CaseReminderTest`
   - `SCRUM438SLAFlsTest.cls` — AC10/AC11/AC13, house-Shape `SCRUM390OverdueCaseFlsTest` (negativer Test via `System.runAs(userWithoutPS)` → expected `No such column` / `Field security exception`)
   - `SCRUM438SLAScaleTest.cls` — AC8 (Batch über > 5000 offene Cases, `@isTest` ohne Timeout-Problem, house `SCRUM367OpenCasesRebuildScaleTest`-Shape)
   - Manifests: `manifest/scr438-phase1-fields.xml` (7 CustomFields), `manifest/scr438-phase2-referencing.xml` (2 PS, 1 Trigger + 4 classes, Layout), `manifest/scr438-apextests.xml` (3 ApexClass)

---

## Architektur-Entscheidungen (ADRs)

**ADR-1: Apex über Flow.**
Rationale: SLA-Logik ist nicht trivial (Deadline-Berechnung über BusinessHours, Prioritätswechsel-Anrechnung, Pause/Resume, Eskalationsstufen, Bulk-Batch über den VOLLSTÄNDIGEN Bestand). Flow hätte hier (a) kein `BusinessHours.diff`-Äquivalent, (b) Batch-Bulk-Granularität 200er-Chunks mit QueryLocator nicht, (c) wiederholt Deployment/Schema-Validierungs-Fehler in diesem Projekt (SOUL-Default). ADR-Dokumentation: Apex.

**ADR-2: Batch + reaktiver Trigger (kein Flow-Schedule, kein Pure-Trigger).**
Rationale: AC8 verlangt „verliesslich: keine Duplikation der Logik zwischen Batch und Trigger.
Governor: Batch ohne sharing (deterministisch unabhängig vom Scheduled-User-Sharing; ADR-5), ohne Sharing NICHT die FLS-Wand (ADR-6) → Scheduled-User braucht das System-PS ADR-6.
Deterministische Testbarkeit: `now` per @testVisible-Konstruktor injizierbar (house, SCRUM-436).

**ADR-3: Deadline via `BusinessHours.diff()` — keine eigene Werktag/Zeitzonen-Rechenmaschine.**
Rationale verifiziert (Skill `salesforce-describe-first` S10 + SCRUM-424-Befund): `diff(defaultId, start, end)` behandelt Wochentage, Tagesfenster und Sommerzeit selbst. Die 13. PO-Zeile „Korrekte Werktag-Berechnung (Wochenende-/Feiertagsverhalten)" wird dadurch korrekt behandelt — Wochentage aus den BusinessHours-Regeln, Feiertage aus den BusinessHours-Holiday-Regeln (falls konfiguriert, ADR-4-S1). Die Org-S1-Konfig (Mo-Fr, S1) ist ein Org-Setup-Step (DevOps), kein repo-Artefakt.

**ADR-4: Pause = gespeichertes Feld + konfigurierbare Pause-Statusliste (nicht auf einen konkreten Status-Wert hartkodiert).**
Rationale: Org-S4-Befund — die Picklist trägt den Wert `Warten auf Kunde` nicht. Stattdessen:
- `Case.SLA_Uhr_gestoppt__c` speichert die Pause explizit (wird von `SLAConfig.isCaseInPause()` gesetzt, wenn `Case.Status` in `getPauseStatuses()` liegt).
- `getPauseStatuses()` liefert `DEFAULT_PAUSE_STATUSES` (leer) oder — falls vorhanden — einen CustomMetadata-Record (house: keine MetaData-Abhängigkeit, `if null`-Fallback).
- Resume: beim Statuswechsel **aus** der Pause-Liste `SLA_Uhr_gestoppt__c = false`.
- Eskalationsstufe bleibt bei Pause erhalten (PO-Regel: „Bereits erreichte Eskalationsstufe bleibt auch bei einer Pause bestehen"): `evaluate` prüft **nur** das Vorliegen/Überschreiten der *Deadline*, nie die aktuelle Pause, um die Stufe zu setzen.
- Org-Setup-Step S1 (non-blocking): `Warten auf Kunde` der `Case.Status`-Picklist ergänzen + `SLAConfig.DEFAULT_PAUSE_STATUSES = {'Warten auf Kunde'}` setzen (Developer ändert die Konstante im Commit entsprechend, nachdem der Wert in der Org liegt).

**ADR-5: Neues Feld trägt `SLA_Eskalation__c`, NICHT `Eskalationsstufe__c` (Befund 1). Label `SLA-Eskalationsstufe`.**
Rationale: API-Namens-Kollision mit dem SCRUM-398-Formelfeld (deploy-bar keine zweite Deklaration desselben Namens). Das SCRUM-398-Feld bleibt unverändert (anderes Kriterium: Tage-Überfälligkeit). Der PO-Fall „Eskalationsstufe" wird erfüllt durch `SLA_Eskalation__c` (Label `SLA-Eskalationsstufe`), Picklist `Keine`/`Stufe 1`/`Stufe 2`.

**ADR-6: 2 Permission Sets (Read + System), house-Shape SCRUM436/SCRUM388. Nie Profile.**
Rationale: SOUL-Default (FLS via Permission Set, nie Profile). Der Read-PS (`SCRUM438_SLA_Read`) ist dem Service-Team zuzuweisen (Deploy ≠ Assign — ADR-7-D1). Der System-PS (`SCRUM438_SLA_System`) dem Scheduled-User (Batch-Executor: Apex-DML prüft FLS auch in `without sharing`-Klassen, verified SCRUM-436).