# SCRUM-421 — Servicefälle automatischem Queue zuordnen (Servicebereich / Kundenstatus)

Build-Spec (maßgeblich, steht im Branch). Ticket: https://meerwaisosmani.atlassian.net/browse/SCRUM-421
Architect: architect-agent · Basis: `origin/master` @ **29dec0b** (verifiziert per `git fetch origin`)

---

## Ziel

Neue (und nachträglich in Servicebereich geänderte) Cases werden **automatisch** dem passenden
Bearbeitungs-Queue zugewiesen (4 neue Case-Felder + 4 in der Org aufgesetzte Queues),
**bulk- und rekurssicher** (300 Fälle, keine N+1), **nie** über manuelle Entscheidungen —
bestehende SCRUM-398-/420-Felder bleiben **unangetastet**.

---

## Plattform-Verifikation (2026-09-20, Test-Org / `origin/master`)

| Befund | Wert | Befehl |
|---|---|---|
| Case Custom Fields (live) | 13 — **keine** Kollision mit `Servicebereich__c` / `Kundenstatus__c` / `Automatische_Zuordnung__c` / `Zuordnungszeitpunkt__c` | `sf sobject describe -s Case -o Test-Org` (13 Custom Field names, s. Trail) |
| Bestehende Queues | **0** (`Group.Type='Queue'` → 0) — 4 Queues gehören **zu diesem Ticket** | `sf data query -q "SELECT Id,Name FROM Group WHERE Type='Queue'" -o Test-Org` |
| 4 Ziel-Queues | existieren noch nicht: Technischer Support / Vertragsservice / Billing / First Level Support | dieselbe Query mit `OR Name IN (…)` → 0 |
| Queue = deploybarer Source-Typ? | **Ja** — `directoryName: queues`, `suffix: queue` | CLI `metadataRegistry.json` → `/types/queue` (kein `queues/`-Verzasser im Repo heute) |
| Case Layout live/committed | `Case-Case Layout` im Repo; 420-Sektion «Eskalation (Kunde)» ab Zeile 202 | Repo-Datei (Drift-Check vor Layout-Deploy, 408-Pflicht, s. u.) |
| Haus-PS-Prädikat | 420 grantet auf seine 4 systemgepflegten Felder **nur read-FLS** (`editable=false/readable=true`) — d. h. **eigener Trigger schreibt sie ohne Write-FLS** | `permissionsets/SCRUM420_EskalationKunde.permissionset-meta.xml` |
| Haus-Trigger-Prädikat | after insert/update, `without sharing`, `isRunning`-Reentrancy-Guard, 1 Handler-Call/Batch, `AggregateResult`-Typ | `triggers/CaseEscalationKundeTrigger.trigger` + `classes/CaseEscalationKundeTrigger.cls` |
| apiVersion (Haus) | Apex-Trigger/Klasse = **62.0**; Feld-/PS-/Layout-Meta tragen **kein** `apiVersion`-Element | Meta-Dateien von 420 |

**Konsequenz:** `Technik`, `Vertrag`, `Rechnung`, `Allgemein`, `Standard`, `Premium` und die 4
Queue-Names sind **literale Strings** im Apex-Code (Picklist-Label-Annahmen nicht).
Kein `__c`-Suffix für die Picklist-Values. Queues werden **als Source** mitgeliefert (nicht nur
in der Org angelegt), damit die 4 in Test **und** Prod identisch existieren (AK11).

---

## ADR 1 — Apex-Trigger statt Flow

**Entscheidung: Apex (Trigger + Handler), kein Flow.**
- 300 Fälle parallel, **keine DB-Query je Case** (AK9) — in Flow ein Record-Trigger-Flow pro
  Case mit DML → genau der N+1 und das Loop-Limit (max. 200 Iterationen), das AK9 verletzt.
- Queue-Auflösung per **einer** SOQL + statischer Cache-Map ist in Apex trivial, in Flow nicht.
- Rekursions-Schutz (Trigger feuert durch eigene Owner-DML) + no-op-Diff ist in Apex das
  etablierte House-Pattern (SCRUM-365 / SCRUM-420), identische Logikshape (per-Case Berechnung,
  1 Handler-Call, Reentrancy-Guard). **Wiederverwendung statt Neuentwurf.**

