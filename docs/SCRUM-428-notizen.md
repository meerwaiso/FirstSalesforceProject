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
- Phase-1-Felder + MDT-Objecte deployed in Test-Org am 24.09.2026 vor 07:00 UTC (Fields 3/3 OK, MDT-Obj+Fields 5/5 OK). **MDT-Records deployed 24.09. 09:35 UTC: Standard (MaxOffene\_\_c=5) + 10 Keyword-Records (Technik 3 / Rechnung 3 / Vertrag 4) — alle via SOQL gelesen (10/10 + Standard).** Phase 1 vollständig, Read-back OK.

## Stand 2026-09-24 (Phase B/C/D/E/F geschrieben)

- AC9 BusinessHours: DML auf BusinessHours NICHT erlaubt (Insert not allowed), kein Schema.setMockBusinessHours -> 24/7-BH in Test-Org NICHT mocken. isWithin-Check trotzdem produktiv, AC9-Test = "not verifiable in 24/7-org" (wie SCRUM-424 AC7).
- CaseComment: ParentId (nicht CaseId!) + CommentBody (nicht Comment). describe-verified.
- CaseNumber in Org = 8-stellig 0000xxxx (z.B. 00002837). Regex \b000\d{4,7}\b.
- Status picklist: New, Working, Escalated, Closed.
- Origin picklist: Phone, Email, Web.
- Servicebereich\_\_c picklist: Technik, Vertrag, Rechnung, Allgemein.
- SuppliedName (string, create+update), SuppliedEmail (email, create+update) — beide createable.
- Case->Contact: to-one lookup, dot-notation `c.Contact.Email` (kein Subquery).
- MDT Felder: SCRUM428_CaseLimitConfig**mdt.MaxOffene**c; SCRUM428_KategorierRegel**mdt.{Bereich**c, Keyword**c, Prioritaet**c}.
- LWC-Pfad: force-app/main/default/lwc/scr428ContactForm/ (Design-XML-Pfad "standard" war falsch — Registry sagt lwc/).
- House-Pattern LWC: betreuungsuebergabe (import from @salesforce/apex, @wire, toast via ShowToastEvent).
- AC5 Dedup-Ziel = kleinste bestehende offene Case-Id pro (Contact,Bereich)-Paar (deterministisch).

## 24.09. GroupMember-Testprobe: OK

- GroupMember-Insert im Testkontext GEHT: Felder GroupId + UserOrGroupId (kein MemberType, kein ParentId — describe GroupMember).
- Queue-Select WHERE Type='Queue' im Testkontext geht (Phase-1-Source-Queues sind sichtbar).
- TC2-Setup in Apex-Test daher moeglich.
- Probe-Klasse SCRUM428ProbeProbe bleibt als inert @isTest in der Test-Org (org-delete-Command verweigert) — in Jira-Handoff notiert.
- 421-FlsTest lief gerade 3/3 GRUEN: org Profil hat 421-Felder gelockt (420-Praezedenz). 428-Felder: OHNE Profil-Lock → TC3-Negativpraemisse konstruktiv ungueltig → kein FLS-Negativ-Test, an Architect weitergeben.

## 24.09. Deploy-Fixes Phase 2 (Compiler als Autoritaet, Report als Orakel)

