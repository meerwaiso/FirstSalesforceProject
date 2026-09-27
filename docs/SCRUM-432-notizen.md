# SCRUM-432 — Notizen (Developer)

## Auftrag
Persönliche Wiedervorlage auf Case: 2 Storage-Felder (Datum, Notiz)
+ Mechanismus (Lookup `Wiedervorlage_Von__c`, Formel `Wiedervorlage_Heute_Offen__c`)
+ Listview „Wiedervorlagen – heute offen" + Layout-Sektion + PS
`SCRUM432_Wiedervorlage_ServiceTeam`. Rein deklarativ, kein Apex/Trigger/Flow.
Autoritative Build-Spec: `docs/SCRUM-432-design.md` (Commit 030910e).

## Felder (API-Name exakt, keine Umlaute außer Label)
| API-Name | Label | Typ | Pflicht |
|---|---|---|---|
| Wiedervorlage_Datum__c | Wiedervorlage Datum | Date | optional |
| Wiedervorlage_Notiz__c | Wiedervorlage Notiz | Text 255 | optional |
| Wiedervorlage_Von__c | Gesetzt von | Lookup→User (SetNull) | optional |
| Wiedervorlage_Heute_Offen__c | Wiedervorlage heute offen | Formel→Checkbox | read-only |

Formel (ADR-2):
```
AND(
  Wiedervorlage_Von__r.Id = $User.Id,
  NOT(ISBLANK(Wiedervorlage_Datum__c)),
  Wiedervorlage_Datum__c <= TODAY()
)
```
Nicht im Layout — nur in der Liste.

## KERN-Offenpunkt: Kundenspalte (AC2, FALLENRISIKO)
- `ACCOUNT.NAME` ist im Repo nur auf Opportunity (Hochwertige_Chancen) verifiziert.
- Case-Listview mit Owner zeigt `CORE.USERS.ALIAS`, nicht Account-Name.
- ACCOUNT.NAME für Case NICHT verifiziert. Erste Aktion: dry-run der Listview.
- Kandidaten: ACCOUNT.NAME (Report-Schema), sonst aus Validator-Fehler ablesen.

## Deploy-Sequenz (ADR-9)
1. phase1-fields: die 4 CustomField
2. phase2-referencing: PS + ListView + Layout (Case-Case Layout)
3. apextests: SCRUM432WiedervorlageTest, SCRUM432WiedervorlageFlsTest (RunSpecifiedTests)
4. PS zuweisen an Targetorg-User + 2. Service-Konto, PermissionSetAssignment +
   1 Feld durch reale Session lesen (Read-Back).

## Befunde (hier eintragen)
- Phase-1-Deploy OK: 4 CustomFields in Test-Org (job 0AfWU00000bkWxF0AU).
  Manifest brauchte `Case.`-Prefix bei CustomField (bare Members -> "No source-backed components", House-Pattern scr382/421/428/430).
- Default-FLS nach Deploy: 0 Zeilen FieldPermissions auf alle 4 Felder (Baseline "kein Zugriff" ohne PS -> AC8-Negativ testbar, Grant kommt aus dem PS).
- **Kernfrage ADR-6 BEANTWORTET: `ACCOUNT.NAME` ist gültige Case-Listview-Spalte**
  (Phase-2-Validate status 0). Zusätzlich via `/analytics/report-types/CaseList`
  detailColumnInfo: ACCOUNT.NAME -> Account.Name (7 Col total; Spalten hängen unter
  reportExtendedMetadata.detailColumnInfo, NICHT reportColumns!).
- PS-Description limit 255 (Deploy-Fehler "data value too large") — kurz halten.
- Phase-2-Manifest: ListView-Member mit `Case.`-Prefix (scr403 `Contact.Letztes_Anliegen`);
  ohne Prefix: "named in package.xml, but not found in zipped directory".