---

## ADR 2 — Zuordnungs-Matrix + leeres-Servicebereich-Prädikat (AK7-Reconciliation)

Die PO-Matrix (PO-final, Entscheidung B) hat zwischen sich und AK7 eine **Wort-Kollision**:

| Kundenstatus | Servicebereich | Ziel-Queue |
|---|---|---|
| Standard | beliebig | First Level Support |
| Premium | Technik | Technischer Support |
| Premium | Vertrag | Vertragsservice |
| Premium | Rechnung | Billing |
| Premium | Allgemein / sonstiges | First Level Support |
| Premium | Ziel-Queue existiert nicht | First Level Support (Fallback) |

- AK7 (explizit, testbar): **«Servicebereich leer → Owner bleibt, Checkbox = Nein, kein Zeitstempel»**
  — das ist eine **harte Bedingung unabhängig vom Kundenstatus**.
- Die Matrix-Zeile „Standard | beliebig | First Level Support“ kann „beliebig“ **nicht** auf
  „leer“ ausdehnen, sonst würde AK7 verletzt.

**Entscheidung (Architect, Default):** **Servicebereich leer ⇒ Nie zuordnen** (Owner bleibt,
`Automatische_Zuordnung__c=false`, kein Zeitstempel) — für **beide** Kundenstatus.
„beliebig“ in der Standard-Zeile heißt „jeder **nicht-leere** Servicebereich-Wert“.
AK7 ist das testbare Kriterium und gewinnt im Konflikt mit der Matrix-Zeile.
→ Geht als Non-blocking-Offenpunkt an @PO-Agent (Bestätigung, Default gilt sonst).

**Endgültige Routing-Regel (Handler):**
```pre
if (Servicebereich__c == null)                    → NICHT zuweisen, Checkbox=false, kein Ts (AK7)
else if (Kundenstatus__c == 'Standard')            → 'First Level Support'                (AK2)
else (Kundenstatus == 'Premium'):
    'Technik'   → 'Technischer Support'            (AK1)
    'Vertrag'   → 'Vertragsservice'                (AK1)
    'Rechnung'  → 'Billing'                        (AK1)
    'Allgemein' → 'First Level Support'            (AK1)  // + jeder andere/unerwartete Value = „sonstiges“
// Fallback (AK3): aufgelöster Ziel-Queue-Name existiert in der Org NICHT
//   → 'First Level Support' (sofern vorhanden); auch FLS nicht vorhanden → NICHT zuweisen
```

---

## ADR 3 — Queue-Auflösung: eine SOQL, statischer Cache, kein Query je Case

Die 4 Queue-Ids werden **einmal pro Trigger-Fire** aufgelöst und in einer
`static Map<String, Id>` (Name → Id) gepuffert — **nicht** statisch hartgecodet
(Queue-Ids sind org-spezifisch, nicht portierbar), **nicht** pro Case:

```apex
// 1× SOQL (nur wenn Cache leer), IN-Liste auf die 4 Ziel-Names:
SELECT Id, DeveloperName, Name
FROM Group
WHERE Type = 'Queue' AND Name IN
      ('Technischer Support','Vertragsservice','Billing','First Level Support')
```
→ `Map<String, Id> queueByName` (Name → Id). **Kein Query je Case** (AK9 erfüllt).
In einem Transaction-Lauf wiederholt das Trigger-Fire den Cache (static überlebt den Lauf),
d. h. auch bei 300 Fällen in einer Batch: **exakt 1 Queue-Query** total.

> **Recovery bei AK3:** Der Fallback prüft `queueByName.containsKey(targetName)`.
> Fehlt der Ziel-Queue → Ziel = `'First Level Support'`. Fehlt **auch** FLS in der Map →
> keine Zuweisung (wie AK7: Owner bleibt, Checkbox=false, kein Ts).

---

## ADR 4 — „Manuell“-Diskriminator + Rekursions-Schutz

**Wann greift die Logik?** (PO-Definition „manuell“ = ein Mensch hat entschieden.)
Salesforce-State für „uns (Queue) hat es“ vs. „ein Mensch hat es“:

