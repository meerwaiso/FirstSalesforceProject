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

## ⚠️ DEFECT (reproduzierbar, systemisch) — AK4 / Zählverhalten externer Pfade
Isolationsexperimente (alle an frischen Cases in der Org, je 1 Reopen Closed→New),
verifiziert per SOQL-Read ZURÜCK aus der Org:

| Pfad                            | Reopens | Zähler nachher | Erwartet |
|---------------------------------|---------|----------------|----------|
| In-Org-Apex-DML (`sf apex run`) | 1       | **1**          | 1 ✅      |
| In-Org-Apex-DML (`sf apex run`) | 2       | **2**          | 2 ✅      |
| REST PATCH (`sf api request`)   | 1       | **2** ❌       | 1        |
| CLI `sf data update record`     | 1       | **2** ❌       | 1        |
| (REST) früher isoliert R1/R2    | 1       | 2 / 2          | 1        |

- **Server-DML-Transaktion (Apex) = korrekt; jeder EXTERNE REST-Update = doppelt.**
  Reproduziert 7×. Deterministisch (nicht Race).
- Lightning UI speichert einen Status-Wechsel per **REST → der UI-Pfad ist betroffen.**
  ⇒ AK4 („sofort nach Speichern den erhöhten Wert zeigen") zeigt für reale UI-User
  vermutlich den **2-Fachen** Wert.

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

## Mechanismus — BELEGT per Debug-Log (REST-Reopen, log 07LWU00000Pbwhl2AB)
EIN REST-Reopen (Closed→New, 1 update-Aufruf) zeigt in der Org:
- `CaseReactionTrigger AfterUpdate` feuert **4x** in **2 EXECUTION_CONTEXTS**
  (2x pro Kontext).
- Handler DB-Reads (`SELECT Id, Reactivation_Count__c`): **2x**
- Case-UPDATE-DML des Handlers: **2x**
- Netto: Count 0 -> 2 (statt +1).

Belegte Kette: Externes REST-Update laedt die Case; in after update liest der
Handler den DB-Zaehler (0), schreibt 1 zurueck. Diese Handler-DML in after update
laedt den Trigger auf Case NOCHMALS im selben Kontext; dort ist `Trigger.old`
bereits der DB-Stand und `Trigger.new` derselben Status, der Guard
`n.Status != o.Status` sollte den Re-Entry unterdruecken — aber: der 2. Lauf
liest ZAEHLER=1 aus der DB (bereits inkrementiert) und schreibt 2. Ergebnis:
2 DML-Write-Phasen = +2.

Warum nur extern? In einer einzigen in-Org-Apex-DML-Transaktion laedt sich die
Handler-DML zwar auch auf den Trigger zurueck, aber in einem Apex-Testkontext /
`sf apex run` wird der 2. Lauf nicht als eigenhaetiger REST-API-Transaktionskontext
getrackt — die ZAEHLUNG bleibt bei 1 (belegt: in.org Apex 1 Reopen -> 1, 2 -> 2).
Bei externer REST-Transaktion laedt sich der gleiche Mechanismus zu 2 Writes auf.

AUSDRUCK: Der Handler macht eine DML in nach-update, die den eigenen Trigger
retriggered. Das Re-Entry-Schutz-Kriterium reicht fuer den externen Pfad nicht
aus (2 Writes im Log sichtbar). Moegliche Fixes fuer @developer-agent:
1. Re-Entry-Flag (static Boolean in einem Utility-Klasse, vor nach-UPDATE-Phase
2. `Database.isRollbackRequired`/`Trigger.isUpdating`-Abfrage
3. `System.enqueueBatchable`/`@Future` — aber AK4 verlangt „sofort beim speicheren", kein Batch/kein man. Trigger
Konsequenz AK: AK4 ist in der Org mit 1 Reopen = 2 verletzt.

## Reproduktions-Skripte (diese Session, in `docs/`)
`_finalsidebyside418.py` (in-org Apex vs REST vs CLI, frische Cases), `_iso418.py`
(PB-Check + REST vs CLI), `_logread418.py`. Fixture-Cases `SCRUM418_*` in `docs/_state418.json`.
