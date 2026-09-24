# SCRUM-428 — Automatische Fall-Erfassung, Kategorisierung & Zuteilung

**Status:** Freigegeben (Architekt-Design) · **Repo-Bezug:** `origin/master` @ `0d3a931`
**Org-Fakten:** Test-Org, abgefragt 2026-09-24 (Befehl in §2)
**Autoritative Build-Spec:** dieses Dokument. Jira-Kommentare & Code-Comments zeigen hierauf.

---

## 1. Ziel
Eingehende Kundenanfragen (E-Mail, Kontaktformular) werden automatisch als Case angelegt, kategorisiert (AC3) bzw. im gewählten Bereich (AC2), doppelt eingehende Nachrichten an bestehende Fälle angehängt (AC4/AC5), in Geschäftszeiten an das verfügbare Teammitglied mit den wenigsten offenen Fällen zugewiesen (AC6–AC10) — und jeder neue Fall bekommt sofort eine Eingangsbestätigung mit Fallnummer (AC11). Die Teamleitung sieht unverteilte Fälle per Report (AC12).

## 2. Verifizierte Befunde (Basis jedes Entwurfs — nichts davon raten)

### 2.1 Test-Org (2026-09-24)
| Befund | Verifiziert per |
|---|---|
| „Bereiche"-Feld = **`Case.Servicebereich__c`** (Picklist Technik/Vertrag/Rechnung/Allgemein, kein Default, nullable) | `sf sobject describe -s Case -o Test-Org` |
| **`Case.Automatische_Zuordnung__c` (Boolean) + `Case.Zuordnungszeitpunkt__c` (DateTime) existieren bereits** (SCRUM-421) → wiederverwenden, nicht neu anlegen | dito |
| `Case.Origin` = Email/Web/Phone (Standard) → wird von Email-to-Case gesetzt; für „Erfassungsquelle" genügt es **nicht** (braucht exakt 2 Werte) → neues Feld (ADR-2) | dito |
| `Case.Status` = New/Working/Escalated/Closed → **„offen" := `Status != 'Closed'`** (AC8) | dito |
| `Case.Comment`-Objekt (CaseComment) vorhanden → Anhängen der Dup-Nachricht (AC4/AC5) | `sf sobject describe -s CaseComment` (Developer-Check) |
| Standard-Case-Nummern **8-stellig ohne Präfix** (`00002837`) → AC4-Regex `\b000\d{4,7}\b` | `SELECT CaseNumber FROM Case ORDER BY CreatedDate DESC` |
| 4 Queues existieren, **ohne Mitglieder**: `Technischer Support`, `Vertragsservice`, `Billing`, `First Level Support` (DeveloperNames: `Technischer_Support`, `Vertragsservice`, `Billing`, `First_Level_Support`) | `Group WHERE Type='Queue'` + `GroupMember` |
| `BusinessHours` „Default", active, **Europe/Berlin** | `SELECT Name,IsActive,TimeZoneSidKey FROM BusinessHours` |
| **`User` hat KEIN `IsOffline`**, keine Custom-Fields → AC10 braucht ein neues User-Field (ADR-2) | `sf sobject describe -s User` |
| Aktiv: Email-to-Case **noch nicht** konfiguriert (Org-Schritt O1) | DevOps verifiziert in O1-Readback |

