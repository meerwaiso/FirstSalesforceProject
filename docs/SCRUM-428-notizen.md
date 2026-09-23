# SCRUM-428 Notizen (Architect)

Harterkämpfte Befunde + Org-Abfragen — überleben die Kontext-Kompression.

## Org-Fakten (Test-Org, 2026-09-24)
- „Bereiche" = `Case.Servicebereich__c` (Picklist Technik/Vertrag/Rechnung/Allgemein, kein Default).
- `Case.Automatische_Zuordnung__c` (Boolean) + `Case.Zuordnungszeitpunkt__c` (DateTime) EXISTIEREN schon (SCRUM-421) — wiederverwenden, nicht neu anlegen.
- `Case.Status`: New / Working / Escalated / Closed → "offen" := `Status != 'Closed'`.
- Case-Nummer = 8-stellig, KEIN Präfix (z. B. 00002837) → AC4-Regex `\b000\d{4,7}\b`.
- Queues (DeveloperName): `Technischer_Support`, `Vertragsservice`, `Billing`, `First_Level_Support` — alle OHNE Mitglieder.
- BusinessHours: "Default", active, Europe/Berlin.
- `User` hat KEIN `IsOffline` und keine Custom-Fields → AC10 brauch neues Field `SCRUM428_Verfuigung__c` (Checkbox, Default true).
- Email-to-Case noch nicht konfiguriert (O1).

## Repo-Fakten (origin/master @ 0d3a931)
- `CaseQueueAssignment` + Trigger existieren (SCRUM-421, api 62.0): setzt OwnerId → Queue bei Insert/Update (SB/KS-Filter), `isEligible` = CreatedById oder Queue-Owner. **421-Code NICHT ändern müssen** — 428 Phase B (Queueable) ändert nur OwnerId, 421-Filter greift nicht (nur SB/KS-Wechsel).
- House-Pattern: apex 62.0, after-insert Trigger + stateless Service, FLS-PS pro Ticket, Test-<Name>+<Name>FlsTest, Manifeste phase1-fields/phase2-referencing, Report-Shapes `reports/Service/*.report-meta.xml`.
- Analytics-API CaseList: Detail-Cols `OWNER`, `OPEN`, `CLOSED`, `CREATED_DATE`, `AGE`, `SUBJECT`, `ACCOUNT.NAME`; Aggregat `RowCount`. Report "unverteilt" = `OWNER includes <4 Queue-Namen>`.

## Metadata-Typen (per CLI metadataRegistry.json verifiziert)
- Custom Metadata Type: `custommetadata` (suffix `.md`, dir `customMetadata`) — source-deploybar. Custom Setting: NICHT im Registry (ABSENT) → MDT statt Custom Setting.
- MDT-Record-Dateiname: `<Objektname>__mdt.<DeveloperName>.md` (z. B. `SCRUM428_CaseLimitConfig__mdt.Standard.md`).
- LWC im Manifest: Type `LightningComponentBundle` (dir `lwc`, bundle-Strategie), Members = Bundlename.
- `sf api request rest -S /pfad.json <url>` (Beta, `-S` streamt in Datei statt `--output`), Analytics-Pfad mit Bindestrich: `/analytics/report-types/<Type>`.

## CLI-Quirks (dieses Ticket)
- `sf sobject describe -s <Objekt>` (=sobject), `-o` = target-org (default Test-Org). `--json --output-dir` → parse the stdout JSON (result key missing → top-level object).
- Session's default workdir kann gestört sein (scr427-wt fehlt) → immer `workdir` param im Terminal-Call setzen.

## Design-Entscheidungen (kurz)
- ADR-2: 2 Entry Points (Email-to-Case + LWC→AuraEnabled Controller), 1 Pipeline.
- ADR-3: EIN after-insert Trigger `SCRUM428CaseIngestTrigger`, 2 Phasen (A im Trigger, B Queueable). 421 wird NICHT geändert (Reihenfolge/Filter gelöst).
- ADR-5: Limit + Keywords per MDT (`SCRUM428_CaseLimitConfig__mdt`, `SCRUM428_KategorierRegel__mdt`).
- ADR-8: 2 PS (`SCRUM428_ServiceTeam`, `SCRUM428_Teamleitung`), System=without sharing (kein PS dafür).
- ADR-9: Sharing kein Impact.
