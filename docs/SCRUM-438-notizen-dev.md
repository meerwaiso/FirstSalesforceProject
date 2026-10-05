# SCRUM-438 — Dev-Notizen (Developer-Agent)

Build-Spec: `docs/SCRUM-438-design.md` (fded433c). Architect-Survey: `docs/SCRUM-438-notizen.md` (fded433 — NICHT überschreiben, nur zitieren).
Target-Org: **Test-Org**. House-Referenzen: SCRUM-436 (Reminder, 1:1-Form) + SCRUM-424 (BusinessHours).

## ⚠️ Wichtige Korrektur gegenüber Architect-Notiz Zeile 15 (VERIFIZIERT 2026-10-04, `sf apex run`)
Architect-Notiz sagt: "BusinessHours Default = 24/7, America/Los_Angeles". **FALSCH / stale.** Live-Probe an Test-Org:
- BusinessHours "Default", **TZ = Europe/Berlin** (nicht America/Los_Angeles).
- Geometrie: **Mo–Fr 9:00–17:00 (8h, kein Mittag), Sa + So 24/7.**
- Beweise (ms→min), ALLE konsistent: mon9→tue9=480; mon9→mon17=480; mon17→tue9=0 (Nacht zählt 0); tue9→sat9=41h (=4×8h+Sa 00–09=9h); sat→sun Tag=24h; sun23→mon0=1h; mon0→mon9=0 (Mo-Vorm. <9 zählt 0); thu17→fri9=0.
- → **`BusinessHours.diff` liefert DIREKT echte Werkzeit.** ADR-3 ohne Org-Setup befriedigt; "Mo-Fr ausstehender Org-Step" entfällt. FÜR REVIEW/PO dokumentieren (Befund 5 im Design überholt).

## ⚠️⚠️ Kritisch: `BusinessHours.add` IST IN DIESER ORG KAPUTT (VERIFIZIERT 2026-10-04, Probe4/5, Test-Org)
`BusinessHours.add(hid, start, m)` liefert für ALLE Inputs (start 00:00 ODER 09:00; m=25..1000) denselben Wert **07:00:00** (= 09:00 CEST in UTC gerendert) — d.h. Fensterstart, unabhängig von m. m=1000 bringt nur +1 Sekunde. → **FÜR DIE DEADLINE NICHT VERWENDEN.**
**Stattdessen:** `estimateDeadline(bhId, from, totalMins)` = **Binary Search über `BusinessHours.diff`** (verifiziert-exakt, monoton) → erstes T mit `diff(from,T) >= totalMins`, 1s-Präzision, ~20 Iterationen, nur diff (kein add). Selbstkonsistent testbar: `assert diff(created, deadline) == total`.
**Konsequenz für ADR-3:** ADR-3 sagt "via BusinessHours.diff, keine eigene Rechenmaschine". Ich nutze `diff` (verifiziert) für ALLE SLA-Mathematik; `add` wird umgangen (kaputt). Intent (Plattform-Kalender statt Handwerk-Tag-Mathematik) voll gewahrt → **Abweichung für Review/PO dokumentieren (ADR-3-Ergänzung).**

## ARCHITEKTUR (final, alle Plattform-APIs verifiziert)
- before-Trigger (0 DML, Felder auf Trigger.new) + Batch (macht die DML) → EIN Service `SLAService` (AC8: keine Logik-Duplikation).
- **Ganzer Status/Eskalation = `diff`-Minuten vs. total (Config).** Kein absoluter DateTime nötig für Kernlogik. Deadline `SLA_Zielzeit__c` = DISPLAY-Wert via estimateDeadline (Binary Search auf diff).
- **Pause-Korrektur (gefrorene Uhr), geometry-UNABHÄNGIG:**
  - `A` = SLA_Akkumulierte_WorkingMins__c (gefrorene gearbeitet-Std beim letzten Check)
  - `L` = SLA_Last_Checked__c (läuft IMMER auf now, auch in Pause)
  - NICHT in Pause: worked = A + diff(L, now); danach A:=worked, L:=now.
  - IN Pause: worked = A (frozen); L:=now (Pause-Intervall wird so exkludiert, A bleibt).
  - Resume → erste nicht-pausierte eval: worked = A + diff(L_vorPause→now) → Pause exkludiert. exakt in Std, auch über Nacht/Wochenende (24/7-Parts).
  - Deadline (Zielzeit) bleibt bei Pause STABIL (nur gearbeitet-Uhr friert). PO-Regel "Eskalationsstufe bleibt bei Pause" = erfüllt (Eskalation hängt von worked ab, worked friert).
- Status: worked≥total → "Überschritten"; else (total-worked)/total < 0.20 → "Gefährdet"; else "Im Zeitplan".
- Eskalation (monoton via worked, nie fallend): worked≥total → "Stufe 1" (+Überschritten=true); worked≥total+240 → "Stufe 2".
- Priority-Change: neue Deadline = estimateDeadline(now, newTotal − worked); Akk/LC unchanged.
- Self-Heal: LC null (legacy) → bootstrap A:=0, L:=now, deadline von created (≈now bei erstem Lauf).

