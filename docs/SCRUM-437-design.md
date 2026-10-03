# SCRUM-437 — Architektur-Design: Wiedererkennende Servicefälle (Problemkategorie + Problemserie)

**Status:** freigegeben zum Build · **Architekt:** architect-agent · **Datum:** 2026-10-03
**Survey-Basis:** `origin/master` @ `43a4e9b` (2026-10-03).
**Autoritative Build-Spec — die Repo-Dateien sind der Maßstab, nicht der Jira-Kommentar.**

---

## 1. Ziel (ein Satz)
Ein Case erkennt automatisch, ob derselbe Account bereits ≥ 2 weitere ähnliche Cases (gleiche **Problemkategorie**, offen oder ≤ 30 Tage geschlossen) hat; die zugehörigen Cases werden in einer gemeinsamen, persistierten **Problemserie** verbunden, und das alles bulkified (1 gruppenweise SOQL + 1 gruppenweise DML pro Batch, kein pro-Case-Einzel-SOQL) — House-Pattern **`CaseOpenCountTrigger`/`recompute`** (SCRUM-365/370).

---

## 2. Betroffene Objekte
- **Case** (Standard) — 5 neue Custom Fields.
- **Kein** neues SObject. `Problemserie` ist auf Case persistiert (ADR-1).
- **Account** (Standard) — nur als Referenz (`Case.AccountId`), unverändert.

---

## 3. Datenmodell — 5 neue Felder auf Case

> **Namen-Regel:** API-Names des Architekten. Labels = PO-Fachbegriffe. **Die Feld-Dateien in der Repo sind die einzige exakte Quelle für API-Names** (Jira-Markup würde Doppel-Underscores/XMML zerlegen — daher werden die Namen hier, nicht im Kommentar, definiert).

| # | API-Name | Type | Label | Beschreibung |
|---|----------|------|-------|--------------|
| 1 | `Wiederkehrendes_Problem__c` | Checkbox | Wiederkehrendes Problem | System-gesetzt, read-only. Ja, wenn im Pool ≥ 2 weitere ähnliche Cases. |
| 2 | `Anzahl_aehnlicher_offener_Cases__c` | Number(8,0), defaultValue 0 | Anzahl ähnlicher offener Cases | Zahl der Pool-Cases mit Status offen. |
| 3 | `Letzter_aehnlicher_Case__c` | **Lookup auf Case** (self-lookup) | Letzter ähnlicher Case | Der zuletzt passende Case im Pool (neuere `CreatedDate`). |
| 4 | `Problemserie__c` | Text(40), **unique=false** (Review-Korrektur 2026-10-03: gemeinsam geteilter String je Serie — row-level `unique=true` würde beim 2. Case der Serie in Duplicate-Violation laufen) | Problemserie | Gemeinsame eindeutige Kennung je Serie. |
| 5 | `Problemkategorie__c` | Picklist | Problemkategorie | Einziges manuell gepflegtes Feld. |

### 3.1 Feld-Detail (Shape = verifierte House-Beispiele)
- **Number-Shape:** 1:1 `Case/fields/Offene_Cases_Kunde__c.field-meta.xml` (precision 8, scale 0, defaultValue 0, required false, unique false, trackTrending false).
- **Picklist-Shape:** 1:1 `Case/fields/Ursache__c.field-meta.xml` (`<valueSet><valueSetDefinition>`, `required=false`, trackFeedHistory false).
- **Checkbox-Shape:** `type=Checkbox`, `defaultValue=false`, `required=false`, `trackTrending=false`.
- **Self-Lookup-Shape:** `<type>Lookup</type><referenceTo>Case</referenceTo><relationshipLabel>Cases_der_Selben_Serie__r</relationshipLabel><relationshipName>Recurring_Problem_Series</relationshipName><deleteConstraint>SetNull</deleteConstraint>` — ⚠️ vgl. ADR-2/⚠️-Befund.

### 3.2 Picklist-Werte `Problemkategorie__c`
PO-Fachwerte → API-Labels (Labels exakt wie im Ticket, API-`fullName` sauber tokenisiert; `fullName` entfällt bei `valueSetDefinition` — Salesforce leitet ihn ab, House-Shape `Ursache__c` zeigt Label-basierte Einträge):

