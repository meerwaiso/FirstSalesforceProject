# SCRUM-430 — Developer-Notizen

Stand: 2026-09-25. Worktree `scr430-wt`.
Design: `docs/SCRUM-430-design.md` (Commit 40eee48, freigegeben).

## Werte aus der Org (gemessen, Test-Org, 2026-09-25)

- **Feld deployt:** `Contact.Rueckruf_Zeitfenster__c` live (Phase 1, NoTestRun, Succeeded).
  Read-back FieldDefinition: Label "Rückruf-Zeitfenster".
- **Layout deployt:** `Contact-Contact Layout` (Phase 1b, Succeeded). Org-Retrieve bestätigt:
  Feld steht direkt hinter `ConsentDate__c` in Sektion **"Contact Information"** (2. Spalte),
  `<behavior>Edit</behavior>`. AC2 erfüllt.
- **PermissionSet deployt:** `SCRUM430_RueckrufZeitfenster` (Phase 1b, Succeeded), nur FLS read+edit.
- **S2 (zuweisung) — ERLEDIGT + Read-back:**
  - `sf org assign permset -o Test-Org -n SCRUM430_RueckrufZeitfenster -b <user>`
  - Read-back `SELECT Assignee.Username, Assignee.Profile.Name FROM PermissionSetAssignment
WHERE PermissionSet.Name='SCRUM430_RueckrufZeitfenster'` →
    - `devops-agent@cline.test` (System Administrator)
    - `meerwais.osmani@resourceful-bear-6f1u4j.com` (System Administrator) — PO-Test-Konto
  - Hinweis: beide Accounts sind System Administrator → haben FLS ohnehin via Profil.
    Die Zuweisung ist korrekt (Deploy≠Assign-Hausregel) und für den negativen AC4-Test
    irrelevant (der nutzt einen frischen Standard-User OHNE PS, nicht diese Accounts).
- **FLS-Default des neu deployten Felds (wichtige Messung):**
  `SELECT Parent.Name, PermissionsRead, PermissionsEdit, Parent.IsOwnedByProfile
 FROM FieldPermissions WHERE Field='Contact.Rueckruf_Zeitfenster__c'` → **1 Zeile**
  (nur das PermissionSet, read+edit, IsOwnedByProfile=false).
  `... AND Parent.Name='Standard User'` → **0 Zeilen**.
  → **Das Standard-User-Profil bekommt KEINE Read+Edit auf das neue Feld.**
  → **WICHTIG (Abweichung zum Design-§6):** Design-Prämisse "Standard-User-Profil erhält
  automatisch Read+Edit (SCRUM-421-Lesson) ⇒ S1 Profil-Sperre nötig" hat sich NICHT
  reproduziert. Der negativer AC4-Test (`withoutPS_fieldInvisible`, frischer Standard-User
  OHNE PS, `SELECT ... WITH USER_MODE`) PASST OHNE jeden S1-Schritt.
  → S1 ist in der Test-Org NICHT blockierend; AC4 hält, wie gemessen. Für Prod-Org
  vermutlich dieselbe Default-Situation. Für den Architect dokumentiert (Review).

## Manifeste (Reihenfolge: 1 → 1b → 2) — ALLE deployt & erfolgreich

- `manifest/scr430-phase1-fields.xml` (CustomField) → Succeeded, NoTestRun
- `manifest/scr430-phase1-ref.xml` (Layout + PermissionSet) → Succeeded, NoTestRun
- `manifest/scr430-phase2-apextests.xml` (2 ApexClass) → Succeeded, RunSpecifiedTests

## Deploy-Stand — ALLES deployt & verifiziert

- Phase 1 (Feld): Succeeded
- Phase 1b (Layout+PS): Succeeded
- Phase 2 (Tests): Succeeded
- PS zugeordnet + Read-Back: ERLEDIGT (2 Assignees, s. oben)

## Test-Fazit (Read-back `sf apex run test`, Run Id 707WU00001KVxM3)

**9/9 gesamt, 100% Pass**

- SCRUM430RueckrufZeitfensterTest: defaultValue_empty, overwrite_vormittags_to_abends,
  picklistHasExactlyThreeValues, value_abends, value_nachmittags, value_vormittags — alle Pass
- SCRUM430RueckrufZeitfensterFlsTest: precondition_contactReadable, withPS_readableAndWritable,
  withoutPS_fieldInvisible — alle Pass
- AC1: Wertematrix + leer + exakt 3 Werte ✓
- AC2: Feld sichtbar in "Contact Information" (Layout, read-back Org) ✓
- AC3: lesbar + editierbar mit PS (insert/update/select durch) ✓
- AC4: SELECT ohne PS (Standard-User) wirft → Feld unsichtbar ✓ (ohne S1)

## Offene Punkte für den Handoff / Review

1. **S1 unnötig (Test-Org):** negativer FLS-Test hält ohne Profile-Sperre. Design-§6/ADR-7-Prämisse
   (SCRUM-421-Lesson "neue Felder = Read+Edit im Standard-Profil") gilt hier NICHT.
   → Architect entscheiden, ob S1 für Prod-Org dennoch gesetzt wird (Defensive).