## Impl-Konsequenz für Tests (wichtig)
- Code ist org-agnostic (`BusinessHours.diff/.add` rechnet mit konfiguriertem Set) → **keine hard-coded Kalendertage-/Wochenende-Minuten-Konstanten** in Tests, die BH-Geometrie voraussetzen.
- Test-Assertions basieren auf `BusinessHours.diff`-Ergebnissen zur Laufzeit ODER intraday-Intervallen innerhalb eines Wochentags (9–17, da 8h fest) + ein expliziter Wochentag-Sprung-Test mit relativer Assertion (diff(nachWoche) > diff(intraTag)).
- Pause (Gefrieren) ist geometry-UNABHÄNGIG testbar: worked = diff(anker, now) − diff(pauseStart, pauseEnd) — beide mit gleichem Set → Pause-Länge = exakte Stunden, auch über Nacht/Wochenende hinweg (24/7-Parts).

## Kern-Modell (implementiere so)
- `totalTargetMinutes`: High=240 / Medium=480 / Low=1440; Premium (`Case.Kundenstatus__c='Premium'`) ×0.75.
- `SLA_Akkumulierte_WorkingMins__c` (Decimal-Feld) = worked so far = BusinessHours.diff(Last_Checked→now, minus Pause-Intervalle).
- `SLA_Last_Checked__c` = Clock-Anker, läuft IMMER auf now; +worked-Delta nur wenn NICHT paused.
- Status: worked≥total → "Überschritten"; rest/total<0.20 → "Gefährdet"; else "Im Zeitplan".
- Eskalation monotone: worked≥total → Stufe 1 (+`SLA_Ueberschritten__c=true`); worked≥total+240 → Stufe 2.
- Zielzeit `SLA_Zielzeit__c`: Erstlauf = createdBy + total (via BusinessHours.add); Priority-Change = now+(newTotal−worked); sonst stabil.
- 7 neue Case-Felder (API): SLA_Zielzeit__c (DateTime), SLA_Status__c (Picklist), SLA_Eskalation__c (Picklist Keine/Stufe 1/Stufe 2), SLA_Ueberschritten__c (Checkbox), SLA_Akkumulierte_WorkingMins__c (Number), SLA_Last_Checked__c (DateTime), SLA_Uhr_gestoppt__c (Checkbox).

## ADR-Abweichung (bewusst, für Review)
**Trigger = before insert/update (NICHT after).** Design-Zeile 93 "after", aber Zeile 94 "0 SOQL, 0 DML im Trigger" — after+DML bräuchte 1 DML + isRunning-Guard + Edit-FLS vom init. User (PO gibt Service nur Read → würde fehlschlagen). before (House SCRUM-436, grün) setzt Felder auf Trigger.new, 0 DML, kein Re-Entry. Intent (reaktiv, keine Duplikation) erhalten.

## Deploy-Reihenfolge (Memory: CustomField ZUERST, dann Referenzierer; einzeln wo ref.)
1. `manifest/scr438-phase1-fields.xml` (7 CustomField) → validate → deploy
2. `manifest/scr438-phase2-referencing.xml` (2 PS + Trigger + 4 Classes + Layout) → validate → deploy
3. `manifest/scr438-apextests.xml` (Test-Classes) → deploy + `--test-level RunSpecifiedTests --tests SCRUM438*`
- `sf project deploy validate` VOR `deploy start` (phased).
- BusinessHours.diff = 1 Lookup `getBusinessHoursId()` AUSSERHALB der Loop (House SCRUM-424).
- Commit pro Deploy-Readiness-Einheit (User-Regel: öfter committen).

## FLS (PS ≠ zugeordnet; DoD = vorhanden UND zugewiesen) — 7. Wiederholung riskieren? NEIN
- `SCRUM438_SLA_Read` (editable=false ×7) → Service-Team. `SCRUM438_SLA_System` (editable=true ×7) → Batch/Scheduled-User.
- NACH Deploy: an CLI-User + Mensch-Test-Account zuweisen, 2×2-Beleg per SOQL `PermissionSetAssignment`, 1 Feld per realer Session read-back.
- **ERGEBNIS (2026-10-04):** beide PS an `devops-agent@cline.test` + `meerwais.osmani@resourceful-bear-6f1u4j.com` zugewiesen (House-Prezedenz SCRUM-436, gleiche 2). `fls-gate.py --base origin/master --org Test-Org` → **grün** (A: Feld→PS, B: PS zugewiesen). Feld-Read-back als CLI-User (hält beide PS): alle 7 `SLA_*__c` lesbar, kein „No such column". 2×2-Beleg in Jira-Handoff.

