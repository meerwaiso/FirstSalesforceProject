# SCRUM-424 DevOps-Notizen (Prod-Release: S2 + S4 + Deploy)

User-Entscheidung 23.09. (Fino, Telegram): **Arbeitszeiten = Mo–Fr 09:00–17:00 Europe/Berlin.
"Ignoriere die andere Zeiten."** → PO-08:00-Variante (cmt 20355) wird verworfen, Design-Doc
(Mo–Fr 9:00–17:00) ist korrekt. Wochenende: geschlossen (null).

## PO-Auftrag (cmt 20355, 23.09. 14:42)
KEINE Release-Freigabe — 2 Restposten an DevOps, danach direkt Prod-Release:
- S2: Default-BusinessHours Test-Org ist 24/7 → auf Mo–Fr 09–17 umstellen (Setup, nicht Metadata). Live-Read-back.
- S4: Report `Service/Erstreaktionszeit_Pro_Servicebereich` braucht Average auf
  First_Response_Working_Mins__c (House-Muster beachten). Live-Read-back via fresh retrieve.
- Danach: Release direkt in Prod-Org (S1 TZ Europe/Berlin + S2 Arbeitszeiten + S4 Report-Average),
  Read-backs in den Release-Kommentar + Release-Tag. PO nimmt ab + Release Note.

## Live-Read-backs (23.09., read-only)
- TEST-Org BusinessHours: Name='Default' IsDefault=True TZ=**Europe/Berlin** (S1 OK),
  aber ALLE 7 Tage 00:00:00→00:00:00 = 24/7 (S2 NICHT gesetzt). [cmt 20289 bestätigt: 100% Kalender]
- PROD-Org BusinessHours: Name='Default' IsDefault=True TZ=**America/Los_Angeles** (S1 NICHT gesetzt in Prod!),
  ALLE Tage 00:00:00 = 24/7 (S2 NICHT gesetzt). → Prod-Release MUSS S1+ S2 beides fixen.
- BusinessHours = DML-addressable sObject (felder MondayStartTime..SundayEndTime, TimeZoneSidKey,
  alle updatable=True); NICHT deployable metadata (Registry: 0 Einträge). → S2 = Daten-Update, nicht Deploy.
- Report = deployable metadata type (Registry: Report=1, reportTypes=1). → S4 = Report-Datei-Änderung + Deploy.
- Repo hat KEIN BusinessHours-File (nur SCRUM424BusinessHoursTest). Repo-Report-File:
  force-app/main/default/reports/Service/Erstreaktionszeit_Pro_Servicebereich.report-meta.xml
  (columns: CASE_NUMBER, SUBJECT, Case.First_Response_Working_Mins__c, Case.First_Response_Target_Missed__c;
  grouping Servicebereich__c; filter First_Response_Time__c != empty; scope=organization).
- KEIN House-Report im Repo nutzt Aggregate (grep average/aggregate/sumAggregate/total = 0 Treffer außer der 424-Description).
- origin/master = 67775e4 (424-Merge). Worktree /tmp/scr424-work @ 67775e4 (detached, unangetastet Shared-Checkout).

## Offene (noch zu klären)
- S4 exaktes XML: Report-Column Average-Element (Verdacht `<aggregateType>AvG</aggregateType>` im `<columns>`)
  → NUR via authoritative Prüfung bestätigen (House-Beispiel aus Org retrieve ODER dry-run validate), NICHT raten.
- S2-Update-Weg weekend=null: REST PATCH (sf api request) weil CLI data update nulls schwierig.
- Branch-Protection master: direkter Push erlaubt oder PR nötig (für S4-Report-Change in Repo)?

## Status
- [x] S4 Report Average: Form = `<aggregateTypes>Average</aggregateTypes>` (CLI-Typschema ReportSummaryType; 'AvG' Org-seitig verworfen). Test-Org dryrun + real deploy + fresh-retrieve ✅
- [x] S4 in Repo: branch release/scr424-s4-average (head a5ec9f4), PR #130. Nur 424-Report + manifest/scr424-s4-report.xml commited; die 8 Nebenänderungen am Retrieve-Auswahl-Run wurden wieder verworfen.
- [x] S2 (Test-Org): Mo–Fr 09–17 gesetzt + empirisch verifiziert (Thu09-17=480, Fri18-Mon09=0, Sat-Sun=0) — **dann aber wieder auf 24/7 zurückgespielt**, weil mit gesetzter WW der AC7-Test (hartkodiert 24/7, 2520) 952 liefert → Smoke rot (Run 35877336351). Bug SCRUM-426 (Developer).
- [x] S2-Prod-Vorbereitung: JSON bereitzustellen (bh_s2_prod.json: TZ Europe/Berlin + Mon-Fri 09:00Z-17:00Z). Id Prod BusinessHours 'Default' = 01mg5000004gR7xAAE. Prod-Aktuell: TZ America/Los_Angeles, 00:00→00:00 (24/7). @user Prod-TZ = Europe/Berlin (005g5000009C38DAAS).
- [x] Prod-Validierung: Phase1 (3 Felder + PS) ✅ Succeeded (4 Komponenten, 209 Tests, check-only Job 0Afg500000F8KDpCAN). Phase2/Phase3 validiert NUR nach Phase1 (Sequenz-Fehler erwartet, nicht echte Defekte) — im Release-Reihenfolge: 1→2→3.
- [ ] PR #130: CI-Rerun abwarten (35877336351) → grün → Merge (Gate 4: Ticket Release/devops-agent ✅ cmt 20355, Arch-Approval ✅ 20187, Tester-Sign-off ✅ 20289, CI muss zu Merge-Head a5ec9f4 gehoren)
- [ ] AC7/S2: SCRUM-426-Entscheidung (Developer/Tester) oder PO-Freigabe — bestimmt ob S2-Release sofort oder verzögert.
- [ ] Prod-Release: S1+S2 Daten-Update Prod-Org (Europe/Berlin, Mo–Fr 09-17, weekend null) → Read-back (+ BusinessHours.diff-Probe Prod)
- [ ] Prod-Release: Phasen-Deploy 424 (Felder+PS → Apex+Trigger+Tests → Layout+Report) + PS-Zuweisung @user + devops CLI-User (REST PermissionSetAssignment, Feld AssigneeId)
- [ ] Release-Tag release/2026-09-23-SCRUM-424 + Jira-Release-Kommentar mit allen Readbacks, Übergabe PO
