# SCRUM-436 — Notizen (developer-agent, 2026-10-02)

Harterkämpfte Befunde aus der Implementierung — alles org-verifiziert, nichts geraten.

## Apex-Date/DateTime-Primitives (apiVersion 62.0, org-verifiziert via `sf apex run`)
- `DateTime.newInstance(y, mo, d, h, min, sec)` — 6-arg **ohne ms** ✓. 7-arg und 6-arg-`new DateTime(...)` existieren NICHT.
- `Date.valueof('yyyy-MM-dd')`, `Date.daysBetween`, `Date.addDays`, `Math.mod(Long,Long)` ✓.
- Existieren NICHT: `new Date(y,m,d)`, `Date.newInstance`, `Date.dayOfWeek()`, `Date.daysSinceEpoch()`, `Date.compareTo`, `%`-Operator.
- Apex-Reservierte Parameter: `from`, `to` (nicht als Bezeichner).

## Plattform-Befunde
- `Database.Batchable<SObject>` + `execute(List<Case>)` — `<Case>` matcht `QueryLocator` (= `Iterable<SObject>`) nicht. House: `AccountReactivationBatch`.
- `Database.executeBatch(b)` deserialisiert `b`: Stateful-Counter des lokalen Objekts bleibt 0 im Test. Assertions immer auf Org-State (SOQL), nie auf Instanz-Counter.
- **`Test.startTest()`/`Test.stopTest()` = genau EINS pro Test-Methode.** Zweiter `startTest` wirft `System.FinalException: Testing already started` (gemessen, Run 707WU00001LeuT9). Mehrere Batches in ein Fenster packen — Sequenz bleibt, Flush am `stopTest`.
- `Database.QueryLocator` + `update toFlag` (konditionales Bulk-DML) bulk-safe.
- `Limits.getQueries()` ist das house-Idiom. `LIMITS.getSoqlQueries()` existiert nicht.
- PS-Description: max 255 Zeichen.

## Org-Validierung auf Case (SCRUM-434)
- `Ursache_PflichtBeiGeschlossen`: geschlossener Case braucht **Custom-Feld `Ursache__c`** (Picklist, z. B. `TechnischerFehler`), NICHT Standard-`Reason`.
- FLS für `Ursache__c`: einzig PS `SCRUM434_Ursache` (FieldPermissions 1 Zeile, IsOwnedByProfile=false). Standard-User-Profil kein Profil-FLS → runAs-Standard-User kann das Feld nicht schreiben.
- Konsequenz für Tests: Closed-Cases als negativen Filter-Kontrollfall im **System-Modus** pflanzen (Owner/FLS für die Assertion irrelevant).

## FLS der eigenen Reminder-Felder
- PS `SCRUM436_CaseReminder` (Lesen, Layout) + `SCRUM436_CaseReminderSystem` (Write für Batch-Executor).
- IDs: `0PSWU00000WYTrZ4AX` / `0PSWU00000WYTra4AH`. Beiden an CLI-User `devops-agent@cline.test` (User `005WU000017tEKLYA2`) via `PermissionSetAssignment` zugewiesen — **Deploy ≠ Zuweisung**.
- Read-back nach Zuweisung: `PermissionSetAssignment` 2 Zeilen; SOQL der Session liest die Felder.

## Deploy-Stufe
- `sf project deploy start -o Test-Org -m "ApexClass:Name"` — `-m` ist `<Typ>:<Name>`, **kein Dateipfad** (Pfad → `ComponentSetError: No source-backed components`).
- Reihenfolge: Felder zuerst, dann Layout/PS/Referenzierer (sonst `no CustomField named ... found`).
- Manifeste: `manifest/scr436-phase1-fields.xml`, `phase2-referencing.xml`, `apextests.xml` (apiVersion 67.0 im Manifest, 62.0 in den Apex-Meta-Dateien — house-Konvention).

## Statuspicklisten (Case)
- Status: `New / Working / Escalated / Closed`. **„Warten auf Kunde" existiert NICHT** → PO-Offenpunkt #1, `SUSPENDED_STATUSES` Default leer (ADR-4).
- Priority: `High / Medium / Low` (Default Medium).

## Tests
- 10/10 grün, Run `707WU00001LfJyz`. Coverage 89,6 % gesamt (Service 94 %, Config 88 %, Batch 84 %).
- Coverage holen: `sf apex get test -o Test-Org -i <runId> -c -d <dir>` → `test-result-codecoverage.json` (per-Klasse `totalCovered`/`totalLines`).
- `sf apex run test` gibt `result.testRunId` zurück (nicht `jobId`); Pollen via `sf apex get test -i <runId>` — das Ergebnis liegt unter `result.summary.outcome` und `result.tests[]`.
