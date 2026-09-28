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
- [x] Feld Ursache__c
- [x] ValRule Ursache_PflichtBeiGeschlossen
- [x] PS SCRUM434_Ursache
- [x] Case-Layout Section „Rückschau" vor „System Information"
- [x] Report Faelle_Nach_Ursache
- [x] Apex-Tests (value-set + FLS + AC2/AC3)
- [x] Deploy (Field → dann Layout+PS) + Test-Org Read-back
- [x] Commit pro Deploy-Einheit, PR, Handoff → Review
## Enderstand (28.09.2026, verifiziert an Test-Org)
**⚠ VERALTET — nur noch historisch relevant. Die Diagnose „Query-Engine-Propagation-Lag,
selbstheilend" in diesem Abschnitt ist FALSCH (FLS-Wand + IsClosed-Vor-Zustand).
Gültiger Stand: Abschnitt „ENDGÜLTIGER Befund" weiter unten.**
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



## 2026-09-28 ~19:00Z — ENDGÜLTIGER Befund (setzt beide früheren „Ursachen" außer Kraft)

**Die drei roten Tests hatten ZWEI getrennte Ursachen, keinesfalls Propagation/Timing.
Beide sind behoben; Stand: 6/6 grün (standalone `sf apex run test`, ausgeführt gegen die
aktive Org, nicht geglaubt).**

### Ursache 1 (Hauptursache, 4 der 3+1 Fehler) — fehlende FLS-Zuweisung (korrekt so: „FLS-Wand")
`SCRUM434_Ursache` war deployt, aber **niemandem zugewiesen**. Für den ausführenden User war
das Feld unsichtbar → `No such column` im SOQL, `fields being inaccessible` im DML, ValRule
könnte ein unsichtbares Feld nicht prüfen. @user hat das gemessen
(`SELECT Assignee.Name FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM434_Ursache'`
→ 0 Zeilen). **Reparatur (erledigt):**
```
sf org assign permset -n SCRUM434_Ursache -o Test-Org                      (devops-agent)
sf org assign permset -n SCRUM434_Ursache -b meerwais.osmani@resourceful-… -o Test-Org
```
Beide nötig (FLS-Gate verlangt namentlich devops-agent UND Meerwais Osmani).
Read-back: `SELECT Id, Ursache__c FROM Case LIMIT 1` → läuft durch (Field sichtbar).
→ AC2-MitUrsache + AC3 + beide FLS-Tests damit grün. **Timing war nie dabei.**

### Ursache 2 (letzter Rest: AC2_OhneUrsache_Block) — `IsClosed` wertet Vor-Zustand aus
Die ValRule ist **aktiv korrekt deployt** (Tooling-Id `03dWU00000D8Z17YAF`,
`active=true`, Formel byte-geprüft), feuerte aber NICHT beim Schliessen-Eingabe-Akt.
Entscheidende DML-Befunde (gleiche Org, dieselbe Reg):
- **Insert** `new Case(Status='Closed', Ursache__c=null)` → wird **GESPEICHERT** (Reg feuert nicht),
  Zeile wird erst POST-COMMIT auf `IsClosed=true` gelesen.
- **Update** einer bereits geschlossenen Zeile (beliebiges Feld) → **WIRD BLOCKIERT** (Reg feuert).
Ursache: `IsClosed` ist ein abgeleitetes Standard-Boolean; bei der DML-Aktion, die den Case
schließt, ist `IsClosed` im Reg-Eval noch `false` (Vor-Zustand), erst danach `true`. Das
Design-`AND(IsClosed,…)` blockt also nie genau den Schliess-Akt — die Lücke, die AC2 prüft.

**Fix (erledigt, in Org verifiziert → 6/6 grün):** Gate auf den Zustand der DML-Aktion selbst
gestützt statt auf das erst später sichtbare abgeleitete Boolean:
```
AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Ursache__c)))
```
`ISPICKVAL(Status,'Closed')` deckt den Schliess-Akt (Insert UND Update) ab, `IsClosed` bleibt
als Zweitsicherung für später geschlossene/renamed Status. Nach Deploy (`Changed`, Succeeded)
und Neu-Run: alle 6 Tests Pass.