### 2.2 Repo `origin/master` @ `0d3a931`
- **`CaseQueueAssignment` + `CaseQueueAssignmentTrigger`** (SCRUM-421, apiVersion 62.0) setzen bei Case-Insert/Update den `OwnerId` auf die passende **Queue** (Servicebereich+Kundenstatus → 1 von 4 Queues, Fallback FLS, leer → nicht). **Wichtig für 428:** 421 greift bei Update nur, wenn sich `Servicebereich__c` ODER `Kundenstatus__c` geändert hat (Änderungs-Filter im Handler), und überschreibt nie einen Owner, der schon ein User ist (`isEligible`). → Die 428→421-Interaktion ist gelöst, **ohne** 421-Code zu ändern (ADR-3, Schritt 6).
- House-Stack: Apex **apiVersion 62.0**, `without sharing`-Service + `after insert`-Trigger, FLS-PS pro Ticket (Shape: `SCRUM421_Zuordnung.permissionset-meta.xml`), Test-Paare `<FunktionsTest>`+`<FlsTest>` (Shape: `SCRUM421QueueAssignmentTest`/`FlsTest`), Scheduler `implements Schedulable`, Manifeste `manifest/scrNNN-phase1-fields.xml` + `phase2-referencing.xml`.
- Report-Shape: `reports/Service/*.report-meta.xml` (Shape: `Ueberfaellige_Faelle`), `reportType=CaseList`.
- Analytics-API `CaseList` (per `sf api request rest …/analytics/report-types/CaseList` verifiziert): Detail-Spalten u. a. **`OWNER`** (filterbar) und **`OPEN`/`CLOSED`**, Aggregat `RowCount`. Für „unverteilt" (Owner = Queue) filtert der Report auf `OWNER` ∈ {4 Queue-Namen} — mehrwertiger Filter via Operator `includes` mit Komma-Liste; **Developer verifiziert den Report per Retrieve nach erstem Deploy** (org-seitig erzeugtes Metadata ist die Wahrheit, nicht die Vermutung).
- **Neu für 428 (existiert noch NICHT):** Ingest-Handler, Zuteilungs-Service, Formular-Controller, Bestätigung, `User.SCRUM428_Verfuigung__c`, `Case.Erfassungsquelle__c`, `Case.Dedupliziert__c`, MDT-Konfigurationen, Report, LWC.

## 3. Architektur-Entscheidungen (ADRs)

### ADR-1 — Apex statt Flow
Alle Kernlogik in Apex. Begründung: Bulk (Dedup-Zuordnung ist ein Suchproblem über bestehende Cases, Zuteilung = Aggregation), dieses Projekt hat mit Flows wiederholte Deploy-/Schema-Probleme, und SCRUM-421 beweist bereits das House-Pattern (after-Trigger + stateless Service, 1 SOQL + 1 DML pro Phase) für Case-Automatisierung. Flow wird nirgendwo benötigt.

### ADR-2 — Zwei Entry Points, eine Pipeline
1. **E-Mail:** Standard-„Email to Case" (Setup → Email to Case) auf die Service-Adresse. **Setzt org-seitig:** Contact (bestehend gematcht per E-Mail, sonst neu — deckt AC1 nativ ab, kein eigener Match-Code), Case mit `Origin=Email`, `Subject`=Betreff, `Description`=Body, `CaseNumber`=Standard-Nummer. Adresse ist offen (Ticket) → Org-Schritt O1. *Email-to-Case erzeugt den Case VOR jedem Trigger — AC4/AC5 können daher kein Insert verhindern, sondern einen angelegten Dup-Case abschließen (ADR-3, Schritt 2).*
2. **Kontaktformular:** LWC `scr428ContactForm` (Targets `lightning__AppPage`, `lightning__Tab`) → `AuraEnabled`-Methode `SCRUM428ContactFormController.submitForm(name, email, bereich, nachricht)` (with sharing, nutzt Session-User). Controller: Contact per `Email` matchen, sonst anlegen (`LastName=name`), Case-Insert (`Subject='Kontaktformular: '+name`, `Description=nachricht`, `Servicebereich__c=bereich`, `Erfassungsquelle__c='Kontaktformular'`). Echtes externes Website-Formular ist Out-of-Scope; die Controller-Methode ist der Kontrakt.

Beide Quellen landen im selben `after insert`-Trigger auf Case → ein Handler für alles Nachfolgende.

### ADR-3 — Ingest-Handler (EIN neuer Trigger, 2 Phasen)
`SCRUM428CaseIngestTrigger on Case (after insert)` → `SCRUM428CaseIngestHandler.process(Trigger.new)`, danach `System.enqueueJob(new SCRUM428AssignmentQueueable(neue, nicht-Dup-Case-Ids))`.

