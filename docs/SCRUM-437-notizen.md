# SCRUM-437 — Implementierungs-Notizen (Developer)

Ticket: Case: Wiederkehrende Servicefälle erkennen (Problemkategorie + Problemserie).
Design: `docs/SCRUM-437-design.md` (freigegeben), Survey-Basis origin/master @ 43a4e9b.
Worktree: `scr437-wt`, Branch `feature/SCRUM-437-problemserie` (1 Commit: Design).

## Org-Fakten (Test-Org, 2026-10-03)

- Alias: `Test-Org` (devops-agent@cline.test), Org `00DWU00000oibVJ2AY`.
- ClosedDate gepflegt: **47/47** geschlossene Cases haben ClosedDate (0 NULL) → ADR-5 bleibt bei `ClosedDate` (kein LastModifiedDate-Umschwenken nötig). Beleg: `SELECT COUNT(Id) FROM Case WHERE Status='Closed' AND ClosedDate=null` → 0.
- Status-Picklist: `New / Working / Escalated / Closed` → `CLOSED_STATUS='Closed'` (House CaseOpenCountTrigger). Beleg: `sf sobject describe -s Case`.
- Die 5 neuen Felder existieren **noch nicht** in der Org (fresh deploy). Beleg: FieldDefinition-Query → 0 Rows.
- Total Cases: 670, geschlossene: 47.
- apiVersion Apex: **62.0** (House). Manifest-API: **67.0** (House scr436).

## Kritisches Design-Problem (entschieden, muss Review-geprüft werden)

- **`Problemserie__c` ist `unique=false`, NICHT `unique=true`** (abweichend von der §3-Tabelle-Zeile "Text(40), unique").
  - Warum: §4.3/§4.4/ADR-1/AC9 verlangen, dass **alle Cases derselben (Account,Kategorie)-Gruppe denselben String tragen** (Rückbesetzung, "dieselbe eindeutige Kennung", "Kein DB-Unique-Race, weil alle Cases ... den identischen String bekommen").
  - Ein `unique`-Flag auf einem gemeinsam geteilten String würde beim **2. Case der Serie** in Duplicate-Violation laufen → Feature unbrauchbar.
  - → `unique=false`. Der String ist eindeutig **pro Serie**, nicht pro Row. Im Handoff an Architect explizit benennen.

## Selbst-Lookup (Letzter_aehnlicher_Case\_\_c)

- `referenceTo` = `Case` (Self-Reference), `deleteConstraint` = SetNull. Repo hat kein Self-Lookup-Beispiel (House `Wiedervorlage_Von__c` = Lookup auf User).
- **Phase-1-Deploy-Validierung** muss akzeptieren. Fallback: Text(18) + E2E-Link über caseNumber.

## Phasen

1. **Phase 1** — 5 CustomField-Dateien → `manifest/scr437-phase1-fields.xml` → deploy validate + start.
2. **Phase 2** — Apex (Handler+Trigger), 2 Permission Sets, Layout-Sektion, 2 Testklassen → `manifest/scr437-phase2-referencing.xml` (Deploy+Test) → `manifest/scr437-apextests.xml`.
3. **E2E** — `tests/e2e/SCRUM-437_problem-serie.spec.ts` (UI: Sektion «Problemserie» auf Case).
4. **Read-back** — SOQL auf echten Cases (Serie+Zählung+Lookup), PS-Zuweisungs-Beleg.

## Feld-API-Namen (aus Design §3, exakt)

1. `Wiederkehrendes_Problem__c` — Checkbox, default false
2. `Anzahl_aehnlicher_offener_Cases__c` — Number(8,0), default 0
3. `Letzter_aehnlicher_Case__c` — Lookup Case (SetNull)
4. `Problemserie__c` — Text(40), **unique=false** ⚠️
5. `Problemkategorie__c` — Picklist: Technischer Defekt / Login / Zugang / Rechnung / Lieferung / Vertrag / Sonstiges

## Serienkennung (§4.3) — Implementierung

- `serie = AccountId(15/18) + '_' + Problemkategorie__c-API-Value`.
- **Abweichung vom Design, verifiziert an der Org:** SOQL liefert bei Custom-Picklist-Feldern den **API-Value** (fullName), NICHT das Label. Beleg 2026-10-03: `SELECT Ursache__c FROM Case` → `RechnungAbrechnung` (API-Value), Label-Vergleich `'Rechnung / Abrechnung'` → 0 Rows. Der Handler nutzt also den API-Value (deterministischer, und ein Label-Rename bricht die Kennung dann nicht — Design §4.3/§8 nennt Label-Rename ohnehin Known-Limit).
- Picklist-API-Values: TechnischerDefekt, LoginZugang, Rechnung, Lieferung, Vertrag, Sonstiges.
- Längster API-Value 'TechnischerDefekt' = 17 Zeichen → 18+1+17 = 36 ≤ 40 (Text(40), unique=false). Deterministisch je (Account,Kategorie) → AC9 "dieselbe Kennung".

