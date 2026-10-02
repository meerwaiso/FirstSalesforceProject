# SCRUM-436 — Architektur-Design: Automatische Wiedervorlage für offene Cases

**Ticket:** SCRUM-436 · **Status:** freigeben → Developer-Agent · **Author:** Architect-Agent
**Repo-Referenz:** `origin/master @ 361a266` (Design gegen diesen Commit erstellt)
**Kein Org-Zugriff des Architects** — alle Org-Fakten unten wurden **vorher in Test-Org `00DWU00000oibVJ2AY` (Alias `Test-Org`) live gelesen** (s. „Org-Belege").

---

## Ziel

Ein Case, der im bearbeiteten Status länger als eine vom PO festgelegte Werktag-Zahl (Standard 3, High 1) ohne relevante Bearbeitung bleibt, wird automatisch per nächtlichem Batch mit `Wiedervorlage erforderlich = Ja` markiert; jede relevante Bearbeitung setzt die Uhr zurück und zählt die Wiedervorlage hoch.

---

## Mechanik — Apex, nicht Flow (ADR-1)

**APEx** für das gesamte Timing. Begründung:
- Logik ist NICHT deklarativ löbar: arithmetische Werktagsdifferenz, Prioritäts-Branching, Idempotenz (nur ungeflaggte Cases), Bulk-Skalierung über den offenen Bestands (AC9). Das ist exakt „branching complexity + bulk processing + likely to evolve" → Apex-Default.
- Flow-Default-Verbot im Team: Flows scheitern hier wiederholt an Deploy/Schema-Validation. Ein Scheduled-Path-Flow mit Batch-Semantik über *alle* offenen Cases ist außerdem gar nicht idiomatic (Flow läuft pro Trigger, nicht nächtlich-über-den-Bestand).
- House-Patterns sind Apex: `AccountReactivationScheduler`+`AccountReactivationBatch` (SCRUM-388, nächtlicher Batch über den Bestands), `CaseReactionTrigger`+`CaseReactionHandler` (SCRUM-418, systemgepflegtes Read-only-Feld per Trigger geschrieben), `CaseCommentFirstResponseTrigger` (SCRUM-424, Staff-Kommentar über `CaseComment after insert`).

**Werktag = Mo–Fr, KEIN Feiertag, KEIN BusinessHours-Objekt (ADR-2):** Der PO definiert die Schwelle in *Kalender-Werktagen* (Mo–Fr ohne Feiertagslogik). Ich rechne das mit reiner Kalendertags-Arithmetik über `DayOfWeek` (`BusinessDayUtil.workingDaysBetween(start, now)` zahlt nur Mo–Fr-Tagwechsel im offenen Intervall). **Bewusst NICHT** das `BusinessHours`-Objekt — das wäre SRM-424-Arbeitsminuten mit TZ/Kopplung und hätte die CI-Drift-Gate-Sorgen der SCRUM-424-Historie neu aufgemacht. Für die PO-Spezifikation („Mo–Fr, kein Feiertag") ist die Kalendertags-Form die wörtlich korrekte und deploystabilere Wahl.

---

## Datenmodell — 4 neue Case-Felder

Alle 4 Felder: `required=false`, `unique=false`, read-only für Endbenutzer, systemgepflegt. API-Namen sind **kollisionsfrei** gegen `origin/master` geprüft (0 Treffer). Bewusst getrennt von den SCRUM-418-Feldern `Reactivation_Count__c`/`Last_Reactivation__c` (die zählen das *Wiederaufmachen geschlossener* Fälle — andere Semantik, Kollisionsgefahr vermieden).

| # | API-Name | Typ | Label (PO-Treue) | Default | Semantik |
|---|----------|-----|------------------|---------|----------|
| 1 | `Last_Relevant_Update__c` | DateTime | Letzte Bearbeitung | — (null) | Zeitstempel der letzten **relevanten** Bearbeitung (PO: „ausschließlich bei definierten relevanten Bearbeitungen gesetzt"). Bei Case-Erstellung = `System.now()`. |
| 2 | `Reminder_Due_Date__c` | DateTime | Wiedervorlage am | — (null) | Zeitpunkt, zu dem der Wiedervorlage-Lauf **ausgelöst** hat (Batch-`System.now()`). |
| 3 | `Reminder_Required__c` | Checkbox | Wiedervorlage erforderlich | `false` | `true` = fällig/ausgelöst, bis nächste relevante Bearbeitung. |
| 4 | `Reminder_Count__c` | Number(3,0) | Anzahl Wiedervorlagen | `0` | Zählt hoch, sobald eine ausgelöste Wiedervorlage durch Bearbeitung „abgearbeitet" wird. |

Feld-Meta-Template (house, SCRUM-418/424/398): `DateTime` als `Last_Reactivation__c`, `Checkbox` als `First_Response_Target_Missed__c`, `Number` als `Reactivation_Count__c` (siehe `force-app/main/default/objects/Case/fields/`). Genau die drei house-Formen übernehmen, `apiVersion` aus `sfdx-project.json` des Targets (aktuell 62.0).

### „Relevante Bearbeitung" = was setzt Feld 1? (ADR-3, Default + PO-Offen)

PO nennt ausdrücklich zwei Quellen; ich implementiere exakt diese zwei und markiere alles Weitere als PO-Offenpunkt #6:
1. **Status-Wechsel** auf dem Case (`old.Status != new.Status`) → setze `Last_Relevant_Update__c = now`.
2. **Mitarbeiter-Kommentar/Antwort** = qualifizierter `CaseComment`-Insert (`CreatedById != Case.CreatedById`, das SCRUM-424-Staff-Guard) → Parent-Case `Last_Relevant_Update__c = now`.

**Zurücksetzen + Zählen (PO-Regel 8, AC8):** Trifft eine relevante Bearbeitung ein, **während** `Reminder_Required__c == true`: zusätzlich `Reminder_Required__c = false` UND `Reminder_Count__c += 1`. Trifft sie auf ein ungeflaggtes Case: nur Feld 1 aktualisieren, Zähler bleibt (PO-AC4: „ohne dass gleich eine Wiedervorlage entsteht").

**`Reminder_Due_Date__c` beim Zurücksetzen:** Default = **beibehalten** (Audit: letzter Auslöse-Zeitpunkt bleibt lesbar). PO-Offenpunkt #5 (beibehalten vs. leeren).

---

## Komponenten

### 1. `CaseReminderService.cls` (bulkified Core, `without sharing`)
Einziger Ort der Logik. Statische Methoden, house-Shape (1 SOQL + 1 DML pro Batch, 0 im Loop):
- `markRelevantWork(List<Case> touched)` — ruft die Trigger auf. Lädt für die betroffenen Case-Ids **einmalig** `SELECT Id, Last_Relevant_Update__c, Reminder_Required__c, Reminder_Count__c FROM Case WHERE Id IN :ids` (1 SOQL), setzt pro Case `Last_Relevant_Update__c=now` und das konditionale Zurücksetzen, schreibt **einmalig** `update toWrite` (1 DML). Idempotenz: `Reminder_Count__c` wird aus dem **DB-Stand** (nicht `Trigger.new`) inkrementiert — house-Pitfall SCRUM-418/365.
- **Re-Entry-Guard** `public static Boolean isReceiving = false;` (house: SCRUM-419 `isRecomputing`, SCRUM-421 `isRunning`). Der `CaseComment`-Pfad triggert ein Case-Update, das den Case-Trigger erneut feuert; das Flag macht genau diesen Re-Lauf inert (`try/finally` zurücksetzen). **Pfad-agnostisch** (UI, REST/CLI-Update, Batch) — exakt der SCRUM-419-Lesson-Schutz.
- `BusinessDayUtil.workingDaysBetween(DateTime from, DateTime to)` (oder eigene stat. Methode): zählt Mo–Fr-Tagwechsel im offenen Intervall `(from, to]`. Rein arithmetisch über `DayOfWeek`, TZ-agnostisch auf Tag-Ebene (nur das Kalendertag-Zeichen zähle ich, keine Stunden). Testbar per injiziertem `now`.

### 2. `CaseReminderTrigger.trigger` `on Case (before insert, before update)`
- **insert:** `Last_Relevant_Update__c = System.now()` (Uhr startet bei Eröffnung, PO-Regel 1/AC1). `Reminder_Required__c`/`Reminder_Count__c` bleiben Default (false/0).
- **update:** nur bei relevanter Benutzer-Änderung → `CaseReminderService.markRelevantWork(...)`. Re-Entry über `isReceiving` überspringt. Felder werden direkt auf `Trigger.new[i]` gesetzt (before-Trigger → **kein Extra-DML** für den Benutzer-Pfad).
- 0 SOQL/DML im Trigger selbst.

### 3. `CaseCommentReminderTrigger.trigger` `on CaseComment (after insert)`
House-Shape `CaseCommentFirstResponseTrigger` (static `isRunning`). Filter: `ParentId != null` **und** `CreatedById != Parent.Case.CreatedById` (Staff, nicht Kunde). Für die Parent-Case-Ids → `CaseReminderService.markRelevantWork` via `update` auf dem Parent (dieses Single-DML wird durch den Guard beim Re-Case-Trigger inert). 0 SOQL/DML im Trigger.

### 4. `CaseReminderBatch.cls` (`Database.Batchable<Case>, Database.Stateful`, `without sharing`)
Nächtlicher Lauf über **alle** relevanten offenen Cases (AC9). House-Shape `AccountReactivationBatch`:
- `start`: `Database.getQueryLocator('SELECT Id, Status, Priority, Last_Relevant_Update__c, Reminder_Required__c, Reminder_Due_Date__c, Reminder_Count__c FROM Case WHERE Status != 'Closed' AND Last_Relevant_Update__c != null')`. QueryLocator über den **Vollbestand** (house SCRUM-388, `without sharing`, 200er-Chunks, kurze DML-Transaction je Chunk) → keine Timeout-Gefahr bei großen Stocks (AC9).
- `execute(scope)`: je Case → **monitored?** (Status ∈ `MONITORED_STATUSES`, s. ADR-4) **und** `Reminder_Required__c == false` **und** `BusinessDayUtil.workingDaysBetween(Last_Relevant_Update__c, now) > threshold(Priority)` → in `toFlag`: `Reminder_Required__c = true`, `Reminder_Due_Date__c = now`. `threshold = (Priority == 'High') ? 1 : 3`. Einmaliger **Bulk-`update`** der geänderten Rows (Idempotenz: nur ungeflaggtes wird geflaggt → zweiter Lauf ohne Änderungen toucht 0 Rows, AC8/SCRUM-388-Idempotenz).
- `now` per `@testVisible`-Konstruktor injizierbar (`CaseReminderBatch(DateTime now, Integer batchSize)`), damit die AC-Arithmetik deterministisch testbar ist.
- `processed`/`flagged` Zähler + `finish`-Debug-Log (house-Shape).

### 5. `CaseReminderScheduler.cls` (`implements Schedulable`)
Nur Start des Batches, keine Logik (house `AccountReactivationScheduler`). **CRON `0 0 1 * * ?`** (01:00) — 02:00 = SCRUM-388, 03:00 = SCRUM-417, 06:00 = Opportunity-Overdue; **01:00 frei**.
> ⚠️ **Scheduled Jobs sind Laufzeit-Objekte, KEINE Metadata.** Der `System.schedule(...)`-Eintrag wird **nicht** per Deploy angelegt und muss in der Org gesetzt werden — sonst läuft der Code deployed aber NIE (house-Vermerk SCRUM-388). → **Org-Schritt, @devops-agent** (Test-Org beim Deploy, Prod-Org beim Release). Siehe „Offene Punkte".

### 6. Layout-Integration
`force-app/main/default/layouts/Case-Case Layout.layout-meta.xml` — 4 Felder in ein bestehendes `<fieldSection>` (house: SCRUM-418 legte `Reactivation_Count__c` + `Last_Reactivation__c` ein, Zeile ~185/189). Read-only-Display. (Lightning-FlexiPage liegt in der Org, nicht im Repo — Sichtbarkeit dort = FLS-Right des PS + App-Builder-Platzierung, **Org-Schritt @devops**, house-Pitfall „Auf allen Layouts".)

### 7. `CaseReminderConfig.cls` (zentrale Status-Definition, PO-Offenpunkt #1)
**Ein einziger Ort**, in dem die Status-Menge definiert ist — so bleibt die PO-Entscheidung (ADR-4) eine 1-Zeilen-Änderung:
```apex
public class CaseReminderConfig {
    // PO-Offenpunkt #1 — DEFAULT-Werte, bis PO bestätigt (s. Abschnitt).
    // Monitored = Uhr läuft; Suspended = keine Wiedervorlage; Closed = nie.
    public static final Set<String> MONITORED_STATUSES  = new Set<String>{ 'Working', 'Escalated', 'New' };
    public static final Set<String> SUSPENDED_STATUSES  = new Set<String>{ /* 'Warten auf Kunde' — PO muss Wert liefern/anzulegen */ };
}
```

---

## FLS / Permission Sets (ADR-5) — per PS, NIE per Profil

**Niemals Profil-Edit.** Zwei PS, house-Modell Read-PS + System-Write-PS (house: `SCRUM418_Reactivation` [Read] + `SCRUM388_...Write` [Write]):

1. **`SCRUM436_CaseReminder`** (Read, → **Service-Mitarbeiter**, alle mit Case-R):
   `readable=true, editable=false` auf **allen 4 Feldern**. Shape exakt `SCRUM418_Reactivation`. Liefert „nur R (systemgesetzt)" wie gefordert.
2. **`SCRUM436_CaseReminderSystem`** (Write, → **der nächtliche Batch-Executor / Automation-User**):
   `readable=true, editable=true` auf **allen 4 Feldern**. Shape `SCRUM388_AccountReactivationWrite`.

**Warum zwei PS (entscheidend für den Batch):**
- **Benutzer-Pfad (Trigger):** mein **Probe-Test `707WU00001LcArj`** (Test-Org) hat **empirisch belegt**, dass ein `Standard User` mit **nur Read**-FLS einen Statuswechsel vornehmen kann und der live-`CaseReactionTrigger` das Read-only-Feld **trotzdem** ohne FLS-Fehler schreibt. → Der editierende User braucht **kein** Write-PS. (Re-Entry/Failure wäre ein `FieldSecurityException` im Test gewesen — war es nicht.)
- **Batch-Pfad (nächtlich, System-Schedule-User):** läuft im Kontext eines *einzigen* Scheduled-Users. Ob der ohne Edit-FLS den `update` setzt, hat meine Probe **nicht** abgedeckt (anderer Kontext). House (SCRUM388) hat dafür exakt das `..._Write`-PS angelegt → **folge ich**. **Org-Schritt @devops**: `SCRUM436_CaseReminderSystem` an den Job-Executor zuweisen, dann **ein Feld durch eine echte Session mit diesem PS zurück-lesen** (house-Read-back, FLS-Regel „ein PS, das existiert, ist keins, das zugewiesen ist").

### Test-FPS-Absicherung (Pflicht, house `SCRUM418CaseReactionFlsTest`)
`SCRUM436CaseReminderFlsTest.cls`: Temp-User auf `Standard User` (keine FLS), **Precondition** `Case` object-level lesbar; **NEGATIV** ohne PS: alle 4 Felder `isAccessible()==false`/`isUpdateable()==false`; PS `SCRUM436_CaseReminder` zuweisen; **POSITIV** mit PS: `isAccessible()==true`, `isUpdateable()==false` auf allen 4 (Read-only). `System.runAs()` übt echte FLS (umgeht sie nicht).

---

## ADR-4 — Status-Mapping (DIE PO-Offene, blocking-for-Test)

**Org-Befund (live `Test-Org`, `sf sobject field get -s Case -f Status`):** `Case.Status` hat genau **4** Werte: `New`, `Working`, `Escalated`, `Closed`. Der PO-Status **„Warten auf Kunde" existiert nicht.**

Das blockiert **nicht** die Architektur — das Timing/FLS/Batch/Test-Grundgerüst ist komplett entworfen (s.o.) und der PO hat das Status-Konzept als „Offene Punkte" selbst eingeplant. Es blockiert **aber die Treue von AC5/AC6** (und Teil-AC4) und damit die Tester-Gültigkeit, **bis** der PO die Status-Menge festlegt.

**Konkrete Optionen für den PO (ich empfehle 1):**
1. **„Warten auf Kunde" als neuen `Case.Status`-Wert anlegen** (Org-Schritt @devops + Layout), dann `SUSPENDED_STATUSES = { 'Warten auf Kunde' }`. Klarest, PO-Treue. → **empfohlen**.
2. „Warten auf Kunde" auf einen **bestehenden** Wert mappen (welchen? keiner passt semantik-korrekt) — nur falls kein Wert neu angelegt werden soll.
- **Ebenfalls vom PO festzulegen:** Behandlung von `New` und `Escalated` (monitored oder nicht). Mein Default: `New` + `Escalated` = **monitored** (ein unarbeiteter neuer Case oder Eskalierte müssen ebenfalls erinnern) → `MONITORED_STATUSES = { 'New', 'Working', 'Escalated' }`; `Closed` = nie monitored.
- **Developer-Handhabung:** Der Developer baut gegen `CaseReminderConfig` mit den obigen **Default-Werten** und kann den Mechanismus sofort **unit-testen** (AC1–AC4, AC7–AC9 laufen Status-neutral, AC5/AC6 mit einem Platzhalter-Status). Vor Test **muss** der PO die reale Status-Menge in `CaseReminderConfig` fixieren; AC5/AC6 werden dann gegen den echten Wert gemappt. (So ist die „Erfindung" sichtbar und gated, nicht versteckt.)

---

## Governor-Limits (dokumentiert)
- **Trigger:** 0 SOQL, 0 DML (alle Felder in `before` direkt auf `Trigger.new`; CaseComment-Pfad = 1 Service-Aufruf).
- **Service:** exakt 1 SOQL + 1 Bulk-DML pro Batch, keine Queries im Loop, 200er-Safe. Idempotenz aus DB-Stand (house SCRUM-365/388/418).
- **Batch:** QueryLocator über den Bestand (keine `COUNT`-Explosion), 200er-Chunks, 1 Bulk-DML je Chunk; `workingDaysBetween` = reine CPU/Arithmetik (kein Governor-Risiko, kein `BusinessHours`-SOQL).
- **Re-Entry** durch stat. `isReceiving`-Flag (SCRUM-419) — kein Kaskaden-DML.

## Sharing-Modell
**Kein Impact** (PO: OWD/Sharing Rules/Rollen-Hierarchie bleiben unverändert). `without sharing` am Batch/Service ist **bewusst**: die nächtliche Zählung ist deterministisch über den gesamten offenen Bestand und unabhängig vom Sharing des Scheduled-Users — exakt house SCRUM-365/388/418. Umgeht `without sharing` **keine** FLS → das Write-PS (ADR-5) bleibt erforderlich.

## Integration über Clouds
Keine. Service-Cloud-only, keine Data-/Marketing-Cloud-Sync-Kopplung (PO: keine Abhängigkeit).

---

## Offene Punkte (Owner + Blockade-Einschätzung)

1. **[BLOCKINGS-FOR-TEST] @po-agent** — „Warten auf Kunde" + `New`/`Escalated`: Status-Menge fixieren (ADR-4, Option 1 empfohlen). Gated: **AC5, AC6, Teil-AC4**. Bis dahin baut Developer gegen `CaseReminderConfig`-Default, unit-testet, Tester wartet mit AC5/AC6.
2. **[non-blocking, @po-agent]** — Benachrichtigungsform: ich implementiere **feld-only** (AC verlangt exakt nur das Feld `Wiedervorlage erforderlich`). Task/E-Mail/Salesforce-Notification = Folge-Ticket.
3. **[non-blocking, @po-agent]** — Mo–Fr ohne Feiertag (PO hat das bereits gesagt): ich nutze Kalendertags-Arithmetik (ADR-2), **keine** `BusinessHours`. Bestätigung reicht.
4. **[non-blocking, @devops-agent] Org-Schritt:** `System.schedule`-CRON `0 0 1 * * ?` in Test-Org setzten (Test) / Prod-Org (Release). Ohne diesen Schritt läuft der Code deployed aber NIE.
5. **[non-blocking, @po-agent]** — `Reminder_Due_Date__c` beim Zurücksetzen: beibehalten (Default) vs. leeren.
6. **[non-blocking, @po-agent]** — „Relevante Bearbeitung" = Status-Wechsel + Staff-CaseComment (Default, PO-genannt). Weitere Felder ergänzen?

## Für @user
- **Was das neue ist:** Auf jedem Servicefall tauchen 4 neue, **nur lesbare** Felder auf — *Letzte Bearbeitung*, *Wiedervorlage am*, *Wiedervorlage erforderlich*, *Anzahl Wiedervorlagen*. Der Mitarbeiter sieht sie, kann sie aber nicht von Hand ändern.
- **Was passiert und wann:** Jeden **morgens um 1 Uhr** prüft das System **alle** offenen Fälle. Liegt ein Fall länger als 3 Werktage (bzw. 1 Werktag bei Priorität „High") ohne echte Bearbeitung (Statuswechsel oder Antwort des Mitarbeiters), wird *Wiedervorlage erforderlich* auf **Ja** gesetzt und *Wiedervorlage am* mit dem Zeitpunkt befüllt.
- **Fall arbeitet man wieder:** Wird der Fall bearbeitet (Status geändert oder Mitarbeiter antwortet), springt die Uhr auf Null zurück, der Wiedervorlage-Zeiger wird auf **Nein** gesetzt und die *Anzahl Wiedervorlagen* zählt hoch. Geschlossene Fälle werden nie erinnert; ein Fall, der auf Kunden-Antwort wartet, wird — sobald der PO den genauen Status dafür festlegt — pausiert.
- **Wer es sieht:** Service-Mitarbeiter mit Case-Lesezugriff sehen die Felder (Rechte pro Feld via Permission Set, kein Profile).

---
*Autoritative Build-Spec. Repo-Dateien sind die Quelle der Wahrheit, nicht der Jira-Kommentar (Jira-Markup korruptiert exakte XML-/API-Namen). Survey/Belege: `origin/master @ 361a266`; Org `Test-Org 00DWU00000oibVJ2AY`.*