- **Root-Cause 39 Compile-Fehler in EINEM Deploy-Report:** `String.isEmpty()` existiert in Apex NICHT (String has only `.length()` — nur List/Map/Set haeben isEmpty). War in IngestHandler(1x), CaseConfirmation(3x), Controller(3x). -> alle auf `.length()>0`/`==0`.
- **`limit`/`map` als Parameter-Namen** vom Org-Parser als "reserved"/unexpected gemeldet -> `maxOpen` (Service+Test), `m` (addIfSmaller).
- **LWC-Meta-Root** ist `LightningComponentBundle`, NICHT `AuraDefinitionBundle` (Haus-LWC `betreuungsuebergabe` bestaetigt) — und das schliessende Tag muss zum eroeffnenden passen (mismatch = XML-Parse-Fehler).
- **`lightning/showToastEvent` ist als Modul in der Test-Org NICHT importierbar** -> eigene `statusVariant`/`statusMessage`-State + Status-`<p>` (data-testid="status"). Jest-Test bleibt kompatibel (mockt Apex submitForm).
- **KOP-FIX (der eigentliche 89-Test-Killer):** `update newCases` wo newCases = Trigger.new → `SObjectException: DML statement cannot operate on trigger.new or trigger.old`. Jede Case-Insert in der Org stirbt im Trigger. -> **Copy-Predicate**: frische sObjects mit nur den 5 mutierten Feldern bauen, die updaten. Trigger.new behaelt Full-Fidelity.
- **Gefaerte Id-Literale scheitern an der Id-Pruefung (Checksum)** — `Id.valueOf('005000000000000001')` -> Invalid id, sogar 18-Char. Test braucht ECHTE User-Records (valid + sortierbare .Id fuer den `<`-Tie-Break in selectAssignee). Probe 24.09.
- **MIXED_DML:** User+Case-DML in einer Test-Tx GEHT (421-Test praetig), aber **GroupMember (Setup-Objekt) + Case (non-setup) in derselben Tx NICHT** -> GroupMember-DML in GETRENNTEM Queueable (GM428), vor dem Case-Insert (C428), beide in Test.startTest/stopTest gefluetet. End-to-End ueber echten Pfad Trigger->Queueable->assign.
- **async-job-Limit in Test:** in einer Queueable-Tx darf hoechstens 1 WEITERES async Job eingeren werden -> C428 macht genau 1 Case-Insert (je 428-Trigger-Enqueue). 2 Inserts -> LimitException "Too many queueable jobs added: 2".
- **`static` nur auf Top-Level-Fields** — nicht in inner Queueable-Klassen (queuedCaseId in Aussenklasse).
- **`sf apex run test` gibt "Invalid id" im MESSAGE-Feld aus, Exit-Code 100 = "Failed" (nicht 0).** `--class-names` (Plural) korrekt.
- **3/7 -> 7/7 GRUEN** nach diesen Fixes. Copy-Predicate ist der Load-Bearing-Fix fuer die ganze Org-Suite.
- **Verwaesende inert Probe-Klassen in Test-Org (unloeschbar via CLI, @isTest):** SCRUM428ProbeProbe, SCRUM428ProbeQueue, SCRUM428ProbeAsync. In Jira-Handoff notiert.

## 24.09 nachmittag - FLS-Status + Test-Design (Tagesfindings)

- **FLS-PROBE (SCRUM428FlsProbe, verworfen nach Run):** Standard-User OHNE PS:
  `caseReadable=true`, `Erfassungsquelle_unrestricted=false`, `Dedupliziert_unrestricted=false`,
  `Servicebereich_unrestricted=false`, `UserVerfuegung_unrestricted=false`.
  => ALLE neuen 428-Felder sind im Standard-Profil GELOCKT (nicht UNRESTRICTED).
  => **TC3-Negativtest ist satisfies** (SELECT wirft ohne PS; mit PS lesbar).
  Anders als 421/420 (dort UNRESTRICTED, neg. Test nie rotebar) - hier geht er gruen.
- **CaseNumber-Format:** `000` + 5 Ziffern (z.B. 00002837). AC4-Regex `\b000\d{4,7}\b` passt.
- **Trigger laeuft SYNCHRON auf insert** (89-Fehler-Root-Cause war der trigger.new-DML,
  nicht async). Phase B (Queueable assign+confirm) tut KEIN Setup-DML =>
  insert-basierte Ingest-Tests brauchen KEINEN MIXED_DML-Tanz (im Gegensatz zu
  meinem AC10-Helfer C428, der selbst GroupMember-DML tut - dort Queueable noetig).