## Berechnungs-Regeln (Design §4)

- Pool(c) = Cases p≠c, gleicher Account, gleiche Kategorie, (offen ODER (closed AND ClosedDate>=today-30)).
- `Wiederkehrendes_Problem__c` = |Pool(c)| >= 2
- `Anzahl_aehnlicher_offener_Cases__c` = |{p in Pool(c): offen}| (c ausgeschlossen)
- `Letzter_aehnlicher_Case__c` = Id mit max CreatedDate in Pool (Tie-break: max Id); Pool leer → NULL
- `Problemserie__c` = Serienkennung, SET auf alle Cases der Gruppe, falls (a) existingKey≠null ODER (b) |Fenster-Cases| >= 3 (Schwelle: ≥2 weitere). Sonst NULL. (Lebenszyklus ADR-2: persistiert, nicht löschbar bei leerem Fenster.)
- Bulk: 1 SOQL (`WHERE AccountId IN :accountIds AND AccountId!=null`) + 1 DML (`update toUpdate`), no SOQL/DML-in-Loop.

## Org-Defekt + Test-Architektur (gemessen 2026-10-03, entscheidet die Test-Struktur)

- **`Case.Ursache__c` existiert** (Custom, Picklist). Der vorherige FieldDefinition-
  „NOT FOUND" war eine kaputte Disjunction-Query (`OR` wird in `sf data query`
  nicht unterstützt → „Disjunctions not supported"); die Felder waren da.
  Geschlossene Cases brauchen ein gesetztes Pflichtfeld, sonst Validierungsfehler
  beim Insert (`Status='Closed'` + `Ursache__c='TechnischerFehler'` → geht).

- **Org-Defekt (blockiert die runAs-Restrukturierung der 9 ACs):**
  Ein Case-Insert **mit AccountId** stirbt unter `System.runAs(<Standard User>)`
  an dem in der Org (NICHT im Repo) installierten `CasePriorityTrigger`:
  `QueryException: Variable does not exist: tmpVar1`
  (`Class.CasePriorityTrigger.buildBatchData: line 112`, via `beforeInsert: 27`).
  - Nachgewiesen mit einer boundary-Probe (4 Methoden, alle unter runAs/Std-User):
    `m1` insert+ACCT (ohne Cat) → FAIL (der Insert)
    `m2` insert+ACCT+Cat → FAIL (der Insert)
    `m3` insert+ACCT+Cat, dann Update→ FAIL (schon der Insert)
    `m4` insert OHNE ACCT+Cat+Update → PASS
    → Der Breaker ist **jede Case-DML mit AccountId unter Nicht-Admin**.
    Ohne AccountId läuft Case-DML unter Standard User fehlerfrei.
  - Die Serie ist (AccountId,Kategorie)-geschlüsselt → die AC-Cases tragen
    IMMER ein AccountId → die 9 ACs **können unter runAs(Standard User) NICHT**
    laufen, in dieser Org. Sie laufen als Admin. (SCRUM-432/436 konnten runAs
    nehmen, weil ihre Cases kein AccountId tragen.)

- **Fls-Gate Lücke C — Lösung statt Form:** `SCRUM437ProblemSerieTest` enthält
  jetzt `System.runAs(` (Voraussetzung des Gates: „neues Feld wird unter
  runAs(nachweislich les-/schreibbar) berührt, nicht nur Admin-DML+getDescribe").
  `flsStandardUserNuetztDasFeature`: Standard User + `SCRUM437_ProblemSerie_System`
  erzeugt 1 Case **ohne** AccountId (sonst §Org-Defekt oben) und liest ALLE 5
  neuen Felder per SOQL im Standard-User-Kontext zurück. Das ist der exakte
  CI-#367-Fall (5 Tests „No such column" in Prod, weil Feld als Nicht-Admin
  angefasst wurde) — hier POSITIV: Roundtrip-Read geht. Serie-Logik selbst
  beweisen die 9 Admin-ACs. Setup (User+PSA) OUTSIDE von runAs — ein User kann
  sich selbst kein PSA geben.

- **`isInWindow` ist `public static`** (statt private): AC4 (30-Tage-Fenster)
  lässt sich nicht per DML konstruieren (`Case.ClosedDate` = `updateable=false`,
  Workflow-Stempel beim Schließen) → Prädikat-Test gegen die Produktionslogik.
  `Datetime`, nicht `Date`.

