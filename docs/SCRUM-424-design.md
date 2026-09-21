# SCRUM-424 — Erste Reaktionszeit (CaseComment) — Design

**Status: Build-ready.** Alle ADRs mit Test-Org-Befunden hinterlegt.
**Branch:** `feature/SCRUM-424-first-response` · **apiVersion:** 62.0 (House-Muster 420/421)

## Ziel
Bei der ersten internen Kommentar-Reaktion auf einen Case (by jemand außer dem Ersteller)
werden Zeitpunkt, Arbeitsminuten (per BusinessHours „Default“) und Ziel-Verfehlung
einmalig auf dem Case gesetzt. Report gruppiert nach Servicebereich.

## Hausmuster: SCRUM-421 (und 420)
`feature/SCRUM-421-queue-assignment` ist die Vorlage:
- after-insert-Trigger, Wrapper-Klasse mit static-`isRunning`-Recursive-Guard, Handler-Klasse,
- 2 gekoppelte SOQLs, 1 DML pro Batch, Write-once-Filter (Feld noch null),
- FLS-PermissionSet **ohne** Objekt-CRUD, Negativ-Test mit USER-Modus,
- **Profil-Lock vor dem FLS-Test** (421-Folge, ADR-6).
421 hat 2 FLS-Runden gebraucht — ADR-6 ist in diesem Design verankert, damit 424 eine Runde brauche
t.

---

## ADRs

### ADR-1: Apex auf CaseComment, kein Flow
`CaseComment` ist in Salesforce ohne Apex-Limitation nicht für Logik adressierbar;
die Logik ist bedingungsabhängig (Case.CreatedDate vs. Comment.CreatedDate, Ersteller-Check,
Write-once) und braucht Bulk. Hausregel: Apex für jegliche nicht-triviale Logik.
Flow würde Schema-Validierungs-/Deploy-Spielraum eröffnen, den 421 nicht gebraucht hat.

### ADR-2 (final): `BusinessHours`-Klasse — keine eigene Rechenmaschine
Die Arbeitsminuten berechnet die Standard-Apex-Klasse **`BusinessHours`**:
```apex
DateTime ms = BusinessHours.diff(bhId, caseCreated, commentCreated);  // Arbeits-MILLISEKUNDEN
Integer mins = Integer.div(ms, 60000);
```
`BusinessHours.diff(Id, DateTime, DateTime)` behandelt Wochentage, Tagesfenster und
Sommerzeit um die konfigurierte Zeitzone selbst. Ergänzend verfügbar: `add`,
`isWithin`, `nextStartDate`, `previousEndDate`.

**Widerlegt (Test-Org-Messung 2026-09-21):**
- `ServicePresence` / `WorkingHours`: nicht verfügbar (Deploy-Compile: „Variable does not
  exist“ / „Invalid type“).
- „Es gibt keine Apex-API für Arbeitszeiten“: falsch — `diff()`/`isWithin()` sind die API.
- `TimeZone.getOffset`: existiert, Signatur ist `getOffset(Datetime)` (nicht `Long`).
- `Math.mod(a, b)`: funktioniert (nur `%` und `System.mod` sind in Apex nicht vorhanden).

**Befund (self-measured, Test-Org):**
```
BusinessHours diff(01m000000000001, 2026-09-18T16:00:00Z, 2026-09-21T07:00:00Z) / 60000
    = 3780 Minuten  (exakt die Kalenderminuten — Org läuft 24/7, s. ADR-5)
BusinessHours.isWithin(same, 2026-09-18T16:00:00Z) = true
TimeZone 'America/Los_Angeles'.getOffset(now) = -25200000
Math.mod(17, 7) = 3
```
Die `bhId` wird einmalig im Handler geladen (ein SOQL pro Batch, kein SOQL-in-Loop).

### ADR-3: 3 neue Custom-Fields auf Case
`First_Response_Time__c` (DateTime), `First_Response_Working_Mins__c` (Number 16,0),
`First_Response_Target_Missed__c` (Checkbox) — Name/Kollision geprüft gegen
`origin/master` (40ac174), alle drei kollisionsfrei. Write-once via `= null`-Filter im SOQL.