```pre
eligibel (c)  :=  (c.OwnerId == c.CreatedById)            // neu, nicht weitergeleitet
              ||  (queueByName.values().contains(c.OwnerId))  // aktuell in einem unserer 4 Queues
```

| Event | Bedingung | Ergebnis |
|---|---|---|
| **Insert**, `OwnerId == CreatedById` | neu, standard | **zuordnen** (AK1–3); leer → AK7 |
| **Insert**, `OwnerId != CreatedById` | manuell vorzuweisen | **nicht** greifen, `Automatische_Zuordnung__c=false`, Owner bleibt (AK4) |
| **Update**, Servicebereich/Kundenstatus geändert, `eligibel` | nicht manuell weitergegeben | **neu zuordnen** (AK5) |
| **Update**, …, `OwnerId` = **User** (Mensch hat übernommen) | nicht eligibel | **nicht** greifen (AK6) |

Ein Mensch nimmt einen Case praktisch immer an sich **oder einem anderen Queue → User**:
Sobald `OwnerId` ein **User** ist (kein Creator, keiner unserer Queues), scheidet der Case aus
der Auto-Logik aus — das ist der AK6-Hebel. (Edge „manuell auf *anderen der 4 Queues* legen“:
wir würden bei nächster Servicebereich-Änderung neu zuordnen — akzeptiert, da in dieser Org
Übernahme = User; s. Offenpunkte.)

**Rekursions-Schutz (zwei Ebenen, House 365/420):**
1. **Filter im Trigger:** after-update feuert die Logik **nur** wenn sich
   `Servicebereich__c` oder `Kundenstatus__c` geändert hat. Der Handler schreibt
   `OwnerId` / `Automatische_Zuordnung__c` / `Zuordnungszeitpunkt__c` — **keins** davon
   liegt im Filter → zweiter Durchgang wäre no-op.
2. **`isRunning`-Static-Guard** (wie 420): `isRunning=true; try{…}finally{isRunning=false}` —
   das Handler-eigene Owner-`update` feuert denselben Trigger, der Guard bricht ihn sofort ab.

**Governor-Budget pro Batch (300 Cases, Case-zahl-unabhängig):** 1 Queue-SOQL (nur Cache-miss)
+ 0 weitere SOQL (der Handler liest ausschließlich `Trigger.new` / `Trigger.old`-Felder) +
1 DML (`update toUpdate`). **Keine SOQL im Loop.** AK9 bestanden mit großem Rest; Query-Zählung
per `Limit.getNumQueries()`-Assert im Test (s. T-AK9).

> `update only if !toUpdate.isEmpty()` (418-Lektion: leerer DML-Call = Fehler, keine No-Op).

---

## API-Namen (final, Kollisionsprüfung 2026-09-20 bestanden — 0 Treffer live + auf origin/master)

| API-Name | Type | Label | Detail |
|---|---|---|---|
| `Servicebereich__c` | Picklist | Servicebereich | `Technik`, `Vertrag`, `Rechnung`, `Allgemein` — **nullable**, kein Default |
| `Kundenstatus__c` | Picklist | Kundenstatus | `Standard` (Default), `Premium` |
| `Automatische_Zuordnung__c` | Checkbox | Automatische Zuordnung | systemgepflegt, **read-only** (kein Write-FLS; Trigger/Tx schreibt) |
| `Zuordnungszeitpunkt__c` | DateTime | Zuordnungszeitpunkt | systemgepflegt, **null-Default** (AK7: leer = nicht zugeordnet), read-only |

**Kein** Verwechslungspotenzial mit 398/420-Feldern (`Eskalationsstufe__c`,
`Eskalation_Kunde__c`, …) — alle 13 Live-Custom-Fields abgeglichen.

---

## ADR 5 — Defaults & Picklist-Default-Werte

- `Servicebereich__c`: **null** (nullable, kein Default) — PO: vom Ersteller wahlweise angeben;
  leer = Auslöser für AK7.
