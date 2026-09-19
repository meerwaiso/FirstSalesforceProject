# SCRUM-420 — Servicefälle nach Kundendringlichkeit priorisieren

Build-Spec (maßgeblich, steht im Branch). Ticket: https://meerwaisosmani.atlassian.net/browse/SCRUM-420
Architect: architect-agent · Basis: `origin/master` @ **baf5c30** (verifiziert per `git fetch origin`)

---

## Ziel

Case erhält automatisch, pro Kunde (Account), die Eskalationsstufe (Keine / Beobachten / Kritisch)
aus der Zahl offener High-Priority-Cases desselben Kunden — bulk- und rekurssicher, read-only für
Anwender, bestehendes SCRUM-398-Feld `Eskalationsstufe__c` bleibt **unangetastet**.

---

## Plattform-Verifikation (2026-09-19, Test-Org, 612 Cases — `sf sobject describe` / `sf data query`)

| Befund | Wert | Befehl |
|---|---|---|
| Case.Priority (Picklist) | `Low` / `Medium` / `High` | `sf data query -q "SELECT Priority, COUNT(Id) p FROM Case GROUP BY Priority" -o Test-Org` → 12/594/6 |
| Case.Status (Picklist) | `New` / `Working` / `Escalated` / `Closed` | dito mit `Status` → 570/4/0/38 |
| `offen`-Definition | `Status != 'Closed'` (literal) | PO + Picklist-Verify |
| `High`-Token | `Priority = 'High'` (literal) | dito |
| Name-Kollision | 0 Treffer für die 4 PO-Vorschläge + 4 Alternativnamen auf `origin/master` | `git ls-tree -r --name-only origin/master \| grep` |
| 398-Feld | `Eskalationsstufe__c` = string, formula, updateable=False — **nicht anfassen** | `sf sobject describe -s Case -o Test-Org` |
| Case-Layout | **live == committed master** (identical, 12 summaryLayout / 32 layoutItems) → 408-Drift-Risiko **nicht** vorhanden | `sf project retrieve start -m "Layout:Case-Case Layout"` + Byte-Vergleich |

**Konsequenz:** Im Apex-Code und in der Spec sind `'High'` und `'Closed'` **literale Strings** (nicht Picklist-Label-Annahmen). Kein `__c`-Suffix für Priority/Status/AccountId.

---

## ADR 1 — Apex-Trigger statt Flow

**Entscheidung: Apex (Trigger + Handler), kein Flow.**
Begründung (House-Default, ADR-Pflicht):
- Aggregation mit `GROUP BY` über bis zu 200+ Cases pro Batch ist in Flow nur über
  Record-Trigger-Flow + Aggregate-Element mit geteiltem Feld möglich → Schema-Drift-Gefahr,
  und Flow-Ausführungslimit (max. 200 Iterationen im Loop-Element) ist genau der Fall.
- Rekursionskontrolle + no-op-Write (diff-Prüfung) ist in Apex trivial, in Flow umständlich.
- Bestehendes House-Pattern **SCRUM-365** (`CaseOpenCountTrigger` + `recompute()` + Rebuilder)
  ist für **identische Logikshape** gebaut (Zähler pro Bezugsperson aus offenen Cases) —
  hier nur der Bezug von Contact → Account und die Abfrage-Dimension gewechselt.
  **Wiederverwendung statt Neuentwurf** (House-Rule).

---

## ADR 2 — Bestandsdaten: Rebuilder vs. kein Backfill

**PO-Originalwunsch: "Bestandsdaten: kein Backfill, Werte ab Deploy"** — aber die Matrix gilt
*pro Kunde über seine offenen Cases*: Nach dem Deploy ist `Eskalation_Kunde__c` für alte Cases
`null`, während neue Cases desselben Kunden berechnete Werte tragen. Bei jedem der vier Trigger-Events
(inkl. Schließen eines High-Cases!) wird `recompute()` über **alle offenen Cases des betroffenen
Accounts** aufgerufen → **alle offenen Cases desselben Kunden bekommen sofort denselben Wert**
(inkl. der Bestands-Cases). Bestandsdaten sind also nach dem ersten Case-Event des Kunden konsistent;
komplett konsistent sind sie mit einem einmaligen **Rebuilder-Lauf** (ADR 3).

