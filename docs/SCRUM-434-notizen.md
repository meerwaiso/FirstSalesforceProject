# SCRUM-434 Notizettel (DEV)

## Auftrag
DevOps-Kommentar 21974: Beide harten CI-Gates grün — (a) Smoke = FLS-Gate **Lücke C** (Textprüfung) + (b) Drift = Prod checkOnly (empirisch). Kein Merge von 434/435, bis beide grün.

## EXAKTES rotes Set (aus Live-Logs, 28.09.26)
- **Smoke / Lücke C (TEXT-Check, `System.runAs(` in comment-stripped source fehlt):**
  - SCRUM390OverdueCaseTest
  - SCRUM403LastCaseDateTest
  - SCRUM410CustomerTransferTest
  - SCRUM418CaseReactionTest
  - SCRUM419ReentryRegressionTest
  - SCRUM420EscalationKundeTest
  → 6 Klassen. 434 selbst NICHT dabei (hat runAs in FLS-Tests 5/6).
- **Drift / Prod checkOnly (EMPIRISCH, RunLocalTests):** 410, 434, 428.
  → 428 = SCRUM-435 Scope (geänderte Ingest-Handler + ac4/ac5), NICHT hier fixen. Stacked Merge.
  → 410 + 434 = echtes FLS-Problem → runAs-Wrapper um Ursache__c-DML.

## Befund Lücke C (master fls-gate.py)
- Testklasse rot, wenn: `@isTest` + toucht NEUES Feld (`Ursache__c` — auf master inexistent ⇒ "new") + KEIN `System.runAs(` in comment-stripped source.
- Gate-Docstring Fix-Rezept: Setup-Inserts (User+PSA) DRAUSSEN, fachliches DML/SOQL auf das neue Feld INNERHALB `System.runAs(u)`. Vorlage SCRUM424FirstResponseFlsTest.
- 31 der 51 Testklassen machen es so.

## Fix-Idiom (House Pattern, SCRUM370/424/432, 11/11 grün)
- User + PermissionSetAssignment im System-Kontext (User kann sich kein PSA geben).
- DANN `System.runAs(u) { DML/SOQL auf Ursache__c }`.
- Helper: `SCRUM434TestFixtures.ursacheUser(tag)` → Standard User + PSA für SCRUM434_Ursache, liefert User. (bereits geschrieben, 55 Zeilen)
- PS SCRUM434_Ursache = NUR FLS auf Ursache__c, KEIN Object-CRUD. Standard-User-Profil liefert Case-CRUD.

## Empirisch validiert (diese Session, Test-Org)
- Probe #1: Standard User + PSA + runAs + **closed** Case-Insert mit Ursache__c → PASSED.
- Probe #2: Standard User + PSA + runAs + **open** Case-Insert (Priority High, Status New) + **Restart** (firet CaseReaction/CaseEscalation-Trigger → Reactivation_Count__c) → PASSED. Kein "fields being inaccessible".
- ⇒ Voll-Draperi + Pinpoint-Draperi beide sicher. Pinpoint wählen (minimales Diff).

## Strategie (Pinpoint, minimales Diff)
Nur die `Ursache__c`-tragenden Case-DML/Update/Insert in `System.runAs(u)` wickeln.
Read-back-Queries OHNE Ursache__c-Selektion bleiben im System-Kontext.
`u = SCRUM434TestFixtures.ursacheUser(tag)` einmal vor dem runAs-Block (außerhalb).
6 Fixtures (390,403,410,418,419,420) + 434 (AC2 insert+query, AC3 query). 428 = touchen NICHT.

## Org-Fakten
- Deploy-Target: Test-Org (devops-agent@cline.test). API 61.0.
- 434-Branch hat alle 10 Fixtures bereits modifiziert (commit 2444ed2) → alle im RunLocalTests-Affected-Set.
- Ground truth Test-Org: 23/23 grün (Feld+PS existieren schon ⇒ kein Prod-Repro dort).

## Stand / Checkpoints
- [x] Helper SCRUM434TestFixtures geschrieben
- [x] 434 AC2/AC3 gephact
- [ ] 390, 403, 410, 418, 419, 420 patchen
- [ ] commit + push + PR #149 neu
- [ ] Deploy Test-Org RunSpecifiedTests grün
- [ ] Jira handoff
