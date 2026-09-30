# SCRUM-434 Notizettel (TESTER)

## Auftrag
Testen: 5 ACs gegen Test-Org. PR #149, branch `feature/SCRUM-434-ursache` @ 79ef57e.
Architect approved 3. Durchgang (Kommentar 22040): "Monat/Quartal-Auswahl ist UI-Interaktion auf dem Zeit-Filter → gehört in deinen E2E-Lauf."

## Org-Fakten (read-back, mit Befehlsname)
(siehe unten — hier landen alle aus der Org geholten Werte)

## Befunde
- Developer-Apex `SCRUM434UrsacheTest` (6 Tests) deckt AC1/AC2-Block/AC2-Speichern/AC3/AC5-FLS-neg+pos.
- Report: `Faelle_Nach_Ursache` (name in Report-XML), ReportType CaseList, scope organization, Filter CLOSED=1, timeFrameFilter CLOSED_DATE INTERVAL_LAST90, Grouping Case.Ursache__c.
- ValRule `Ursache_PflichtBeiGeschlossen`: AND(OR(IsClosed, ISPICKVAL(Status,'Closed')), ISBLANK(TEXT(Ursache__c))).
- PS `SCRUM434_Ursache` deployed + assigned (Dev-Read-back: devops-agent, Meerwais Osmani).

## Stand
- [ ] Notizettel angelegt, committet
- [ ] Smoke grün
- [ ] Apex SCRUM434UrsacheTest läuft in Test-Org
- [ ] E2E-Spec für AC4 (+AC2-UI) geschrieben, committet, grün
- [ ] SOQL/Analytics-Lese für Observed-Zahlen
- [ ] Coverage-Tabelle in Jira