### ADR-4: Trigger-Logik (Pseudocode)
```
trigger CaseCommentFirstResponseTrigger on CaseComment (after insert):
    wrapper.afterInsert()  // isRunning-Guard (static Boolean), wie 421

Handler.processFirstResponses(Set<Id> commentIds):
    1. comments = [SELECT Id, ParentId, CreatedById, CreatedDate FROM CaseComment
                   WHERE Id IN :commentIds]
    2. caseIds  = unique(ParentId)
       cases    = [SELECT Id, CreatedById, Kundenstatus__c,
                        First_Response_Time__c, First_Response_Working_Mins__c,
                        First_Response_Target_Missed__c
                   FROM Case WHERE Id IN :caseIds
                     AND First_Response_Time__c = null]      // Write-once
    3. bhId = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1]
    4. for cc in comments:
         c = cases.get(cc.ParentId);  if (c == null) continue;      // schon gesetzt
         if (cc.CreatedById == c.CreatedById) continue;            // Kunde zählt nicht (AC4)
         ms   = BusinessHours.diff(bhId, c.CreatedDate, cc.CreatedDate);
         mins = Integer.div(ms, 60000);
         target = (c.Kundenstatus__c == 'Premium') ? 60 : 240;      // PO-Werte, Leer=Standard
         c.First_Response_Time__c          = cc.CreatedDate;
         c.First_Response_Working_Mins__c  = mins;
         c.First_Response_Target_Missed__c = mins > target;
    5. if (toUpdate nonempty) update toUpdate;    // 1 DML pro Batch
```

**Governor-Limits (Batch 200):** SOQL 3/100 · DML 1/150 · kein SOQL-in-Loop ·
CPU < 500 ms. `BusinessHours.diff` ist eine platte Plattform-Klasse, kein governor-relevant
er Hotspot in dieser Volumen.

