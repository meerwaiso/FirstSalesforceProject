# SCRUM-410 — Betreuung an eine andere Person übergeben (Batch-Transfer mit Vorschau + Audit-Spur)

> Autoritative Build-Spec. Der Developer baut von diesem Dokument, nicht vom Jira-Kommentar
> (der Jira-Konverter korruptiert XML/API-Namen — siehe Skill-Notiz). Repo-Dateien sind
> die Quelle der Wahrheit.

## Ziel
Ein Teamleiter wählt „gibt ab“ und „übernimmt“, sieht eine Vorschau (was würde übergeben),
und stößt mit **einer** Aktion einen atomaren, bulki­fi­zierten Ownership-Wechsel an — der
nachher im System als Audit-Spur nachweisbar ist.

## Scope (aus Ticket, mit @user abgestimmt)
Eine Übergabe betrifft **Account + alle dazugehörigen Kontakte** des abgebenden Betreuers;
dazugehörige **offene Fälle** (`Case.IsClosed=false`) und **laufende Chancen** (`Opportunity.IsClosed=false`)
wechseln mit. **Abgeschlossene Historie** (Closed Cases, `IsClosed=true` Opportunities) bleibt
beim alten Betreuer. Es wird **nur `OwnerId`** geändert — kein anderes Feld.

---

## Architektur-Entscheidungen (ADRs)

### ADR-1: Apex statt Flow (Default-Regel)
Bulki­fi­zierter, atomarer Batch über 4 Objekte mit Vorschau-Query und Fehlerbehandlung —
Flow kann dies nicht sauber (kein sauberes Async, governor-Risiko bei 300 Accounts,
keine Vorschau-Semantik). **→ Apex.**

### ADR-2: Ein.Queueable-Job (eine atomare Transaktion), nicht Batchable
„In einem Stück“ = **atomar**. Ein einziger async `Queueable`-Job in **einer** Transaktion:
4 Bulk-DMLs + Audit-Insert ⇒ alles oder nichts (kein Teilergebnis, nichts „bleibt liegen“).
Bei 300 Accounts (worst case einige tausend Child-Records) liegt das komfortabel innerhalb
der real-time Governor Limits (DMLs, SOQL, Heap). **Fallback dokumentiert:** wachst ein
Gebiet jenseits ~5.000 betroffene Child-Records, ist der Job auf `Database.Batchable`
umzustellen (dann keine Atomicity mehr, Fehler-Audit-Zeile nötig). Für 300 Accounts: Queueable.

### ADR-3: Sharing — Ownership-Wechsel allein ist ausreichend (OWD-unabhängig)
Verifiziert (Test-Org, 2026-09-11): `SharingRules` für Account/Contact/Case/Opportunity
enthält **keine** Owner-Default-Einstellungen (retrieve: leeres `<SharingRules/>`).
Der Feature greift ausschließlich auf **Owner-Zugriff**: der neue Owner hat auf eigene
Records immer Read+Edit (nur durch Profil-Objekt-FLS gedeckelt, das Standardprofile schon
haben ⇒ **AC5 erfüllt ohne Sharing-Änderung**, OWD-Modell egal).
**Kein Change an OWD / Sharing Rules / Profil.** Das ist die Antwort auf PO-Frage (1).
> Nicht verifiziert hier: `Case` Read-FLS für den Overnehmer via Standardprofil — das ist
> Standard-CRUD und in jeder Sales-/Service-Org gesetzt. @tester-agent prüft es per
> UI-API `record-ui` als Endanwender-User ohne PS (siehe Offene Punkte).

### ADR-4: Audit = Custom Object `CustomerTransfer__c` (Run-Log-Pattern aus SCRUM-367)
Wiederverwendet das bewährte `CaseRebuildRun__c`-Muster (AutoNumber, Picklist-Status,
`<sharingModel>Private</sharingModel>`). Sichtbarkeit per `viewAllRecords` — jeder darf
„Warum betreue ich diesen Kunden?“ nachvollziehen. **Kein Profil-Edit.** FLS per PS.
(PO-Frage (2).)
Naming: DevName englisch (Haus-Pattern `CaseRebuildRun__c`), Label deutsch.

### ADR-5: Einstieg = LWC + Quick Action auf `User`
Das UI braucht zwei User-Picker + Vorschau + Bestätigung = ein kleines Formular ⇒ **LWC**,
exponiert als **Quick Action auf dem `User`-Objekt** (source-persistierbar, kein
Utility-Bar-Org-Config nötig). Flow: Teamleiter öffnet den User-Record der abgebenden
Kollegin → klickt „Betreuung übergeben“ → „Abgibt“ = dieser User (vorausgefüllt, read-only),
„Übernimmt“ = Picklist → „Vorschau“ → „Übernehmen“. Platzierung ist ADR, nicht Pflicht —
Utility-Bar-Alternative ist ein @devops-agent-Org-Schritt (blockiert NICHT).

---

## Komponenten & exakte Pfade

### 1. Audit-Objekt `CustomerTransfer__c`
`force-app/main/default/objects/CustomerTransfer__c/`

