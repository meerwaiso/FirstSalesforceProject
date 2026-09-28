# SCRUM-434 — Dev-Notizen
Quellen der Wahrheit: `docs/SCRUM-434-design.md` @ commit 5255638 (byte-exakte XML).

## Befunde (mit Befehl)
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
