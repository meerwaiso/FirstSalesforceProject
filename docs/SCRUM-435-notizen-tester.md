# SCRUM-435 Tester-Notizen

## Befunde (alle in Test-Org gemessen, 2026-09-29)

- **Volllauf `RunAllTestsInOrg`**: 311/311 Pass, 64 Test-Klassen, 0 failing — Job `707WU00001L7V9gYAF` (09:03 CEST).
  Rekonkordiert die Ticket-Zahl (311). Der Developer hatte 309/309 gemeldet — mein unabhängiger Messwert ist 311 (getrennter Job, eigene Auswertung via Tooling-API `ApexTestResult`).
- **Fokussierte Runs** (Job `707WU00001L7pVp`, 12/12):
  `SCRUM428IngestTest` 9/9 (ac1, ac2x2, ac3x3, ac4, ac5, ac11) + `SCRUM428IngestFlsTest` 3/3.
- **Org-State-Verifikation**: `sf data query --use-tooling-api "SELECT Body FROM ApexClass WHERE Name='SCRUM428CaseIngestHandler'"` —
  beide Zeilen in der Org: Zeile 332 `c.Status='Closed';`, Zeile 333 `c.Ursache__c='KeinFehlerKeineMassnahme';`, Zeile 121 `copy.Ursache__c = c.Ursache__c;`.
- **435-Delta verifiziert** (`git diff feature/SCRUM-434-ursache..feature/SCRUM-428-followup --stat`):
  exakt 3 Files — `SCRUM428CaseIngestHandler.cls` (2 Zeilen), `manifest/scr435-apex-handler.xml`, `docs/SCRUM-435-notizen.md`.
  Keine der rotierenden CI-Fixture-Klassen (SCRUM390/403/410/418/419/420) wird von 435 berührt → rotes CI ist 434-Basis-Defekt (Architect-Befund bestätigt, nicht widersprochen).

## Tester-Verificationstest (neu, von mir)

`SCRUM435TesterVerificationTest` (Commit `7946e52` + Fix-Commit danach) — 3 Tests, Pfad über den echten
Trigger `SCRUM428CaseIngestTrigger` (after insert → `process` → `applyDup`), keine Mocks:

1. `ac1_dedup_case_number_sets_ursache` — ac4-Pfad (Case-Nummer im Text): dup wird `Closed`,
   `Dedupliziert__c=true`, **und `Ursache__c='KeinFehlerKeineMassnahme'`** (Wert-Assertion, die die
   Developer-Tests nicht hatten), Ziel-Case bleibt offen.
2. `ac1_dedup_contact_bereich_sets_ursache` — ac5-Pfad (gleiche ContactId + Bereich): dieselben Assertions.
3. `neg_control_close_without_ursache_is_blocked` — Negativ-Kontrolle: manuelles `update c.Status='Closed'`
   OHNE `Ursache__c` wird von der SCRUM-434-ValRule hart blockiert
   (`FIELD_CUSTOM_VALIDATION_EXCEPTION, Bitte wählen Sie eine Ursache...`).
   Beweis: die ValRule ist aktiv → das Grün der Dedup-Tests ist kein Vakuum.

Result: 3/3 Pass, Job `707WU00001L7um7`.

## Stolperfallen (dieses Ticket)

- **Existing ac4/ac5 asserten NICHT den `Ursache__c`-Wert** — nur `Status='Closed'` + `Dedupliziert__c`.
  AC1 verlangt explizit "hat sie `Ursache__c = 'KeinFehlerKeineMassnahme'`". Ohne eigene Wert-Assertion
  wäre AC1 halb abgedeckt gewesen. (Gilt als Muster: "bisher rote Tests werden grün" ≠ die AC vollständig.)
- **Apex: `String`-Methoden sind Instanzmethoden** — `String.toLowerCase(x)` und `System.fail(String)`
  existieren nicht (Deploy-Validator hat beide abgewiesen). Korrekt: `x.toLowerCase()`, `System.assert(false, msg)`.
- **Tooling-API-Feldnamen raten ist teurer als `sobject describe`**: `AsyncApexJob` heißt `TotalJobItems`
  (nicht `JobItemsTotal`), die Ergebniszeilen stehen in `ApexTestResult` (nicht `AsyncApexJob`),
  `ApexTestResult` heißt `TestMethodName`? → nein: `MethodName` + `ApexClass.Name`. `ValidationRule`
  heißt `ValidationName` (nicht `DeveloperName`), `Metadata` liefert JSON mit `errorConditionFormula`.
- **ValRule-Formel der 434 (aus Org gelesen)**:
  `AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Ursache__c)))` — aktiv, `Id=03dWU00000D8Z17YAF`.
- **Exception-String**: ValRule wirft `FIELD_CUSTOM_VALIDATION_EXCEPTION` (nicht `custom validation rule`) —
  erste Assert-Version hat deshalb fehlgeleitet; Match auf `field_custom_validation_exception`.

## Offene Punkte (übergibt an DevOps)

- PR #151 CI: FLS-Gate + Prod-Org Drift Gate ROT = 434-Basis (6 Fixture-Klassen ohne `System.runAs`).
  Fix gehört in 434 (runAs-Wrapper + PermissionSetAssignment, Vorbild `SCRUM424FirstResponseFlsTest`).
  Blockiert den Merge von #151, ist KEIN 435-Defekt. Merge-Reihenfolge bleibt: erst 434, dann 428/435.