Object (`CustomerTransfer__c.object-meta.xml`) — Pattern aus `CaseRebuildRun__c`:
```xml
<CustomObject>
  <label>Betreuungs-Übergabe</label>
  <pluralLabel>Betreuungs-Übergaben</pluralLabel>
  <sharingModel>Private</sharingModel>
  <deploymentStatus>Deployed</deploymentStatus>
  <nameField>
    <displayFormat>TRANSFER-{0000}</displayFormat>
    <label>Lauf-Nr.</label>
    <type>AutoNumber</type>
  </nameField>
  <description>Übergeben von SCRUM-410: wer zu welchem Zeitpunkt wie viel Kunden/Fälle/Chancen an wen übergeben hat (Audit-Spur).</description>
</CustomObject>
```

Felder (je `objects/CustomerTransfer__c/fields/<Name>__c.field-meta.xml`):

| Feld (DevName) | Typ | Label | Zweck |
|---|---|---|---|
| `From_User__c` | Lookup → `User`, required | Gibt ab | abgebende Betreuungsperson |
| `To_User__c` | Lookup → `User`, required | Übernimmt | übernehmende Person |
| `Transferred_At__c` | DateTime | Übergeben am | Zeitpunkt (System.now()) |
| `Accounts_Transferred__c` | Number(18,0) | Übergebene Accounts | Count |
| `Contacts_Transferred__c` | Number(18,0) | Übergebene Kontakte | Count |
| `Open_Cases_Transferred__c` | Number(18,0) | Übergebene offene Fälle | Count |
| `Open_Opportunities_Transferred__c` | Number(18,0) | Übergebene laufende Chancen | Count |
| `Status__c` | Picklist (Abgeschlossen / Fehler) | Status | default Abgeschlossen |

Lookup-Shape (Pattern, `required` optional):
```xml
<CustomField>
  <fullName>From_User__c</fullName>
  <label>Gibt ab</label>
  <referenceTo>User</referenceTo>
  <relationshipLabel>Übergaben (von)</relationshipLabel>
  <relationshipName>Transfers_By_User</relationshipName>
  <required>true</required>
  <type>Lookup</type>
</CustomField>
```

### 2. Apex — Controller + Queueable-Job (2 Klassen, 1 Trigger: **kein** Trigger)
`force-app/main/default/classes/`

`CustomerTransferController.cls` — `@AuraEnabled`-Methode für das LWC:
- `preview(Id fromUser, Id toUser)` → liefert 4 Counts (AC1/AC6). 4 SOQLs (`SELECT COUNT()`
  o.Ä.), **read-only**, kein DML. Predicates (org-verifiziert):
  - Accounts: ` WHERE OwnerId=:fromUser`
  - Contacts: ` WHERE OwnerId=:fromUser`
  - offene Fälle: ` WHERE OwnerId=:fromUser AND IsClosed=false`
  - laufende Chancen: ` WHERE OwnerId=:fromUser AND IsClosed=false`
- `launch(Id fromUser, Id toUser)` → validiert (from ≠ to, beide existieren),
  `System.enqueueJob(new CustomerTransferJob(fromUser, toUser))`, zurück JobId/Audit-Info.
  Kein DML hier (Audit wird im Job geschrieben ⇒ atomar mit dem Transfer).

`CustomerTransferJob.cls` — `implements Queueable`, `execute()` in **einer** Transaktion:
- 4× ID-Listen laden (bulk SOQL, **nicht in Loop**):
  - `SELECT Id FROM Account WHERE OwnerId=:fromUser`
  - `SELECT Id, AccountId FROM Contact WHERE OwnerId=:fromUser`
  - `SELECT Id FROM Case WHERE OwnerId=:fromUser AND IsClosed=false`
  - `SELECT Id FROM Opportunity WHERE OwnerId=:fromUser AND IsClosed=false`
- je `update` mit List (nur `OwnerId` setzen) ⇒ 4 Bulk-DMLs:
  - Accounts: `OwnerId=toUser`
  - offene Cases, laufende Opps, Kontakte: `OwnerId=toUser`
  - **abgeschlossene** Cases/Opps werden **nicht** geladen ⇒ bleiben beim Alten (AC4).
- Counts = `list.size()` je Objekt, dann 1× `insert new CustomerTransfer__c(... Status__c='Abgeschlossen', Transferred_At=System.now())`.
- Bulkification / Governor: keine SOQL/DML in Loop; 4+1 DMLs, 4+1(SOQL); Heap klein.
  `@isTest`-sicher (Queueable in Test via `Test.startTest/endTest`).
- **AC3 (Inhalt unverändert):** wird durch Konstruktion trivial erfüllt — die Lists tragen
  nur `Id`, und nur `OwnerId` wird geschrieben; Status/Frist/Priorität bleiben unangetastet.