| Label (angezeigt) |
|-------------------|
| Technischer Defekt |
| Login / Zugang |
| Rechnung |
| Lieferung |
| Vertrag |
| Sonstiges |

Alle `default=false` (Feld ist optional; nur bei gesetzt = Neubewertung).

---

## 4. Geschäftsregeln — Berechnungslogik (präzise)

**Pool(aktuelleCase c):** alle Cases `p` (p ≠ c) mit
- `p.AccountId == c.AccountId` (und `c.AccountId != null`), **UND**
- `p.Problemkategorie__c == c.Problemkategorie__c` (und beide == nicht null), **UND**
- (`p.Status` ist offen) **ODER** (`p.Status == 'Closed'` **UND** `p.LastModifiedDate >= System.Date.today().addDays(-30)`).

> ⚠️ **Zeitfenster-Felder:** Der PO sagt «innerhalb der letzten 30 Tage geschlossen». Das **schlüssige Feld** ist **`ClosedDate`** (die echte Schließzeit), nicht `LastModifiedDate` — `LastModifiedDate` rutscht bei jedem späteren Edit nach vorne und verlässt dann das Fenstergeschäft. **Entscheidung:** Pool-Zugehörigkeit über `p.ClosedDate >= today.addDays(-30)` (NULL-frei: nur geschlossene Cases haben `ClosedDate`; offene Cases zählen ohnehin über den Status-Ort). Der Developer liest die Picklist `Case.Status` aus der Org (offen = alles ungleich `Closed`, House-Vorgabe `CaseOpenCountTrigger.CLOSED_STATUS='Closed'`). Falls die Org `ClosedDate` nicht pflegt → Read-back-Prüfung vor Deploy (siehe §8).

**Felder je Case c:**
- `Anzahl_aehnlicher_offener_Cases__c` = `|{ p in Pool(c) : p.Status offen }|`.
- `Wiederkehrendes_Problem__c` = `|Pool(c)| >= 2`. *(«mindestens zwei weitere» → Ja bei ≥ 2 weiteren.)*
- `Letzter_aehnlicher_Case__c` = Id des `p in Pool(c)` mit max `CreatedDate` (Tie-break: max `Id`). **Falls Pool leer → NULL und** `Wiederkehrendes_Problem__c=false`, `Anzahl=0`.
- `Problemserie__c` = gemeinsamer String je Serie (Berechnung ADR-1/2). ⚠️ **Nur gesetzt, wenn c selbst teil der Serie ist** — Definition siehe ADR-2 (Schwellen-Lebenszyklus).

### 4.1 Bewerten «neu berechnen, kein Delta»
**Jedes mal, wenn die Eingangsgrößen für eine (AccountId, Kategorie)-Gruppe sich ändern, wird die ganze Gruppe neu berechnet** (kein Incremental/Drift, 1:1 `CaseOpenCountTrigger.recompute`): alle zugehörigen Cases der Gruppe in einer SOQL lesen, berechnen, nur die mit Änderung `update` (no-op-skip, verhindert After-Update-Zyklen + LastModified-Ruhelosigkeit).

### 4.2 Bulkified-Implementierung (Pflicht: kein pro-Case-SOQL)
1. **Trigger** sammelt je Batch die **betroffenen Gruppen** `Set<(AccountId, Problemkategorie)>` (insert/delete: aus Trigger.new/.old; update: nur wenn `AccountId` oder `Problemkategorie__c` sich ändert → alte UND neue Gruppe/Account).
2. **Ein** `Map<GroupKey, List<Case>>` per **einer GROUP-BY / IN-Query**:
   ```
   SELECT Id, AccountId, Problemkategorie__c, Status, ClosedDate, CreatedDate,
          Anzahl_aehnlicher_offener_Cases__c, Wiederkehrendes_Problem__c,
          Letzter_aehnlicher_Case__c, Problemserie__c
   FROM Case
   WHERE (AccountId = :aid AND Problemkategorie__c = :kat)   -- pro betroffener Gruppe
   ```
   → **ein SOQL pro betrofferer (AccountId,Kategorie)-Gruppe** oder eine **einmalige IN-Query über alle betroffenen AccountIds** + in-memory nach Kategorie gruppieren. **Empfohlen:** einmalige Query über alle betroffenen AccountId (`WHERE AccountId IN :accountIds`) und in Apex nach `(AccountId,Kategorie)` partitionieren — **dann exakt 1 SOQL pro Batch**, unabhängig von Fallzahl (Governor-sicher bei 200-Case-Batch).