**Entscheidung (Architect, klargestellt gegenüber PO-Formulierung):** Rebuilder (Bulk-Batch, ohne
Log-Objekt — `CaseRebuildRun__c` ist Contact-basiert mit `ContactsProcessed__c` und **wiederverwendbar**,
deshalb eigenes minimales Vorgehen ohne 2. Objekt, s. ADR 3) **im selben Deploy** mitgeliefert und
**vor Test-Start einmalig** per `sf apex run` ausgeführt (kein Custom Button nötig, da kein
wiederholbarer UI-Lauf für Endnutzer gefordert ist — PO-AK verlangen keinen Button).
Bestehende Felder sind danach sofort korrekt; AK-Tests laufen auf einem sauberen Zustand.

> **Offen (PO-Entscheidung, vor Implementierung):** Rebuilder-Lauf einmalig (Architect-Default,
> s. o.) oder strikt "erst ab Deploy, Bestandsdaten bleiben leer bis zum nächsten Event"?
> Default = Rebuilder **ja** (sonst sind alte offene Cases eines Kunden, der nie wieder angefasst
> wird, dauerhaft `null` — widerspricht "alle offenen Cases desselben Kunden zeigen dieselbe Stufe").

---

## ADR 3 — Rekursions- & Trigger-Architektur

**Ein** Trigger auf Case, der **alle vier Fälle** sammelt und exakt einmal `recompute()` ruft
(365-Pattern). Der Handler ist **statisch, without sharing, idempotent:**

```
CaseEscalationKunde.trigger   (after insert, after update, after delete)
    → Set<Id> affectedAccountIds
        insert:  AccountId aus Trigger.new
        delete:  AccountId aus Trigger.old
        update:  nur wenn sich Priority, Status (↔Closed) oder AccountId geändert hat
                 → alter AND neuer AccountId (Kundenwechsel = beide, AK6)
    → CaseEscalationKunde.recompute(affectedAccountIds)
```

`recompute(Set<Id> accountIds)` (statisch, `CaseEscalationKunde.cls`):

1. **1× SOQL (Aggregation, GROUP BY):**
   ```apex
   SELECT AccountId,
          COUNT(Id)  openTotal,
          SUM(CASE WHEN Priority = 'High' THEN 1 ELSE 0 END) openHigh
   FROM Case
   WHERE AccountId IN :accountIds AND Status != 'Closed'
   GROUP BY AccountId
   ```
   → `Map<Id, AggregateResult>` (openTotal, openHigh). **Achtung: `AggregateResult`,
   nicht `Aggregate`** (House-Lektion, 2026-09-15) — Typ ist `Map<Id, AggregateResult>`,
   Werte lesen über `.get('openTotal')` / `.get('openHigh')` (Object → Integer cast).

2. **1× SOQL (Zielzustand, für diff + Zeitstempel):**
   ```apex
   SELECT Id, AccountId, Priority, Status,
          Offene_Cases_Kunde__c, Offene_High_Cases_Kunde__c,
          Eskalation_Kunde__c, Eskalationszeitpunkt__c
   FROM Case
   WHERE AccountId IN :accountIds AND Status != 'Closed'
   ```
   (Nur offene Cases werden geschrieben: ein geschlossener Case trägt keine Stufe mehr —
   er scheidet aus der Matrix aus; seine Zähler bleiben wie sie sind, s. ADR 4.)

3. **Diff & Zeitstempel-Logik** (pro Case in der Liste, **keine** SOQL im Loop):
   ```
   H            = openHigh aus der Aggregation (0, wenn Account nicht mehr in Map)
   newStufe     = H >= 2 ? 'Kritisch' : (H == 1 ? 'Beobachten' : 'Keine')
   newTotal     = openTotal  (dito 0-Fallback)
   mustWrite    = (c.Offene_Cases_Kunde__c != newTotal)
              || (c.Offene_High_Cases_Kunde__c != H)
              || (c.Eskalation_Kunde__c != newStufe)
   if mustWrite:
       if (c.Eskalationszeitpunkt__c == null AND newStufe == 'Kritisch')
           c.Eskalationszeitpunkt__c = DateTime.now();   // AK3, AK5, AK8
       // Herabstufung: Zeitstempel NIEMALS anrühren (AK4, AK8 — Wert bleibt)
       // Neueinklassifizierung nach Herabstufung auf Kritisch (AK5):
       //   Zeitstempel ist null oder alt → PO: "setzt neu falls dieser Case zuvor nie kritisch"
       //   → null-Prüfung genügt (AK5 verlangt "neueinstellen" = nur bei null)
       c.... = ...;
       toUpdate.add(c);
   ```