**Phase A (im Trigger, `without sharing`, bulk 1 SOQL/1 DML je Schritt):**
1. **Erfassungsquelle (AC1/2):** für `Origin='Email'` → `Erfassungsquelle__c='E-Mail'`. (Formular-Case kommt mit gesetztem Wert.)
2. **Kategorisierung (AC3, nur E-Mail):** für `Origin='Email'` UND `Servicebereich__c==null`: Keyword-Regeln aus `SCRUM428_KategorierRegel__mdt` (eine Zeile: `Bereich__c` Technik/Vertrag/Rechnung + `Keyword__c`); Match auf `Subject+Description` per `contains` (case-insensitive). Mehrere Treffer: Priority-Ordnung Technik > Rechnung > Vertrag (Developer legt Startliste fest, see §9). Kein Treffer → `'Allgemein'`.
3. **AC4 (Fallnummer im Text):** Regex `\b000\d{4,7}\b` auf `Subject+Description` → Bulk-Lookup offener Cases (`Status!='Closed'`) per `CaseNumber IN :extracted` → Treffer: Dup-Case schließen (`Status='Closed'`, `Subject` mit Präfix `[Dedupliziert: {Ziel-CaseNumber}] `), `Dedupliziert__c=true`, `CaseComment` auf den Ziel-Case (Body = Text der Nachricht).
4. **AC5 (gleicher Contact + Bereich, offen):** nur für noch nicht in Schritt 3 deduplizierte Cases: Bulk-Lookup `SELECT Id, ContactId, Servicebereich__c FROM Case WHERE ContactId IN :contactIds AND Status!='Closed'` → Treffer (gleiche ContactId **und** gleicher `Servicebereich__c`): wie Schritt 3. *Limitation (dokumentiert): ohne gemachten Contact (keine `ContactId`) greift AC5 nicht.*
5. **Rekursions-/Interaktionsschutz (warum 421 NICHT angepasst werden muss):**
   - Trigger-Reihenfolge bei gleichem DML-Batch: alphabetisch → `CaseQueueAssignmentTrigger` (421) vor `SCRUM428CaseIngestTrigger`. 421 routet neuere Cases bereits auf die Queue (wenn `Servicebereich__c` gesetzt) bzw. nicht (wenn null → AK7-Regel 421).
   - Phase A ändert `Servicebereich__c` (Schritt 2) → löst 421-`after update` aus → 421 sieht: `Owner` noch `CreatedById` → eligible → routet exakt auf die jetzt korrekte Queue. **Gewollt.**
   - Phase B (Queueable, s. u.) setzt `OwnerId` Queue→Person → löst 421-`after update` aus → 421-Änderungs-Filter (nur SB/KS-Wechsel) → `continue`. **Kein Überschreiben. 421-Code bleibt unverändert.**

   Klarstellung (Review, 24.09.): Das „unverändert" in 5a/5b gilt für die bereits hier benannten Pfade. Der
   **421-Insert-Pfad** (`afterInsert` — in demselben DML-Batch alphabetisch vor SCRUM428CaseIngestTrigger)
   prüft `Dedupliziert__c` **nicht**, und kann es auch nicht: zum Zeitpunkt des 421-Triggers hat 428 den
   Case noch nicht als Dup markiert (das Flag setzt 428-Phase A, die in diesem Batch danach läuft). Der
   Schaden bleibt begrenzt: ein als Dup markierter Case erhält einen Queue-Owner statt
   User-Owner; `Dedupliziert__c` und `Status='Closed'` werden von 421 nicht angefasst, die Bestätigung
   (Schritt 8) wird korrekt unterlassen. Konsequenzen: (a) AC12-Zählung „unverteilt" ist für solche Dupes
   korrekt (Queue-Owner zählt als unverteilt), (b) der Dup-Case liegt sichtbar in der Queue. Wenn die
   Teamleitung das nicht will, ist ein 421-Fix (einfacher Filter: `Dedupliziert__c != true -> continue` im
   Insert-Pfad) die saubere Lösung — **ausdrücklich nicht Teil dieses Pull-Requests**, eigene Entscheidung
   durch PO. Kein Blocker für das Review dieses PRs.
   - Dup-Schließung (`Status`, `Subject`) und Bestätigung ändern kein 421-relevantes Feld → keine Re-Aktion.
   - 428-Trigger ist `after insert` only → eigene Updates feuern ihn nicht erneut.
6. **Queueable einreihen** für Schritt 7/8 (läuft in derselben Transaktion, NACH allen After-Triggern → 421 hat final die Queue gesetzt, die 428 dann in Phase B zu einer Person macht).

