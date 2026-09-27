# SCRUM-432 — Tester-Notizen

Ticket: Wiedervorlage auf Case (persönliches Follow-up-Datum + Notiz + „heute offen"-Liste)
Branch (Developer): feature/SCRUM-432-wiedervorlage, head 68925c3
PR: #146 (APPROVED vom Architect, Kommentar 21603)
Org: Test-Org

## Komponenten (aus Build-Spec docs/SCRUM-432-design.md)

- 4 Custom Fields auf Case:
  - Wiedervorlage_Datum\_\_c (Date, optional)
  - Wiedervorlage_Notiz\_\_c (Text, optional)
  - Wiedervorlage_Von\_\_c (Lookup->User, SetNull, optional)
  - Wiedervorlage_Heute_Offen**c (Formel->Checkbox, read-only)
    Formel: AND(Von**r.Id=$User.Id, NOT(ISBLANK(Datum)), Datum<=TODAY())
- Listview: Wiedervorlagen_heute_offen (filterScope=Everything, filter Heute_Often\_\_c =1, 5 Spalten)
- PS: SCRUM432_Wiedervorlage_ServiceTeam (RE auf Datum/Notiz/Von, R auf Formel)
- Layout: Sektion „Wiedervorlage" mit 3 Speicher-Feldern (Formel DRAUSSEN)

## KERN-Logik

Formel Heute_Offen**c ist SESSSIONSABHÄNGIG: wird für die abfragende Person
evaluiert ($User.Id). Damit erscheint ein Case NUR in der Liste des Users,
der ihn auf Wiedervorlage gelegt HAT (Von**c = dieser User) UND Datum<=heute.
-> Test-Daten MÜSSEN Von**c = aktuellem Session-User setzen, sonst Formel=false.
Von**c wird MANUELL gesetzt (User wählt sich selbst), kein Auto-Pflegen.

## AC-Mapping (aus Design, 8 ACs)

AC1 Datum+Notiz speichern/zeigen -> Apex SCRUM432WiedervorlageTest + E2E(save)
AC2 5 Spalten in Liste -> E2E(Columns-assert)
AC3 heute/vergangene ja, ohne Datum nein -> Apex(4 Fälle) + E2E
AC4 ältestes Datum oben -> UNTESTED (ADR-7: ListView-Metadata kein sort; UI-Sort)
AC5 eigene sichtbar -> Apex runAs(A) + E2E
AC6 fremde versteckt + umgekehrt -> Apex runAs(A/B) (primär)
AC7 Service-User kann beide setzen -> Apex FlsTest pos + E2E(editable)
AC8 Nicht-Editor nicht ändern -> Apex FlsTest neg

## Befunde (füllt sich)

- Session-User (CLI target-Org): devops-agent@cline.test = 005WU000017tEKLYA2
  -> FÜR E2E-Fixtures: Wiedervorlage_Von\_\_c = 005WU000017tEKLYA2, damit Formel=true
- fls-check.sh: ALLE 4 Felder deployed + FLS-korrekt:
  Datum(Date)/Notiz(Text255)/Von(Lookup User) = read+edit; Heute_Offen(Formula Checkbox)=read only
  -> PS SCRUM432_Wiedervorlage_ServiceTeam, 2 Zuweisungen (devops-agent + meerwais.osmani)
- ListView-Metadaten (retrieve aus Org, 27.09.): fullName Wiedervorlagen_heute_offen,
  5 Spalten (CASES.CASE_NUMBER, ACCOUNT.NAME, CASES.SUBJECT, Notiz, Datum),
  filterScope Everything, filter Heute_Offen=1, LABEL „Wiedervorlagen – heute offen".
  KEIN sort-Element -> AC4 plattform-limitiert (ADR-7), UI-Sort, untested.
- E2E-UI-Basen: baseURL = lightning.force.com (org.ts), Listview-URL /lightning/o/Case/list?filterName=Wiedervorlagen_heute_offen
- House-Helper vorhanden: record-page.ts (openRecordDetails, startInlineEdit, saveInlineEdit), SCRUM-378 als Vorlage

## VERIFIZIERTE BEFUNDE (Finaler Testlauf 27.09., Test-Org)

- SMOKE green (vor Final-Run).
- APEX: 11/11 Pass, 100% — SCRUM432WiedervorlageTest(10) + SCRUM432WiedervorlageFlsTest(1).
  Test-RUN 707WU00001Ksm2P, user 005WU000017tEKLYA2. Negativ-FLS: Felder ohne PS unsichtbar, mit PS sichtbar.
- E2E: 4/4 green (SCRUM-432_wiedervorlage-case.spec.ts):
  1. Formel-Filter (nur eigene fällige) pass
  2. AC2 5 Spalten pass
  3. AC7 Felder im UI setzbar (inline edit) pass
  4. AC1 Speichern + Reload-Persistenz pass
- FIXTURES (6 Cases, Subject-Prefix TEST-SCRUM-432-, via sf data create als Admin):
  OWNTODAY, OWNYEST, FUTURE, FOREIGN_TODAY, FOREIGN_YESTERDAY, CLEANUP. Before-All: idempotent Re-seed
  (Delete leftover -> recreate mit today-relevanten Datums). Von\_\_c = 005WU000017tEKLYA2 (Session-User).

## LERNSCHREITEN (werfen beim 2. Vorkommen in Skill/Memory)

1. Record-URL braucht RE-CORD-Id (15/18 char), NICHT die Case-Number (00002868). Im Grid kommt die
   RecordId aus der Attribut data-row-key-value der [role=row] (data-row-key=Case). 18-char = 15+3 CRC.
2. Case-Record-Page hat KEINEN Details-Tab (andere Objekte schon) -> openRecordPage statt openRecordDetails.
3. EIN Klick auf "Edit <Feld>" setzt die GANZE Feld-SEKTION in Edit-Mode; zweite StartInlineEdit gibt's
   nicht mehr -> zweites Feld via getByLabel("<Feld>",{exact:true}) direkt (record-page.ts, verifiziert).
4. Grid-Zeilen (data row) laden NACH der versteckten HEADER-Zeile -> waitFor auf erste [role=row] ohne
   data-row-key=HEADER, nicht .first().
5. CLI in Test per Kommando-STRING (sfOk/execSync), NICHT array.join(' ') — Quote-Integrität von
   -v "-q '…'" und -i mit Leerzeichen bricht bei join. (378-Nachbau hatte dieselbe Latenz, 2-Wert-pairs nur.)
6. SF-CLI JSON-Output in Playwright-Worker: FORCE_COLOR=0 NO_COLOR=1 setzen (sonst Escape-Codes).