4. **1× DML:** `update toUpdate;` (leere Liste → kein `update`, 418-Lektion: leerer DML-Call
   ist ein Fehler, nicht eine No-Op).

**Governor-Budget pro Batch (unabhängig von Case-Zahl):** 2 SOQL + 1 DML. AK7 (≥200 Cases)
bestanden mit großem Rest — Query-Zählung im Test nachweisbar (s. Technische AC, T-AK7).

**Rekursions-Schutz:** Der Handler schreibt nur die 4 neuen Felder auf offene Cases. Der Trigger
filtert Updates auf Änderungen von `Priority`, `Status` (↔Closed) oder `AccountId` — unsere eigenen
Schreibungen ändern keins davon → **kein** zweiter Feuer-Durchgang, kein Flag nötig
(365/418-Pattern, beide ohne Flag im Betrieb). **Review-Check:** Trigger-MustWrite-Bedingung
darf KEINE der 4 neuen Felder als Condition enthalten.

---

## ADR 4 — Geschlossene Cases: was passiert ihren Werten

Ein Case, der `Status → Closed` wird, scheidet aus der Zählung aus und wird **nicht mehr berührt**
(aus Step 2 SOQL gefiltert). Seine Felder behalten den **letzten** Wert (zuletzt berechnete Stufe,
Zeitstempel intakt). PO-Matrix ist offen (offene Cases); "geschlossener Case trägt veraltete Anzeige"
ist akzeptabel und dokumentiert — niemand erwartet auf einem Closed-Case eine Live-Stufe.
Keine zusätzlichen Felder, kein Reset-Dummy. (AK4 prüft nur den *offenen* Peer + den Zeitchip.)

> **Offen (PO, vor Implementierung, Default = wie beschrieben):** Sollten geschlossene Cases
> ihre Felder bei Schließen auf `Keine` / 0 zurücksetzen (saubere Anzeige)? Default: **nein**
> (weniger Writes, kein Reset-Dummy, Stufe = "war zuletzt kritisch" bleibt als Historie sichtbar).

---

## ADR 5 — Rebuilder (Bestandsdaten, ADR 2)

`CaseEscalationKundeRebuilder` (eigene Klasse, `SCRUM420EscalationKundeRebuilder.cls`),
House-Shape nach `CaseOpenCountRebuilder` (367) — **ohne** 2. Log-Objekt (PO fordert keins;
`CaseRebuildRun__c` ist Contact-basiert und bleibt unverändert):

- `Database.Batchable<Case>`, `Database.Stateful`
- Starter: `SELECT Id FROM Case WHERE Status != 'Closed'` (gesammelte Ids, keine Daten)
- **execute:** pro Batch (200) die AccountIds extrahieren
  (Batch-Elemente tragen AccountId mit) → **einen** Call an
  `CaseEscalationKunde.recompute(accountIds)` — **wiederverwendet** den einen Handler,
  dieselbe Zähllogik, kein Drift zwischen Trigger- und Rebuilder-Pfad.
- `finish/exception`: no-op (kein Status-Objekt; Erfolg = Felder in den Cases, log via
  `System.debug` + Apex-Job-Status in Setup›Apex Jobs).
- Einziges Deploy/Verlauf: `sf apex run -f SCRUM420EscalationKundeRebuilder.cls`
  + `System.runAs`-Ablage: `Database.executeBatch(new SCRUM420EscalationKundeRebuilder(), 200)`
  — Developer führt ein Mal in Test-Org aus, Ergebnis (geheilte Fälle) per SOQL nachweisen.

---