### Stand jetzt (verifiziert, nicht geglaubt)
- 6/6 `@isTest`-Methods grün (statisch gegen aktive Org gelaufen).
- Permission Set beiden Benutzern zugewiesen (FLS-Gate-konform).
- SCRUM432Probe aus der Org weg; UTF-8-„wählen" korrigiert; Report CLOSED-Filter (Haus-Muster)
  deployt fehlerfrei.
- Branch `feature/SCRUM-434-ursache`; PR #149.

### Für Review (Kontrakt-Prüfpunkte)
- AC2: `IsClosed`-Gate ist bewusst `OR(IsClosed, ISPICKVAL(Status,'Closed'))` — ADR-Ausnahme,
  Begründung oben (Vor-Zustand-Problem). Review soll das als bewussten Fix anerkennen, nicht als
  Abweichung ohne Grund.
- FLS-Zuweisung ist **kein** Teil des Deploys (kein Metadata) — sie ist ein einmaliger Org-Schritt.
  Beim Prod-Handoff muss sie wiederholt werden (beide User). In den Deploy-Notizen vermerkt.


**Korrektur:** Der „Query-Engine-Propagation-Lag, selbstheilend" aus dem earlier-Befund
ist NICHT mehr tragfähig. Fakten (roh verifiziert):

- **SCRUM432Probe ist aus der Org gelöscht** (Manifest `scr434-delete-probe.xml`,
  NoTestRun). Check: `SELECT Name FROM ApexClass WHERE Name LIKE 'Probe%'` → 0 Zeilen.
- **Validierung mit richtiger Teststufe** (`--test-level RunSpecifiedTests --tests SCRUM434UrsacheTest`):
  Komponenten **6/6 erfolgreich**, Testfehler **3/6** — und KEIN Probe-Fehler mehr.
  Die Probe war der wiederkehrende Validierungs-Killer (User-Diagnose bestätigt).
- **WAHRE FELD-URSACHE (gemessen vom @user 17:45Z):** Permission Set `SCRUM434_Ursache`
  war deployt, aber NIEMANDEM zugewiesen
  (`SELECT Assignee.Name FROM PermissionSetAssignment WHERE PermissionSet.Name='SCRUM434_Ursache'`
  → 0 Zeilen). Feld für den ausführenden User unsichtbar → `No such column` im SOQL,
  `fields being inaccessible` im DML = die FLS-Wand (Skill salesforce-describe-first §4).
  `getDescribe()` als System-Admin sah das Feld trotzdem (Admin sieht alles) →
  das war die Quelle der Fehldiagnose „Feld existiert, also Propagation".
  DER "Zombie/Rollback"-Befund (vorher) war FALSCH, zurückgezogen.
  **Reparatur (erledigt 18:53Z):** `sf org assign permset -n SCRUM434_Ursache -o Test-Org`
  (devops-agent) + `-b meerwais.osmani@resourceful-bear-6f1u4j.com` (2. User, FLS-Gate).
  Read-back `SELECT Id, Ursache__c FROM Case LIMIT 1` → grün.
  (Manifest `scr434-drop-zombie.xml` bleibt als NICHT ausgeführter Fallback im Repo.)
- **ValRule-Typo „w&ouml;hlen" → „wählen"** gefixt (Commit f641f8f, Literal-UTF-8,
  fehlendes schlieϣendes Anführungszeichen mitbehoben); zieht im nächsten Phase-2-Deploy rein.