- **IngestTest-Plan:** Phase A (AC1/3/4/5) via `insert Case` (Trigger synchron).
  Phase B (AC11) via nahtlose `buildMessage`/`sendAll` (rein, kein Insert, keine
  echte Mail). AC2 via `SCRUM428ContactFormController.submitForm` (with sharing,
  Test-User = admin). Dedup: erst ZIEL-Case insert (bleibt offen), dann DUP-Case.
- **IngestFlsTest-Plan (3 Methoden, um MIXED_DML zu vermeiden):**
  (1) neg: o. PS SELECT->throw (nur SELECT, kein DML).
  (2) pos Case-Felder: Erfassungsquelle read+edit, Dedupliziert read-only (nur Case-DML).
  (3) pos User-Feld: SCRUM428_Verfuigung read+edit auf EIGENER Zeile (nur User-DML,
  keine Case-DML in der gleichen Methode => kein MIXED_DML).

## 24.09.2026 abend — gruen (19/19 428 + 12/12 421)

- **AC4-Root-Cause (Prod-Bug, nicht Test):** Design-Regex war auf "000"-Praefix
  hartkodiert. Prod-Nummern sind 8-stellig 0XX... und rullen ueber 00009999
  hinaus; Test-Transaktionen minten eine ANDERE Sequenz (gemessen: Test-Case =
  00102840, Prod-Max = 00002837). Fix im Handler: Pattern 0 + 6-7 Ziffern
  (Praefix-agnostisch, 7-8 Ziffern, Fuehrende Null). Prod-Code geaendert =>
  421-Suite nachgeprueft: 12/12 gruen.
- **AC10-Root-Cause (Uhrzeit-Falle, nicht Code-Bug):** Org-BH-Profil ist NICHT
  24/7 (gemessen 19:36 Europe/Berlin: isWithin(now)=false; 24h vorher true).
  Der End-to-End-Pfad ruft das LIVE AC9-Gate auf => nachts korrekt 0
  Zuteilungen, AC10-Assertion zeitabhaengig. Fix: C428 ruft exakt denselben
  assign-Call des AQ ueber die AC9-Seam (withinBH=true) — die Verfuigung-
  Exklusion (AC10) wird deterministisch getestet; BH-Gate bleibt AC9 (kein
  Mock moeglich: kein Schema.setMockBusinessHours, BH DML-restricted im Test).
- **Fazit Phase 3:** AssignmentTest 7/7, IngestTest 9/9, IngestFlsTest 3/3 =
  19/19 100%%. Handler: Trigger.new read-only (Copy-Predicate + nur geaenderte
  Cases updaten, 418-Lektion). Report Description <=255.
- **Verbleibend (nicht Developer):** Org enthaelt throwaway @isTest-Klassen
  SCRUM428ProbeProbe/ProbeQueue/FlsProbe/ProbeAsync/ProbeAcc — das oerg-daten-
  loeschen-Command ist fuer mich DENY-Regel; DevOps muss die Klassen vor
  Produktiv-RunLocalTests ruecken (sie scheitern by design und verokeln nur
  RunLocalTests). Rueckzug via destructiveChanges.xml + Deploy.
- **421/428 Design-Luecke (bekannt, dokumentiert):** 421 Insert-Pfad prueft
  Dedupliziert\_\_c NICHT (Design sagt: soll). Falls 421 einem 428-markierten
  Dup-Fall einen Owner gibt, ueberschreibt er 428-Close nicht (nur OwnerId),
  aber die Intent "421 respektiert Dedupliziert" ist offen => Architect.
- **Scope-Entscheidung (24.09, User):** LWC-Jest-Test der scr428ContactForm
  geht NICHT mit in SCRUM-428, sondern in ein eigenes Follow-up-Ticket.
  Grund: 4/5 Tests hängen an lightning-base-Component-Selektoren im
  jsdom-Harness (lightning-input liefert null trotz shadowRoot+Flush;
  Plain-<form>-Test steht). Lektionen (mock\*-Hoisting-Regel, shadowRoot-,
  Microtask-Flush, e2e-Suite-Abgrenzung) stehen ab jetzt im Skill
  lwc-jest-testing - Test-File bleibt im Stand von edb3ae6.