3. Berechnung in-memory (Map), **1 `update` der geänderten Cases**.
4. **Kein SOQL-in-Loop, keine DML-in-Loop.** Governor-Budget: 1 SOQL + max. 1 DML (+ 1 für Serien-Kennungen, s.u.) pro Batch.

### 4.3 Serienkennung berechnen (ADR-1: Textfeld, kein SObject)
Serien-Identität = stabile Kennung je (AccountId, Kategorie). Berechnung **deterministisch und nachvollziehbar:**
```
serie = AccountId (18 Zeichen, volle Key) + '_' + Problemkategorie__c (API-Value)
        z.B. '00D...abc_Rechnung'
```
→ **Implementierungsabweichung (PR #157, Review bestätigt 2026-10-03):** SOQL liefert beim Custom-Picklist-Feld den **API-Value** (fullName), nicht das Label (Beleg im Ticket/Doku: `SELECT Ursache__c FROM Case` → `RechnungAbrechnung`). Die Kennung nutzt deshalb den API-Value — deterministischer, und ein Picklist-**Label**-Rename bricht sie dann nicht mehr. Längster API-Value (z.B. `TechnischerDefekt` = 17 Zeichen) → 18 + 1 + 17 = **36 ≤ 40** (Text(40)), je (AccountId,Kategorie) **immer derselbe String** (AC9: «dieselbe eindeutige Kennung»). Die Kennung ist reine Funktion der Eingabe (AccountId + Picklist-API-Value) → **keine zweite SOQL** nötig (§4.2 bleibt bei exakt 1 Query). ⚠️ **Kein DB-Unique-Race**, weil alle Cases derselben Gruppe den *identischen* String bekommen (daher Feld **unique=false** — s. §3-Zeile 4). ⚠️ **Picklist-VALUE-Umbenennung** ändert die Kennung (API-Value-Rename ist ein Konfig-Migrations-Ereignis; blockiert nichts im Build) — siehe §8.

### 4.4 Schwellen-Lebenszyklus von `Problemserie__c` (ADR-2 — Kern-Entscheidung)
Die **Erkennungsfelder** (1–3) sind strikt **fensterbasiert** (30 Tage) und dürfen bei leerem Fenster auf **false / 0 / NULL** zurückfallen (AC4/5: alte zählen NICHT; Anzahl kann 0 werden).
Die **Serien-Identität** (Feld 4) ist laut PO **persistiert** (Abgrenzung im Ticket: «Erkennung & Zählung = zeitfensterbasiert; Serien-Identität = persistiert»). Der PO überlässt mir genau diesen Lebenszyklus (Offene Designfrage 2: «Entstengung bei Übersteigen der Schwelle; Verhalten bei leerem 30-Tage-Fenster»).

**Geburt der Serie — an die Schwelle gebunden (erfüllt AC1 «keine Serie» UND AC2 «erst beim 3. Fall angelegt»):**
1. **Unter der Schwelle → keine Kennung** (`Problemserie__c = NULL`).
   - AC1 (1. Case): Pool(c) = 0 < 2 → **keine Serie**. ✓
   - AC2 2. Case: Pool = 1 < 2 (nur 1 weiterer) → **keine Serie**. ✓
2. **Erstes Überschreiten der Schwelle → Serie entsteht + wird rückwirkend verknüpft.**
   - Derjenige Case c, bei dem |Pool(c)| erstmals ≥ 2 wird, **gründet die Serie**: `Problemserie__c` wird auf c **und auf ALLE anderen Cases derselben (AccountId,Kategorie)-Gruppe** gesetzt (Rückbesetzung, damit AC2 «Serien angelegt/verknüpft» und AC9 «dieselbe eindeutige Kennung» aus dem einen String folgen). ✓
3. **Nach der Geburt — Kennung wird geerbt und bleibt (persistiert):**
   - Jeder **neue** Case derselben (AccountId,Kategorie) übernimmt die **bereits existente** Kennung (AC: «neue Cases derselben Kategorie werden derselben Serie zugeordnet»).
   - **Leeres 30-Tage-Fenster** (alle Pool-Partner jetzt > 30 Tage): Erkennungsfelder → korrekt «nicht wiederkehrend / 0», aber `Problemserie__c` **bleibt gesetzt**. (Genau die Abgrenzung, die der PO zieht.)
4. **Kategorie-Änderung (AC6):** c verlässt die alte Gruppe (AccountId, alteKat) und fällt in (AccountId, neueKat).
   - Neue Gruppe **mit** existierender Kennung → c erbt die neue Kennung.
   - Neue Gruppe **ohne** Kennung → c trägt vorerst NULL (keine Schwelle) **oder** wird geerbt, falls die neue Gruppe schon eine Serie hat.
   - Die alte Kennung bleibt auf den übrigen Cases der alten Gruppe (c verliert sie nur auf sich). *Kein Löschen fremder Serien.*
   - Erkennungsfelder von c werden gegen die **neue** Gruppe neu berechnet.
   > **Tester-Hook:** Rechnung→Lieferung ⇒ `Problemserie__c` + `Letzter_aehnlicher_Case__c` + `Wiederkehrendes_Problem__c` zeigen den Lieferung-Zustand.

**Wichtig für den Rebuilder / AC-Edge Cases:** Die Rückbesetzung in Schritt 2 und die Erbschaft in Schritt 3 schreiben dieselbe, aus (AccountId,Kategorie) abgeleitete Kennung → kein Konflikt. Der Handler entscheidet je Gruppe: «Kennung vorhanden? → alle Fälle derselben tragen sie; falls nicht UND Schwelle überschritten → jetzt begründen.»

---

## 5. Komponenten (konkret, Pfade auf `force-app/main/default/`)

1. **Felder (Phase 1)** — `objects/Case/fields/` 5 Dateien:
   - `Wiederkehrendes_Problem__c.field-meta.xml`
   - `Anzahl_aehnlicher_offener_Cases__c.field-meta.xml`
   - `Letzter_aehnlicher_Case__c.field-meta.xml`
   - `Problemserie__c.field-meta.xml`
   - `Problemkategorie__c.field-meta.xml`
2. **Berechnungs-Apex (Phase 2):**
   - `triggers/CaseProblemSerieTrigger.trigger` + `-meta.xml` — after insert/update/delete auf Case; sammelt betroffene Gruppen, ruft EXAKT EINMAL `CaseProblemSerieHandler.recompute(...)`.
   - `classes/CaseProblemSerieHandler.cls` — `public without sharing class`; `@future`/bulkified `recompute(Set<Id> accountIds)` nach §4.2; Serienschlüssel aus §4.3; Schwellen-Logik §4.4. **apiVersion 62.0** (House — alle 436-Klassen).
   - ⚠️ **Trigger-Stoß-Vermeidung:** Der Handler schreibt nur die 4 Systemfelder — **niemals** `Problemkategorie__c`/`AccountId` → keine After-Update-Re-Triggerschleife. Zusätzlich Guard: Handler prüft `mustWrite` (nur bei echter Änderung), 1:1 `CaseOpenCountTrigger`.
3. **FLS Permission Sets (Phase 2):** Shape 1:1 `SCRUM436_CaseReminder` / `SCRUM436_CaseReminderSystem`:
   - `SCRUM437_ProblemSerie_Read.permissionset-meta.xml` — Service-Mitarbeiter:
     - `Wiederkehrendes_Problem__c` r/o read-only
     - `Anzahl_aehnlicher_offener_Cases__c` read-only
     - `Letzter_aehnlicher_Case__c` read-only
     - `Problemserie__c` read-only
     - `Problemkategorie__c` **read + editable** (einziges Edit-Feld, triggert Neubewertung)
   - `SCRUM437_ProblemSerie_System.permissionset-meta.xml` — Batch-/Trigger-Executor: alle **5** Felder read+write (sorgt dafür, dass ein `runAs`-Test bzw. ein nicht-System-User die Handhabung simulieren kann; 1:1 System-PS). *Kein `Case`-Object-CRUD nötig — das kommt vom Profil.*
4. **Layout (Phase 2):** `layouts/Case-Case Layout.layout-meta.xml` — **neue Sektion «Problemserie»** (House `Ursache__c` Sektion SCRUM-434, `<platformLayoutSection>`) mit den 5 Feldern; `Letzter_aehnlicher_Case__c` + `Problemserie__c` prominent.
5. **Tests:**
   - `classes/SCRUM437ProblemSerieTest.cls` — die 9 AC (§7) + Concurrency.
   - `classes/SCRUM437ProblemSerieFlsTest.cls` — FLS neg + pos (Shape `SCRUM436CaseReminderFlsTest`).
6. **E2E (Playwright, `tests/e2e/`):** `SCRUM-437_problem-serie.spec.ts` — Case-Seite zeigt andere Cases der Serie (AC-UI). Shape `SCRUM-432_wiedervorlage-case.spec.ts`.
7. **Manifests:**
   - `manifest/scr437-phase1-fields.xml` — 5 `CustomField` (`Case.XXX__c`), version 67.0.
   - `manifest/scr437-phase2-referencing.xml` — 2 `PermissionSet` + `Layout` (`Case-Case Layout`) + `ApexClass` (`CaseProblemSerieHandler`) + `ApexTrigger` (`CaseProblemSerieTrigger`), version 67.0.
   - `manifest/scr437-apextests.xml` — 2 `ApexClass` (Test + FlsTest), version 67.0.

---

## 6. ADRs

### ADR-1 — Problemserie als **Textfeld auf Case** (kein `Problemserie__c` SObject)
**Entscheidung:** Feld 4 = eindeutiger, deterministic berechneter Text auf Case.
**Warum kein SObject:**
- Serien-Identität = reine Funktion von `(AccountId, Problemkategorie)` (§4.3) → **deterministisch, ohne zusätzlichen Read/Unique-Constraint, ohne ein zweites Objekt zu verwalten/sharen**.
- Kein neues Object = kein neues Sharing-Modell (Ticket: «Problemserie begründet keine neue Ownership») und kein zweites FLS-Geschäft; AC9 «dieselbe eindeutige Kennung» fällt aus dem gemeinsamen String.
- Das House `CaseOpenCount` beweist, dass aggregierte Kennzahlen ohne Objekt leben.
**Alternativen abgewogen:** Lookup auf `Problemserie__c` SObject → mehr Objekt, mehr Sharing/FLS, mehr Query (Series-Auswahl pro Case) und ein Unique-Constraint, das bei gleichzeitigen Inserts derselben Serie in einen Duplicate-Violation-Race läuft. Das würde die Concurrency-Anforderung *erzeugen*, nicht erfüllen. **→ verworfen.**

### ADR-2 — Serien-Lebenszyklus: **Kennung persistiert, Erkennung fensterbasiert**
**Entscheidung:** getrennte Lebenszyklen (Erkennungsfelder 1–3 vs Identitätsfeld 4), Regel §4.4.
**Warum:** PO-Abgrenzung verlangt genau diese Trennung. Eine Serienkennung, die bei leerem Fenster löscht, würde AC6/AC9 brechen (gleiche Kennung über Zeit / nach Kategorie-Änderung). Persistenz macht die Kennung test- und auditierbar.

### ADR-3 — **Apex-Trigger (bulkified Handler)**, kein Flow
**Entscheidung:** Trigger + `without sharing` Handler, 1 SOQL + 1 DML pro Batch.
**Warum:** (a) Pflichtheit «Bulk / kein pro-Case-SOQL» — nur Apex liefert deterministisch 1 gruppenweise Query; (b) **Apex-over-Flow-Hausregel** (SCRUM-Deployment/Erfahrungsregeln: Flow = Schema-/apiVersion-Flicker, Governor-Limits bei 200-Case-Batch unzuverlässig); (c) 1:1 House-Pattern `CaseOpenCountTrigger`. **Flow abgelehnt.**
**Governor:** max. 1 SOQL + (1–2) DML pro Batch, kein Loop-SOQL/DML → 200er-Batches sicher. Self-Lookup-Feld (`Letzter_aehnlicher_Case__c`) macht den `update` umständlich (Relation-Lookback) — der Handler schreibt Lookup-Ids, kein rekursives Fetch (Relation-Read in einer separaten, gezielten SOQL **nur** für die geänderten Zeilen, damit Budget nicht sprengt; vgl. ⚠️).

### ADR-4 — FLS: **Permission Sets, kein Profile**
Shape 1:1 `SCRUM436_CaseReminder`/`System`. Service-Mitarbeiter = `SCRUM437_ProblemSerie_Read` (Edit nur auf `Problemkategorie__c`). System/Kontext = `SCRUM437_ProblemSerie_System`. **Kein Profil-Edit.** Negativer Access-Test (DoD) = `SCRUM437ProblemSerieFlsTest` (Standard-User OHNE PS sieht die 4 Berechnungsfelder NICHT und kann `Problemkategorie__c` NICHT ändern).

### ADR-5 — Zeitfenster-Feld: **ClosedDate**
«Letzte 30 Tage geschlossen» misst über `Case.ClosedDate` (echte Schließzeit), nicht `LastModifiedDate` (rutscht bei Edits). Read-back-Verifikation vor Deploy (§8): ist `ClosedDate` in der Test-Org gepflegt? (House `Ursache__c` setzt voraus, dass Cases geschlossen werden.)

### ADR-6 — `Wiederkehrendes_Problem__c`-Schwelle
«mindestens zwei weitere ähnliche Cases» ⇒ `|Pool(c)| >= 2` (Pool schließt c selbst aus). AC2 verifiziert den Rand: 2 weitere offene → Ja; 1 weitere → Nein.

---

## 7. Technische Akzeptanz (Mapping auf die 9 Gherkin-AC)

| AC | Test (in `SCRUM437ProblemSerieTest` / FlsTest) | Beweiserzeugnis |
|----|------------------------------------------------------|-----------------|
| 1 | `ac1_ersterCase_keineSerie` | `Wiederkehrendes=Nein`, `Anzahl=0`, `Letzter_aehnlicher_Case__c=NULL`, **`Problemserie__c=NULL`** (kein Mindest-2 → keine Serie, ADR-2 Schritt 1) |
| 2 | `ac2_zweiterUndDritterFall` | 2 weitere → Ja + Anzahl + `Letzter` gesetzt + gleiche Serie-Id |
| 3 | `ac3_andereKategorie_nichtVerrechnet` | Rechnung ≠ Lieferung → Anzahl 0, nein, keine gemeinsame Kennung |
| 4 | `ac4_aelter30Tage_geschlossen` | `ClosedDate` > 30 Tage → zählt NICHT |
| 5 | `ac5_offen_und_geschlossen` | 1 offen + 1 (vor 10 Tg) geschlossen → beide im Pool, Anzahl offen = 1 |
| 6 | `ac6_kategorieGeaendert_neuBewertet` | Lieferung-Gruppe: neue Kennung + Neubewertung |
| 7 | `ac7_zweiAccounts_gleichzeitig` | 2 Accounts in 1 `insert` → Serien getrennt, pro Account korrekt |
| 8 | `ac8_vieleCases_concurrency` | z. B. 4 Cases gleicher Account/Kategorie in **einem** `insert` → Zählung + Serie korrekt; **assert via Governor/Query-Count**: keine pro-Case-Query (QueryCount < Threshold) |
| 9 | `ac9_dieselbeKennung` | alle Cases der Serie → identisch `Problemserie__c` |
| FLS (DoD) | `SCRUM437ProblemSerieFlsTest` | neg: 4 Felder unsichtbar + `Problemkategorie__c` nicht editierbar; pos: mit PS lesbar, `Problemkategorie__c` editierbar, 4 Berechnungsfelder read-only |
| UI (DoD) | `tests/e2e/SCRUM-437_problem-serie.spec.ts` | Case-Seite zeigt andere Cases der Serie (Section «Problemserie») |
| Test-Org Read-back (DoD) | Manual/SOQL nach Deploy | Felder + Serie + `Letzter`-Lookup auf echten Cases |

**DoD-Read-back (Developer-Handoff, Test-Org):** nach Deploy via Session einen echten (AccountId,Kategorie)-Nachweis SOQL-lesen: `SELECT Id, Problemkategorie__c, Problemserie__c, Anzahl_aehnlicher_offener_Cases__c, Letzter_aehnlicher_Case__c FROM Case WHERE Problemkategorie__c != null` — die Serienkennungen + Zählungen + Lookup sind der Beleg (nicht nur «Deploy grün»).

---

## 8. Offene Punkte (blocken die Implementierung NICHT)
- ⚠️ **Self-Lookup deploy-verify** (Developer, Phase 1): `referenceTo>Case` (self-reference) auf einem Custom-Feld — **Repo hat kein etabliertes Self-Lookup-Beispiel** (House-Lookups zeigen Account/Lead/Contact auf History-Objekte). Die Phase-1-Deploy-Validierung (`RunSpecifiedTests`/`NoTestRun`-Dry-Run) muss bestätigen, dass `referenceTo=Case` + `deleteConstraint=SetNull` akzeptiert ist. **Falls die Org es ablehnt:** Fallback — `Letzter_aehnlicher_Case__c` als Text(18), der die Case-Id als String trägt + ein E2E-Link über `caseNumber` in der UI. **Nicht spekulieren — deploy-validate.**
- ⚠️ **`ClosedDate` gepflegt?** (Developer vor Phase-2-Deploy): `SELECT COUNT(Id) FROM Case WHERE Status='Closed' AND ClosedDate = null` in Test-Org. Falls massig NULL → ADR-5 auf `LastModifiedDate` umschwenken (Kommentar im Ticket + Designer benachrichtigen), die 30-Tage-Fensterlogik ist identisch, nur das Feld.
- **Layout-Platz:** die 5 Felder in einer eigenen Sektion; falls die Case-Layout-Breite knapp wird, `Problemserie__c` + `Letzter_aehnlicher_Case__c` in die erste Reihe. Nicht blockierend.
- **E2E-UI-Locator:** die Sektions-/Feld-Locators in der Spec per Probe bestimmen (House: nie raten), `networkidle`-Verbot beachten (Lightning). Tester übernimmt.
- **Picklist-Label-Umbenennung ändert die Serienkennung** (folgen §4.3): `Problemkategorie__c`-Label fließt in `Problemserie__c`. Label-Migration ist ein Konfig-Ereignis im Release, kein Build-Blocker. Soll das jemals stabil bleiben, ist ein Rebuilder nötig — hier **bewusst NICHT** gebaut (Scope), im Release-Kommentar als Known-Limit nennen.

---

## 9. Pre-Handoff-Checkliste (Architect → Developer)
- [x] Datenmodell dokumentiert (§3, 5 Felder, exakte Shapes).
- [x] Permission-Set / FLS-Design dokumentiert (§5.3, ADR-4, zwei PS).
- [x] Sharing-Modell: **kein neues** (nur Case-Felder + self-lookup; Serie = Text, kein Object; Ticket bestätigt «Problemserie begründet keine Ownership»).
- [x] Governor-Limit-Risiken dokumentiert (§4.2: 1 SOQL + 1 DML pro Batch, kein Loop; ADR-3).
- [x] (Kein Flow) — Apex gewählt, ADR-3; apiVersion **62.0** spezifiziert (House, alle 436/Klassen).
- [x] Serien-Schlüssel & Lebenszyklus fest (ADR-1/2, §4.3/4.4).
- [x] UI-Ansatz: Case-Layout-Sektion (kein LWC) — ADR-/⚠️ §8.3.

*Story wird an developer-agent übergeben, Spalte «In Bearbeitung».*
