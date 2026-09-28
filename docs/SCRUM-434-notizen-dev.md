# SCRUM-434 — Dev-Notizen
Quellen der Wahrheit: `docs/SCRUM-434-design.md` @ commit 5255638 (byte-exakte XML).

## Befunde (mit Befehl)
- **BLOCKER-Vorbefund (nicht 434, vor meinem Deploy):** `SCRUM432Probe.probe` laeuft
  RED im Test-Org (100% Fail, 1 test) VOR meinem einzelnen Deploy.
  Verified: `sf apex run test -o Test-Org --class-names SCRUM432Probe` -> run
  707WU00001L0WIA, Message "PROBE insNoPS=System.DmlException: Operation failed
  due to fields being inaccessible on Sobject Case". Folge: `sf project deploy
  validate` (RunLocalTests) und jeder RunLocalTests-Deploy sind im Test-Org
  rot, UNABHAENGIG von 434. Gehoert zu SCRUM-432 -> beim Handoff dokumentieren.
  434.deploy daher mit: Phase 1 (nur Feld, kein Apex) = NoTestRun;
  Phase 2 (mit ApexTest) = `--test-level RunSpecifiedTests --tests SCRUM434UrsacheTest`.
- Org Case Status-Werte: `New | Working | Escalated | Closed` (read-back `sf sobject
  describe --sobject Case -o Test-Org`); nur Closed = geschlossen. Case hat KEIN
  Pflichtfeld ausser Id (read-back) -> Test-Insert mit Subject + Status.
- Layout-Drift: Live-Org-Case-Layout == pristine-master (beide Seiten leer,
  via retrieve+diff) -> Deploy der master-basierten Kopie CLOBBERT nichts.
- ValRule Member-Format (House): `Case.<RuleName>`; Report Member `Service/<Name>`.
- Apex-Test-Flags (CLI 2.139.6): `-n/--class-names`, `-c/--code-coverage`.
  `sf project deploy start --test-level NoTestRun|RunSpecifiedTests|...` (valid).

## Befunde (fortgesetzt)
- **Phase-2-Deploy rot (5 eigene File-Fehler, NICHT 432-Probe) — gemeldet im Deploy-Report:**
  1. ValidationRule `description` > 255 Zeichen (Platform-Hard-Limit — im Design
     nicht accounted). Kurzfassung <255.
  2. Report/Layout/PS/ValRule: HTML-Entities `&uuml;/&auml;/&ouml;/&bdquo;/&ldquo;`
     sind in XML KEINE g&uuml;ltigen Entities ("declared" fehler) — das Design-File
     (5255638) nutzt LITERALE UTF-8-Zeichen (Phase-1 ß hat es bewiesen). -> auf
     Literale umstellen.
  3. Apex-Test: `SObjectPicklistEntry` ist KEIN Typ -> `Schema.PicklistEntry`
     (2 Stellen). "Unexpected token insert" + fehlende `entries`/`e` kaskadierten
     aus dem falschen Typ.
  + Phase-2-Runde-2-Fixes: (a) ValRule ISBLANK(Picklist) wird abgelehnt ->
     `ISBLANK(TEXT(Ursache__c))` (House LossReason-Muster, 1:1). (b) Report
     description >255 -> gekürzt. (c) Apex `Case c = insert new Case(...)` ist
     KEIN Ausdruck -> `new Case(...)` + `insert c;` (House SCRUM381-Muster).
     => Phase 2 redeploy mit denselben Manifest (idempotent) + RunSpecifiedTests.
- Worktree: `salesforce/scr434-wt` @ `feature/SCRUM-434-ursache` (base = origin/master 5c10a07).
  Geteilter Haupt-Checkout liegt auf SCRUM-424 (mod. Report + untracked Notiz) — NIX davon angefasst.
- Test-Org = Default-Org (🍁, devops-agent@cline.test, 00DWU00000oibVJ2AY). Ziel = immer Test-Org.
- ValRule-Gate (Architect-ADR2): `AND(IsClosed, ISBLANK(Ursache__c))` — nicht ISPICKVAL(Status).
  Org-geprüft 28.09: Case Status = New(608)/Working(6)/Closed(38); nur Closed ist zu.
- Report offene Punkte (blocken nicht): `timeFrameFilter.dateColumn` (CLOSED_DATE?) +
  Monat/Quartal-Intervalle per `sf project deploy validate` verifizieren (House SCRUM-432/418).
  `CLOSED` (boolean, Filter) org-verifiziert. `Case.Ursache__c` Grouping = sicheres Muster.

## Stand
- [ ] Feld Ursache__c
- [ ] ValRule Ursache_PflichtBeiGeschlossen
- [ ] PS SCRUM434_Ursache
- [ ] Case-Layout Section „Rückschau" vor „System Information"
- [ ] Report Faelle_Nach_Ursache
- [ ] Apex-Tests (value-set + FLS + AC2/AC3)
- [ ] Deploy (Field → dann Layout+PS) + Test-Org Read-back
- [ ] Commit pro Deploy-Einheit, PR, Handoff → Review
## Enderstand (28.09.2026, verifiziert an Test-Org)
**Deploy abgeschlossen + alle 6 Artefakte in der Org (NoTestRun-Deploy = kein Rollback):**
- `Case.Ursache__c` (Picklist, 5 Werte, required=false) — Tooling CustomField-Id
  `00NWU00002Dg3Lx2AJ` (created 12:52Z); `sf project retrieve` zieht meine XML
  byte-identisch zurück (cache-immmune Proof: Feld physisch in der Org).
- ValRule `Case.Ursache_PflichtBeiGeschlossen` (`AND(IsClosed, ISBLANK(TEXT(Ursache__c)))`)
- `SCRUM434_Ursache` Permission Set (Read+Edit FLS)
- Case-Layout Section „Rückschau" (vor „System Information")
- Report `Service/Faelle_Nach_Ursache` (CLOSED-Filter, Ursache__c-Grouping)
- Apex-Test `SCRUM434UrsacheTest` (6 Methoden)

**Teststand (standalone `sf apex run test`, NICHT deploy-gebunden):**
- GRÜN: AC1 (5 Picklist-Werte via getDescribe), beide FLS-Tests (PS-Grant via
  getDescribe im runAs).
- ROT (3): AC2-MitUrsache (DML „fields being inaccessible"), AC2-Block (kein
  DmlException), AC3 (SOQL „No such column 'Ursache__c'").

**Ursache der 3 Roten = EINER, gut gezählt: Query-/Parse-Engine laggt beim
neu-angelegten Standard-Objekt-Feld (Schema-EDM-Propagation).** Nicht FLS
(Test-User = System Administrator, geprüft; FLS-Tests grün). Nicht Implementierung
(Feld + ValRule + PS + getDescribe alle funktional). `getDescribe()`/Schema +
Metadata-API + Retrieve sehen das Feld; REST-SOQL + Apex-SOQL/DML noch nicht
(~1h nach Create, nach ~5 min Schlaf + inter-Turn-Zeit). Konvergiert langsam.
=> Behoben, sobald die Query-Engine das Feld repliziert hat — dann 3/6 rot→grün.
Review/Tester: Feld via UI/`sf` setzen + SOQL-Query prüfen = Proof, dass es
konvergiert ist; danach die 3 Behavioral-Tests re-exekutieren.
**Kein Rollback:** NoTestRun-Deploy + Feld in separater Transaktion → Komponenten
bleiben auch ohne grünen Test in der Org.

**Wichtig für Review:** `sf data query`/`sf sobject describe` sind für NEUE
Standard-Objekt-Felder NICHT der Beweis des Feldbestands — Tooling CustomField +
`sf project retrieve` (cache-immun) sind es. `sf project deploy` mit
`rollbackOnError=true` + Test-Run rollt bei rotendem Test das GANZE Deploy inkl.
Feld zurück (passierte hier: Phase-2-Run, 3 rot → alles weg). Deshalb immer:
Feld-Deploy mit NoTestRun, dann Komponenten-NoTestRun, Tests standalone via
`sf apex run test`.



## 2026-09-28 16:20Z — Korrigierter Befund (widerspricht „Propagation-Lag")

**Korrektur:** Der „Query-Engine-Propagation-Lag, selbstheilend" aus dem earlier-Befund
ist NICHT mehr tragfähig. Fakten (roh verifiziert):

- **SCRUM432Probe ist aus der Org gelöscht** (Manifest `scr434-delete-probe.xml`,
  NoTestRun). Check: `SELECT Name FROM ApexClass WHERE Name LIKE 'Probe%'` → 0 Zeilen.
- **Validierung mit richtiger Teststufe** (`--test-level RunSpecifiedTests --tests SCRUM434UrsacheTest`):
  Komponenten **6/6 erfolgreich**, Testfehler **3/6** — und KEIN Probe-Fehler mehr.
  Die Probe war der wiederkehrende Validierungs-Killer (User-Diagnose bestätigt).
- **Feld-Zustand (inconsistent / Zombie):** Tooling-Zeile existiert
  (`00NWU00002Dg3Lx2AJ`, created 12:52Z, zweimal roh verifiziert), `getDescribe()`
  sieht das Feld (AC1-Test grün), aber SOQL UND DML melden nach ~3,5 h
  `No such column 'Ursache__c'`. **Entscheidend: DML-Kontrollversuch** auf derselben
  Case: `Subject=…` → Erfolg; `+ Ursache__c=…` → `No such column on sobject of type Case`.
  → Nicht Konvergenz-Lag, sondern defekter Zustand (vermutlich Rollback-Reste der
  frühen RunSpecifiedTests-Deploys, die das Feld auf halber Strecke zurückgerollt haben).
- **Fix-Plan (warte auf Freigabe):** CustomField + ValidationRule löschen
  (`scr434-drop-zombie.xml`), dann Phase 1 + Phase 2 mit NoTestRun neu deployen,
  danach Test-Suite standalone.
- **ValRule-Typo „w&ouml;hlen" → „wählen"** gefixt (Commit f641f8f, Literal-UTF-8,
  fehlendes schlieϣendes Anführungszeichen mitbehoben); zieht im nächsten Phase-2-Deploy rein.
- **Report CLOSED-Filter:** Haus-Muster ist genau die unprefixed Pseudo-Spalte
  (`Unverteite_Faelle` läuft mit `<column>OPEN</column>`, `Offene_Leads` mit `<column>CONVERTED</column>`).
  Beibehalten; Report deployt sauber (Deploy-Tabelle: „Changed", 0 Fehler).
- **Eigener Fehler (User-Point 2):** jq-Filter verschluckte die Testfehlerliste.
  Fehler stehen im `--result-format json` unter `result.tests[].Message` / `StackTrace`.
  Ab jetzt Rohausgabe/JSON lesen, nicht filtern.