## API-Namen (final, Kollisionsprüfung 2026-09-19 bestanden — 0 Treffer auf origin/master)

| API-Name | Type | Label | Detail |
|---|---|---|---|
| `Eskalation_Kunde__c` | Picklist | Eskalationsstufe (Kunde) | `Keine` (Default), `Beobachten`, `Kritisch` — **read-only** (kein Write-FLS, Trigger-schreibt) |
| `Offene_Cases_Kunde__c` | Number | # offene Cases (Kunde) | `0` Default (PO: Zähler, nicht NULL — "leer" unleserlich; s. ADR 6), Precision 0, Scale 0 |
| `Offene_High_Cases_Kunde__c` | Number | # offene High-Cases (Kunde) | `0` Default, Precision 0, Scale 0 |
| `Eskalationszeitpunkt__c` | DateTime | Eskalationszeitpunkt (Kunde) | **null-Default** (AK1: leer = nie kritisch); **niemals überschrieben** |

**Wichtig für XML:** `Eskalation_Kunde__c` ist die PO-Vorschlags-`Eskalation_Kunde__c`
(Picklist), **nicht** zu verwechseln mit dem bestehenden `Eskalationsstufe__c` (398, formula,
read-only). Beide leben nebeneinander auf Case — 398 bleibt unberührt (Akzeptanzkriterium
Abgrenzung).

---

## ADR 6 — Defaults & Picklist-Default-Werte

- `Eskalation_Kunde__c`: Picklist, **default `Keine`**, Werte exakt: `Keine` → `Beobachten` → `Kritisch`.
  Kein `formula`, kein `updateable` in der Feld-Def (Read-only-FLS regelt den Rest via PS).
- `Offene_Cases_Kunde__c` / `Offene_High_Cases_Kunde__c`: **`<defaultValue>0</defaultValue>`**
  (PO: Zähler; `null` = "noch nicht berechnet" wäre für ein Picklist-geleitetes UI
  mehrdeutig mit "kein Kunde / kein Account" — bei 0 ist die Anzeige klar, und der
  Trigger kann ohne NULL-Handling diffen). Bei Cases **ohne** Account (AccountId null)
  schreibt der Handler `Keine` / 0 / 0 (kein Account = kein Kunde = keine Eskalation);
  Zeitstempel bleibt null.
- `Eskalationszeitpunkt__c`: **kein** Default (null = "nie kritisch").

---

## Permission Set (PS-House-Rule, 398-Template)

**`SCRUM420_EskalationKunde.permissionset-meta.xml`** — **nur Read-FLS** auf die 4 Felder,
kein Objekt-CRUD, kein Write, keine Apex. Label `SCRUM420_EskalationKunde`, Kurzbeschreibung
wie 398. **Kein Aktivations-Picklist (kein `hasActivationRequired=true`)** wie 398
(Read-FLS, direkt wirksam, kein manuelles Aktivieren).

> **Wichtig (House-Lektion SCRUM-365):** Die 4 Felder sind **nur** via diesem PS lesbar —
> ohne Assignment ist das negative FLS-Test (AK) der Nachweis. **Deployment ≠ Assignment.**
> Developer **muss** nach dem Deploy das PS der **Test-Org-CLI-User** UND dem
> **menschlichen Test-Account** zuweisen (`sf org assign permset`), Read-Back eines Feldes
> in einer echten Session (Playwright bzw. `sf data query` als eingelogte User) **vor**
> dem Handoff. (SCRUM-382/386/388/390/394/398 alle schon einmal an dieser Stelle gescheitert.)

---

## Page Layout (Case)

- **Live = committed (verified, byte-identical, 12 summaryLayout/32 layoutItems)** →
  kein 408-Drift-Risiko; die committete Layout-Datei darf deployed werden (Voraussetzung:
  der Drift-Check wird im Implementierungs-Kommentar dokumentiert, mit Datum).
- Neue `layoutSection` (oder `section`) **`Eskalation (Kunde)`** neben (nicht ersetzend)
  dem bestehenden `Eskalationsstufe__c`-Block; 4 `layoutItem`s (je Feld), Reihenfolge:
  `Eskalation_Kunde__c`, `Offene_Cases_Kunde__c`, `Offene_High_Cases_Kunde__c`,
  `Eskalationszeitpunkt__c`.
