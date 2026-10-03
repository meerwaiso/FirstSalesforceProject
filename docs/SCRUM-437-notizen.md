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

## Selbst-Lookup (Letzter_aehnlicher_Case__c)
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
- `Anzahl_aehnlicher_offener_Cases__c` = |{p in Pool(c): offen}|   (c ausgeschlossen)
- `Letzter_aehnlicher_Case__c` = Id mit max CreatedDate in Pool (Tie-break: max Id); Pool leer → NULL
- `Problemserie__c` = Serienkennung, SET auf alle Cases der Gruppe, falls (a) existingKey≠null ODER (b) |Fenster-Cases| >= 3 (Schwelle: ≥2 weitere). Sonst NULL. (Lebenszyklus ADR-2: persistiert, nicht löschbar bei leerem Fenster.)
- Bulk: 1 SOQL (`WHERE AccountId IN :accountIds AND AccountId!=null`) + 1 DML (`update toUpdate`), no SOQL/DML-in-Loop.