### 3. LWC `Betreuungsuebergabe`
`force-app/main/default/lwc/betreuungsuebergabe/`
- 2 User-Picker (`from`=vorausgefüllt aus dem User-Record, read-only; `to`=wählbar)
- Button „Vorschau“ → zeigt 4 Counts
- Button „Übernehmen“ → bestätigt → `launch` → Toast „Übergabe abgestoßen, Lauf-Nr. …“
- Kein `networkidle`/DOM-Timeout in eigenen Tests nötig; E2E nutzt den `sf auth`-Token-Pattern
  (siehe Offene Punkte).

### 4. Quick Action auf `User` (source-persistierbar)
`force-app/main/default/objects/User/quickActions/Betreuungsuebergabe.quickAction-meta.xml`:
```xml
<QuickAction>
  <optionsCreateFeedItem>false</optionsCreateFeedItem>
  <type>LightningComponent</type>
  <lightningComponent>betreuungsuebergabe</lightningComponent>
  <label>Betreuung übergeben</label>
  <optionsFeedItem>false?</optionsFeedItem><!-- nur createFeedItem relevant für Feeds -->
</QuickAction>
```
(Developer prüft die exakten QuickAction-Child-Elemente per `QuickAction`-Registry /
bestehenden Beispiel — nicht blind aus diesem Block kopieren; das LWC-`type` ist sicher.)

### 5. Permission Set (FLS, Pattern aus SCRUM-367)
`force-app/main/default/permissionsets/SCRUM410_CustomerTransfer.permissionset-meta.xml`
- `objectPermissions` `CustomerTransfer__c`: `allowCreate=false, allowDelete=false,
  allowEdit=false, allowRead=true, viewAllRecords=true`
- `fieldPermissions` Read (editable=false) auf allen 7 Feldern + Lookup-Felder.
- `tabSettings` (falls Tab vorhanden) Visible.
- **Kein Profil-Edit.** Zuweisen an: Teamleitung-Role (Read), und die Endanwender-Rollen
  die die Audit-Spur lesen → per Assignment (Org-Schritt, @devops).

### 6. Layout `CustomerTransfer__c`
`force-app/main/default/layouts/CustomerTransfer__c-Betreuungs-Übergabe Layout.layout-meta.xml`
— Pattern aus `CaseRebuildRun__c-...Layout.layout-meta.xml`: 1 Section, Felder
Lauf-Nr.(read-only), Gibt ab, Übernimmt, Übergeben am, 4 Counts.

### 7. Manifest
`manifest/scr410-phase1-object.xml` (Object+Fields) → `scr410-phase2-referencing.xml`
(Controller+Job+LWC+QuickAction+PS+Layout) → `scr410-phase3-apextests.xml` (Testklasse).
House-Pattern 3-Phasen-Deploy (siehe `manifest/scr405-*`).

---

## Tests (PR-Gate — „deployed + live run“ reicht NICHT, SCRUM-359-Regel)
`CustomerTransferServiceTest.cls` (Apex, `@isTest`):
- **AC2/AC3/AC7:** 300 Accounts + Child-Records (open + closed) → `Test.startTest` →
  `enqueueJob` → `Test.endTest` ⇒ alle Accounts/Kontakte/**offenen** Cases/**laufenden**
  Opportunities haben `toUser` als Owner; **abgeschlossene** behalten `fromUser`; nur
  `OwnerId` geändert; keine Governor-Ausnahme.
- **AC1:** `preview()` liefert korrekte Counts.
- **AC6:** genau 1× `CustomerTransfer__c`-Zeile, Counts stimmen, From/To/User gesetzt.
- **AC4:** Closed-Case/Closed-Opp-Precondition (org-Writability-Regel: ClosedDate per
  DML setzen NICHT — Status='Closed' + assertNotEquals(null, ClosedDate) als
  Precondition, siehe Skill-Notiz SCRUM-390).
E2E (`tests/`) für die LWC Vorschau/Übernehmen-UI (Shape `SCRUM-378_*`-Spec), mit
`sf auth`-Token-Login, ohne `networkidle`.

---

## Offene Punkte (blocken die Implementierung NICHT)
- [ ] **Endanwender-Fallback-FLS:** @tester-agent verifiziert via UI-API `record-ui`
      (ohne PS zugewiesen) dass der Overnehmer Read+Edit auf übergebenen Cases/Opps hat —
      ADR-3 (Owner-Zugriff) ist die Architektur, der Test ist die Bestätigung.
- [ ] **PS-Zuweisung an Rollen** (Teamleitung + Leser): @devops-agent Org-Schritt nach Deploy.
- [ ] **Utility-Bar-Platzierung** als Alternative zur Quick Action: @devops-agent, nur
      wenn @user es wünscht (ADR-5) — Quick Action auf User ist der Default, source-persistiert.
- [ ] **Fehler-Audit-Zeile** (Status=Fehler bei abgebrochenem Job): bewusst NICHT in dieser
      Story (atomarer Queueable hinterlässt bei Fehler kein Teil­ergebnis, aber auch keine
      Audit-Zeile). Enhancement → spätere Story, wenn @user es will.
- [ ] **QuickAction-exakte Child-Elemente:** Developer prüft per Registry (ADR-4-Notiz).