**Phase B (`SCRUM428AssignmentQueueable`, `without sharing`, 1 SOQL/1 DML je Schritt):**
7. **Zuteilung (AC6/7/8/9/10):** je Case (Queue-Id aus 421-Ergebnis = `Case.OwnerId`, muss `Group Type='Queue'` sein, sonst überspringen):
   - **AC9:** `BusinessHours` „Default" (active) → `getBusinessHoursWindowForDateTime(System.now())`; `null`/Weekend → **kein** Owner-Wechsel, Fall wartet in der Queue (AC6).
   - Queue-Mitglieder: `SELECT UserOrGroupId FROM GroupMember WHERE GroupId=:queueId AND UserOrGroupId IN (SELECT Id FROM User WHERE IsActive=true AND SCRUM428_Verfuigung__c=true)` (**AC10**: abgemeldete/fehmelde User ausgeschlossen; leer = alle abgemeldet → AC6).
   - Offene Fälle je Kandidat: `SELECT OwnerId, COUNT(Id) FROM Case WHERE OwnerId IN :candidates AND Status!='Closed' GROUP BY OwnerId` (**AC8**: „offen" := nicht Closed).
   - **Limit aus MDT:** `SELECT MaxOffene__c FROM SCRUM428_CaseLimitConfig__mdt WHERE DeveloperName='Standard' LIMIT 1` (Default 5, Fallback bei leerer Zeile: 5). Kandidaten mit `COUNT < Limit` qualifiziert; **wenigste** offene Fälle gewinnt; Tie-Break: kleinstes `User.Id` (deterministisch, testbar).
   - Update: `OwnerId=kandidat`, `Automatische_Zuordnung__c=true`, `Zuordnungszeitpunkt__c=System.now()`.
   - Niemand qualifiziert → **kein** Update (AC6: unassigned in Queue, in AC12-Sicht).
8. **Eingangsbestätigung (AC11):** nur für Cases OHNE `Dedupliziert__c`: `Messaging.SingleEmailMessage` an `Contact.Email` (sonst `SuppliedEmail`), Subject `Ihre Anfrage wurde erfasst — Fall {CaseNumber}`, Plain-Text-Template aus `SCRUM428CaseConfirmation` (ADR-4). `Messaging.sendEmail(batch)`; vor Senden `Limits.getEmailInvocations()`-Rest prüfen (Bulk-Schutz).

### ADR-4 — Bestätigung als Apex-Email, kein Template-Objekt, kein Flow
`Messaging.SingleEmailMessage` mit festem Plain-Text im Code (keine PII über den Empfänger hinaus, kein `EmailTemplate`-Metadata nötig):
```
Guten Tag {Name},

Ihre Anfrage ist bei uns eingegangen und wurde unter der
Fallnummer {CaseNumber} erfasst.

Wir melden uns schnellstmöglich bei Ihnen.

Mit freundlichen Grüßen
Ihr Service-Team
```
(AC4/AC5-Dup: KEINE Bestätigung — Schritt 8 filtert.)

### ADR-5 — Konfiguration per Custom Metadata Type (limit + Keywords, ohne Code-Change änderbar)
- `SCRUM428_CaseLimitConfig__mdt` — 1 Zeile `Standard` (`DeveloperName='Standard__mdt'`): `MaxOffene__c` (Number, Default 5). Ändern = MD-Record ändern/Deploy — **keine** Codeänderung (AC8 „konfigurierbarer Startwert").
- `SCRUM428_KategorierRegel__mdt` — N Zeilen: `Bereich__c` (Picklist Technik/Vertrag/Rechnung), `Keyword__c` (Text(80)). Startwerte liefert der Developer (§9).
- **Why MDT, nicht Custom Settings:** Custom Settings sind im Source-Deploy nicht adressierbar (`customsetting` im CLI-Registry ABSENT); `custommetadata` (Suffix `.md`, Directory `customMetadata`) ist es — nach `metadataRegistry.json` verifiziert.
- **Shape-Verifizierung Schritt (Developer):** MDT via Setup anlegen (Test-Org), `sf project retrieve start --metadata "CustomObject:SCRUM428_*"` + `--metadata "CustomMetadata:SCRUM428_*"` → die zurückgeholte XML ist die Vorlage für das Repo (don't-invent-metadata-shapes).

### ADR-6 — Neue Custom Fields (exakt diese drei, kein mehr)
| Field | Objekt | Typ | Default | Zweck |
|---|---|---|---|---|
| `Erfassungsquelle__c` | Case | Picklist (`E-Mail`, `Kontaktformular`) | null | AC1/2 „Quelle markieren" (ADR-2) |
| `Dedupliziert__c` | Case | Checkbox | `false` | AC4/5-Flag; steuert AC11 (keine Bestätigung) und AC12-Report-Ausschluss |
| `SCRUM428_Verfuigung__c` | User | Checkbox **`true`** | `true` | AC10: `false` = abgemeldet/Feierabend, bekommt keine NEUEN Fälle, behält Bestehende |

Namen/APIs exakt so — Developer kopiert das `Servicebereich__c.field-meta.xml`-Shape (vorhanden, deploybar) und das User-Field-Shape aus `generating-custom-field`.

### ADR-7 — AC12 als Report (kein LWC-Dashboard)
`reports/Service/Unverteite_Faelle.report-meta.xml`, `reportType=CaseList`:
- Filter: `OPEN = true` (offene Fälle) **und** `OWNER` `includes` `First Level Support, Technischer Support, Vertragsservice, Billing` (unverteilt := Owner ist eine der 4 Queues).
- Spalten: `CASE_NUMBER`, `SUBJECT`, `OWNER`, `CREATED_DATE`, `AGE`; Sortierung `CREATED_DATE` Asc → oberste Zeile = ältester wartender Fall; Record Count (Tabular/Summary-Footer) = Anzahl unverteilt. **Beides aus AC12** (Anzahl + Alter ältester) ohne eigene Aggregation.
- `<scope>org</scope>` — Sicht der Teamleitung ist org-weit, nicht „my records" (Lektion SCRUM-394/417: ohne `<scope>` sieht der Report nur eigene Records).
- **Developer-Verifikation nach erstem Deploy:** Report retrieve → XML-Filter lesen → falls `includes` mit Komma-Liste von der Org anders serialisiert wird, Repo-File daraus anlernen (Retrieve = Wahrheit).

### ADR-8 — Permission Sets (kein Profil-Edit, FLS explizit)
Zwei PS, House-Naming `SCRUM428_*`:
1. **`SCRUM428_ServiceTeam`** (an Support-User + alle 4 Queues-Zugriffe …):
   - `Case.Erfassungsquelle__c`: readable ✅, editable ✅
   - `Case.Dedupliziert__c`: readable ✅, editable ❌
   - `User.SCRUM428_Verfuigung__c`: readable+editable ✅ (sich selbst toggeln — User-Profil-Beschränkung: PS gewährt FLS, Edit auf eigene Zeile ist Default-Verhalten)
2. **`SCRUM428_Teamleitung`** (an Teamleitungs-Rolle/User):
   - `Case.Erfassungsquelle__c` readable, `Case.Dedupliziert__c` readable (AC12 braucht beide)
   - Report-Zugriff über Report-Permission (Folder `Service` readable) — im PS via `reportFolderAccess`? → **Nein:** Reportsicht ist org-seitig (Report-Tab-Zugriff der Rolle); PS hält nur FLS. (Kein `reportFolderAccess`-Element im PS — das ist `Reports`-Objekt-CRUD, nicht FLS; Report-Zuweisung bleibt O5.)
- **System/Automation-Kontext (AC-„Create,Read/Edit/Delete"):** Trigger/Queueable laufen `without sharing` — schreiben ohne FLS (exakt das 420/398/421-Hausverhalten). Ein PS für „System" existiert nicht und ist nicht nötig; dokumentiert statt erfunden.
- **Zuweisung (Developer-Pflicht, Hausregel):** PS an `devops-agent@cline.test` UND den menschlichen Test-Account zuweisen + Readback `PermissionSetAssignment` + ein Feld per `WITH USER_MODE` lesen.

### ADR-9 — Sharing: **kein** Impact
- OWD Case unverändert (Ticket: „OWD unverändert").
- Unverteilt = `OwnerId` einer Queue → Queue-Sharing (bestehend) zeigt sie den Queue-Mitgliedern/Leitung.
- Keine neuen Sharing Rules, keine OWD-Änderung, kein OWD-Schritt im Org-Setup. → **Sharing-Abschnitt der Pre-Handoff-Checkliste: „no impact" (explizit).**

## 4. Komponenten & Dateien (vollständige Liste — Developer folgt 1:1)

### Apex (alle `apiVersion 62.0`)
```
force-app/main/default/classes/
  SCRUM428CaseIngestHandler.cls            # Phase A: ADR-3 Schritte 1–6
  SCRUM428AssignmentQueueable.cls          # Phase B: ADR-3 Schritte 7–8 (Queueable)
  SCRUM428AssignmentService.cls            # AC6–AC10-Logik, vom Queueable aufgerufen
  SCRUM428CaseConfirmation.cls             # ADR-4: Bestätigung bauen+senden
  SCRUM428ContactFormController.cls        # ADR-2(2): AuraEnabled submitForm + Contact-Match
  (+ 5 × .cls-meta.xml)
```

### Trigger
```
force-app/main/default/triggers/
  SCRUM428CaseIngestTrigger.trigger        # after insert only → Handler.process(Trigger.new)
  (.trigger-meta.xml)
```

### Custom Fields (ADR-6)
```
force-app/main/default/objects/
  Case/fields/Erfassungsquelle__c.field-meta.xml    # Picklist: E-Mail / Kontaktformular
  Case/fields/Dedupliziert__c.field-meta.xml        # Checkbox, Default false
  User/fields/SCRUM428_Verfuigung__c.field-meta.xml # Checkbox, Default true
```

### Custom Metadata (ADR-5)
```
force-app/main/default/customMetadata/
  SCRUM428_CaseLimitConfig__mdt.Standard.md    # 1 Record „Standard", MaxOffene__c = 5
  SCRUM428_KategorierRegel__mdt.Tech_Fehler.md # + weitere Startliste vom Developer (§9)
force-app/main/default/objects/
  SCRUM428_CaseLimitConfig__mdt/SCRUM428_CaseLimitConfig__mdt.object-meta.xml
  SCRUM428_CaseLimitConfig__mdt/fields/MaxOffene__c.field-meta.xml
  SCRUM428_KategorierRegel__mdt/SCRUM428_KategorierRegel__mdt.object-meta.xml
  SCRUM428_KategorierRegel__mdt/fields/Bereich__c.field-meta.xml
  SCRUM428_KategorierRegel__mdt/fields/Keyword__c.field-meta.xml
```
*(Shape erst per ADR-5-Verifikation gegen die Org — NICHT frei erfinden.)*

### LWC (AC2)
```
force-app/main/default/scr428ContactForm/
  scr428ContactForm.html / .js / .js-meta.xml   # targets: lightning__AppPage, lightning__Tab
```

### Permission Sets (ADR-8)
```
force-app/main/default/permissionsets/
  SCRUM428_ServiceTeam.permissionset-meta.xml
  SCRUM428_Teamleitung.permissionset-meta.xml
```

### Report (AC12)
```
force-app/main/default/reports/Service/Unverteite_Faelle.report-meta.xml
```

### Tests (Haus-Pattern, alle apiVersion 62.0)
```
force-app/main/default/classes/
  SCRUM428IngestTest.cls       # AC1–AC5, AC11 (E-Mail-Case simulieren = Case-Insert mit Origin='Email' + Erfassungsquelle-Fall)
  SCRUM428AssignmentTest.cls   # AC6–AC10 (inkl. Grenzwert Limit=5, BusinessHours via Test-Setup, MDT-Limit)
  SCRUM428IngestFlsTest.cls    # ADR-8: neg/pos FLS je neues Feld, WITH USER_MODE
  (+ 9 × .cls-meta.xml)
```
**Test-Kontext-Hinweise (House):** Business-Hours-Tests mit `Schema.setMockBusinessHours`/`Test.startTest`-Zeitsteuerung oder Mock per `BusinessHours`-Insert in der Testdatenbank; `Messaging.sendEmail` per `Messaging.setMockCallables`… (Developer prüft exakte API per `--help`/docs — hier nur der Punkt: Bestätigung im Test über Mock verifizieren, KEINE echte Mail). E-Mail-Eingang (AC1) im Apex-Test = direkter Case-Insert in der Form, die Email-to-Case erzeugt (Origin/Subject/Description/ContactId) — E-Mail-Transport selbst ist kein Apex-Test-Objekt, sondern E2E-Manuelle-Verifikation (O1).

### Manifeste
```
manifest/scr428-phase1-fields.xml
  CustomField:Case.Erfassungsquelle__c
  CustomField:Case.Dedupliziert__c
  CustomField:User.SCRUM428_Verfuigung__c
  CustomObject:SCRUM428_CaseLimitConfig__mdt
  CustomObject:SCRUM428_KategorierRegel__mdt
  CustomMetadata:SCRUM428_CaseLimitConfig__mdt.Standard
  CustomMetadata:SCRUM428_KategorierRegel__mdt.<alle MDT-Records>
manifest/scr428-phase2-referencing.xml
  ApexClass:SCRUM428*
  ApexTrigger:SCRUM428CaseIngestTrigger
  LightningComponentBundle:scr428ContactForm
  PermissionSet:SCRUM428_ServiceTeam
  PermissionSet:SCRUM428_Teamleitung
  Report:Service/Unverteite_Faelle
```
*(LWC-Manifesttyp: `LightningComponentBundle` — per `metadataRegistry.json` verifiziert (`directoryName: lwc`, bundle-Strategie); Members = Bundlename.)*

## 5. Governor-Limit-Risiken → Mitigation
| Risiko | Mitigation |
|---|---|
| SOQL-in-Loop (AC4/5 dedup, Zuteilung) | jede Phase: 1 Bulk-SOQL (IN-Liste / GROUP BY), danach 1 Bulk-DML |
| DML nach Trigger-Update → Trigger-Loops (421↔428) | nur `after insert` für 428; 421-Änderungs-Filter + Queueable-Reihenfolge (ADR-3 Schritt 5) — kein Loop möglich; `isRunning`-Guard nicht nötig, dokumentiert |
| Bestätigungs-Mails bei Bulk | `Limits.getEmailInvocations()` vor Senden, Rest prüfen, nur nicht-Dup |
| `Messaging` im Trigger | Phase B ist Queueable (in derselben Transaktion, nach den Triggern) — `Messaging`-Aufruf ist erlaubt (kein Async-Queue-REST-Restriktions-Szenario relevant) |
| Governor 421 + 428 zusammen (beide firen) | 421: 1 Group-SOQL + max 1 DML; 428 Phase A: 4 SOQL + 3 DML; Phase B: 3 SOQL + 2 DML → weit unter 100/150 |

## 6. Org-Setup-Schritte (NACH Deploy — DevOps/PO; jeder Schritt mit Readback)
| # | Schritt (Org) | Readback (SOWOLSO) |
|---|---|---|
| O1 | Email to Case aktivieren, Service-Adresse einrichten, Ziel „New Case“, Contact-Matching aktiv | UI + 1 Testmail → Case existiert mit `Origin=Email`, `Erfassungsquelle__c='E-Mail'`, `ContactId` gesetzt |
| O2 | PS `SCRUM428_ServiceTeam` auf Support-User + Test-Account, `SCRUM428_Teamleitung` auf Teamleitungs-User zuweisen | `SELECT … FROM PermissionSetAssignment WHERE PermissionSet.DeveloperName IN ('SCRUM428_ServiceTeam','SCRUM428_Teamleitung')` |
| O3 | 4 Queues mit echten Mitgliedern befüllen | `SELECT COUNT FROM GroupMember WHERE GroupId IN (:queueIds)` + User-Liste |
| O4 | LWC `scr428ContactForm` als Tab/Utility-Item einrichten | UI-Readback + 1 Formular-Submit → Case mit `Erfassungsquelle__c='Kontaktformular'` |
| O5 | Report `Unverteite_Faelle` dem Teamleitungs-User zugänglich machen (App/Tab) | UI + 1 Öffnen als Teamleitungs-User |

*(Org-Setup-ACs sind KEINE Apex-Test-Assertions — Readback ist der Nachweis. House-Regel SCRAM-424.)*

## 7. Pre-Handoff-Checkliste
- [x] Datenmodell dokumentiert (ADR-6: 3 neue Custom Fields + 2 MDTs; bestands: `Servicebereich__c`, `Automatische_Zuordnung__c`, `Zuordnungszeitpunkt__c`, `Origin`, `CaseNumber` unverändert)
- [x] Permission-Set-/FLS-Design dokumentiert (ADR-8, 2 PS, explizite Felder, kein Profil-Edit)
- [x] Sharing-Modell: **kein Impact** (AD-9)
- [x] Governor-Limit-Risiken dokumentiert (§5)
- [x] Flow: **nicht** verwendet (ADR-1) → kein apiVersion/Naming für Flows
- [x] Bestehende Muster wiederverwendet: 421-Trigger/Handler (Queue-Routing, eligibility), 420/398 FLS-Hausverhalten, Test-/Manifest-/Report-Shapes (§2.2)

## 8. Offene Punkte (NICHHT build-blockierend)
- **[PO] AC4-Abschlussform:** Entwurf schließt Dup-Case (`Status='Closed'`, Subject-Präfix). Nur wenn PO ablehnt: eigene `InboundEmailHandler`-Klasse (Insert-Verhindern) — deutlich größer. **Default: schließen. Widerspruch nur per Kommentar.**
- **[PO] AC12:** Report genügt (ADR-7) oder Dashboard/LWC gewünscht? → eigenes Ticket, blockiert 428 nicht.
- **[Developer] AC3-Start-Keywords:** MDT-Startliste festlegen (Vorschlag je 3–5 Keywords/Bereich), im Commit dokumentieren.
- **[DevOps/PO] Service-E-Mail-Adresse** → O1. **[PO] Queue-Mitglieder** → O3. Beides im Ticket als offen deklariert.

## 9. Technische Akzeptanzkriterien (ergänzend zu den 12 funktionalen ACs des Tickets)
- **TC1:** `SCRUM428IngestTest`: je ein Test für AC1, AC2 (per Controller), AC3 (je Bereich + Fallback=Allgemein), AC4, AC5, AC11 (sendet/verschweig per Mock/Probe). Mind. 1 Assertion pro AC.
- **TC2:** `SCRUM428AssignmentTest`: AC6 (niemand verfügbar → kein Owner), AC7 (wenigste), AC8 (Grenzwert: Kandidat mit genau Limit=5 wird übersprungen), AC9 (außerhalb BusinessHours → kein Owner), AC10 (`SCRUM428_Verfuigung__c=false` → ausgeschlossen).
- **TC3:** `SCRUM428IngestFlsTest`: ohne PS → `WITH USER_MODE`-SELECT auf alle 3 neuen Felder wirft; mit PS → lesbar; `Dedupliziert__c` read-only (DML wirft), andere editierbar. (Shape: `SCRUM421QueueAssignmentFlsTest`.)
- **TC4:** `sf project deploy` Test-Org mit `--test-level RunSpecifiedTests --tests SCRUM428IngestTest,SCRUM428AssignmentTest,SCRUM428IngestFlsTest` grün.
- **TC5:** Beide PS deployed **und** an Test-User + Teamleitungs-User zugewiesen; Readback `PermissionSetAssignment` + 1 `WITH USER_MODE`-Lesen pro PS.
- **TC6:** Report `Unverteite_Faelle` deployed; Retrieve-Readback zeigt `OPEN=true` + 4 Queue-Namen im OWNER-Filter + `scope=org`.
- **TC7:** LWC + Controller deployed; Controller aufrufbar (Apex-Test mit `with sharing`-Kontext) → Case mit `Erfassungsquelle__c='Kontaktformular'`.
- **TC8:** KEIN `waitForLoadState('networkidle')` in E2E; Formular-E2E (falls Tester einen möchte) mit frontdoor.jsp-Auth via globalSetup. (Für 428 optional — Apex-TC1/TC7 decken AC2.)

## 10. Für @user (Einführung in die Automation)
Beim Eingang einer E-Mail an die Service-Adresse oder beim Absenden des Kontaktformulars erstellt das System automatisch einen Fall. Der Absender wird als Kontakt erfasst (bei E-Mail automatisch aus der Absenderadresse). Bei E-Mails erkennt das System aus dem Text den Themenbereich (Technik, Vertrag oder Rechnung) und legt den Fall im richtigen Bereich an; wenn der Text nicht eindeutig ist, wird „Allgemein" gewählt. Der Kundenanfrage wird automatisch zugewiesen: das System prüft, wer aus dem zuständigen Team gerade verfügbar ist (weniger als fünf offene Fälle, Montag bis Freitag 9–17 Uhr, nicht abgemeldet) und gibt den Fall an die Person mit der wenigsten Arbeit. Wenn niemand verfügbar ist, bleibt der Fall in der zuständigen Warteschlange und wird automatisch vergeben, sobald jemand frei wird. Gibt dieselbe Person erneut eine Nachricht mit der Fallnummer oder im selben Bereich, entsteht kein zweiter Fall — die Nachricht hängt an dem bestehenden Fall an. Jeder neue Fall erhält sofort eine Bestätigungs-E-Mail mit der Fallnummer; bei doppelt eingehenden Nachrichten nicht. Sie als Teamleitung sehen jederzeit in einem Report, wie viele Fälle unverteilt in den Warteschlagen warten und wie lange der älteste davon schon wartet.
