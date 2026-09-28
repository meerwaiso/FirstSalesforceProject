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

## Befunde (fortgesetzt, oben)
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