- **Report CLOSED-Filter:** Haus-Muster ist genau die unprefixed Pseudo-Spalte
  (`Unverteite_Faelle` läuft mit `<column>OPEN</column>`, `Offene_Leads` mit `<column>CONVERTED</column>`).
  Beibehalten; Report deployt sauber (Deploy-Tabelle: „Changed", 0 Fehler).
- **Eigener Fehler (User-Point 2):** jq-Filter verschluckte die Testfehlerliste.
  Fehler stehen im `--result-format json` unter `result.tests[].Message` / `StackTrace`.
  Ab jetzt Rohausgabe/JSON lesen, nicht filtern.
- **ZWEITER Fehler derselben Art (verursachte den Zombie-Irrlauf):** Tooling-SOQL mit
  ungültigen Spalten (`FullName` filterbar ist NICHT, `ErrorConditionFormula` heißt
  im Tooling-Context anders) lief STUMM leer/fehlerlos durch und wurde als
  „ValRule nicht in der Org" fehlgelesen. Sie war die ganze Zeit aktiv deployed
  (Tooling-Id `03dWU00000D8Z17YAF`, `active=true`, korrekt auf `EntityDefinitionId=Case`).
  **Lektion:** leere Tooling-Ergebnisliste = NICHT Beweis für Abwesenheit;
  Spaltennamen zuerst per `sf sobject describe -t -s ValidationRule` prüfen.

## 2026-09-28 ~22:30Z — REJEKTION-SPIEL: die 10 Fixtures sind nicht die ganze Erreichweite des org-weiten Gates

Re-Review (Jira-Kommentar 21837) freibt ADR-2 (die `OR(IsClosed, ISPICKVAL(Status,'Closed'))`-
Klausel im ValRule-File) und wirft das Ticket zurück, weil mein 6/6 (nur die eigene
`SCRUM434UrsacheTest`) das orgweite Gate nicht sah: das Gate greift auf **jede** schließende
Case — auch auf fremde Test-Fixtures, die per Code schließen.

**Fix (dieser Commit):** alle 10 benannten Fixture-Klassen (`SCRUM365/367/370/390/403/410/418/419/420
OpenCases/OpenCount/Overdue/LastCaseDate/CustomerTransfer/CaseReaction/Reentry/EscalationKunde`-
Test) tragen jetzt `Ursache__c = 'HowToAnfrage'` an (a) jeder `new Case(...)` (49 St.; konditional
unnötig aber uniform → auch offene Fälle, die das Gate nicht treffen, tragen den Wert; kein Test
inspiziert das Feld) und (b) vor jedem update-auf-Closed (`<recv>.Ursache__c = 'HowToAnfrage';`
vor `<recv>.Status='Closed';`, 10 St.) — essenziell für sObjects, die das Feld nie SELECT-ten
(370 `closeCases` / `closeOneCase` laden nur `Id,Status`). Verifiziert: `SCRUM370OpenCasesRatingTest`
(vorher rot im Drift-Gate) ist jetzt grün.

**Aber der Voll-Lauf (RunAllTestsInOrg, Run 707WU00001L2XzB) zeigt, dass das Gate eine
Elfte Erreichweite hat, die nicht in der 10er-Liste stand:** `SCRUM428CaseIngestHandler.applyDup`
(Productionscode, Zeile 328, `c.Status='Closed'` beim Dedup-Abschluss, kein `Ursache__c`) wird von
`SCRUM428IngestTest.ac4_case_number_in_text_dedupes` + `ac5_same_contact_same_bereich_dedupes`
ausgeübt → 2 Fails (Run-Ausgang **309/311 = 99 %**). Das ist SCRUM-428-Code — NICHT in der
10er-Fixture-Direktive, und die Erreichweite ist Produktionsrelevant (echtes Dedup-Ingest schließt
heute ohne Ursache → wäre im Produkt blockiert). Hausregel „Checkout geteilt, Zweig nicht" →
SCRUM-428s Handler wird hier **nicht** selbst redigiert.

**Zwei legitime Optionen (bitte freigeben, sonst Re-Review rot):**
1. 11te Fixture-Fix auf die richtige Weise: `SCRUM428IngestTest` (Testklasse) baut den
   Dup-Source-Case mit `Ursache__c` + `SCRUM428CaseIngestHandler` bleibt angetastet (produktions-
   neutral) — aber das ist SCRUM-428-Ticket und ich will nicht in fremdes Produktionsmetadata
   gehen ohne Freigabe. ODER
2. SCRUM-428 als eigenständiges Follow-up-Ticket (Handler setzt `Ursache__c` bei `applyDup`; das
   korrigiert die Produktion, nicht nur die Tests).

Bis dahin: 10er-Fix committed/greent in diesem PR; die 2 SCRUM428IngestFails bleiben bewusst offen
und blocken den Run — der Voll-Lauf ist erst bei 311/311 grün.