**Known limitation (Doku-Vermerk, kein Bug):** Bestands-Cases, die vor dem Deploy
kommentiert waren, erhalten ihren Wert beim **nächsten** Kommentar (mit deren Zeitstempel)
— nicht rückwirkend auf den ursprünglichen ersten. Rebuild-Only if PO verlangt (Open
Decision #4). Kein `*Rebuilder` in der Baseline.

### ADR-5: BusinessHours „Default“ = 24/7 — AC7 ist damit bauartbedingt unerfüllbar
Org-Fakt (SOQL + self-measured 2026-09-21): `Default`, IsActive, **00:00–00:00 an allen
7 Tagen**, TZ `America/Los_Angeles`. Es gibt also **keine** arbeitsfreie Zeit:
`diff()` liefert Kalenderminuten (die gemessenen 3780 bestätigen das).

Konsequenzen:
1. **AC7** („0 Arbeitsminuten über Nacht/Wochenende“) ist mit der aktuellen Org-Konfiguration
   **nicht testbar** — ein Test dieser Behauptung wäre grün-falsch. Der AC7-Apex-Test prüft
   stattdessen: 1 Comment an einem Wochenende → `mins == Kalenderminuten(Case→Comment)`
   (assert gegen explizit berechneten Wert, nicht gegen 0). Nach Org-Setup S1+S2 (AC11)
   gilt AC7 wie in der PO-Spezifikation.
2. **BusinessHours ist kein Source-Artefakt**: `sf project retrieve start -m "BusinessHours:
   Default"` ergibt `RegistryError` („Unknown metadata type: BusinessHours:Default“ — nicht
   in der SDR-Registry); SDR-Deploy-Probe hatte sie nie mitgeführt. Konfiguration = Setup,
   Read-back = SOQL.
3. PO beschreibt eine „Flow-WorkWeek“; die Org hat **0 Flows** und die klassische
   BusinessHours — Org-Fakt siegt (Dokumentation, kein Blocker für den Build).

### ADR-6: FLS — PS ohne Objekt-CRUD, Profil-Vor-Lock, Negativ-Test USER-Modus (421-Folge)
- `SCRUM424_FirstResponse_Read`: 3 Felder read-only, **kein** `objectPermissions`-Block
  (House-Form, identisch zu SCRUM421).
- **Vor dem FLS-Test:** Standard-Profil der Test-Org für die 3 Felder auf **Read (kein
  Edit)** verriegeln (Setup → Profiles → Field Security). Fehlt dieser Schritt, ist der
  Negativ-Test rot, weil das Profil Edit grantet (421 Cycle-1: 2 rote Tests, 1 Runde
  Verlust). Das PS *entziehen* kann die PS nicht — die Lücke schließt nur der Profil-Lock.
- Negativ-Test: `System.runAs` + `QueryingContext.USER`-Modus bzw. `AccessLevel.USER_MODE`
  — sonst läuft der Test im Systemmodus und ist bauartbedingt grün.
- PS-Zuweisungs-Read-back: `PermissionSetAssignment`-COUNT + 1 Feld-Read durch eine
  Session mit PS (Developer-Handoff-Pflicht).

---

## Org-Setup-Schritte (Source-unabhängig, Read-back obligatorisch)

| # | Schritt | Org | Read-back | Blockiert |
|---|---|---|---|---|
| S1 | BusinessHours „Default“ → TZ `Europe/Berlin` (AC11) | Test **und** Prod (DevOps) | SOQL `SELECT TimeZoneSidKey FROM BusinessHours WHERE IsDefault` | AC11, AC7 (eigentliches Semantik) |
| S2 | BusinessHours „Default“ → echte Tageswerte (PO-Werte, z. B. Mo–Fr 08–17) | Test **und** Prod | SOQL der 7 Tagesfelder | AC7 |
| S3 | Profil `Standard` → 3 neue Felder auf Read-only | Test **und** Prod (DevOps) | FLS-Negativ-Test (AC10) | AC10 |
| S4 | Report-Spalte `First_Response_Working_Mins__c` → Aggregation „Average“ | Test **und** Prod | AC9-Auslesung | AC9 (Durchschnitt) |

**Reihenfolge:** S1+S2 **vor** AC7/AC11-Tests. S3 **vor** AC10-Apex-Test. S4 **vor** AC9-E2E.
Jeder Schritt: Ausführen → Read-back ausführen → Ergebnis in den Handoff-Kommentar.
Solange S1+S2 offen: alle Tests liefern Kalenderminuten (nicht 0 über Nacht/Wochenende) —
das ist korrektes Verhalten auf 24/7, kein Bug.

---

## Artefakte

```
force-app/main/default/
├── objects/Case/fields/
│   ├── First_Response_Time__c.field-meta.xml          (DateTime, required=false, helpText)
│   ├── First_Response_Working_Mins__c.field-meta.xml  (Number 16,0)
│   └── First_Response_Target_Missed__c.field-meta.xml (Checkbox)
├── triggers/CaseCommentFirstResponseTrigger.trigger
├── classes/
│   ├── CaseCommentFirstResponseTrigger.cls   (Wrapper + static isRunning-Guard, 421-Form)
│   ├── CaseCommentFirstResponse.cls          (Handler, ADR-4)
│   └── SCRUM424FirstResponseTest.cls         (Apex-Test, ADR-6, AC-Matrix unten)
├── permissionsets/SCRUM424_FirstResponse_Read.permissionset-meta.xml  (3× fieldPermissions, nur Read)
├── layouts/Case-Case Layout.layout-meta.xml  (Insertion s.u.)
└── reports/Service/Erstreaktionszeit_Pro_Servicebereich.report-meta.xml

manifest/package.xml  (Einträge + apiVersion 62.0)
```

**Layout-Insertion (exakt):** neue Sektion „Erste Reaktion“ — nach der SCRUM-421-Sektion
„Zuordnung“, vor „System Information“, `<style>OneColumn</style>`, 3 Felder `Readonly`
(Same pattern as "Zuordnung": Edit für 421-Eingabefelder, Readonly für errechnete — hier
alle Readonly, es ist ein System-Ergebnisfeld).

**Report (Haus-Form `Ueberfaellige_Faelle`):** `reportType=CaseList`, Summary:
- `groupingsDown`: `Case.Servicebereich__c` (Asc)
- `columns`: `CASE_NUMBER` (token — Standardfelder als Token, kst. `Case.X`),
  `Case.First_Response_Working_Mins__c` (später Average via S4),
  `Case.First_Response_Target_Missed__c`
- `filter`: `Case.First_Response_Time__c` `notEqual` (leer) — nur Cases mit gesetzten Werten
  (House-Filter-Form: `<filter><criteriaItems><column>..</column><operator>..</operator>..</criteriaItems></filter>`)
- Record Count je Gruppe kommt automatisch mit Summary

**Deploy-Sequenz:**
1. 3 Felder (2 SOQL-Felder des Triggers müssen existieren)
2. Trigger-Stack + PS (PS-Zuweisung + Read-back s. ADR-6)
3. Layout + Report
Test-Lauf: `--test-level RunSpecifiedTests --tests SCRUM424FirstResponseTest`.
API-Version für sämtliche Metadaten 62.0.

## Sharing/OWD: keine Änderung (PO-bestätigt). Kein Trigger auf Case selbst (Kein Re-Entry).

---

## Open Decisions (PO)
| # | Frage | Blockierend |
|---|---|---|
| 1 | Bestätigung Zielwerte: Standard **240 min (4 h)**, Premium **60 min (1 h)** — wie im Entwurf angenommen | Nicht blockierend (in Code einstellbar, 1 Zeile) |
| 2 | S2: konkrete Tageswerte + Feiertage für „Default“ (z. B. Mo–Fr 08:00–17:00, keine Feiertage) — ohne PO-Entscheid bleibt AC7 auf Kalenderminuten | Blockiert AC7-Semantik, nicht den Build |
| 3 | Kundenstatus 'Premium' vs. andere Werte: alles außer 'Premium' = Standard? | Nicht blockierend |
| 4 | Bestands-Cases: Rebuild nötig (ältester nicht-Ersteller-Comment als 1. Reaktion)? Baseline: nein, nächster Comment setzt (Known limitation) | Nur falls PO ja sagt → `*Rebuilder` + 1 Apex-Test |

---

## AC → Beleg-Artefakt (Reviewer-Matrix)

| AC | Test | Artefakt / Vorbedingung |
|---|---|---|
| AC1 Premium, Ziel erreicht | Apex | `SCRUM424FirstResponseTest.test_AC1_Premium_InTarget` |
| AC2 Standard, Ziel **verfehlt** | Apex | `test_AC2_Standard_TargetMissed` |
| AC3 Kundenstatus leer = Standard | Apex | `test_AC3_Blank_TreatedAsStandard` |
| AC4 Kommentar des Erstellers zählt nicht | Apex | `test_AC4_Creator_Comment_Ignored` |
| AC5 Write-once (2. Comment ändert nichts) | Apex | `test_AC5_WriteOnce_SecondCommentNoChange` |
| AC6 Wiedereröffneter Case: Feld bleibt gesetzt | Apex | `test_AC6_Reopen_NoOverwrite` |
| AC7 Wochenende → im 24/7-Fall: Kalenderminuten | Apex | `test_AC7_CalendarMinutes_Under247` (assert == explizit berechnet); nach S1+S2: E2E-Spec `tests/e2e/SCRUM-424.spec.ts` für die echten 0-Min-Fälle |
| AC8 Bulk 200 Comments on 20 cases | Apex | `test_AC8_Bulk_200` (assert Limits im Testlog) |
| AC9 Report gruppiert nach Servicebereich, Average + Miss-Rate | E2E | `SCRUM-424.spec.ts` (Report aufrufen, Gruppen auslesen); Vorbedingung S4 |
| AC10 FLS: ohne PS kein Read, mit PS Read, kein Write | Apex, USER-Modus | `test_AC10_FLS_NoReadWithoutPS_ReadOnlyWithPS`; Vorbedingung S3 |
| AC11 TZ = Europe/Berlin | Org-Read-back | SOQL in Testklasse (assert `TimeZoneSidKey == 'Europe/Berlin'`); Vorbedingung S1; DevOps wiederholt in Prod |

---

## Test-Org-Hygiene (Vermerk)
3 Probe-Klassen aus der Architektur-Phase liegen in der Test-Org: `SCRUM424_ProbeObj`,
`SCRUM424_ProbeRunner`, `SCRUM424_ModProbe` (in `@IsTest`-Klassen verpackt, nicht aktiv,
deploy-behoben). Org-Delete ist verboten — sie bleiben, bis die Org purged wird. Kein
Einfluss auf Deploy oder CI. DevOps kann sie beim Release-Deploy ignorieren (stehen nicht
im Manifest).

---

## Für den Developer — Kurzfassung
1. **3 Felder** deployen (Phase 1), Manifest `apiVersion 62.0`.
2. **Trigger + 2 Klassen + PS** deployen (Phase 2). ADR-4 exakt, 420/421-Guard-Form.
3. **PS zuweisen** (Target-Org-User + menschlicher Test-Account) + `PermissionSetAssignment`
   Read-back mit ins Handoff.
4. **Org-Setup S3** (Profil-Lock) **vor** AC10-Testlauf; **S1+S2** **vor** AC7/AC11; **S4** **vor**
   AC9. Jeder Schritt mit SOQL/UI-Read-back dokumentieren.
5. **Layout + Report** deployen (Phase 3), Report-Spalte per S4 auf Average.
6. **Apex-Bestanden:** AC-Matrix, USER-Modus für AC10, `--test-level RunSpecifiedTests --tests
   SCRUM424FirstResponseTest`.
7. **Kein** `%`-Operator in Apex (→ `Math.mod`), **keine** `ServicePresence`/`WorkingHours`
   (existieren nicht — ADR-2), **keine** eigene Wochentag-/TZ-Berechnung (die macht `BusinessHours.diff`).

*Design abgeschlossen — Build-ready.*