- `Kundenstatus__c`: **default `Standard`** (PO-empfohlen).
- `Automatische_Zuordnung__c`: Checkbox, **default `false`** (Salesforce-Checkbox-Default).
- `Zuordnungszeitpunkt__c`: **kein** Default (null = „noch nie automatisch zugeordnet“).
- FLS-Split: `Servicebereich__c`/`Kundenstatus__c` = read+edit; `Automatische_Zuordnung__c`/
  `Zuordnungszeitpunkt__c` = **read-only** (kein Write-FLS — wie 420; Trigger schreibt trotzdem,
  s. ADR-Prädikat im Plattform-Verifikation-Trail).

---

## Queue-Provisioning (Zusatzumfang dieses Tickets, AK11)

4 Queues **als Source-Metadaten** (registry-verifiziert: `queues/`-Verzeichnis, `.queue`-Suffix):

| Datei | Queue-Name |
|---|---|
| `force-app/main/default/queues/Technischer_Support.queue-meta.xml` | Technischer Support |
| `force-app/main/default/queues/Vertragsservice.queue-meta.xml` | Vertragsservice |
| `force-app/main/default/queues/Billing.queue-meta.xml` | Billing |
| `force-app/main/default/queues/First_Level_Support.queue-meta.xml` | First Level Support |

