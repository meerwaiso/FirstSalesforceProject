# SCRUM-435 Notizen (Developer)

Ticket: SCRUM-428 follow-up — applyDup setzt Ursache__c bei Dedup-Abschluss.
1 Zeile in SCRUM428CaseIngestHandler.applyDup nach `c.Status='Closed'`.

## Stand
- Branch: `feature/SCRUM-428-followup`, abgewinkt von `origin/feature/SCRUM-434-ursache` @ d77e16f (nicht master — Ursache__c existiert dort nicht).
- Worktree: `~/Desktop/SoftwareProjects/Salesforce/scr435-wt` (434-Worktree `scr434-wt` unangetastet).
- ÄNDERUNG: `c.Ursache__c = 'KeinFehlerKeineMassnahme';` nach `c.Status = 'Closed';` (Zeile 328→329). Literal = Picklist-API-Wert (devops-agent verifiziert gegen field-meta.xml).
- Manifest (neue Datei): `manifest/scr435-apex-handler.xml` (nur SCRUM428CaseIngestHandler, ApexClass, apiVersion 61.0).
- Diff: 1 Zeile (Handler) + Manifest.

## Befunde
- `deploy validate` mit RunSpecifiedTests (SCRUM428IngestTest + Scr428IngestFlsTest) = **check-only, keine Persistierung** → tests laufen gegen ALTEN Handler → ac4/ac5 dort noch ROT (FIELD_CUSTOM_VALIDATION_EXCEPTION). Das beweist nur: Fix kompiliert + Tests aktuell rot. NICHT dass grün.
- Test-Org = Default-Org (devops-agent@cline.test).
- 428-Test-Klassen + Handler ALLE schon in Test-Org (AC2 "aktuell rot im RunAllTestsInOrg, Run 707WU00001L2XzB"). Nur die 1 Zeile muss deployen.
- ac4 (215-248) + ac5 (278-…) selektieren Status/Dedupliziert__c, nicht Ursache__c — aber der rote DML ist das Insert der Dup-Case selbst (Trigger→Handler→Closed ohne Ursache→ValRule). Fix greift auf dem DML-Pfad, nicht im Assert.

## Rest (nach echtem Deploy)
- [ ] echtes `deploy start` RunSpecifiedTests 428 → ac4/ac5 grün (12/12)
- [ ] RunAllTestsInOrg = 311/311 (AC4)
- [ ] push + PR (base master, stacked-Diff dokumentiert)
- [ ] Handoff → Review → architect-agent
