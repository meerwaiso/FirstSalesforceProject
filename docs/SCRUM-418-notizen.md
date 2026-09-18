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

## Mechanismus-Hypothese (für Developer — zu bestätigen per Debug-Log)
Handler = **Delta-Inkrement** (liest DB-Zähler, +1, schreibt zurück). In nach-update
feuert der handler-`update` einen **Re-Entry-Lauf**; dort gilt:
`old.Status` (DB) ist bereits `New`, `new.Status` (Trigger.new) auch `New` →
Guard `n.Status != o.Status` = false → 2. Lauf ist ein no-op. **In einer einzigen
Apex-DML-Transaktion** stimmt das (belegt: server DML → 1).
- Die Doppelzähl tritt **nur** bei einem externen REST-/CLI-Update auf. Vermutlich
  erhält der nach-update-Lauf bei einem REST-API-Update ein `Trigger.new`/`Trigger.old`
  (Status-Granularität) anders als bei In-Org-DML, sodass der Guard den Re-Entry NICHT
  unterdrückt und der Handler ZWEIMAL inkrementiert — ODER der REST-Aufruf sendet
  einen Status-Wechsel in zwei DML-Phasen.
- **Nächste Evidenz = Debug-Log eines einzelnen REST-Reopens** (Trigger-Feuerzählung;
  `EXECUTION_STARTED` pro Trigger-Lauf, `recompute`-Zählung). Debug-Log-Fetch der Apex-
  MessageLog lieferte in dieser Session leere Bodies (`Location=Monitoring`, API-Logs) —
  `sf apex log get` gibt ein List-Result mit leerem `body` für die v63/v67-Logs zurück;
  der Developer soll den Trace in seiner Session ziehen (DebugLevel via
  `DeveloperName`, TraceFlag `LogUserId`+`DebugLevelId`+`StartDate`/`ExpirationDate`).

## Reproduktions-Skripte (diese Session, in `docs/`)
`_finalsidebyside418.py` (in-org Apex vs REST vs CLI, frische Cases), `_iso418.py`
(PB-Check + REST vs CLI), `_logread418.py`. Fixture-Cases `SCRUM418_*` in `docs/_state418.json`.
