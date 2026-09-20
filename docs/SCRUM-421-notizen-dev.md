# SCRUM-421 Notizen (Developer) — finaler Stand 2026-09-20

## Org-Fakten (Test-Org, geprüft)
- **Phase 1 LIVE:** 4 Case-Felder (`Servicebereich__c`, `Kundenstatus__c`, `Automatische_Zuordnung__c`, `Zuordnungszeitpunkt__c`) + PS `SCRUM421_Zuordnung` in der Org (Beweis: 12 Tests kompilierten/liefen im 11:27-Deploy mit direkten Feldreferenzen, Job `0AfWU00000bZzg10AC`).
- **Phase 2 rolled back** nach 11:27 (`rollbackOnError: true`): 4 Queues, `CaseQueueAssignment`, `CaseQueueAssignmentTrigger`, Trigger, beide Testklassen NICHT in der Org (Tooling `ApexClass`-Read-Back, `Group`-Leere).
- **Phase 3 (Layout) nie deployed.**
- 420-Komponenten: unangetastet, grün.

## Test-Status (11:27-Deploy-Report, JOb `0AfWU00000bZzg10AC`)
- **9/12 grün = gesamte Funktionsklasse `SCRUM421QueueAssignmentTest` (AK1–AK9) komplett grün.**
- 3 Fails, alle in `SCRUM421QueueAssignmentFlsTest`:
  - `testQueuesExist` L152 "Expected 4, Actual 1" → **eigener Test-Bug**: `.size()` auf `AggregateResult` = Zeilenanzahl. **FIXED** (2026-09-20): `COUNT(Id) q` + `(Integer) r.get('q')`.
  - `testWithoutPermset_selectFails` L53: SELECT ohne PS **ging durch** → Standard-User-Profil gewährt Read auf 421-Felder.
  - `testWithPermset_readableAndWriteSplit` L122: Write auf `Automatische_Zuordnung__c` **ging durch** → Profil gewährt Edit; PS kann entziehen NICHT (effective FLS = Profil OR PS).

## FLS-Lock — Blocker (org-seitig, Governance)
- 420-Präzedenz: 420-Felder sind **org-seitig** im Standard-User-Profil verriegelt (Read=false/Write=false, Tooling `FieldPermissions`); 420-FELS-Test mit identischem Aufbau GRÜN. Kein Profile-File im 420-Repo (git ls-tree). = manueller Profil-Schritt (420-Notizen).
- 421-Felder: `Read=true/Write=true` in allen Profilen (Default nach SFDX-Field-Deploy).
- **CLI-Kanäle geprüft → kein sicherer Pfad:**
  - `sf project retrieve "Profile:Standard"` liefert nur 197 Z / 5.756 B: **nur** `userLicense` + `userPermissions`, **0** `objectPermissions`, **0** `fieldPermissions` (2× identisch). Full-Source-Deploy dieses Teilkorns = Zerstörungsrisiko (löscht Grants). → VERWORFEN.
  - `MetadataComponent WHERE Type='Profile'` (Tooling): mehrfach Fehler/leer → verworfen.
  - `Profile:Standard User` (Anzeigename): cannot be found; FullName = `Standard`; Id `00eWU00000NzbZCYAZ`.
  - Per-Field-FLS-Deny-Command existiert in SFDX nicht; PS addiert nur.
- **Entscheidung:** 421-Felder müssen analog 420 im Standard-User-Profil org-seitig verriegelt werden (readable=false, editable=false; PS grantet den Split). Handoff an Architect mit exaktem Request; Feature-Deploy NICHT davon blockieren (Gating nur durch grüne Funktionsklasse).

## Deploy-Plan (Final)
1. Phase 2: `--manifest manifest/scr421-phase2.xml --test-level RunSpecifiedTests --tests SCRUM421QueueAssignmentTest` (nur grüne klasse als Gate — FLS-Klasse deployet mit, blockt nicht).
2. Phase 3: Layout `scr421-phase3.xml` (kein Test-Gating nötig, kein Apex).
3. PS `SCRUM421_Zuordnung` zuweisen: `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com`; Read-Back `PermissionSetAssignment` + 1 Feld-SOQL als Nutzer mit PS.
4. Standalone (kein Deploy, kein Rollback-Risiko): `sf apex run test -o Test-Org -n SCRUM421QueueAssignmentFlsTest -n SCRUM420EscalationKundeTest -n SCRUM365OpenCasesCountTest -n SCRUM418CaseReactionTest`. Erwarten: FLS-negativ = 2 rote Methoden (Profile-Lock ausstehend), Rest grün. Exakt dokumentieren im Handoff.
5. Push + PR, Jira → Architect (Review).

## Konventionen (während implementiert, final)
- Queue: Dateiname/Manifest-Member = DeveloperName mit `_` (`Technischer_Support`), `<name>` = Display-Name mit Leerzeichen; `<queueSobject><sobjectType>Case</sobjectType></queueSobject>`, `<doesSendEmailToMembers>`; kein `<queueType>`.
- Manifest-ApiVersion: Phase 1 = 67.0, Phase 2/3 = 62.0 (Haus-Shape).
- Trigger: `after insert, after update`, dünner Handler + `isRunning`-Guard.
- Apex-Tests: `%` existiert nicht im Org-Parser → `mod()`-Helper; `DateTime`-Typfix wo nötig.
- Shell/Kernel: **jeder** Aufruf braucht `workdir=/tmp/scr421-wt` (CWD hängt an gelöschtem `/tmp/scr419-wt`). Lange inline-Bash-Quotings → truncated; statt Script-File + kurze Einzelliner.
- Ground-Truth-Quellen: Deploy-Report, Tooling `FieldPermissions`/`ApexClass`, erfolgreich laufende Tests. UNVERLÄSSLICH in dieser Org: `sf apex run`-Compile auf Custom Fields (Schema-Cache-Phantomfehler "Variable does not exist"), `sf sobject describe --json` (leer), `sf api request rest` (exit 1), `FieldDefinition.DefinitionDate` (0-Zähler).
- `sf data create/update record --values`: Feldpaare mit **Leerzeichen** trennen, nie Kommas.
