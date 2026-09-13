# SCRUM-413 — Design: Feld „Letzter echter Kontakt“ am Kontakt

> **Autoritative Build-Spec.** Der Developer baut VON dieser Datei, nicht vom
> Jira-Kommentar (Jira-Markup mutiert API-Namen: doppelte Unterstriche → Bold,
> XML-Endtags, `+`). Alle exakten Namen/XML sind hier in Codeblöcken.
>
> **Status:** Freigegeben (Architect). Objektiv: Contact (Kontakt). Nur Sales Cloud.
> **Ziel:** Am Kontakt auf einen Blick sehen, wann der letzte *tatsächlich
> abgeschlossene* Call war — filterbar/sortierbar („nicht erreicht seit > 6
> Monaten“ / „nie erreicht“).

---

## Goal (1 Satz)

Ein systemseitig gepflegtes, schreibgeschütztes Date-Feld
`Contact.Last_Real_Contact_Date__c` (Tagebene), das je Kontakt das Datum des
**neuesten abgeschlossenene Calls** (Task mit `Type='Call'` + `Status='Completed'`)
abbildet — laufend beim Call-Abschluss per Apex-Trigger und einmalig rückwirkend
für den Bestand per Bulk-Batch.

---

## Kernerregel (aus PO-Spec, ungeändert übernommen)

- **Zählt:** abgeschlossener Call dem Kontakt zugeordnet → in der Org: ein
  `Task` mit `Type='Call'` **und** `Status='Completed'`, dessen `WhoId` den
  Kontakt referenziert. Zeitbasis = **`ActivityDate`** (das Call-Datum).
- **Zählt NICHT:** eingeplanter/zukünftiger Call (`Status != 'Completed'`).
- **Zählt NICHT:** Serienbriefe, Massen-/automatische Mails, sonstige automatische
  Aktivitäten, echte 1:1-Mails → alles `Type != 'Call'` und daher per
  `Type='Call'`-Filter ausgeschlossen.
- **Neuester abgeschlossener Call gewinnt** → `MAX(ActivityDate)` über die
  abgeschlossenen Calls des Kontakts.

### ⚠️ Befund „Call-Representation“ (Org, read-only, 2026-09-13)

- In der Test-Org existiert **kein** Custom Call-Objekt. Ein „Call“ ist ein
  Standard-`Task`. Verifiziert via `sf sobject list` (kein Call-*) und
  `sf sobject describe -s Task` (Feld `CallType` Picklist
  `Internal/Inbound/Outbound` existiert → Call-Semantik in Task).
- `Task.Type='Call'`, `Task.Status='Completed'`, `Task.WhoId`,
  `Task.ActivityDate` sind alle querybar (SOQL-Roundtrip grün; absichtlich
  falsches Feld liefert sauberen Fehler → Query-Soundness bestätigt).
  `Task.Type` erschien in `sobject describe` nicht (FLS-filtet für den
  Test-User) — ist aber als SOQL-Filter gültig, das reicht für die Automatisierung
  (System-Modus, FLS-unabhängig).
- **Aktuell 0 Tasks in der Test-Org** (633 Contacts, 543 Cases mit ContactId).
  → Consequence: **AC6 (Bestand) liefert 0 geänderte Contacts im Live-Lauf.**
  AC6 muss proof via Apex-Test mit synthetischen abgeschlossenen Calls
  (`insert new Task(Type='Call', Status='Completed', WhoId=contact, ActivityDate=...)`).
  Ein „im Live-Lauf 0 geändert“ ist dann korrekt und erwünscht, kein Defekt.

### ⚠️ Befund „Trigger-DML umgeht FLS“ (Org, empirisch 2026-09-13)

In der Test-Org tragen **521/633** Contacts bereits einen Wert in
`Last_Case_Date__c` — geschrieben vom deployten `LastCaseDateTrigger`
(SCRUM-403) trotz `editable=false` im Permission Set. Damit ist empirisch
bestätigt: **Trigger-/Batch-DML im System-Modus umgeht FLS** und braucht
kein Update-Right. Das entgegnet der älteren Haus-Annahme „Trigger-DML wird
von read-only-FLS blockiert“ (SCRUM-388). Für SCRUM-413 gilt:
**read-only-FLS, kein Update-Grant an niemanden.**

---

## Architektur-Entscheidung (ADR)

