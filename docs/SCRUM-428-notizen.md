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

## Harte Befunde vom Developer (24.09.2026) — Org-Verifikation, bevor Code steht
- AC9-API: `BusinessHours.isWithin(Id, Datetime)` — NICHT `getBusinessHoursWindowForDateTime` (existiert nicht, Compile-Fehler). Verifiziert per `scripts/apex-probe.sh`.
- CaseComment Felder in DIESER Org: `ParentId` (Lookup→Case) + `CommentBody` (Text Area) + `IsPublished` (Check). `CaseId` und `Comment` sind KEINE gültigen SOQL-/Constructor-Namen hier (Compile-Fehler "No such column 'CaseId'"). Verifiziert per Probe + Describe.
- BusinessHours "Default": Mon–Thu `09:00–17:00 Berlin` (480 bh-min/24h), **Friday 840**, **Saturday 1440 (24/7!)**, **Sunday 1080 (~18h)** — verifiziert per `BusinessHours.diff`-Probe + FieldDefinition-Read der Time-Spalten. **⚠️ WICHTIG:** Das Ticket sagt "Mo–Fr 9–17 gemäß bestehenden Business Hours", aber die ORG hat Samstag 24/7 und Sonntag ~18h. **Design-Folge:** Implementierung nutzt `BusinessHours.isWithin` (der richtige Mechanismus gemäss ADR), aber die PO muss die Org-Konfig klären ODER das Ticket korrigieren. In der Handoff-Kommentar deklariert.
- CaseList (Report) Scope-Wert ist `organization`, NICHT `org` (ADR-7 sagt "org" — das ist die Lektion aus SCRUM-394). Verifiziert per `sf api request rest` → `reportMetadata.scope='organization'`.
- CaseComment `CommentBody` + Insert-Test mit `ParentId` + `IsPublished=true` + `CommentBody` OK (Probe 24.09. 08:39).
- Case-Spalten verifiziert: `Servicebereich__c`, `Kundenstatus__c`, `Automatische_Zuordnung__c`, `Zuordnungszeitpunkt__c`, `Origin`, `Status`, `CaseNumber`, `SuppliedEmail`, `ContactId` alle existieren mit erwartetem DataType.
- User: `IsActive` (Checkbox) ist das Feld — kein `IsInactive`. Kein Custom Field auf User in der Org → `SCRUM428_Verfuigung__c` existiert noch nicht (deploybar).
- MDT Registry: `custommetadata` dir=`customMetadata` suffix=`.md`. `customsetting` ist im Registry ABSENT (also MDT, nicht Custom Setting — bestätigt ADR-5).
- LWC-Manifest: `LightningComponentBundle` (dir=`lwc`).
- Apex-Quirks diese Session: `Datetime.valueOfGmt()` ist die ISO-Parser; `%` und `System.mod` sind beide KEINE Operators — nur `Math.mod(a, b)`; `Datetime.dayOfWeek()` gibt es NICHT (weder auf Date noch Datetime); `Datetime.clone()` existiert NICHT im Apex 62.0.
- **CustomMetadata-Record `.md` Wert-Shape (verifiziert per Deploy + Web-Dokumentation, 24.09.):** Die korrekte Source-Form erfordert `xmlns:xsd` auf dem Root-Element und `xsi:type` auf dem Value. Number(scale 0) = `<value xsi:type="xsd:int">5</value>`; Number(scale >0) = `<value xsi:type="xsd:double">5.0</value>`; String = `<value xsi:type="xsd:string">TEXT</value>`. **Keine `xsi:nil`**, keine Nested-Form `<xsdType>/<numberValue>` (fuehrt zu Parse-Fehler `Only the following configurations are supported`). Quelle: Salesforce Metadata API Developer Guide (meta_custommetadata.htm), nicht SDR/CLI.
- **Diagnose-Lektion (24.09.):** Mehrere MDT-Records in EINEM Deploy → bei Fehlern nur `UNKNOWN_EXCEPTION` + fester ErrorID-Suffix (-315522575), 0 components processed, keine componentFailures. BIS per Einzel-Record-Deploy → echte Parse-Error-Meldung (z.B. `Error parsing file: …`). Das Gleiche für das `--no-prompt`-Flag: existiert NICHT (help hat es nicht). `sf project deploy validate` ohne lokale Tests läuft trotzdem durch den "Running Tests"-Phase und fällt dort bei `UNKNOWN_EXCEPTION` aus — `sf project deploy start` (echtes Deploy) zeigt dagegen die componentFailure. **Regel: bei `UNKNOWN_EXCEPTION` ohne componentFailures → Einzel-Komponente deployen, die echte Error-Meldung kommt raus.**
- Phase-1-Felder + MDT-Objecte deployed in Test-Org am 24.09.2026 vor 07:00 UTC (Fields 3/3 OK, MDT-Obj+Fields 5/5 OK). **MDT-Records deployed 24.09. 09:35 UTC: Standard (MaxOffene__c=5) + 10 Keyword-Records (Technik 3 / Rechnung 3 / Vertrag 4) — alle via SOQL gelesen (10/10 + Standard).** Phase 1 vollständig, Read-back OK.