- Phase-2-Validate status 0 (ListView + Layout + PS).
- **ACCOUNT.NAME als Case-Listview-Spalte: VALIDIERT und DEPLOYED** (Phase-2-Deploy 0AfWU00000bkY2z0AE). ADR-6-Kernfrage gelöst.
- Apex-Tests: 11/11 PASS (10 Value TCs + 1 FLS AC8) via `sf apex run test -n <klasse> -o Test-Org` (FLAGS: `-n`, `-o` — KEIN `--class-name`!). Deploy-embedded-Run zeigt leerer counter, separater Run liefert die Tabelle.
- **`bulk` ist reserviertes Apex-Wort (API 63+)** — Bezeichner `cases` statt `bulk`.
- **`[SELECT COUNT() ...]` liefert Integer direkt**, kein List, KEIN `.size()` (House: scr367/384/424).
- **Read-only Formelfeld nicht via Apex-DML "update" testen**: Compiler-Fehler "Field is not writeable" (kein DmlException zur Laufzeit) — read-only-Natur gehört per getDescribe().isUpdateable() (im FlsTest) bewiesen, nicht per try/update.
- **PS Assign + Read-Back ERLEDIGT**: Assign zu devops-agent (0PaWU00000qetPd0AI) + meerwais.osmani (0PaWU00000qetSr0AI); Read-Back via echter CLI-Session: Test-Case 00002842 mit Datum=2026-09-27, Notiz=Readback432, Von=null, Formel=false (korrekt: kein Setzer). Record nach Read-Back gelöscht.
- **CLI-Flags gemessen**: `sf apex run test` nutzt `-n` (class-names) + `-o` (target-org); `sf data delete record` nutzt `--record-id` (KEIN `--id`); `sf data create record --values` bricht bei Leerzeichen WERTE (Subject=SCRUM432 readback → "Malformed key=value") — Werte ohne Spaces.
- **SOQL**: Case-Nummer Feld heißt `CaseNumber` (KEIN `CASE_NUMBER`, das ist nur Report-Token).
- Deployment-IDs: Phase1 0AfWU00000bkWxF0AU, Phase2 0AfWU00000bkY2z0AE. Apex-Deploy (scr432-apextests.xml) Status 0, Details in /tmp/scr432_apex.json — keine Job-ID hier behauptet.

## Lücke C Fix (2026-09-27, nach Architect-Rejection PR #146)

- **Lücke C erkannt**: `fls-gate.py` auf origin/master ist die neuere 292-Zeilen-Version
  (Zweig-`fls-gate.py` hat nur Lücke A+B). Regel C: Testklasse, die neue Felder berührt,
  muss `System.runAs(` in der comment-gestreiften Quelle enthalten; sonst rot.
  CI deployt den mergenden Stand -> die master-Version zählt (CI-Run 36315786493:
  Step 9 Apex SUCCESS, Step 11 FLS-Gate FAILED).
- **Probe-first (SCRUM432Probe, Throwaway, nachher aus Branch entfernt)**:
  Standard-User OHNE PSA: `insert Case` mit den 4 Feldern ->
  `DmlException "fields being inaccessible"` (= genau das Lücke-C-Symptom).
  MIT PSA (`SCRUM432_Wiedervorlage_ServiceTeam`): insert=ok, update=ok, read=ok,
  Formel=true. DELETE=TypeException (Standard User löst Cases nicht -> design-konform,
  Tests rollen Txn zurück, DELETE bewusst nicht geprüft).
  => Fix-Form bestätigt, BEVOR Umbau: Business-DML im runAs, Setup (User + PSA) DRAUSSEN
  (Standard User kann sich selbst keine PSA geben).
- **SCRUM431-Memory-Konflikt aufgelöst**: "Full-DML-in-runAs bricht 6/14" galt dort,
  weil der Reader die DML-Rechte NICHT hatte. Hier: Standard-User-Grund-CRUD + PSA für
  Feld-FLS -> 11/11 green im runAs. Regel: Vor runAs-Migration Probe an der Org messen.
- **Ergebnis**: SCRUM432WiedervorlageTest umstrukturiert (alle 10TCs im
  `System.runAs(Standard-User + PS)`; TC10 Bulk 200 cases ebenfalls). 11/11 PASS
  (Run `707WU00001KrlhC`, 17,3 s). FLS-Test (AC8) lief bereits mit runAs, untouched.
- **FLS-Gate lokal simuliert (master-Logik, `--base origin/master --org Test-Org`):
  GATE_EXIT=0** — 4 Felder "ok (SCRUM432_Wiedervorlage_ServiceTeam)", "FLS-Gate grün."
  (Temporäre Kopie `scripts/.__fls-gate-master-tmp.py` danach gelöscht, nicht committet.)
- **CLI-Befunde (CLI 2.150.6)**:
  a) Manifest AUSSERHALB Repo -> "No source-backed components" (Manifest muss im Repo stehen).
  b) `.cls` ohne `.cls-meta.xml` wird nicht als source-backed erkannt.
  c) `-v <alias>` existiert nicht -> `--target-org <alias>`.
  d) Apex-Testmethode braucht EIGENES `@isTest` (Klassen-Level reicht nicht), sonst
     `Tests Ran: 0 / outcome Skipped` ohne Fehlermeldung.
  e) `sf apex get test -i <RunId> -o <username>` zeigt abgeschlossene Runs (kein `--wait`-Flag).