### ADR-1: Apex (Trigger + Batch), **kein** Flow
Rationale:
- **Hausmuster exakt nachbauen** — der deployte SCRUM-403
  (`LastCaseDateTrigger` + `LastCaseDateRebuilder`) ist der direkte Vorbild.
  Gleicher Dual-Mechanismus: bulkified `recompute(Set<Id>)` + Batch, der
  dieselbe Methode ruft. Konsistenz > Neukonstruktion.
- „Neuester abgeschlossener Call gewinnt“ mit korrektem **Rückfall/NULL**
  (Call reopened → aus demMAX fallen; gelöschter completed Call → vorheriger)
  ist reine event-getriebene Neu-Berechnung → Apex. Flow für
  recompute-MAX-over-aggregate mit NULL-Semantik und Bulk-Governor ist
  anfällig (Schema-Drift, apiVersion, Limits) — genau die Failure-Mode, die
  dieses Haus von Flow abhält.
- Governor: **1 Aggregate-SOQL + 1 SOQL + 1 DML** pro Batch unabhängig von
  Call-Anzahl → kein SOQL-in-Loop.

### ADR-2: Zeitbasis = `ActivityDate` (nicht CreatedDate, nicht LastModified)
`ActivityDate` ist das Call-Datum selbst und ist bei Status-Wechsel
(Abruf zu „abgeschlossen“) **nicht** automatisch verändert → „abgeschlossen am
Datum X“ bleibt deterministisch. (SCRUM-403 nutzte CreatedDate, weil ein Case
beim *Anlegen* zählt; hier zählt der *Call zu dem Termin*.)

### ADR-3: Kontakt-Link = `WhoId` (nicht WhatId)
Ein Call auf einen Kontakt referenziert den Kontakt über `Task.WhoId`
(Pickliste Contact/Lead). Das entspricht „dem der Kontakt zugeordnet ist.“
Handler: `SELECT WhoId, MAX(ActivityDate) FROM Task WHERE Type='Call'
AND Status='Completed' AND WhoId IN :whoIds GROUP BY WhoId`.
(Offen für PO/Devops, blockt NICHT: falls die Org Calls über `WhatId` auf
Account + ein anderes Feld auf den Kontakt legt, ist genau diese WHERE-Klausel
die einzige Stelle, die angepasst wird — siehe Offene Punkte.)

### ADR-4: NULL-Semantik (exakt getrennt von SCRUM-403)
`Last_Real_Contact_Date__c = null` bedeutet **»nie ein abgeschlossener Call«**
(= „nie erreicht“, AC5). `mustWrite` pro WhoId:
`cur == null ? (new != null) : (new != cur)` → NULL→Wert schreiben ·
Wert→Wert nur bei Änderung · NULL→NULL no-op. **Kein** „heute“, **keine** 0.

### ADR-5: FLS via Permission Set (read-only), kein Profile-Edit, kein Update-Grant
Pattern SCRUM403/321/327/329. `Last_Real_Contact_Date__c`: `readable=true,
editable=false`. „Schreibgeschützt für Nutzer“ (AC7) = read-only-FLS **und**
Readonly im Layout. System-Context (Trigger/Batch) umgeht FLS → niemand braucht
Write.

### ADR-6: Sharing = **kein Impact**; keine Log-Zeile; kein Custom Button
Feld erbt Contact-Sharing (OWD/Rules/Hierarchy) — keine neuen Regeln.
Rebuilder: `without sharing`, `finish()` = no-op, kein `*RebuildRun__c`
(das gehört zu SCRUM-365). Idempotent: 2. Lauf ändert 0 (mustWrite-Schutz).

