# SCRUM-403 — Kontakt: Datum des letzten Anliegens + Dauer seitdem

**Status:** Freigegeben für Implementierung (Architect). **Autoritative Build-Spec** — diese Datei ist die
Einzig-Wahrheit für Names, Pfade und XML; Jira-Kommentare dürfen bei Markup-Artefakten abweichen (bekannter
Jira-Konverter-Vorfall: doppelte Unterstriche → Bold). Der Developer baut von hier.

**Ticket:** [SCRUM-403](https://meerwaisosmani.atlassian.net/browse/SCRUM-403) (Sprint 68)
**Entwurf:** architect-agent, 2026-09-09

---

## 1. Ziel

Service-Mitarbeiter sehen am Contact das Datum des jüngsten zugeordneten Cases (offen **und** erledigt) plus eine
menschenlesbare Dauer («heute» / «vor N Tagen» / «vor M Monaten») — automatisch gepflegt, für niemanden manuell
änderbar, rückwirkend für den Bestand gefüllt.

## 2. ADR

### ADR-1: Apex (Trigger + Batch) statt Flow / Roll-Up / LWC

Entscheidung: **Apex**, nach dem bewiesenen Muster SCRUM-365/367 («Offene Fälle»).

| Option | Bewertung |
|---|---|
| **Apex-Trigger (before/after) + Batch** | **Genommen.** Exakt das SCRUM-365/367-Muster im Repo: eine Aggregate-Query zählt neu (hier: `MAX(CreatedDate)` statt `COUNT()`), nur veränderte Contacts werden geschrieben (no-op-Schutz gegen Trigger-Loops). Deckt alle 8 Akzeptanzszenarien nativ, inkl. Löschen (Case-Delete feuert den Trigger) und Umbuchung (alter + neuer Contact werden re-rechnet). |
| Roll-Up Reporting / Master-Detail | **Verworfen.** Case–Contact ist kein Master-Detail; Roll-Up-Reporting braucht eine eigene Roll-Up-Def + eine 2. Stufung für die Dauer und liefert keine deutschen Textwerte. |
| Flow (Record-Triggered) | **Verworfen.** Flow hat wiederholt Deploy-/Schema-Validierungsprobleme gemacht (Haus-Regel); zudem ist eine Lookup-Aggregation pro Contact in einem Flow fragiler als eine GROUP-BY-Query. |
| LWC mit eigener Aggregation | **Verworfen.** Kein persistenter Wert → AC «Listenansicht filterbar/sortierbar nach Datum» (PO) und Report-Kompatibilität unmöglich; N-1-Problem im List View. |

### ADR-2: Getriggertes Feld + Formel statt zwei Getriggerten Feldern

`Last_Case_Date__c` ist das einzige **getriggerte** Feld (Date). `Time_Since_Last_Case__c` ist eine
**Text-Formel** über `Last_Case_Date__c` (Muster SCRUM-394 `Data_Quality__c`: `type=Text`, `required=false`,
**kein `length`-Element** — deploy-geprüft).

Begründung: die Formel kann nie vom Datum abdriften (gleicher ADR-Wie-SCRUM-370-Grund: keine Zweistellung),
braucht keine eigene DML und kein eigenes Trigger-Handling. `Last_Case_Date__c = null` → Formel liefert null
→ beide Felder leer (AC 2: kein «heute», keine 0).

### ADR-3: Zeitbasis `CreatedDate` (Fall-Aktivität), nicht `LastModifiedDate` oder `ClosedDate`

Anliegen = der Case wurde angelegt. `CreatedDate`:
- ist bei Insert **immer** gesetzt → AC 4 (neues Anliegen aktualisiert sofort),
- ändert sich bei Umbuchung nicht mit → AC 6 (alter Contact fällt exakt auf den vorherigen jüngsten zurück),
- ist bei gelöschten Cases irrelevant → AC 5 (neu gezählt aus dem, was übrig ist).

`LastModifiedDate` würde jede Status-Änderung/Notiz-Bearbeitung eines alten Cases fälschlich als «neues
Anliegen» anzeigen. `ClosedDate` ist für offene Cases NULL und in der Test-Org per UI-API nicht DML-schreibbar.
**Folgerichtig ist die Relevanzprüfung beim Update `ContactId`-Änderung nur** (Status-Wechsel spielt keine Rolle
für dieses Feld — anders als beim SCRUM-365-Trigger, der den Status für die Offene-Zählung braucht).

### ADR-4: NULL-Semantik, exakt getrennt von SCRUM-365

| Field | NULL bedeutet | Kontakt ohne Cases zeigt |
|---|---|---|
| `Open_Cases_Count__c` (SCRUM-365) | «nie gezählt» | 0 |
| `Last_Case_Date__c` (SCRUM-403) | «kein Case je vorhanden» | NULL (leer) |

`Last_Case_Date__c` wird **niemals** auf 0/1900/TODAY normalisiert. mustWrite-Bedingung pro Contact:
`currentDate == null ? (newDate != null) : (newDate != currentDate)` — NULL → Wert schreiben, Wert → nur bei
Änderung, NULL → NULL schreiben (kein no-op-Problem, weil beide NULL). Kontakte ohne Cases bleiben dauerhaft leer.

### ADR-5: «Wie lange her» — Textformel, deutsche Anzeige, feste Abstufung

Formel (Salesforce-Formel, **keine Infix-`AND`** — nur Funktionsform `AND(a,b,c)`):

```
IF(ISBLANK(Last_Case_Date__c), null,
  IF(TODAY() = Last_Case_Date__c, "heute",
    IF(TODAY() - Last_Case_Date__c <= 1, "gestern",
      IF(TODAY() - Last_Case_Date__c <= 30, "vor " & TEXT(TODAY() - Last_Case_Date__c) & " Tagen",
        "vor " & TEXT(ROUND((TODAY() - Last_Case_Date__c) / 30, 0)) & " Monaten"))))
```

Regeln: null → leer · 0 Tage → «heute» · 1 Tag → «gestern» · 2–30 Tage → «vor N Tagen» · > 30 Tage →
«vor N Monaten» mit Monats-Runden auf ganzzahlige Vollmonate (31–60 → «vor 2 Monaten», 61–… → «vor M
Monaten»). 30-Tage-Näherung, dokumentiert als Akzeptanzentscheidung — der PO hat die Abstufung «heute / vor N
Tagen / vor M Monaten» gefordert, nicht Kalendarmonate.

### ADR-6: Bestandsmigration — Batch im SCRUM-367-Muster

`LastCaseDateRebuilder`: `Database.Batchable<Contact>` + `Database.Stateful`, QueryLocator über **ALLE**
Contacts (kein `LastModified`-Filter → AC 3), Batch-Größe 200, pro Chunk ein Aufruf des **bestehenden** Handlers
`LastCaseDateTrigger.recompute(ids)` — eine einzige Definition der Logik, exakte Neu-Berechnung statt Delta,
kurze DML-Transactions ohne `SELECT FOR UPDATE`. Idempotent (2. Lauf korrigiert 0).

**Auslösung:** `Database.executeBatch` aus der Developer Sandbox bzw. via Apex-Execute im Setup — **keinerlei
UI-Auslösung** (kein Custom Button), und **keine** Lauf-Log-Zeile (`CaseRebuildRun__c` gehört zu SCRUM-365 und
wird NICHT für diese Felder weiterverwendet). Rationale: die 8 ACs verlangen keinen sichtbaren Korrekturlauf;
ein zweiter Button + zweite Log-Semantik am Contact-Layout würde Service-UI-Lautstärke für einen
einmaligen Einoff-Shot erzeugen. Der DevOps-Agent führt den Batch beim Release aus (Org-Schritt, §8).

### ADR-7: FLS über Permission Set, nie Profile

Neues PS `SCRUM403_LastCaseDate`: Read = true auf beiden Feldern, Editable = false. Kein Update-Right für
jemanden — System-Modus-Trigger/Batch-Schreibzugriffe umgehen FLS (exakt die Begründung aus
`SCRUM365_OpenCasesCount`, die wir beibehalten). Objekt-Zugriff Contact: bleibt wie gehabt (kein neuer
ObjectPermission-Block nötig, das PS ist FLS-only wie SCRUM365).

## 3. Datenmodell (vor Implementierung festgeschrieben)

| API-Name | Label (deutsch, ohne Umlaute — Haus-Konvention) | Typ | Detail |
|---|---|---|---|
| `Last_Case_Date__c` | `Letztes Anliegen` | Date | `required=false`, `trackTrending=false`, `unique=false`, **kein defaultValue** (NULL bleibt NULL) |
| `Time_Since_Last_Case__c` | `Wie lange her` | Text-Formel | `required=false`, **kein `length`**, keine `precision`/`scale` (nur Number) |

PO-Vorschläge aus dem Ticket (`Letztes_Anliegen__c` / `Zeit_Zum_Letztem_Anliegen__c`) bewusst **nicht**
übernommen: API-Namen im Repo sind durchgehend Englisch; Labels tragen die deutsche Bedeutung.

## 4. Komponenten & Pfade (Developer baut exakt diese Dateien)

1. **Felder** (Phase 1, deploybar allein):
   - `force-app/main/default/objects/Contact/fields/Last_Case_Date__c.field-meta.xml`
   - `force-app/main/default/objects/Contact/fields/Time_Since_Last_Case__c.field-meta.xml`
   - Feld-Beschreibungstexte dürfen auf die Pflege-Logik verweisen (Muster `Open_Cases_Count__c`).

2. **Trigger** (Phase 2, referenziert Trigger-Klasse):
   - `force-app/main/default/triggers/LastCaseDateTrigger.trigger` + `-meta.xml`
   - `on Case (after insert, after delete, after update)`, `apiVersion 62.0`, `Active`.

3. **Handler-Klasse:**
   - `force-app/main/default/classes/LastCaseDateTrigger.cls` + `-meta.xml` — `public without sharing`,
     **statik-Methode** `recompute(Set<Id> contactIds)` (aufruf- und batch-kompatibel, Muster
     `CaseOpenCountTrigger.recompute`).

4. **Batch-Rebuilder:**
   - `force-app/main/default/classes/LastCaseDateRebuilder.cls` + `-meta.xml` — Batchable+Stateful,
     `start()` = `SELECT Id FROM Contact`, `execute()` = `recompute(ids)` pro Chunk, `finish()` no-op,
     statik `runOnce()` als Startpunkt (executeBatch + Rückgabe der Batch-Id).

5. **Layout** (Phase 3):
   - `force-app/main/default/layouts/Contact-Contact Layout.layout-meta.xml`: Abschnitt «Offene Faelle» erweitert
     — Spalte 1: `Open_Cases_Count__c` **und** `Last_Case_Date__c` (Readonly); Spalte 2: `Open_Cases_Rating__c`
     **und** `Time_Since_Last_Case__c` (Readonly). Beide neuen Items `<behavior>Readonly</behavior>`.

6. **Permission Set:**
   - `force-app/main/default/permissionsets/SCRUM403_LastCaseDate.permissionset-meta.xml` — Read-only FLS für
     beide Felder, `hasActivationRequired=false`, Label `SCRUM403_LastCaseDate`.

7. **Manifeste** (House-Layout, 3 Deploy-Stufen):
   - `manifest/scr403-phase1-fields.xml` — 2 CustomFields
   - `manifest/scr403-phase2-referencing.xml` — ApexTrigger + 2 ApexClasses
   - `manifest/scr403-phase3-apextests.xml` — Test-Klassen
   - Layout + PS in Phase 3 oder eigener Phase 4 — Developer entscheidet, sofern Deploy-Reihenfolge sauber.

8. **Apex-Tests** (PR-Gate, Muster `SCRUM367OpenCasesRebuildTest` / `SCRUM382CustomerSinceDaysFlsTest`):
   - `force-app/main/default/classes/SCRUM403LastCaseDateTest.cls` + `-meta.xml`
   - `force-app/main/default/classes/SCRUM403LastCaseDateFlsTest.cls` + `-meta.xml`

9. **E2E** (List-View-AC):
   - Test-Spec `tests/e2e/` nach Muster `SCRUM-378_lead-nachfassliste.spec.ts`: Classic-/Lightning-Record-View
     + List-View-Filter nach `Letztes Anliegen`.

**Nicht anfassen:** `CaseOpenCountTrigger`/`CaseOpenCountRebuilder` bleiben unverändert (anderes Feld, andere
Relevanzprüfung). Ein neuer Trigger auf derselben Object ist korrekt und nötig — Trigger-Fanout ist in
Salesforce Standard.

## 5. Interface (Apex)

```apex
public without sharing class LastCaseDateTrigger {
    // Neuberechnung: pro Contact MAX(CreatedDate) über ALLE zugeordneten Cases
    // (offen UND geschlossen). Aggregate GROUP-BY = 1 SOQL.
    // 2. SOQL: aktueller Last_Case_Date__c der betroffenen Contacts.
    // 3. DML: update ONLY mit NULL-Semantik aus ADR-4.
    // Governor: 1 Aggregate-SOQL + 1 SOQL + 1 DML pro Batch(200) — null in Loop.
    public static Integer recompute(Set<Id> contactIds);   // -> Anzahl geänderter Contacts
}
```

Query (Kern von `recompute`):

```sql
SELECT ContactId, MAX(CreatedDate) dt
FROM Case
WHERE ContactId IN :contactIds
GROUP BY ContactId
```

Trigger-Relevanz (= der einzige Unterschied zu `CaseOpenCountTrigger`):
- **insert:** `c.ContactId` aus `Trigger.new` (immer relevant — jedes neue Anliegen verschiebt das Datum).
- **delete:** `c.ContactId` aus `Trigger.old` (jüngster Case weg → Rückfall; einziger Case weg → NULL).
- **update:** `cNew.ContactId != cOld.ContactId` **nur**; dann alter **und** neuer Contact (Umbuch-AC 6).
  Status-/Datum-Änderungen eines bestehenden Cases sind NICHT relevant (ADR-3).

## 6. Sharing / Governor Limits

- **Sharing:** kein Impact. Felder vererben die Sicht des Contact; keine OWD-, Rollen- oder
  Sharing-Regel-Änderung. (Ticket-PO-Festlegung übernommen, dokumentiert hier als «no impact».)
- **Trigger-Fanout:** 2 Trigger auf Case (`CaseOpenCountTrigger`, `LastCaseDateTrigger`) — beide bulkified,
  beide mit no-op-DML-Schutz; keine Zyklen (beide schreiben Contact, nie Case).
- **Governor:** Budget aus ADR-2/§5, identisch zum bewiesenen SCRUM-365-Pattern (200-er Batches).

## 7. Abdeckung der 8 Akzeptanzszenarien → Testartefakte

| AC | Beweis (Apex-Test-Methode, Vorlage) |
|---|---|
| 1 (Datum + Dauer, Case offen oder erledigt) | `existingCase_showsDateAndHumanDuration` — Case Status «New» und «Closed» je 1 Kontakt; Assert `Last_Case_Date__c == max(CreatedDate)` + `Time_Since_Last_Case__c = 'heute'` (gleicher Tag) |
| 2 (Neukunde leer) | `contactWithoutCases_staysBlank` — kein «heute», keine NULL-normalisierte 0; **beide Felder null** |
| 3 (Bestand rückwirkend) | `batchRun_healsAllContacts` — Bestands-Contacts mit Cases vor dem Trigger-Deploy simuliert (wie SCRUM-367: Feld nach Insert manuell NULL, dann `LastCaseDateRebuilder.runOnce()` + `Test.stopTest()`); **2. Lauf idempotent (geändert = 0)** |
| 4 (neues Anliegen → Datum rückt nach) | `newCase_updatesToYoungest` — altes Case (CreatedDate backdated), neues Case insert → Feld = neue CreatedDate |
| 5 (Löschen des jüngsten → Rückfall) | `youngestDeleted_fallsBack` — 2 Cases, jüngstes löschen → Datum = älteres; letztes löschen → NULL (beide Felder) |
| 6 (Umbuchung) | `reassign_movesDateAndFallsBack` — Case von A → B: B trägt das Datum, A fällt auf seinen vorherigen jüngsten (oder NULL) zurück |
| 7 (read-only) | Fls-Test `SCRUM403LastCaseDateFlsTest`: ohne PS kein Zugriff, mit PS readable=true/editable=false auf **beiden** Feldern (Vorbild `SCRUM382CustomerSinceDaysFlsTest`) |
| 8 (Sichtbar in Lightning + Classic) | Repo = Classic-Layout + FLS (PR-Gate: E2E-Record-View + List-View-Filter). **Lightning-FlexiPage: Org-Schritt (§8) — FLS ohne App-Builder-Platzierung reicht NICHT** |

**Zur Review:** «live run + read-back» ist Evidenz, **kein** Test — jedes AC braucht die Apex-Methode (oder die
E2E-Spec bei AC 8).

## 8. Deploy-Phasen & Org-Schritte

**Deploy (Developer/DevOps, Reihenfolge):** Phase 1 Felder → Phase 2 Trigger+Klassen → Phase 3 Tests (+
Layout+PS). Jede Phase: `sf project deploy validate` (Test-Level je Manifest: Felder `NoTestRun`, Referenzierung
**RunSpecifiedTests eigene Klassen** — AGENTS.md-Guardrail, Test-Org erlaubt 1 breiten Apex-Lauf gleichzeitig)
→ `sf project deploy start`.

**Org-Schritte (blocken die Implementierung NICHT — Owner @devops-agent beim Release):**
1. `LastCaseDateRebuilder.runOnce()` ausführen + verifizieren (`sf data query` über `Contact` WHERE
   `Last_Case_Date__c = null` → nur Contacts **ohne** Case verbleiben).
2. **Lightning-FlexiPage** Contact: beide Felder in den Service-Sichtbereich legen — Classic-Layout im Repo,
   Lightning liegt in der Org (bekanntes Repo-Limit, siehe SCRUM-367/378-Befund).
3. PS `SCRUM403_LastCaseDate` an Service-/Leitungs-User aktivieren (Assignment ist Org-Pflege, nicht Source).

## 9. Offene Punkte (nicht blockierend)

- [ ] Lightning-Platzierung + Batch-Lauf beim Release → **@devops-agent** (Org-Schritt §8).
- [ ] E2E-List-View-Filter (AC 8): Tester prüft **beide** UIs — Classic aus dem Repo-Layout, Lightning nach
      FlexiPage-Platzierung → **@tester-agent**.
