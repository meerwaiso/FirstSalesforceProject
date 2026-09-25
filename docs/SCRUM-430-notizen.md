# SCRUM-430 — Developer-Notizen

Stand: 2026-09-25. Branch `feature/SCRUM-430-rueckruf-zeitfenster`, Worktree `scr430-wt`.
Design: `docs/SCRUM-430-design.md` (Commit 40eee48, freigegeben).

## Werte aus der Org (hier reinschreiben, sobald vorhanden)
- FieldPermissions für Contact.Rueckruf_Zeitfenster__c (welches Profil hat Read/Edit?): _noch offen_
- Wer sind die Test-Accounts für S2 (CLI-User + menschlicher Test-Account): _noch offen_
- FLS-Default des neu deployten Felds im Standard-User-Profil: _zu messen nach Phase-1-Deploy_

## Design-Ablösung (Abweichung, für Review-Dokumentation)
- Design §4.4a TC `reject_invalid_value`: „update auf 'Mittags' → Expect Exception".
  **Abgelöst**: Apex-DML auf ein Picklist-Feld warnt/verwirft einen fremden Wert NICHT (kein
  Exception). Statt AC1-Constraint „exakt 3 Werte" per Schema-API-Assert prüfen:
  `Contact.Rueckruf_Zeitfenster__c.getDescribe().getPicklistValues()` == {Vormittags,
  Nachmittags, Abends}. In Handoff-Kommentar + hier dokumentiert, Reviewer-Entscheidung.

## Manifeste (Reihenfolge: 1 → 1b → 2)
- `manifest/scr430-phase1-fields.xml`  (CustomField)
- `manifest/scr430-phase1-ref.xml`     (Layout + PermissionSet)
- `manifest/scr430-phase2-apextests.xml`(2 ApexClass)

## Deploy-Stand
- Phase 1 (Feld): _noch offen_
- Phase 1b (Layout+PS): _noch offen_
- Phase 2 (Tests): _noch offen_
- PS zugeordnet + Read-Back (Assignee-Liste + WITH USER_MODE Feldlesung): _noch offen_