### ADR-7: Layout-Sichtbarkeit in Lightning = Org-Step (DevOps), Classic via FLS+Layout
Das Repo trackt nur das Classic `.layout-meta.xml`. AC7 (Feld sichtbar +
read-only) gilt in Classic über das Repo-Layout; in **Lightning** zusätzlich
über die FlexiPage (App-Builder-Step) — exakt wie bei SCRUM-403 (Spec #8).

---

## Komponenten (Konkret, exakte Pfade + Namen)

> **Namensgebung:** API-Name des PO wird übernommen →
> `Last_Real_Contact_Date__c` (Date). Label = „Letzter echter Kontakt“.

### 1. Custom Field — `Contact.Last_Real_Contact_Date__c`
Pfad: `force-app/main/default/objects/Contact/fields/Last_Real_Contact_Date__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Last_Real_Contact_Date__c</fullName>
    <description>Datum des neuesten ABGESCHLOSSENEN Calls (Task Type='Call' und Status='Completed'), gemessen an der ActivityDate (SCRUM-413). Wird ausschliesslich vom System gepflegt (LastRealContactDateTrigger/Rebuilder); von Hand nicht aenderbar. Blank = der Kontakt hat noch nie einen abgeschlossenen Call („nie erreicht“).</description>
    <label>Letzter echter Kontakt</label>
    <required>false</required>
    <trackHistory>false</trackHistory>
    <trackTrending>false</trackTrending>
    <type>Date</type>
    <unique>false</unique>
</CustomField>
```

### 2. Apex Class (Recompute-Handler) — `LastRealContactDateTrigger.cls`
Pfad: `force-app/main/default/classes/LastRealContactDateTrigger.cls`
(`<apiVersion>62.0</apiVersion>`, Pattern `LastCaseDateTrigger.cls`)

Verantwortung: `recompute(Set<Id> whoIds)` — pro übergebenem Kontakt das Datum
des neuesten **abgeschlossenen** Calls exakt neu berechnen (MAX(ActivityDate),
`Type='Call' AND Status='Completed'`), nur Contacts updaten, deren sich der
Wert geändert hat. Governor: 1 Aggregate-SOQL + 1 SOQL + 1 DML. `without
sharing`.

Referenz-Implementierung (Developer passt SOQL/Relevanz an; Struktur 1:1
SCRUM-403):

```apex
public without sharing class LastRealContactDateTrigger {

    // 1 AGGREGATE-SOQL: neueste ActivityDate pro Kontakt NUR über
    // ABGESCHLOSSENE Calls. Ein Kontakt OHNE abgeschlossenen Call liefert
    // KEINE Zeile -> Fehlen = null (= ADR-4 „nie erreicht“).
    static Map<Id, Date> latestCompletedCall(Set<Id> whoIds) {
        Map<Id, Date> latest = new Map<Id, Date>();
        for (AggregateResult r : [
            SELECT WhoId, MAX(ActivityDate) latest
            FROM Task
            WHERE Type = 'Call' AND Status = 'Completed' AND WhoId IN :whoIds
            GROUP BY WhoId
        ]) {
            Object v = r.get('latest');
            if (v != null) {
                latest.put((Id) r.get('WhoId'), ((Datetime) v).date());
            }
        }
        return latest;
    }

    // 2 SOQL: aktueller Zustand der betroffenen Kontakte (nur diese — kein Voll-Scan).
    static Map<Id, Date> currentValues(Set<Id> whoIds) {
        Map<Id, Date> cur = new Map<Id, Date>();
        for (Contact ct : [
            SELECT Id, Last_Real_Contact_Date__c
            FROM Contact
            WHERE Id IN :whoIds
        ]) {
            cur.put(ct.Id, ct.Last_Real_Contact_Date__c);
        }
        return cur;
    }

    public static Integer recompute(Set<Id> whoIds) {
        if (whoIds == null || whoIds.isEmpty()) {
            return 0;
        }
        Map<Id, Date> latest = latestCompletedCall(whoIds);
        Map<Id, Date> cur    = currentValues(whoIds);

        List<Contact> toUpdate = new List<Contact>();
        for (Id wid : whoIds) {
            Date newDate     = latest.get(wid);            // null wenn „nie erreicht“
            Date currentDate = cur.get(wid);
            Boolean mustWrite = (currentDate == null)
                ? (newDate != null)
                : (newDate != currentDate);
            if (mustWrite) {
                toUpdate.add(new Contact(Id = wid, Last_Real_Contact_Date__c = newDate));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }
}
```

### 3. Apex Trigger — `LastRealContactDateTrigger.trigger` **auf Task**
Pfad: `force-app/main/default/triggers/LastRealContactDateTrigger.trigger`
(`<apiVersion>62.0</apiVersion>`)

Events: `on Task (after insert, after update, after delete)`. Ruft
`LastRealContactDateTrigger.recompute(affected)` **exakt einmal** auf (bulkified).

**Relevanz = „die abgeschlossenen-Calls-Menge des WhoId kann sich geändert
haben.“** (recompute ist exakt → Trigger darf großzügig sammeln; Idempotenz
garantiert keine Falschschreibweise.)

```apex
trigger LastRealContactDateTrigger on Task (after insert, after update, after delete) {
    Set<Id> affected = new Set<Id>();

    if (Trigger.isInsert) {
        // nur relevante wenn sofort abgeschlossen (z. B. „Log Call“-Quick-Action
        // legt den Task direkt mit Status='Completed' an)
        for (Task t : Trigger.new) {
            if (t.Type == 'Call' && t.Status == 'Completed' && t.WhoId != null) {
                affected.add(t.WhoId);
            }
        }
    } else if (Trigger.isDelete) {
        // abgeschlossener Call gelöscht -> ggf. auf vorherigen zurückfallen
        for (Task t : Trigger.old) {
            if (t.Type == 'Call' && t.WhoId != null) {
                affected.add(t.WhoId);
            }
        }
    } else if (Trigger.isUpdate) {
        // relevant wenn: Abschluss-Status wechselt, Wer (WhoId) wechselt,
        // oder Type wechselt (z. B. Mail -> Call).
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Task n = Trigger.new[i];
            Task o = Trigger.old[i];
            Boolean nCounted = (n.Type == 'Call' && n.Status == 'Completed' && n.WhoId != null);
            Boolean oCounted = (o.Type == 'Call' && o.Status == 'Completed' && o.WhoId != null);
            if (nCounted != oCounted || n.WhoId != o.WhoId || n.Type != o.Type) {
                if (n.WhoId != null) affected.add(n.WhoId);
                if (o.WhoId != null) affected.add(o.WhoId);
            }
        }
    }

    if (!affected.isEmpty()) {
        LastRealContactDateTrigger.recompute(affected);
    }
}
```

> **Zyklen-sicher:** Trigger schreibt nur `Contact`, nie `Task`. Es existiert
> kein Contact-Trigger, der Task/Case schreibt → kein Re-Entry. Fan-out:
> **kein** anderer Task-Trigger im Repo (5 vorhan- den: AccountLockGuard,
> LeadDuplicateGuard, OpportunityOverdueReset, CaseOpenCountTrigger,
> LastCaseDateTrigger) → dieser ist der **einzige** Task-Trigger.

### 4. Apex Batch (Bestand) — `LastRealContactDateRebuilder.cls`
Pfad: `force-app/main/default/classes/LastRealContactDateRebuilder.cls`
(`<apiVersion>62.0</apiVersion>`, Pattern `LastCaseDateRebuilder.cls`)

`public without sharing class LastRealContactDateRebuilder implements
Database.Batchable<SObject>, Database.Stateful`. Start `SELECT Id FROM Contact`
(kein LastModified-Filter — AC6 „Bestand rückwirkend“). Pro Chunk (200)
`LastRealContactDateTrigger.recompute(ids)`. `finish()` = no-op.
`public static String runOnce() { return Database.executeBatch(new
LastRealContactDateRebuilder(), 200); }`
**Kein Button, keine Log-Zeile.** Auslösung First-Deploy: DevOps via
`Execute Anonymous` / `sf apex run`.

### 5. Permission Set — `SCRUM413_LastRealContactDate`
Pfad: `force-app/main/default/permissionsets/SCRUM413_LastRealContactDate.permissionset-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <fieldPermissions>
        <editable>false</editable>
        <field>Contact.Last_Real_Contact_Date__c</field>
        <readable>true</readable>
    </fieldPermissions>
    <hasActivationRequired>false</hasActivationRequired>
    <label>SCRUM413_LastRealContactDate</label>
    <description>Read-only FLS fur Contact.Last_Real_Contact_Date__c (Letzter echter Kontakt, SCRUM-413). Systemmaintained via LastRealContactDateTrigger/Rebuilder - kein Update-Right fur irgendwen. PO: Sales, nur lesen.</description>
</PermissionSet>
```

### 6. Layout-Integration — `Contact-Contact Layout.layout-meta.xml`
Pfad: `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`

Im Section **`Offene Faelle`** (customLabel=true, das Datum-Feld-Panel mit
`Last_Case_Date__c` / `Time_Since_Last_Case__c`) als **`Readonly`** einfügen —
daneben, im zweiten `<layoutColumns>` direkt nach `Time_Since_Last_Case__c`:

```xml
<layoutItems>
    <behavior>Readonly</behavior>
    <field>Last_Real_Contact_Date__c</field>
</layoutItems>
```

> **⚠️ Befund Layout (wie SCRUM-403):** Das committed Repo-Layout referenziert
> `Betreuungsstufe__c` (anderes Ticket). **Test-Org-Deploy des Layouts** ist
> erlaubt (Feld dort vorhanden). **Prod-Release-Layout**: DevOps entscheidet
> (SCRUM-403 schloss es aus, weil `Betreuungsstufe__c` in Prod fehlt und der
> Deploy Lightning `platformActionList`/`summaryLayout` entfernen würde).
> Lightning-Sichtbarkeit für AC7 = **FlexiPage-Org-Step** (@devops-agent),
> Classic = dieses Repo-Layout.

### 7. Custom ListView (AC8 Filter/Sort) — `Contact.Letzter_Real_Kontakt`
Pfad: `force-app/main/default/objects/Contact/listViews/Letzter_Real_Kontakt.listView-meta.xml`
(Pattern `Letztes_Anliegen`, `<version>62.0</version>` im Manifest)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ListView xmlns="http://soap.sforce.com/2006/04/metadata">
    <columns>Contact.Last_Real_Contact_Date__c</columns>
    <fullName>Letzter_Real_Kontakt</fullName>
    <filterScope>Everything</filterScope>
    <label>Letzter echter Kontakt</label>
</ListView>
```

> Träger für AC8: Spalte vorhanden → in Classic/Lightning filterbar &
> sortierbar, inkl. „älter als 6 Monate“ (Filter „vor X Monaten“) und
> „nie erreicht“ (Filter „leer“). Das speichert nichts extra; der Date-Wert
> selbst erlaubt beide Filter. Ein zweites „wie lange her“-Feld **nicht**
> nötig (PO fragt es nicht).

### 8. Apex Tests
- **`SCRUM413LastRealContactDateTest`** (funktional, AC1/AC2/AC4/AC5/AC6):
  - **AC1:** `insert new Task(Type='Call', Status='Completed', WhoId=who, ActivityDate=Date.yesterday())` → Feld = yesterday.
  - **AC2:** `insert` mit `Status='Not Started'` / `Status='In Progress'` → Feld bleibt null.
  - **AC2/Update:** Task anfänglich nicht abgeschlossen, dann `update Status='Completed'` → Feld springt auf (der update-Pfad der Trigger-Logik).
  - **AC2/Negative Mail:** `insert new Task(Type='Email', Status='Completed', WhoId=who, ...)` → Feld bleibt null (Type-Filter).
  - **AC4:** 2 abgeschlossene Calls mit unterschiedlichen `ActivityDate` → Feld = das neuere.
  - **AC5:** Kontakt ohne abgeschlossenen Call → Feld bleibt null.
  - **AC6 (synthetisch, wg. 0 reale Tasks):** Bestand-Kontakt mit historischem
    completed Call; `LastRealContactDateRebuilder.runOnce()` ausführen → Feld gesetzt.
  - **Rückfall (Rigidity):** neuester Call gelöscht bzw. reopened (`update Status!=
    'Completed'`) → Feld fällt auf vorherigen / null zurück.
  - Bulk: 200 Contacts × Calls in einem Batch → Governor-Check (Assertions auf
    Limits, SOQL/DML-COUNT).
- **`SCRUM413LastRealContactDateFlsTest`** (AC7, Pattern `SCRUM403LastCaseDateFlsTest`):
  temp user, PRECONDITION object-access, NEGATIV ohne PS (nicht lesbar/bar),
  PS zuweisen, POSITIV mit PS (lesbar, **nicht** updatable).

### 9. Manifests (3-Phasen-Hausmuster, exakt wie scr403)
- `manifest/scr413-phase1-fields.xml` — `CustomField: Contact.Last_Real_Contact_Date__c` — **`<version>67.0</version>`**.
- `manifest/scr413-phase2-referencing.xml` — `ApexTrigger: LastRealContactDateTrigger`; `ApexClass: LastRealContactDateRebuilder, LastRealContactDateTrigger, SCRUM413LastRealContactDateFlsTest, SCRUM413LastRealContactDateTest`; `Layout: Contact-Contact Layout`; `PermissionSet: SCRUM413_LastRealContactDate` — **`<version>67.0</version>`**.
- `manifest/scr413-phase3-listview.xml` — `ListView: Contact.Letzter_Real_Kontakt` — **`<version>62.0</version>`**.
- `manifest/scr413-prod-release.xml` — **Layout-Behandlung = DevOps-Entscheidung**
  (siehe ADR-7 / Komponente 6). Rest wie Phase2+Phase3 ohne Layout, sofern DevOps es ausschließt.

> **apiVersion-Konvention (ausdrücklich festgelegt, Pflicht):**
> - Apex `.cls-meta.xml` + `.trigger-meta.xml`: `62.0` (wie SCRUM-403).
> - Manifest Phase1/2: `67.0`; Phase3 (ListView): `62.0` — 1:1 scr403.

---

## Governor-Limit-Risiken & Mitigation
- **SOQL-in-Loop:** keine — `recompute` nutzt IN-List + GROUP-BY (max. 2 SOQL/Aggregate pro Call).
- **Bulk 200/50k:** `recompute` = 1 Agg-SOQL + 1 SOQL + 1 DML **pro** Aufruf, unabhängig von Call-Anzahl. Trigger & Batch rufen je Batch **einmal** pro affected-Satz.
- **Trigger-Volume:** Task-Trigger feuert nur bei relevanten WhoId-Änderungen (Relevanz-Klausel), nicht bei jedem irrelevanten Feld (z. B. Beschreibung-Wechsel eines offenen Calls).
- **Batch:** Chunk 200, kurze DML-Transaktionen, kein `SELECT FOR UPDATE`, idempotent.

---

## Offene Punkte (blocken die Implementierung NICHT)
- [ ] **Kontakt-Link bestättigt via `WhoId` (ADR-3).** Falls die Org Calls via `WhatId`/anderes Feld an den Kontakt bindet, ist genau die WHERE-Klausel in `latestCompletedCall` die einzige Anpasungsstelle. @developer-agent verifiziert das bei Testdaten-Erstellung; @po-agent bestätigt bei Bedarf.
- [ ] **Prod-Layout-Handling** (Komponente 6): @devops-agent entscheidet bei Release (aus SCRUM-403 bekanntes `Betreuungsstufe__c`-Problem).
- [ ] **Lightning-FlexiPage-Platzierung** für AC7-Sichtbarkeit in Lightning: @devops-agent (Org-Step).
- [ ] **AC6-Proof** = Apex-Test (synthetische Calls), kein Live-Lauf — @tester-agent trägt das in die Abnahme (0 reale Tasks in Test-Org).

---

## Für @user (Was ändert sich für dich)

- **Feld „Letzter echter Kontakt“** erscheint auf dem Kontakt und zeigt das
  Datum des **letzten Telefonats, das tatsächlich stattgefunden und abgehakt
  wurde** (abgeschlossener Call). Geplante Anrufe, Serien-Mails und automatische
  Aktivitäten zählen **nicht** — nur echte, abgeschlossene Calls.
- **Wenn wird es gepflegt:** automatisch, sobald ein Call als *abgeschlossen*
  markiert wird (z. B. über „Call protokollieren“). Bei mehreren Calls wird
  immer das **neueste** übernommen. Manuell kannst du es **nicht** bearbeiten —
  das Feld ist für Nutzer schreibgeschützt; ein Irrtum (z. B. Call wieder
  geöffnet) korrigiert sich von selbst.
- **Bestand:** Beim ersten Go-Live wird das Feld einmalig für alle bestehenden
  Kontakte aus der alten Call-Historie nachgefüllt — sonst stünde überall
  „nie erreicht“, obwohl längst Kontakt bestand.
- **Filtern:** Über eine neue Listenansicht „Letzter echter Kontakt“ kannst du
  z. B. „Kunden, die ich älter als 6 Monate nicht mehr erreicht habe“ oder
  „noch nie erreicht“ auswählen.

---

## Handoff
Story SCRUM-413 → **@developer-agent**, Spalte **Implementierung**.
Build-Spec: `docs/SCRUM-413-design.md` (dieser Commit).
**Developer: baue von diesem Doc, nicht vom Jira-Kommentar** (API-Namen in
Codeblöcken sind hier maßgeblich).