- **Deploy-Strategie (408-Pflicht, auch wenn hier kein Drift sichtbar):** Vor dem Layout-Deploy
  `sf project retrieve start -m "Layout:Case-Case Layout"` neu ausführen und Byte-Vergleich
  mit der committeten Datei — falls sich das Live-Layout in der Zwischenzeit geändert hat,
  nur die neue `layoutSection` manuell in das Live-artefakt einfügen und deployen
  (408/403-Lektion: nie die committete Datei blind deployen, wenn sich Live in der
  Zwischenzeit geändert hat).

---

## Komponenten-Übersicht (was gebautes wird)

| Datei (Pfad) | Typ | Zweck |
|---|---|---|
| `objects/Case/fields/Eskalation_Kunde__c.field-meta.xml` | CustomField | Picklist, default Keine |
| `objects/Case/fields/Offene_Cases_Kunde__c.field-meta.xml` | CustomField | Number, default 0 |
| `objects/Case/fields/Offene_High_Cases_Kunde__c.field-meta.xml` | CustomField | Number, default 0 |
| `objects/Case/fields/Eskalationszeitpunkt__c.field-meta.xml` | CustomField | DateTime, null-default |
| `triggers/CaseEscalationKunde.trigger` + `CaseEscalationKundeTrigger.cls` | ApexTrigger | Sammelt AccountIds, ruft recompute 1× |
| `classes/CaseEscalationKunde.cls` (+meta) | ApexClass | Statisch `recompute()`, 2 SOQL + 1 DML |
| `classes/SCRUM420EscalationKundeRebuilder.cls` (+meta) | ApexClass | Batch, ruft recompute |
| `permissionsets/SCRUM420_EskalationKunde.permissionset-meta.xml` | PermissionSet | Read-FLS × 4, kein Write |
| `layouts/Case-Case Layout.layout-meta.xml` | Layout | Neue Section (nur wenn Live==committed am Deploy-Tag) |
| `classes/SCRUM420EscalationKundeTest.cls` | TestClass | Funktional (AK1–6, 8) + Governor-Zähler (AK7) |
| `classes/SCRUM420EscalationKundeFlsTest.cls` | TestClass | Negatives FLS (AK negativ) |
| `manifest/scr420-phase1.xml` | Manifest | 4 Felder + 1 PS |
| `manifest/scr420-phase2.xml` | Manifest | Trigger + 2 Apex + 3 Test + Layout |

**Zwei-Phasen-Deploy (418/419/408-Pattern):** Phase 1 = Felder + PS (Deploy, dann PS
zuweisen, Read-Back). Phase 2 = Apex + Tests + Layout (deploy mit
`--test-level RunSpecifiedTests --tests SCRUM420EscalationKundeTest,SCRUM420EscalationKundeFlsTest`).
Danach Rebuilder per `sf apex run` ausführen, Ergebnis nachweisen.

---

## Test-Vorgaben (Developer — exakt, nicht umformulieren)

### Funktionstest `SCRUM420EscalationKundeTest` (Setup: 1 Account, Cases je AK)