Shape (pro Queue, `masterLabel`/`description`/`queueType`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Queue xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>SCRUM-421: auto-Zuordnungs-Ziel (Servicebereich …).</description>
    <name>Technischer Support</name>
    <queueType>Case</queueType>
</Queue>
```

> **Queue-Membership (Wer arbeitet im Queue?):** In der Org existieren **0 Support-Users**
> (PO-Befund) — d. h. die 4 Queues werden **mit leerer Membership** aufgesetzt. Wer die
> Mitglieder sind, ist ein **operativer Folgepunkt** (Org-Setup › Queues › Members), **nicht**
> via Permission Set grantbar und **nicht** Teil von AK1–11 (AK10 = reine FLS, AK11 = Existenz).
> → Geht als Non-blocking-Offenpunkt an @PO-Agent (Team-Mitglieder bestimmen).
> `sf` kann Queues via Source deployen; Membership bleibt Org-Schritt.

---

## Permission Set

**`permissionsets/SCRUM421_Zuordnung.permissionset-meta.xml`** — Haus-Shape 420,
**nur die 4 fieldPermissions**, kein Objekt-CRUD, kein Apex, kein Write-FLS auf Systemfelder:

```xml
<fieldPermissions><editable>true</editable>    <field>Case.Servicebereich__c</field>        <readable>true</readable></fieldPermissions>
<fieldPermissions><editable>true</editable>    <field>Case.Kundenstatus__c</field>         <readable>true</readable></fieldPermissions>
<fieldPermissions><editable>false</editable>   <field>Case.Automatische_Zuordnung__c</field><readable>true</readable></fieldPermissions>
<fieldPermissions><editable>false</editable>   <field>Case.Zuordnungszeitpunkt__c</field>  <readable>true</readable></fieldPermissions>
<hasActivationRequired>false</hasActivationRequired>
<label>SCRUM421_Zuordnung</label>
```

- Objekt-CRUD (Create/Read/Edit auf Case) kommt aus dem **vorhandenen** Service-Profil des
  Users (TK: „Profile mit Case-Zugriff“) — das PS grantet **nur die Felder**.
- „Queue-Zugriff/Membership“ aus der TK-Beschreibung: Membership ist **PS-ungegrantbar**
  (Salesforce: Membership = Org-Setup je User); „Queue-Zugriff“ im Sinne „Cases der Queue
  sehen“ ergibt sich aus Case-OWD + Queue-Membership + Profil, **nicht** aus FLS. Kein
  PS-Element dafür erfunden (s. Queue-Provisioning).
- **Deployment ≠ Assignment** (PO-Regel): Developer **muss** nach Deploy das PS der
  **Test-Org-CLI-User** UND dem **menschlichen Test-Account** zuweisen
  (`sf org assign permset -n SCRUM421_Zuordnung -o Test-Org`), Read-Back eines Feldes in
  echter Session **vor** Handoff. (SCRUM-382/386/388/390/394/398 alle schon an dieser Stelle
  gescheitert.)

## Profil-FLS-Lock (Standard User) — manuell, keine Metadaten-Syntax

> **Befund (2026-09-20, Review-Zyklus 2):** Ein per `sf project deploy` ausgeliefertes
> Custom Field startet im Profil **«Standard User»** (DeveloperName `Standard`) **unrestricted**
> — das Profil gewährt **Read UND Write** auf die 4 421-Felder. Die Field-Grants des PS
> (`SCRUM421_Zuordnung`) **erteilen nur** und können Profil-FLS **nicht widerrufen**
> (`editierbare Effektive-FLS = Profil OR PS`). Dadurch schlagen die AK10-Negativtests
> (ohne-PS-SELECT + read-only-Write-Split auf Checkbox/Zeitstempel) rot.
>
> **Warum nicht via Metadaten/CLI (bewusst):** (a) Die Data-API speichert FLS auf **standard**
> Profilen nicht als adressierbare `FieldPermissions`-Zeilen (`sf data create record -s
> FieldPermissions` → „Parent ID: id value of incorrect type"); (b) der `Profile:Standard`-
> **Retrieve** in dieser Org liefert ein **teilweises** Profil (nur `userLicense`+
> `userPermissions`, **0** `objectPermissions`/`fieldPermissions`) — ein Source-Deploy würde
> sämtliche übrigen Profile-Rechte löschen (destruktiv). → **Kein** Profile-File gehört in den
> Repo; der Lock ist ein **manuelles Setup-Schritt**. Präzedenz **SCRUM-420** (dort org-seitig
> verriegelt, 420-FLS-Test grün im selben Profil).

**Schritt (manuell, Setup › Profiles):**
1. Setup → **Profiles** → Profil **«Standard User»** (DeveloperName `Standard`) öffnen.
2. Reitschen **Object Settings** → Objekt **Case** → **Field Permissions**.
3. Für **alle vier** Felder **Read und Edit entziehen** (beide Haken entfernen):
   - `Servicebereich__c`
   - `Kundenstatus__c`
   - `Automatische_Zuordnung__c`
   - `Zuordnungszeitpunkt__c`
4. Speichern. Sichtbarkeit/Write-Split bleibt danach **ausschließlich** über das PS
   `SCRUM421_Zuordnung` steuern (read/edit- bzw. read-only-Grants oben).
5. Bestätigen: `sf apex run test -o <Org> -n SCRUM421QueueAssignmentFlsTest` → **grün**
   (negat. SELECT-Exception + posit. Control + read-only-Write-Split).

> ⚠️ **Release-Hinweis für die PROD-ORG (@devops-agent / @po-agent):** Der Lock ist **nicht**
> source-deployt und damit **keine** Teil der 3-Phasen-Deploy. Nach dem Prod-Deploy gelten
> dieselben Felder im Prod-«Standard User»-Profil **ebenfalls unrestricted** → **gleicher
> manueller Setup-Schritt obengenannt muss in der PROD-ORG wiederholt werden, bevor AK10
> (negat. FLS) dort validiert/abgenommen wird**. AK10 schlägt in Prod sonst ebenso fehl, wie er
> ungelocked in Test-Org fehlte. Bei Release/Deployment-Handoff als expliziter Org-Schritt
> mitführen (analog Queue-Membership oben, das ebenfalls Org-seitig bleibt).

---

## Page Layout (Case)

- Neue `layoutSection` **«Zuordnung»** — **nach** der 420-Sektion «Eskalation (Kunde)»
  (Zeile 226 in `layouts/Case-Case Layout.layout-meta.xml`), **vor** «System Information».
  Style `OneColumn`, `detailHeading=true`, `customLabel=true` (exakt wie die 420-Sektion).
- 4 `layoutItem`s, Reihenfolge:
  `Servicebereich__c` (Edit), `Kundenstatus__c` (Edit),
  `Automatische_Zuordnung__c` (Readonly), `Zuordnungszeitpunkt__c` (Readonly).
- **408-Drift-Pflicht (auch wenn 420 live==committed war):** Vor Layout-Deploy
  `sf project retrieve start -m "Layout:Case-Case Layout" -o Test-Org` + Byte-Vergleich mit
  der committeten Datei — Live-Änderung in der Zwischenzeit? → neue Sektion manuell ins
  Live-Artefakt einfügen, nie die committete Datei blind deployen.

---

## Komponenten-Übersicht

| Datei | Typ | Zweck |
|---|---|---|
| `objects/Case/fields/Servicebereich__c.field-meta.xml` | CustomField | Picklist, nullable |
| `objects/Case/fields/Kundenstatus__c.field-meta.xml` | CustomField | Picklist, default Standard |
| `objects/Case/fields/Automatische_Zuordnung__c.field-meta.xml` | CustomField | Checkbox, default false |
| `objects/Case/fields/Zuordnungszeitpunkt__c.field-meta.xml` | CustomField | DateTime, null-default |
| `queues/*.queue-meta.xml` (×4) | Queue | 4 Ziel-Queues (AK11) |
| `triggers/CaseQueueAssignment.trigger` + `.trigger-meta.xml` | ApexTrigger | after insert/update, nur bei SB/KS-Wechsel |
| `classes/CaseQueueAssignmentTrigger.cls` | ApexClass | Trigger-Wrapper, Reentrancy-Guard |
| `classes/CaseQueueAssignment.cls` | ApexClass | statisch `route()`, 1 Queue-SOQL + 1 DML |
| `permissionsets/SCRUM421_Zuordnung.permissionset-meta.xml` | PermissionSet | 4 FLS-Grants (2 rw, 2 ro) |
| `layouts/Case-Case Layout.layout-meta.xml` | Layout | neue Sektion «Zuordnung» |
| `classes/SCRUM421QueueAssignmentTest.cls` | TestClass | AK1–9 (funktional + Bulk-Query-Assert) |
| `classes/SCRUM421QueueAssignmentFlsTest.cls` | TestClass | AK10 (negativ + positiv) + AK11 |

> Klassennamen final: `CaseQueueAssignment`, `CaseQueueAssignmentTrigger`,
> `SCRUM421QueueAssignmentTest`, `SCRUM421QueueAssignmentFlsTest` (PascalCase = API-Name).
> Der Trigger-Dateiname ist case-insensitiv; die Datei heißt `CaseQueueAssignment.trigger`.

---

## Deploy-Strategie (Manifeste, Haus-Phasen-Muster 420)

| Manifest | Inhalt | Reihenfolge |
|---|---|---|
| `manifest/scr421-phase1.xml` | 4 CustomFields + 1 PermissionSet | **1. Zuerst** (Felder/PS live) |
| `manifest/scr421-phase2.xml` | 4 Queues + Apex (2 Klassen) + Trigger + 2 Testklassen | **2.** (referenzieren Felder) |
| `manifest/scr421-phase3.xml` | Layout `Case-Case Layout` | **3.** (nach Feldern live) |

- Phase 2 deploy mit `--test-level RunSpecifiedTests --tests SCRUM421QueueAssignmentTest,SCRUM421QueueAssignmentFlsTest`
  (keine volle Org-Testlauf — Core-Prinzip; 1 RunSpecifiedTests je Ticket).
- **Rebuilder / Backfill: keiner** — TK-Scope ist „neue Servicefälle“; Bestands-Cases bleiben
  beim Owner. (Falls PO später Bestands-Cases neu zuordnen will → eigener Punkt, hier nicht.)

---

## Test-Vorgaben (Developer — exakt, nicht umformulieren)

**Setup (je Test-Methode):** 1 Test-User mit Profil „Standard User“ + die 4 Queues als
`Group`-Inserts anlegen (Name exakt, `Type='Queue'`), `queueType` Case. Kein Produktiv-Profil
angetasten (House-FLS-Test-Pattern 353/359/398/420).

### Funktionstest `SCRUM421QueueAssignmentTest`

| TC | Setup | Erwartung | AK |
|---|---|---|---|
| TC1 | 4 Cases (1 je Technik/Vertrag/Rechnung/Allgemein), **Premium**, `Owner=Creator` | Owner = je Technischer Support / Vertragsservice / Billing / First Level Support; Checkbox=true; Ts≠null | AK1 |
| TC2 | 1 Case, **Standard**, Servicebereich=Technik | Owner = First Level Support (nicht Technischer Support!); Checkbox=true | AK2 |
| TC3 | Premium, Technik, aber Queue „Technischer Support“ **nicht** angelegt (nur FLS + 3 andere) | Fallback → Owner = First Level Support | AK3 |
| TC4 | insert mit `OwnerId` = User ≠ Creator (manuell vorzuweisen) | Owner unverändert (User), Checkbox=**false**, kein Ts | AK4 |
| TC5 | Case mit Premium/Technik → zuordnung zu Technischer Support; dann `Servicebereich__c='Rechnung'` (nicht manuell weitergegeben, Owner=Queue) | neu zugeordnet → Owner = Billing; Checkbox=true; Ts=neu | AK5 |
| TC6 | wie TC5, dann Owner manuell auf **User** umstellen; danach `Servicebereich__c` ändern | Owner bleibt User, Logik greift **NICHT** (kein Ts-Update, Checkbox unverändert) | AK6 |
| TC7 | 1 Case insert, **Servicebereich leer** (null), Premium | Owner=Creator, Checkbox=**false**, kein Ts | AK7 |
| TC8 | TC1-Fall (Zuordnung erfolgreich) | Checkbox=**true** **und** `Zuordnungszeitpunkt__c != null` (beides im selben Assert) | AK8 |
| TC9 | **Bulk:** 300 Cases in 1 `insert`-Batch, gemischt (Premium/Standard × 4 Bereiche, einige mit `OwnerId`≠Creator) | alle korrekt (AK1–4-Logik in bulk); `Integer qBefore=Limit.getNumQueries();` vor `Test.startTest()`, `qAfter` nach `stopTest()`; **`assertTrue(qAfter-qBefore < 20)`** — erwartet: 1 Queue-Query + 0 Case-Queries + Setup (Pauschal-Assert, kein bloßes `System.debug`) | AK9 |

**Bulk-Prüfung (AK9, PO: „Governor/Query-Zählung, nicht nur grüner Lauf“):** `Test.startTest()`
/`stopTest()`-Markierung um die 300er-`insert`; `Limit.getNumQueries()`-Delta-Assert **< 20**
(ein `System.debug` ohne Assert = Scheitern beim Review).

### FLS-Test `SCRUM421QueueAssignmentFlsTest` (House-Pattern 420/398)

- 1 Test-User (minimales Profil, **ohne** PS-Assignment).
- `testWithoutPermset`: `System.runAs(user)`: `SELECT Servicebereich__c FROM Case LIMIT 1` →
  **Exception** (`No such column` / `SecurityException`) — beide Typen; `try/catch` + `fail()`
  wenn **kein** Fehler. **Kein** exacter Message-Abgleich (flaky).
- `testWithPermset_readable`: **derselbe** User **mit** `SCRUM421_Zuordnung` → `SELECT` liefert
  den Wert (positiv-Kontrolle). **Ohne diese zweite Methode ist der negative Test wertlos**
  (bricht auch bei fehlendem Case-CRUD und beweist dann nur das Objekt-CRUD-Fehlen).
- `testWithPermset_writeSplit`: mit PS → `Servicebereich__c`/`Kundenstatus__c` **editierbar**
  (DML ok), `Automatische_Zuordnung__c`/`Zuordnungszeitpunkt__c` **read-only** (DML → Exception).
  (AK10 „inkl. positiver Kontrolle + Read-only auf Systemfeldern“.)
- **AK11 (Existenz):** gleiche Klasse, `testQueuesExist`:
  `SELECT COUNT(Id) FROM Group WHERE Type='Queue' AND Name IN (4)` → `== 4` (Read-Back nach
  Deploy; `Group WHERE Type='Queue'` war vor dem Deploy 0).

### Regression (Developer-Kommentar am Ticket, vor Handoff)
`sf apex run test -o Test-Org -n SCRUM420EscalationKundeTest -n SCRUM365OpenCasesCountTest
-n SCRUM418CaseReactionTest` — alle grün, sonst Stop (Case-Trigger-Regressionsfläche prüfen:
meine Trigger-Felder dürfen 365/420/418 nicht stören — sie schreiben nur `OwnerId`+meine
2 Systemfelder, liegen nicht in deren Filtern).

---

## Technische Abnahmekriterien (Review-Kriterien für mich, abgesehen von PO-AK)

- [ ] Trigger: after insert/update; **Update-Filter enthält NUR** `Servicebereich__c`/`Kundenstatus__c` (keine OwnerId/Checkbox/Ts) → Rekursions-Filter
- [ ] `isRunning`-Reentrancy-Guard im Wrapper (try/finally)
- [ ] Handler: **1× Queue-SOQL** (nur Cache-miss) + **1× DML**, **keine SOQL im Loop**; `Trigger.new/old`-Feld-Lesung, sonst kein Query
- [ ] Fallback-Kette: Ziel-Name fehlt → `First Level Support` → auch FLS fehlt → nicht zuweisen
- [ ] Eligibility: `OwnerId==CreatedById || queueByName.values().contains(OwnerId)` (AK4/5/6-Hebel)
- [ ] `update toUpdate` nur bei `!toUpdate.isEmpty()`
- [ ] Defaults: SB null, KS `Standard`, Checkbox `false`, Ts null
- [ ] 4 Queues als Source (`.queue-meta.xml`), `queueType=Case`, `name`=Exact-Label
- [ ] PS: exakt 4 `fieldPermissions` (SB rw, KS rw, Checkbox ro, Ts ro), **kein** Objekt-CRUD, **kein** Apex, `hasActivationRequired=false`
- [ ] PS **zugewiesen + per Read-Back verifiziert** (Developer-Handoff)
- [ ] Layout: Sektion «Zuordnung» mit 4 Items, **nach** 420-Sektion, bestehende Sektionen unangetastet
- [ ] Manifest 3 Phasen, Reihenfolge korrekt; Phase-2 mit `RunSpecifiedTests`
- [ ] **Keine** 398/420-Feld- oder -Trigger-Änderung (Abgrenzung)

---

## Offene Punkte (Non-blocking, Default gilt sonst)

1. **Queue-Membership** (wer arbeitet in den 4 Queues?): Org hat **0 Support-Users** → Queues
   werden mit leerer Membership mitgeliefert; Team-Mitglieder = operativer Folgepunkt (Org-Setup).
   → @PO-Agent bestimmt die Mitglieder (Default: leer, nichts blockiert).
2. **AK7-Reconciliation** (ADR 2): „Standard + leerer Servicebereich → FLS“ (Matrix) vs.
   „leer → nicht zuordnen“ (AK7). **Default: AK7 gewinnt** (leer ⇒ nie zuordnen). → @PO-Agent
   bestätigt; bis dahin Default gilt.

---

## Für @devops-agent (Deploy/Merge, nicht Test)

- PR braucht **Architect-APPROVE** + **3/3 grüne CI** vor Merge.
- **3-Phasen-Deploy** (Test-Org beim Developer, Prod-Org beim DevOps auf Release):
  Phase 1 (Felder+PS) → Phase 2 (Queues+Apex+Trigger+Tests, `RunSpecifiedTests`) → Phase 3 (Layout).
- **4 Queues werden via Source in Prod mitgedeployt** (Phase 2) — d. h. in Prod existieren
  nach dem Release automatisch die 4 Queues (AK11 gilt auch für Prod).
- **Queue-Membership bleibt Org-Schritt** (leer, bis PO die Support-User bestimmt).
- **Kein** 398/420-Feld- oder -Trigger-Deploy.

---

## Verifikation-Trail (alle per CLI, 2026-09-20, Test-Org / origin/master @ 29dec0b)

- 13 Custom Case Fields, **0** Kollision mit 4 Kandidaten: `sf sobject describe -s Case -o Test-Org`
- 0 Queues, 0 Ziel-Queues: `sf data query -q "SELECT Id,Name FROM Group WHERE Type='Queue' OR Name IN (…)" -o Test-Org`
- Queue-Source-Typ: CLI `metadataRegistry.json` → `/types/queue {directoryName:"queues",suffix:"queue"}`
- 420 PS = read-FLS-nur (Trigger schreibt trotzdem): `permissionsets/SCRUM420_EskalationKunde.*`
- 420 Trigger-Guard + apiVersion 62.0 + Feld-/PS-/Layout-Meta ohne apiVersion: 420-Dateien
- Layout-Sektion „Eskalation (Kunde)“ Zeile 202, Insertion vor „System Information“:
  `layouts/Case-Case Layout.layout-meta.xml`