## ⚠️⚠️ CLOSED CASES — ClosedDate NICHT im before-Kontext (KERN-BEFUND, VERIFIZIERT 2026-10-04)
- `Case.ClosedDate` wird erst **BEIM insert** aus `Status='Closed'` auto-gesetzt → im **before-insert** ist `c.ClosedDate == null`, SELBST wenn Case mit `Status='Closed'` angelegt wird. Trigger-Guard `if (c.ClosedDate == null)` initSLA → würde CLOSED Cases initialisieren (BUG).
- **Fix:** before-insert-Guard auf `if (c.Status != 'Closed')` (Design-Note 4: „Closed" = geschlossener Picklist-Wert). Batch-Filter `ClosedDate = null` bleibt (Batch liest Post-Insert-Daten, da ist ClosedDate gesetzt).
- Beweistest (Probe438Close, Test-Org, Test-Context → auto-rollback): open `New` Case → `ZIEL=SET LASTCHK=SET`; closed `Closed` Case → `ZIEL=NULL LASTCHK=NULL` (Engine hat ihn NICHT angefasst). Trigger korrekt.

## ⚠️ AC8-Picklist-Default-Gefahr (VERIFIZIERT 2026-10-04)
- Ich hatte `<default>true` auf `SLA_Status__c="Im Zeitplan"` + `SLA_Eskalation__c="Keine"` gesetzt → **JEDER insert** (auch closed, Engine inaktiv) füllt Status/Eskalation mit dem Default. Geschlossener Case zeigte `SLA_Status__c='Im Zeitplan'` obwohl Engine ihn nie sah.
- Design-Note 3: „geschlossener Case: **alle** SLA-Felder bleiben leer" → Default-Werte RÄSCHTIG. **ENTFERNT** aus beiden field-meta.xml + redeployed.
- **AC8-Test darf NICHT auf `SLA_Status__c == null` asserten** (Default füllt ihn = Probe, die under my Hypothese nicht failen kann). Korrekt: `SLA_Zielzeit__c == null` OR `SLA_Last_Checked__c == null` — das sind die von der Engine verwalteten Felder.

## Compiler-Quirks (in dieser Org/CLI 2.150.6, VERIFIZIERT 2026-10-04)
- **`%` Operator:** `i % 3` → Deploy-Error „Found punctuation symbol or operator '%'" (trotz gültiger Apex-Syntax, unbekannter Parser-Quirk). **Workaround: `Math.mod(i,3)`.**
- **Reserved Words:** `from`, `end` als Variablenamen → Compile-Fehler. `basis`/`stopp` verwenden.
- **`Integer`:** kein `.doubleValue()` → `* 1.0`. **`DateTime.addMinutes`:** erwartet `Integer`, nicht `Long` → explicit Cast.
- **`ISNULL(ClosedDate)`** ungültiges SOQL (kein WHERE-Aggregat) → `ClosedDate = null`.
- House-Konvention: jede `.cls` braucht `.cls-meta.xml`, jeder `.trigger` braucht `.trigger-meta.xml` — fehlt → `project deploy` (mit --source-dir) findet Komponente nicht beim Zipping.
- Meta apiVersion: **62.0** (House-Pattern). Test-Deploy-Manifest `scr438-apextests.xml` separat.

## Offene Punkte (PO/Org, blocken NICHT, Defaults implementiert — für Review aufzählen)
a) Feiertagskalender (Default: Mo-Fr ohne Feiertage — Org hat ohnehin keine Feiertage). b) Picklist-Wert "Warten auf Kunde" (Org-Step, DevOps) → PAUSE_STATUSES leer im Default, Pause über Checkbox-Test. c) Eskalations-Sprung 4h = WERK-stunden (BusinessHours.diff, Default). d) **Org-Orphan `Probe438Close`** (benign @isTest, in Test-Org, NICHT in der Branch — CLI 2.150.6 hat kein `sf org metadata delete`; 4 Lösungswege abgebrochen, DevOps kann purgen). e) Scheduled Job manuell setzten (`System.schedule`, Cron `0 15 * * * ?`) — kein Metadata.

## FINAL (2026-10-04, Test-Org, Run 707WU00001LwtVF)
- **9 Tests: SCRUM438SLATest (8 fktl., AC2/3/4/6/7/8/9 + Config) + SCRUM438SLAFlsTest (1, FLS neg/pos alle 7 Felder) = 9/9 PASS, 0 % Fail, 0 % Skip.**
- Deploy: Phase 1 (7 Felder) + Phase 2 (PS+Layout+4 Apex+Trigger+Meta-Companions+Layout) + apextests + 2 Feld-Redeploys (Default-Entfernung) + `SLAJobBatch`-Redeploy (ISNULL-Fix) — alle **Succeeded**.
- Probe-Pollution (probe438closeX) aus Test-Org entfernt.