| TC | Setup | Erwartung | AK |
|---|---|---|---|
| TC1 | 1 Case, Priority ≠ High, offen | `Eskalation_Kunde__c == 'Keine'`, `Offene_Cases_Kunde__c == 1`, `Offene_High_Cases_Kunde__c == 0`, Zeitstempel null | AK1 |
| TC2 | 1 Case, Priority == High, offen | `'Beobachten'`, 1, 1, Zeitstempel null | AK2 |
| TC3 | 2 offene High-Cases desselben Account (zweiter als `insert`) | **beide** Cases `'Kritisch'`, beide haben Zeitstempel **gesetzt (≠ null)** | AK3 |
| TC4 | TC3-Zustand → 1 High-Case auf `Status='Closed'` | Verbleibender Case `'Beobachten'`; **Zeitstempel des verbleibenden Cases bleibt ≠ null** | AK4 |
| TC5 | TC4 → geschlossenen Case wieder auf `Status='New'` (Priority High) | Beide offen + H=2 → beide `'Kritisch'`; der wiedereröffnete Case hat Zeitstempel **≠ null** (neu gesetzt, da null) | AK5 |
| TC6 | Case mit AccountId A (1 offener High) → `AccountId` auf B (1 offener High, B bisher 0 offen) | **Beide** Accounts neu berechnet: A-Case `'Keine'` (0 offen), B-Case `'Beobachten'` (1 offen) — `Offene_Cases_Kunde__c` korrekt für beide | AK6 |
| TC7 | **Bulk:** 200 Cases in einem `insert`-Batch, gemischt über mehrere Accounts, je Account 0/1/2+ High offen | Korrekte Werte auf allen; `Limit.getQuery()` (vorher `System.runAs` mit `Test.startTest()`-/`stopTest()`-Markierung) **< 100** — `assertEquals(Limit.getLimit('Queries') - Limit.getNumQueries(), > X)` oder `Test.isTestable` + `System.debug`-Zähler; **mindestens** `assertThat`-Pauschal-Assert auf `Limit.getNumQueries()` im Test-Rahmen | AK7 |
| TC8 | TC3-Zustand → beide High-Cases auf `Status='Closed'` → wieder auf offen → Herabstufung | Zeitstempel der Cases, die **schon** kritisch waren, bleibt unverändert (kein Überschreiben) | AK8 |