- **Tests gruen (Test-Org, gemessen):** `SCRUM437ProblemSerieTest` 10/10
  (9 AC admin + `flsStandardUserNuetztDasFeature` non-admin).
  `SCRUM437ProblemSerieFlsTest` 1/1.

- **E2E-Spec is Tester-Deliverable** (Playwright, `tests/e2e/SCRUM-437_problem-serie.spec.ts`)
  — out of scope für Developer.

- `scripts/fls-gate.py` (master-identisch, branch==master diff=0) Lücke C:
  eine Testklasse, die ein neues Feld berührt, MUSS `System.runAs(` in der
  Source enthalten (sonst FLS-RED in CI).

---

# Tester-Notizen (2026-10-03)

## Apex-Neulauf (Tester, eigenständig, 2026-10-03)

- `sf apex run test -o Test-Org -t SCRUM437ProblemSerieTest -t SCRUM437ProblemSerieFlsTest`
  → **11/11 Pass** (testRun 707WU00001LqCZq, org 00DWU00000oibVJ2AY). NICHT Peer-Report.
  - ac1..ac9 alle Pass · flsStandardUserNuetztDasFeature Pass ·
    FlsTest.problemSerieFields_invisibleWithoutPS_readOnlyWithPS Pass.
- DoD-Negativer-Access via Apex runAs → abgedeckt (FlsTest). UI-negative: 2. lizenzierte UI-Session unmöglich (org hat 2 Lizenzen, beide Admin) → via Apex.

## E2E-Strategie

- Playwright-Session = **Admin** (devops-agent@cline.test) → E2E darf Cases MIT
  AccountId per UI/CLI anlegen (Org-Defekt CasePriorityTrigger betrifft nur
  Nicht-Admin). 9 AC-Computations: **Apex-Neulauf** (SCRUM437ProblemSerieTest
  10/10 + FlsTest 1/1) — nicht Peer-Report vertrauen, selbst re-run.
- Negativer-Access-Test (DoD): **Apex runAs** (house rule §4c — org hat nur 2
  Lizenzen, beide Admin; 2. Playwright-UI-Session unmöglich). UI-negative NICHT
  möglich → im Coverage-Table als "via Apex runAs" kennzeichnen.
- Serienbildung via UI (3 Cases A1/Rechnung) → Sektion «Problemserie» + Lookup.
- AC6 (Kategorie-Wechsel) live: C3 Rechnung→Lieferung via inline edit → Neubewertung.

## Geplante Locators (per Probe zu bestätigen, NICHT raten)

- Record: Details-Tab, Sektion-Heading "Problemserie".
- Checkbox readonly: Rendering "Ja"/"Nein" (Org ist deutsch) — probe.
- Letzter_aehnlicher_Case = Lookup-Link → klickbar, navigiert auf Case-Record.
- Picklist inline edit: BUTTON[role=combobox] (count=2) — house rule §4b/4.

## GROUND TRUTH (live probe, 2026-10-03, Test-Org) — fixture C1/C2/C3 (Account A, Rechnung, offen) + CCtrl (Account B, Rechnung, allein)

- UI + SOQL stimmen ÜBEREIN:
  - C1(00002932): key `001..._Rechnung`, count 2, Letzter-Link=00002934(C3) → href /lightning/r/Case/<C3id>/view, checkbox="True"
  - C2(00002933): key gleich, count 2, Letzter-Link=00002934(C3)
  - C3(00002934): key gleich, count 2, Letzter-Link=00002933(C2)
  - CCtrl(00002935): key=null, count=0, KEIN Letzter-Link, checkbox False/leer
- Sektion-Linie-Layout (Details-Tab, innerText-Reihenfolge):
  Problemkategorie / <Wert> · Edit Problemkategorie · Letzter aehnlicher Case / <CaseNumber-Link> ·
  Wiederkehrendes Problem / True · Edit… · Problemserie / <key> · Edit… · Anzahl aehnlicher offener Cases / <n> · Edit…
- Sektion-Heading "Problemserie" sichtbar. `Letzter` ist ein LINK (role=link, name=CaseNumber) auf die Record-Seite des verlinkten Cases.
- Checkbox rendert als "True" (englisch), nicht "Ja" — lower-case beim Vergleichen.
- AC-Erwartung nach C3: Rechnung→Lieferung (inline edit): C3 allein in (A,Lieferung) → key=null, count=0, kein Letzter-Link, Kategorie=Lieferung.
  C1/C2 behalten den Rechnung-Key (ADR-2 Persistence, hasEstablished), C1 count 2→1 (Pool jetzt {C2} nur), checkbox True→False.