2. **Beide Test-Accounts sind System Administrator** → FLS-Positiv (AC3) für sie trivial grün.
   Der FLS-Test erzeugt eigene Standard-User (korrekte Methode). Kein Problem, aber für Tester
   dokumentieren: AC3/AC4 werden über die erzeugten Standard-User geprüft, nicht über die
   System-Admin-Accounts.

## Design-Ablösung (Abweichung, für Review-Dokumentation)

- Design §4.4a TC `reject_invalid_value`: „update auf 'Mittags' → Expect Exception".
  **Abgelöst**: Apex-DML warnt/verwirft einen fremden Picklist-Wert nicht reliably.
  Stattdessen AC1-Constraint „exakt 3 Werte" per Schema-API-Assert (`picklistHasExactlyThreeValues`).
  In Handoff-Kommentar + hier dokumentiert.

## Tester-Befunde (2026-09-25, SCRUM-430 Testphase)

- **E2E neu geschrieben**: `tests/e2e/SCRUM-430-rueckruf-zeitfenster.spec.ts` (3 Tests, 37s, grün)
  - AC2 Test 1: Feld-Label + Edit-Button auf dem Details-Tab sichtbar, kein Aufklappen
  - AC2 Test 2: Wert „Abends" (per SOQL gesetzt) wird im read-View korrekt gerendert
  - AC3 Test 3: Picklist „Nachmittags" via Inline-Edit ausgewählt, gespeichert, SOQL bestätigt
- **Picklist-DOM** (empirisch verifiziert, 2026-09-25):
  - Im edit mode: `BUTTON[role=combobox][aria-label="Rückruf-Zeitfenster"]` +
    `DIV[role=listbox][aria-label="Rückruf-Zeitfenster"]` → `getByLabel(...).count() = 2`
  - Der House-Helper `startInlineEdit` (erwartet count=1, Textinput) ist hier NICHT anwendbar.
  - Options werden als `role=option` im Overlay gerendert; `getByRole('option', {name, exact:true})` funktioniert.
- **Festlegung**: S1 (Profile-Sperre) ist in der Test-Org nicht erforderlich — FeldPermissions zeigt 1 Zeile (nur das PermissionSet), 0 Zeilen für Standard User.
- **Feld-Label in der Org**: `Rückruf-Zeitfenster` (Umlaut), API-Name `Rueckruf_Zeitfenster__c`.

## Rework 2026-09-25 (CI-Lücke C + Prod-Drift, DevOps 21194/21195)

**Zwei CI-Gates rot, EIN gemeinsamer Ursprung** (NICHT „Neufeld fehlt in Prod“ — diese
Annahme von Architect 16:46 / Tester 17:23 ist für diesen PR korrigiert):

- **Smoke-Gate Lücke C** (fls-gate.py, `runas_luecke`): `SCRUM430RueckrufZeitfensterTest.cls`
  fasste `Contact.Rueckruf_Zeitfenster__c` **ohne** `System.runAs` an. Die Schwesterklasse
  (FlsTest) wies die PS im Test zu und lief unter runAs → grün. Lücke C greift nur bei
  NEUEN Feldern: eine Testklasse mit `@isTest`, Referenz auf das neue Feld und ohne
  `System.runAs(` im Quelltext (post comment-strip) schlägt an.
- **Prod-Drift-Gate (RunLocalTests check-only)**: dieselben 4 DML/SELECT-Methoden
  werfen `No such column` / `fields being inaccessible`. Der Feld+PS wandern als
  Metadatum im check-only-Validate mit; die PermissionSetAssignment ist ein DATENSATZ,
  wandert NICHT mit → ausführender Testuser hat kein FLS → Fehler.

**Fix** (Hausform SCRUM424FirstResponseFlsTest, 31/51 Klassen):
- `SCRUM430RueckrufZeitfensterTest.cls` komplett rewritten: `mkTestUser` + `assignPS`
  als Setup, dann JEDE fachliche DML/SELECT in einem eigenen `System.runAs(u)`-Block.
  `picklistHasExactlyThreeValues` (Schema-API, kein Feld-DML) bleibt System-Mode.
  MIXED_DML-Operation vermieden: Setup-DML ZUERST, fachliche DML NUR INNERHALB runAs.
- `SCRUM430RueckrufZeitfensterFlsTest.cls`: Header-Kommentar „PRÄMISSE kritisch / S1
  nötig“ durch gemessene FLS-Statement ersetzt (0 Zeilen Standard-User-Profil, S1 NICHT
  nötig, Negativ-Test PASST ohne S1). Kein Verhaltenswandel, nur Doc-Korrektur.

**Verifikation (2026-09-25):**
- `sf apex run test` Run `707WU00001KXNxv`: **9/9, 100 % Pass** (6 funk + 3 FLS),
  inkl. `withoutPS_fieldInvisible` (AC4) und aller runAs-Funktions-Methoden.
- Deploy `0AfWU00000bhvXB0AY` (beide Klassen, RunSpecifiedTests): Succeeded.
- Lücke C: `System.runAs(` in der Klasse (grep count 7) → gate überspringt die Klasse.
- Prod-Drift: PSA im Test-Scope → ausführender runAs-User besitzt FLS → 4 Methoden grün.
