# SCRUM-418 Notizen — Tester (verifizierte Befunde)

## Grundprinzip: Ich verifiziere am Ziel-System, nicht am Tool-Output.
Jeder Wert unten ist per `sf`/SOQL/Apex/DOM gegen die Test-Org `devops-agent@cline.test`
(Org `00DWU00000oibVJ2AY`) gelesen — nicht aus dem CLI-Exit-Code.

## Apex (named run, beide SCRUM-418-Klassen)
- `sf apex run test --class-names SCRUM418CaseReactionTest --class-names SCRUM418CaseReactionFlsTest --code-coverage --wait 10`
  → **exit 0, 8/8 Passed, 100 %-Coverage** auf `CaseReactionHandler` + `CaseReactionTrigger`.
  (Log `docs/_apex_418.log`.)
- Coverage-Listing zeigt **4 aktive Case-Triggers** in der Org: `CaseReactionTrigger`,
  `CaseOpenCountTrigger`, `CasePriorityTrigger`, `LastCaseDateTrigger`.

## Existenz + FLS (admin-Blick + PS-Zuweisung)
- `sf sobject describe -s Case`: `Reactivation_Count__c` (Number 3/0, „Reaktivierungszahl"),
  `Last_Reactivation__c` (DateTime, „Letzte Reaktivierung") — beide vorhanden (Date `docs/_case_describe.json`).
- PS `SCRUM418_Reactivation` (0PSWU00000WIZPt4AP) **an der Session-User zugewiesen**
  (PermissionSetAssignment-Row vorhanden) → die UI-Session sieht beide Felder (POSITIV geprüft).
- „Standard User"-Profil existiert (41 Profile) → FLS-Test-Voraussetzung erfüllt.

## Layout (Repo-XML, Classic `Case-Case Layout` Zeile ~185)
- `Reactivation_Count__c` + `Last_Reactivation__c` in Sektion „Überwachung", beide
  `readOnly=false`-fremd — im Layout als Felder aufgelistet (read-only-Präsentation per
  FLS-PS, edit=false). Lightning-FlexiPage NICHT im Repo (Architekt-Kommentar) →
  Lightning-Sichtbarkeit = FLS (PS) + App-Builder-Platzierung (Org-Schritt, DevOps).

## REPORT
- `Wiedereroeffnungen_3Monate` = `00OWU00000QSeUz2AL`, Standard-ReportType `CaseList`,
  `groupingsDown` (Desc) auf `Reactivation_Count__c`, `scope=organization`,
  `timeFrameFilter INTERVAL_LAST90` auf `Last_Reactivation__c` (ADR-5 — dokumentierte
  Fenstereinschränkung, KEIN Defekt).

## AK3 (neu = 0, Datum leer) — POSITIV
- Frisch per API erzeugter Case, nie geschlossen: `Reactivation_Count__c = 0`,
  `Last_Reactivation__c = null` (SOQL). **Bestanden.**
- Erste Öffnung zählt NICHT (Guard `old.Status != 'Closed'`), im Apex-Test + Live bestätigt.

## ⚠️ DEFECT (reproduzierbar, pfadspezifisch) — externes Single-Field-REST / `sf data update record`
Isolationsexperimente (alle an frischen Cases in der Org, je 1 Reopen Closed→New),
verifiziert per SOQL-Read ZURÜCK aus der Org:

| Pfad                                        | Reopens | Zähler nachher | Erwartet |
|---------------------------------------------|---------|----------------|----------|
| **Lightning-UI (Playwright, echter User)**  | 1       | **1**          | 1 ✅     |
| In-Org-Apex-DML (`sf apex run`)             | 1/2     | **1/2**        | 1/2 ✅   |
| REST Single-Field-PATCH                     | 1       | **2** ❌       | 1        |
| REST Full-Payload-PATCH                     | 1       | **2** ❌       | 1        |
| CLI `sf data update record`                 | 1       | **2** ❌       | 1        |
| (früher isoliert REST R1/R2)                | 1       | 2 / 2          | 1        |

- **Primärer User-Pfad (in-app Lightning) = korrekt.** AK4 bestanden für UI + Apex.
- **Jeder EXTERNE REST/CLI-Update = doppelt gezählt** (Reopen A/B/C = 2/2/2).
- **Korrektur der alten Vermutung:** Vor-Kompression stand hier „Lightning speichert
  per REST → UI-Pfad betroffen (rot)". **FALSCH** — sauberes Side-by-Side
  (`docs/_sidebyside2_418.py`, 4 frische Cases, gleicher Moment): UI=1, REST=2.
  Lightning sendet intern ein volles Record-Payload mit mehr Kontext; der Trigger
  zählt da korrekt. Der Defekt ist auf den EXTERNEN Single-Field-API-Update
  beschränkt (Integrations-/Bulk-API, nicht UI, nicht in-Org-Apex).
- Akzeptanc-Status (alle mit Zielsystem-Readback belegt):
  - AK1 ✅ — Felder auf Case sichtbar (Probe: `Edit Reaktivierungszahl`), Werte per SOQL.
  - AK2 ✅ Observed: **24 Cases im 90-Tage-Fenster** mit Reaktivierung, absteigend nach
    Reaktivierungszahl (Top: Count 6). `LAST_N_DAYS:90` wird vom CLI-SOQL-Parser
    abgewiesen (Token `:`) → Fenster client-seitig in Python (skript `docs/_ak2obs418.py`).
  - AK3 ✅ — neuer Case: Count=0, `Last_Reactivation__c` null.
  - AK4 ✅ für UI-Pfad — Playwright-Spec `SCRUM-418.spec.ts` grün (1 passed, 32.8s):
    Status→New verifiziert per SOQL + Count=1 sofort nach Save. HTML-Report:
    `playwright-report/index.html` (lokal, NICHT committen).
- **Urteil: GRÜN für User-Pfad**; externer API-Pfad → SCRUM-419 (Bug, developer-agent,
  verlinkt).

## Root-Cause-Ausschluss (was ich NICHT als Ursache gefunden habe)
- **Kein zweiter Trigger, der das Feld schreibt:** Tooling `ApexTrigger`-Query (Body) —
  `CaseReactionTrigger` (1 aktive Version, Body **byte-identisch** mit Repo),
  `CaseOpenCountTrigger` (schreibt nur `Contact.Last_Real_Case_Date__c`),
  `CasePriorityTrigger` (insert-only, setzt `Priority`), `LastCaseDateTrigger`
  (setzt `Case_Last_Case_Date__c`) — **keiner** schreibt `Reactivation_Count__c`.
- **Kein Flow:** Tooling `FlowDefinition`-Query → 0 Records (Case).
- **Kein Process Builder:** `ProcessDefinition` in Tooling-Objektliste = False (PB nicht
  als Flow-Metadaten aktiv), `FlowDefinition`(Flow) = 0.
- **Kein Workflow Field Update auf dem Feld:** Tooling `WorkflowFieldUpdate` → 1 Record
  (Case-Priority, `touchesReactivation=False`).
- **Keine Feld-Formel:** `Reactivation_Count__c.field-meta.xml` = `type=number`,
  `updateable=false`, kein `formula`.
- **Kein anderer Apex-Caller:** Tooling `ApexClass`-Body-Scan — nur
  `CaseReactionTrigger` + die 2 SCRUM-418-Test-Klassen referenzieren
  `CaseReactionHandler`/`Reactivation_Count__c`. `AccountReactivationBatch` = SCRUM-388
  (Account/Opportunity), schreibt NICHT das Case-Feld.

## Mechanismus — BELEGT per Debug-Log (exklusiv EXTERNER REST-Pfad; UI + Apex unbeeinträchtigt)
EIN REINES REST-Single-Field-Update (Closed→New, 1 Aufruf) zeigt in der Org:
- `CaseReactionTrigger AfterUpdate` feuert 4x in 2 EXECUTION_CONTEXTS.
- Handler DB-Reads (`SELECT Id, Reactivation_Count__c`): 2x; Case-UPDATE-DML: 2x → +2.
- Kette: Externes REST laedt die Case; after update liest Handler DB-Zaehler (0),
  schreibt 1. Handler-DML laedt den Trigger noxmal im selben Kontext; der 2. Lauf
  liest ZAEHLER=1 (bereits inkrementiert) und schreibt 2.
- **Warum nur extern:** Bei in-Org-Apex-DML und in-app-Lightning-UI laedt zwar
  dieselbe Handler-DML den Trigger zurueck, aber der Guard / der Kontext unterdrueckt
  den 2. Lauf korrekt → +1 (UI: Playwright-Run Count=1; Apex: 1 Reopen→1, 2→2).
  NUR beim externen Single-Field-REST-Update bleibt der 2. Lauf aktiv → +2.
**Moegliche Fixes (developer-agent):** static Re-Entry-Flag, das den Handler im
2. AfterUpdate-Lauf kuerzt; oder `Database.isRollbackRequired()`/
`Trigger.isExecuting()`-Check.

## Reproduktions-Skripte (diese Session, in `docs/`)
`_finalsidebyside418.py` (in-org Apex vs REST vs CLI, frische Cases), `_iso418.py`
(PB-Check + REST vs CLI), `_logread418.py`. Fixture-Cases `SCRUM418_*` in `docs/_state418.json`.