**Bulk-Prüfung (T-AK7, PO: „nachgewiesen durch Governor/Query-Zählung, nicht nur grüner Lauf"):**
Im TC7 `Integer qBefore = Limit.getNumQueries();` vor `Test.startTest()`,
`Integer qAfter = Limit.getNumQueries();` nach `Test.stopTest()`,
`assertTrue(qAfter - qBefore < 20)` (erwartet: 2 SOQL + 1 DML + Setup-Queries, je nach
`System.runAs`-Wrapper < 10). **Pauschal-Assert** (nicht nur `System.debug`) — ein
`System.debug` ohne Assert ist ein Scheitern beim Review.

### Negativ-FLS-Test `SCRUM420EscalationKundeFlsTest` (House-Pattern 353/359/398)

- 1 TestUser (neu, via `User`-Insert mit minimalem Profil — House-Pattern, kein Produktiv-Profil
  angetasten), **ohne** PS-Assignment.
- `System.runAs(testUser)`: `SELECT Eskalation_Kunde__c FROM Case LIMIT 1` →
  **`SecurityException` / `No such column`** (Feld FLS-kapital, nicht lesbar).
  **Beide** Exception-Typen möglich (Case-Feld vs. Objekt-CRUD) — Assert auf
  `Test.startTest`-Wrapper + `try/catch` und `fail()` wenn **kein** Fehler;
  exakter Message-Abgleich ist flaky (Wording-Änderungen) → `catch` + Assert
  "wurfe eine Exception" genügt (House 398-FSL-Test, 2026-09-11).
- **Positiv-Kontroll-Run (selbe Klasse, getrennte Methode):** derselbe User **mit**
  PS → `SELECT` liefert den Wert. **Ohne diese Kontroll-Methode ist der negative Test
  wertlos** (er bricht auch bei fehlendem Case-CRUD und beweist dann nur das Fehlen
  von Objekt-Zugriff, nicht das Fehlen des Felds). **Zwei Methoden, ein User:**
  `testWithoutPermset` (negativ) und `testWithPermset_isReadable` (positiv).
- **Wichtig:** `Eskalationsstufe__c` (398) **darf** weiterhin lesbar sein
  (sehr PS, bereits zugewiesen) — Test darf 398-Feld **nicht** als Kontrollfeld nutzen.

### Regression (Developer-Kommentar am Ticket, vor Handoff)

`sf apex run test -o Test-Org -n SCRUM418CaseReactionTest -n SCRUM418CaseReactionFlsTest
-n SCRUM419ReentryRegressionTest -n SCRUM365OpenCasesCountTest` — alle grün, sonst Stop.

---

## Techn. Abnahemerkmalen (Review-Kriterien für mich, abgesehen von PO-AK)

- [ ] Trigger: keine der 4 neuen Felder als Update-Bedingung (Rekursions-Schutz, ADR 3)
- [ ] Handler: exakt 2 SOQL-Aufrufe (Aggregation + Zustands-Query), 1 DML, keine SOQL im Loop
- [ ] `AggregateResult` Typ (nicht `Aggregate`) — 2026-09-15-Lektion
- [ ] `update toUpdate` nur bei `!toUpdate.isEmpty()` (418-Lektion)
- [ ] Zeitstempel-Schreiblogik: nur `null → set` (AK5 „neu falls nie kritisch"), nie `alt → neu`
- [ ] PS: nur 4 `fieldPermissions`, `readable=true`, `editable=false`, keine Objekt-Permissions, kein Apex
- [ ] PS **zugewiesen und per Read-Back verifiziert** (Developer-Kommentar, ADR 6)
- [ ] Layout: `section` `Eskalation (Kunde)` + 4 Items, bestehenden `Eskalationsstufe__c`-Block angetastet
- [ ] Kein `Eskalationsstufe__c`-Änderung (398 bleibt, Abgrenzung)
- [ ] Manifest: Phase 1 und Phase 2 separat, Reihenfolge im Test-Abschnitt korrekt

---

## Offene Punkte (PO-Entscheidungen, vor Start der Implementierung finalisieren)

1. **Bestandsdaten / Rebuilder** (ADR 2+5): Rebuilder im Deploy, oder nur ab nächstem Event?
   **Architect-Default: Rebuilder ja**, PO-Bestätigung bevor Developer startet.
2. **Geschlossene Cases** (ADR 4): Felder bei Schließen auf `Keine`/0 zurücksetzen oder
   letzten Wert behalten? **Architect-Default: behalten** (Historie sichtbar).
3. **Eskalationszeitpunkt-Reset bei erneutem Kritisch-Event** (AK5): PO text liest sich
   als „neu setzen, falls nie kritisch" (= null → setzen). Gilt der **alte** Wert für
   einen Case, der **wieder** kritisch wird nach Herabstufung? **Default: alter Wert
   bleibt** (AK8/PO „beibehalten"). PO-Bestätigung.

Diese 3 Punkte gehen als Kommentar an @PO-Agent, **bevor** Developer-Auftrag geht.
Wenn PO in 4h nicht antwortet → Default gelten (Architect-Entscheidung, im
Implementierungs-Kommentar dokumentiert).

---

## Für @devops-agent (Merge, nicht Test)

- PR muss **Architect-APPROVE** + **3/3 grüne CI** haben, bevor merged.
- **Bestandsdaten** in Test-Org: Rebuilder-Lauf **vor** dem Merge (sonst ist die
  Test-Org im Merge-Zustand mit inkonsistenten Bestandsdaten → Tester muss
  nicht warten).
- **Prod-Deploy** (wenn das Ticket danach auf Release geht): Phase-1 + Phase-2
  + Rebuilder-Lauf in Prod. Bestandsdaten in Prod = 0-Initialisierung, **nicht**
  ein Fehler im Deploy.
- **Kein** `Eskalationsstufe__c`-Deploy (398 bleibt). Kein `CaseRebuildRun__c`-Deploy.

---

## Verifikation-Trail (alles per CLI am 2026-09-19, Test-Org / origin/master)

- Picklist + Feldtyp: `sf sobject describe -s Case -o Test-Org` → Priority/Status updateable, Formel-Feld 398 updateable=False
- Kollision: `git ls-tree -r --name-only origin/master | grep -ic "^force-app/main/default/objects/Case/fields/(Name)\.field"` → 0 für alle 8 Kandidaten
- Layout-Drift: `sf project retrieve start -m "Layout:Case-Case Layout"` + Byte-Vergleich → identisch
- 365-House: `git show origin/master:force-app/main/default/triggers/CaseOpenCountTrigger.trigger` + `classes/CaseOpenCountTrigger.cls`
- 398-PS-Template: `git show origin/master:force-app/main/default/permissionsets/SCRUM398_Eskalationsstufe.permissionset-meta.xml`
- apiVersion 62.0: `git show origin/master:force-app/main/default/triggers/CaseOpenCountTrigger.trigger-meta.xml`
